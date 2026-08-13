unit RateLimitTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.DateUtils,
  Common.SystemContext,
  Common.RateLimitState;

type
  // Clock com tempo ajustável — isola os testes de Now() real.
  TManualClock = class(TInterfacedObject, IClock)
  private
    FTime: TDateTime;
  public
    constructor Create(ATime: TDateTime);
    procedure SetTime(ATime: TDateTime);
    function Now: TDateTime;
    function Date: TDateTime;
  end;

  [TestFixture]
  TRateLimitStateTests = class
  private
    FState: IRateLimitState;
    FClock: TManualClock;
    FT0:    TDateTime;
    procedure FillBucket(const AKey: string; ALimit, AWindowSeconds, ACount: Integer);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    { Requisição inicial }
    [Test] procedure FirstRequest_NotExceeded;
    [Test] procedure FirstRequest_Remaining_IsLimitMinusOne;

    { Limite exato }
    [Test] procedure AtLimit_LastRequest_Passes;
    [Test] procedure AtLimit_Remaining_IsZero;

    { Acima do limite }
    [Test] procedure OverLimit_Exceeded_IsTrue;
    [Test] procedure OverLimit_Remaining_IsZero;
    [Test] procedure OverLimit_DoesNotConsumeSlot;

    { Decremento de Remaining }
    [Test] procedure Remaining_DecrementsWithEachRequest;

    { Expiração de janela }
    [Test] procedure AfterWindowExpires_NotExceeded;
    [Test] procedure AfterWindowExpires_FullQuotaRestored;

    { Chaves independentes }
    [Test] procedure DifferentKeys_AreIndependent;

    { ResetUnix }
    [Test] procedure ResetUnix_IsOldestEntryPlusWindow;
    [Test] procedure ResetUnix_AdvancesAfterOldestExpires;

    { Limite unitário }
    [Test] procedure SingleRequestLimit_FirstPasses_SecondBlocked;
  end;

implementation

const
  SECS_PER_DAY = 86400;

{ TManualClock }

constructor TManualClock.Create(ATime: TDateTime);
begin
  FTime := ATime;
end;

procedure TManualClock.SetTime(ATime: TDateTime);
begin
  FTime := ATime;
end;

function TManualClock.Now: TDateTime;
begin
  Result := FTime;
end;

function TManualClock.Date: TDateTime;
begin
  Result := Trunc(FTime);
end;

{ TRateLimitStateTests }

procedure TRateLimitStateTests.Setup;
begin
  FT0    := EncodeDate(2025, 1, 1) + EncodeTime(12, 0, 0, 0);
  FClock := TManualClock.Create(FT0);
  TClock.SetClock(FClock);
  FState := TRateLimitState.Create;
end;

procedure TRateLimitStateTests.TearDown;
begin
  FState := nil;
  TClock.Reset;
end;

procedure TRateLimitStateTests.FillBucket(const AKey: string;
  ALimit, AWindowSeconds, ACount: Integer);
var
  I: Integer;
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  for I := 1 to ACount do
    FState.CheckAndRecord(AKey, ALimit, AWindowSeconds, LRem, LReset, LExc);
end;

{ Primeira requisição }

procedure TRateLimitStateTests.FirstRequest_NotExceeded;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.IsFalse(LExc, 'Primeira requisição não deve ser bloqueada');
end;

procedure TRateLimitStateTests.FirstRequest_Remaining_IsLimitMinusOne;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.AreEqual(9, LRem, 'Após 1 req de 10, Remaining deve ser 9');
end;

{ Limite exato }

procedure TRateLimitStateTests.AtLimit_LastRequest_Passes;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 9);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.IsFalse(LExc, '10ª requisição (exatamente no limite) deve passar');
end;

procedure TRateLimitStateTests.AtLimit_Remaining_IsZero;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.AreEqual(0, LRem, 'Ao exceder o limite, Remaining deve ser 0');
end;

{ Acima do limite }

