unit Horse.Middleware.RateLimit;

interface

uses
  System.Generics.Collections,
  System.SyncObjs,
  Horse.Callback;

type
  TRateLimitKeyExtractor = reference to function(Req: THorseRequest): string;

  /// Opções do middleware de rate limiting.
  /// Use TRateLimitOptions.Default como base e ajuste Limit/WindowSeconds conforme necessário.
  TRateLimitOptions = record
    /// Número máximo de requisições permitidas dentro da janela. Padrão: 60.
    Limit: Integer;
    /// Tamanho da janela deslizante em segundos. Padrão: 60.
    WindowSeconds: Integer;
    /// Função que extrai a chave de agrupamento por requisição.
    /// Padrão: IP do cliente (X-Forwarded-For, depois RemoteAddr).
    KeyExtractor: TRateLimitKeyExtractor;
    class function Default: TRateLimitOptions; static;
  end;

  /// Interface do estado da janela deslizante. Exposta para permitir testes unitários.
  IRateLimitState = interface
    ['{4A2E8F1C-9B3D-4C7A-8E5F-1D6A2B3C4D5E}']
    procedure CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
      out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
  end;

  /// Implementação in-memory da janela deslizante. Thread-safe via TCriticalSection.
  /// Usa TClock.Now para permitir injeção de clock em testes.
  TRateLimitState = class(TInterfacedObject, IRateLimitState)
  private
    FLock:    TCriticalSection;
    FBuckets: TObjectDictionary<string, TList<TDateTime>>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
      out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
  end;

  /// Middleware de rate limiting com janela deslizante (sliding window).
  ///
  /// Comportamento:
  ///   - Conta requisições por chave (IP por padrão) dentro de uma janela de tempo.
  ///   - Ao exceder o limite, retorna 429 com JSON {"error": "..."} e Retry-After.
  ///   - Emite os headers X-RateLimit-Limit, X-RateLimit-Remaining e X-RateLimit-Reset
  ///     em todas as respostas (inclusive as bloqueadas).
  ///   - Estado em memória, thread-safe via critical section.
  ///   - KeyExtractor customizável para limitar por API key ou outro critério.
  ///
  /// Uso no DPR (após TErrorHandlerMiddleware, antes de RegisterRoutes):
  ///
  ///   // 60 requisições por minuto por IP (padrão)
  ///   THorse.Use(TRateLimitMiddleware.New(60, 60));
  ///
  ///   // 1000 requisições por hora
  ///   THorse.Use(TRateLimitMiddleware.New(1000, 3600));
  ///
  ///   // Por API key no header X-Api-Key
  ///   var LOptions := TRateLimitOptions.Default;
  ///   LOptions.Limit := 200;
  ///   LOptions.KeyExtractor :=
  ///     function(Req: THorseRequest): string
  ///     begin
  ///       Result := Req.Headers['X-Api-Key'];
  ///       if Result.IsEmpty then Result := 'anonymous';
  ///     end;
  ///   THorse.Use(TRateLimitMiddleware.New(LOptions));
  TRateLimitMiddleware = class
  public
    class function New(ALimit, AWindowSeconds: Integer): THorseCallback; overload;
    class function New(const AOptions: TRateLimitOptions): THorseCallback; overload;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  System.JSON,
  Common.SystemContext,
  Horse;

function ExtractClientIP(Req: THorseRequest): string;
var
  LForwarded: string;
  LComma: Integer;
begin
  LForwarded := Req.Headers['X-Forwarded-For'];
  if not LForwarded.IsEmpty then
  begin
    LComma := Pos(',', LForwarded);
    if LComma > 0 then
      Result := Trim(Copy(LForwarded, 1, LComma - 1))
    else
      Result := Trim(LForwarded);
  end
  else
    Result := Req.RemoteAddr;

  if Result.IsEmpty then
    Result := 'unknown';
end;

{ TRateLimitOptions }

class function TRateLimitOptions.Default: TRateLimitOptions;
begin
  Result.Limit         := 60;
  Result.WindowSeconds := 60;
  Result.KeyExtractor  := ExtractClientIP;
end;

{ TRateLimitState }

constructor TRateLimitState.Create;
begin
  FLock    := TCriticalSection.Create;
  FBuckets := TObjectDictionary<string, TList<TDateTime>>.Create([doOwnsValues]);
end;

destructor TRateLimitState.Destroy;
begin
  FBuckets.Free;
  FLock.Free;
  inherited;
end;

procedure TRateLimitState.CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
  out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
var
  LBucket:      TList<TDateTime>;
  LNow:         TDateTime;
  LWindowStart: TDateTime;
begin
  LNow         := TClock.Now;
  LWindowStart := LNow - AWindowSeconds / SecsPerDay;

  FLock.Enter;
  try
    if not FBuckets.TryGetValue(AKey, LBucket) then
    begin
      LBucket := TList<TDateTime>.Create;
      FBuckets.Add(AKey, LBucket);
    end;

    // Lista em ordem crescente — remove entradas expiradas pela frente
    while (LBucket.Count > 0) and (LBucket[0] < LWindowStart) do
      LBucket.Delete(0);

    AExceeded := LBucket.Count >= ALimit;

    if not AExceeded then
      LBucket.Add(LNow);

    // Reset: quando a entrada mais antiga da janela atual vai expirar
    if LBucket.Count > 0 then
      AResetUnix := DateTimeToUnix(LBucket[0] + AWindowSeconds / SecsPerDay, False)
    else
      AResetUnix := DateTimeToUnix(LNow + AWindowSeconds / SecsPerDay, False);

    ARemaining := Max(0, ALimit - LBucket.Count);
  finally
    FLock.Leave;
  end;
end;

{ TRateLimitMiddleware }

class function TRateLimitMiddleware.New(ALimit, AWindowSeconds: Integer): THorseCallback;
var
  LOptions: TRateLimitOptions;
begin
  LOptions               := TRateLimitOptions.Default;
  LOptions.Limit         := ALimit;
  LOptions.WindowSeconds := AWindowSeconds;
  Result := New(LOptions);
end;

class function TRateLimitMiddleware.New(const AOptions: TRateLimitOptions): THorseCallback;
var
  LState:   IRateLimitState;
  LOptions: TRateLimitOptions;
begin
  LState   := TRateLimitState.Create;
  LOptions := AOptions;

  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LKey:        string;
      LRemaining:  Integer;
      LResetUnix:  Int64;
      LExceeded:   Boolean;
      LRetryAfter: Int64;
      LJson:       TJSONObject;
    begin
      LKey := LOptions.KeyExtractor(Req);

      LState.CheckAndRecord(LKey, LOptions.Limit, LOptions.WindowSeconds,
        LRemaining, LResetUnix, LExceeded);

      Res.AddHeader('X-RateLimit-Limit',     IntToStr(LOptions.Limit));
      Res.AddHeader('X-RateLimit-Remaining', IntToStr(LRemaining));
      Res.AddHeader('X-RateLimit-Reset',     IntToStr(LResetUnix));

      if not LExceeded then
      begin
        Next();
        Exit;
      end;

      LRetryAfter := LResetUnix - DateTimeToUnix(TClock.Now, False);
      if LRetryAfter < 0 then LRetryAfter := 0;

      Res.AddHeader('Retry-After', IntToStr(LRetryAfter));

      LJson := TJSONObject.Create;
      try
        LJson.AddPair('error',
          Format('Rate limit excedido. Tente novamente em %d segundo(s).', [LRetryAfter]));
        Res.Status(429).ContentType('application/json; charset=utf-8').Send(LJson.ToJSON);
      finally
        LJson.Free;
      end;
    end;
end;

end.
