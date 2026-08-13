unit Common.RateLimitState;

interface

uses
  System.Generics.Collections,
  System.SyncObjs;

type
  /// Interface da janela deslizante de rate limiting.
  /// Separada do middleware Horse para permitir testes unitários sem dependência de Horse.
  IRateLimitState = interface
    ['{4A2E8F1C-9B3D-4C7A-8E5F-1D6A2B3C4D5E}']
    procedure CheckAndRecord(const AKey: string; ALimit, AWindowSeconds: Integer;
      out ARemaining: Integer; out AResetUnix: Int64; out AExceeded: Boolean);
  end;

  /// Implementação in-memory da janela deslizante.
  /// Thread-safe via TCriticalSection; usa TClock.Now para permitir injeção de clock em testes.
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

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  Common.SystemContext;

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

end.