procedure TRateLimitStateTests.OverLimit_Exceeded_IsTrue;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.IsTrue(LExc, '11ª requisição deve ser bloqueada');
end;

procedure TRateLimitStateTests.OverLimit_Remaining_IsZero;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.AreEqual(0, LRem);
end;

procedure TRateLimitStateTests.OverLimit_DoesNotConsumeSlot;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
  I: Integer;
begin
  FillBucket('ip1', 10, 60, 10);
  for I := 1 to 5 do
    FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);

  FClock.SetTime(FT0 + 61 / SECS_PER_DAY);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);

  Assert.IsFalse(LExc, 'Após janela expirar, não deve estar bloqueado');
  Assert.AreEqual(9, LRem,
    'Requisições bloqueadas não consomem slot: após expiração, quota deve ser 10-1=9');
end;

{ Decremento }

procedure TRateLimitStateTests.Remaining_DecrementsWithEachRequest;
var
  I: Integer;
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  for I := 1 to 5 do
  begin
    FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
    Assert.AreEqual(10 - I, LRem,
      Format('Após %d req, Remaining deve ser %d', [I, 10 - I]));
  end;
end;

{ Expiração de janela }

procedure TRateLimitStateTests.AfterWindowExpires_NotExceeded;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FClock.SetTime(FT0 + 61 / SECS_PER_DAY);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.IsFalse(LExc, 'Após janela expirar, requisição deve ser aceita');
end;

procedure TRateLimitStateTests.AfterWindowExpires_FullQuotaRestored;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FClock.SetTime(FT0 + 61 / SECS_PER_DAY);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  Assert.AreEqual(9, LRem, 'Após janela expirar, deve restar 9 de 10');
end;

{ Chaves independentes }

procedure TRateLimitStateTests.DifferentKeys_AreIndependent;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FillBucket('ip1', 10, 60, 10);
  FState.CheckAndRecord('ip2', 10, 60, LRem, LReset, LExc);
  Assert.IsFalse(LExc, 'ip2 não deve ser afetado pelo limite de ip1');
  Assert.AreEqual(9, LRem, 'ip2 deve ter quota completa');
end;

{ ResetUnix }

procedure TRateLimitStateTests.ResetUnix_IsOldestEntryPlusWindow;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
  LExpected: Int64;
begin
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);
  LExpected := DateTimeToUnix(FT0 + 60 / SECS_PER_DAY, False);
  Assert.AreEqual(LExpected, LReset, 'ResetUnix deve ser T0 + WindowSeconds');
end;

procedure TRateLimitStateTests.ResetUnix_AdvancesAfterOldestExpires;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
  LReset2: Int64;
  T1: TDateTime;
begin
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset, LExc);

  T1 := FT0 + 10 / SECS_PER_DAY;
  FClock.SetTime(T1);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset2, LExc);
  Assert.AreEqual(LReset, LReset2,
    'ResetUnix deve apontar para a entrada mais antiga enquanto ela não expirar');

  FClock.SetTime(FT0 + 61 / SECS_PER_DAY);
  FState.CheckAndRecord('ip1', 10, 60, LRem, LReset2, LExc);
  Assert.IsTrue(LReset2 > LReset,
    'Após expirar a entrada mais antiga, ResetUnix deve avançar');
end;

{ Limite unitário }

procedure TRateLimitStateTests.SingleRequestLimit_FirstPasses_SecondBlocked;
var
  LRem: Integer; LReset: Int64; LExc: Boolean;
begin
  FState.CheckAndRecord('ip1', 1, 60, LRem, LReset, LExc);
  Assert.IsFalse(LExc, 'Primeira requisição com limite 1 deve passar');
  Assert.AreEqual(0, LRem);

  FState.CheckAndRecord('ip1', 1, 60, LRem, LReset, LExc);
  Assert.IsTrue(LExc, 'Segunda requisição com limite 1 deve ser bloqueada');
end;

initialization
  TDUnitX.RegisterTestFixture(TRateLimitStateTests);

end.
