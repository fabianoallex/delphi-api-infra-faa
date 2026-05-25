unit Common.PaginationTests;

{$CODEPAGE UTF8}

interface

uses
  DUnitX.TestFramework,
  Common.Pagination,
  Common.Optionals;

type
  [TestFixture]
  TPaginationTests = class
  public
    // --- TPageMeta ---

    [Test]
    procedure TotalPages_DivisaoExata;

    [Test]
    procedure TotalPages_ArredondaPraCima;

    [Test]
    procedure TotalPages_TotalZero_RetornaUm;

    [Test]
    procedure TotalPages_TotalMenorQueLimite_RetornaUm;

    [Test]
    procedure HasNext_VerdadeiroNasPrimeiras;

    [Test]
    procedure HasNext_FalsoNaUltimaPagina;

    [Test]
    procedure HasPrev_FalsoNaPrimeiraPagina;

    [Test]
    procedure HasPrev_VerdadeiroAPartirDaSegunda;

    [Test]
    procedure WrapJson_ContemChavesObrigatorias;

    [Test]
    procedure WrapJson_ValoresCorretos;

    // --- TPageParams ---

    [Test]
    procedure PageParams_UsaDefaults_QuandoNil;

    [Test]
    procedure PageParams_ValoresForneicidos;

    [Test]
    procedure PageParams_OffsetCalculadoCorretamente;

    [Test]
    procedure PageParams_ClampLimit_AcimaDoMax;

    [Test]
    procedure PageParams_ClampPage_AbaixoDe1;

    [Test]
    procedure PageParams_ClampLimit_AbaixoDe1;
  end;

implementation

uses
  System.SysUtils;

{ TPageMeta helpers }

function MakeMeta(APage, ALimit, ATotal: Integer): TPageMeta;
begin
  Result.Page  := APage;
  Result.Limit := ALimit;
  Result.Total := ATotal;
end;

{ TotalPages }

procedure TPaginationTests.TotalPages_DivisaoExata;
begin
  Assert.AreEqual(2, MakeMeta(1, 10, 20).TotalPages);
end;

procedure TPaginationTests.TotalPages_ArredondaPraCima;
begin
  Assert.AreEqual(3, MakeMeta(1, 10, 21).TotalPages);
  Assert.AreEqual(3, MakeMeta(1, 10, 29).TotalPages);
end;

procedure TPaginationTests.TotalPages_TotalZero_RetornaUm;
begin
  Assert.AreEqual(1, MakeMeta(1, 10, 0).TotalPages);
end;

procedure TPaginationTests.TotalPages_TotalMenorQueLimite_RetornaUm;
begin
  Assert.AreEqual(1, MakeMeta(1, 20, 5).TotalPages);
end;

{ HasNext / HasPrev }

procedure TPaginationTests.HasNext_VerdadeiroNasPrimeiras;
begin
  Assert.IsTrue(MakeMeta(1, 10, 30).HasNext);  // page 1 de 3
  Assert.IsTrue(MakeMeta(2, 10, 30).HasNext);  // page 2 de 3
end;

procedure TPaginationTests.HasNext_FalsoNaUltimaPagina;
begin
  Assert.IsFalse(MakeMeta(3, 10, 30).HasNext);  // page 3 de 3
  Assert.IsFalse(MakeMeta(1, 10,  5).HasNext);  // única página
end;

procedure TPaginationTests.HasPrev_FalsoNaPrimeiraPagina;
begin
  Assert.IsFalse(MakeMeta(1, 10, 30).HasPrev);
end;

procedure TPaginationTests.HasPrev_VerdadeiroAPartirDaSegunda;
begin
  Assert.IsTrue(MakeMeta(2, 10, 30).HasPrev);
  Assert.IsTrue(MakeMeta(5, 10, 50).HasPrev);
end;

{ WrapJson }

procedure TPaginationTests.WrapJson_ContemChavesObrigatorias;
var
  LJson: string;
begin
  LJson := MakeMeta(1, 10, 5).WrapJson('[]');
  Assert.IsTrue(LJson.Contains('"page"'));
  Assert.IsTrue(LJson.Contains('"limit"'));
  Assert.IsTrue(LJson.Contains('"total"'));
  Assert.IsTrue(LJson.Contains('"totalPages"'));
  Assert.IsTrue(LJson.Contains('"hasNext"'));
  Assert.IsTrue(LJson.Contains('"hasPrev"'));
  Assert.IsTrue(LJson.Contains('"items"'));
end;

procedure TPaginationTests.WrapJson_ValoresCorretos;
var
  LJson: string;
begin
  LJson := MakeMeta(2, 10, 25).WrapJson('[1,2]');
  Assert.IsTrue(LJson.Contains('"page":2'));
  Assert.IsTrue(LJson.Contains('"limit":10'));
  Assert.IsTrue(LJson.Contains('"total":25'));
  Assert.IsTrue(LJson.Contains('"totalPages":3'));
  Assert.IsTrue(LJson.Contains('"hasNext":true'));
  Assert.IsTrue(LJson.Contains('"hasPrev":true'));
  Assert.IsTrue(LJson.Contains('"items":[1,2]'));
end;

{ TPageParams }

procedure TPaginationTests.PageParams_UsaDefaults_QuandoNil;
var
  P: TPageParams;
begin
  P := TPageParams.From(nil, nil);
  Assert.AreEqual(PAGE_DEFAULT,  P.Page);
  Assert.AreEqual(LIMIT_DEFAULT, P.Limit);
end;

procedure TPaginationTests.PageParams_ValoresForneicidos;
var
  P: TPageParams;
begin
  P := TPageParams.From(TOptNullInteger.From(3), TOptNullInteger.From(15));
  Assert.AreEqual(3,  P.Page);
  Assert.AreEqual(15, P.Limit);
end;

procedure TPaginationTests.PageParams_OffsetCalculadoCorretamente;
var
  P: TPageParams;
begin
  P := TPageParams.From(TOptNullInteger.From(3), TOptNullInteger.From(10));
  Assert.AreEqual(20, P.Offset);  // (3-1) * 10

  P := TPageParams.From(TOptNullInteger.From(1), TOptNullInteger.From(20));
  Assert.AreEqual(0, P.Offset);   // (1-1) * 20
end;

procedure TPaginationTests.PageParams_ClampLimit_AcimaDoMax;
var
  P: TPageParams;
begin
  P := TPageParams.From(nil, TOptNullInteger.From(LIMIT_MAX + 1));
  Assert.AreEqual(LIMIT_MAX, P.Limit);
end;

procedure TPaginationTests.PageParams_ClampPage_AbaixoDe1;
var
  P: TPageParams;
begin
  P := TPageParams.From(TOptNullInteger.From(0), nil);
  Assert.AreEqual(PAGE_DEFAULT, P.Page);
end;

procedure TPaginationTests.PageParams_ClampLimit_AbaixoDe1;
var
  P: TPageParams;
begin
  P := TPageParams.From(nil, TOptNullInteger.From(0));
  Assert.AreEqual(LIMIT_DEFAULT, P.Limit);
end;

end.
