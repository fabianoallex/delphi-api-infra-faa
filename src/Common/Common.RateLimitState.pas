unit Common.RateLimitState;

interface

uses
  System.Generics.Collections,
  System.SyncObjs;

type
  /// Interface da janela deslizante de rate limiting.
  /// Separada do middleware Horse para permitir testes unitários sem dependência de Horse.
  IRateLimitState = interface
    ['{1D76258F-A73D-4B6A-AEE1-7EB316213BAC}']
    procedure CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
      out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
  end;

  /// Implementação in-memory da janela deslizante.
  /// Thread-safe via TCriticalSection.
  ///
  /// A janela é medida com TTicker (relógio monotônico), nunca com TClock:
  /// com o relógio de parede, um recuo da hora do sistema (fim do horário de
  /// verão, NTP, operador) deixava as entradas "no futuro" e mantinha um
  /// cliente bloqueado até o relógio alcançá-las — até 1h a mais que a
  /// janela. TClock só entra para expressar AResetUnix (agora de parede + o
  /// que falta da janela). Os dois são injetáveis em testes.
  TRateLimitState = class(TInterfacedObject, IRateLimitState)
  private
    FLock:    TCriticalSection;
    FBuckets: TObjectDictionary<string, TList<UInt64>>; // leituras de TTicker.NowMs, crescentes
  public
    constructor Create;
    destructor Destroy; override;
    procedure CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
      out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  PascalCommon.SystemContext;

{ TRateLimitState }

constructor TRateLimitState.Create;
begin
  FLock    := TCriticalSection.Create;
  FBuckets := TObjectDictionary<string, TList<UInt64>>.Create([doOwnsValues]);
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
  LBucket:      TList<UInt64>;
  LNowMs:       UInt64;
  LWindowMs:    UInt64;
  LResetInMs:   UInt64;

  // Idade de uma entrada; 0 se ela estiver à frente de LNowMs (só acontece
  // com um ticker de teste que volta) — nunca dá a volta no UInt64.
  function AgeMs(AEntryMs: UInt64): UInt64;
  begin
    if LNowMs > AEntryMs then
      Result := LNowMs - AEntryMs
    else
      Result := 0;
  end;

begin
  LWindowMs := UInt64(Max(AWindowSeconds, 0)) * 1000;

  FLock.Enter;
  try
    // Lido sob o lock: as entradas de uma chave ficam em ordem crescente
    // mesmo com requisições concorrentes.
    LNowMs := TTicker.NowMs;

    if not FBuckets.TryGetValue(AKey, LBucket) then
    begin
      LBucket := TList<UInt64>.Create;
      FBuckets.Add(AKey, LBucket);
    end;

    // Lista em ordem crescente — remove entradas expiradas pela frente
    while (LBucket.Count > 0) and (AgeMs(LBucket[0]) > LWindowMs) do
      LBucket.Delete(0);

    AExceeded := LBucket.Count >= ALimit;

    if not AExceeded then
      LBucket.Add(LNowMs);

    // Reset: quando a entrada mais antiga da janela atual vai expirar,
    // expresso no relógio de parede (é um timestamp Unix para o cliente)
    if LBucket.Count > 0 then
    begin
      if AgeMs(LBucket[0]) < LWindowMs then
        LResetInMs := LWindowMs - AgeMs(LBucket[0])
      else
        LResetInMs := 0;
    end
    else
      LResetInMs := LWindowMs;
    AResetUnix := DateTimeToUnix(TClock.Now + LResetInMs / MSecsPerDay, False);

    ARemaining := Max(0, ALimit - LBucket.Count);
  finally
    FLock.Leave;
  end;
end;

end.
