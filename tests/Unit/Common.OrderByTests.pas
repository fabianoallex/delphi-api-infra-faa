unit Common.OrderByTests;

interface

uses
  DUnitX.TestFramework,
  Common.OrderBy;

type
  [TestFixture]
  TOrderByTests = class
  private
    function Spec: TOrderBySpec;
  public
    [Test]
    procedure Build_CampoValido_ASC;

    [Test]
    procedure Build_CampoValido_DESC;

    [Test]
    procedure Build_MultiplosCampos;

    [Test]
    procedure Build_UsaDefault_QuandoVazio;

    [Test]
    procedure Build_CampoInvalido_LevantaExcecao;

    [Test]
    procedure Build_CampoInvalido_MensagemListaCamposPermitidos;

    [Test]
    procedure Build_TiebreakerApareceAoFinal;

    [Test]
    procedure Build_CaseInsensitiveNoCampo;

    [Test]
    procedure Build_SemDefaultNemTiebreaker_LevantaExcecao;

    [Test]
    procedure Build_DefaultDesc;

    [Test]
    procedure DocHint_TiebreakerUsaNomeCliente;

    [Test]
    procedure DocHint_NaoExpoeColunaSQL;

    [Test]
    procedure DocHint_ListaCamposDisponiveis;

    [Test]
    procedure DocHint_MostraDefault;
  end;

implementation

uses
  System.SysUtils;

// Spec padrão reutilizado nos testes:
//   campos: nome→NOME, codIbge→COD_IBGE, uf→UF
//   default: nome
//   tiebreaker: COD_IBGE ASC
function TOrderByTests.Spec: TOrderBySpec;
begin
  Result := TOrderBySpec.New
    .Allow('nome',    'NOME')
    .Allow('codIbge', 'COD_IBGE')
    .Allow('uf',      'UF')
    .Default('nome')
    .AlwaysLast('COD_IBGE');
end;

procedure TOrderByTests.Build_CampoValido_ASC;
begin
  Assert.AreEqual('NOME ASC, COD_IBGE ASC', Spec.Build('nome'));
end;

procedure TOrderByTests.Build_CampoValido_DESC;
begin
  Assert.AreEqual('NOME DESC, COD_IBGE ASC', Spec.Build('-nome'));
end;

procedure TOrderByTests.Build_MultiplosCampos;
begin
  Assert.AreEqual('UF ASC, NOME DESC, COD_IBGE ASC', Spec.Build('uf,-nome'));
end;

procedure TOrderByTests.Build_UsaDefault_QuandoVazio;
begin
  Assert.AreEqual('NOME ASC, COD_IBGE ASC', Spec.Build(''));
end;

procedure TOrderByTests.Build_CampoInvalido_LevantaExcecao;
begin
  Assert.WillRaise(
    procedure begin Spec.Build('invalido') end,
    EOrderByException);
end;

procedure TOrderByTests.Build_CampoInvalido_MensagemListaCamposPermitidos;
var
  LMsg: string;
begin
  LMsg := '';
  try
    Spec.Build('invalido');
  except
    on E: EOrderByException do LMsg := E.Message;
  end;
  Assert.IsTrue(LMsg.Contains('nome'),    'Mensagem deve listar "nome"');
  Assert.IsTrue(LMsg.Contains('codIbge'), 'Mensagem deve listar "codIbge"');
  Assert.IsTrue(LMsg.Contains('uf'),      'Mensagem deve listar "uf"');
end;

procedure TOrderByTests.Build_TiebreakerApareceAoFinal;
var
  LResult: string;
begin
  LResult := Spec.Build('uf');
  Assert.AreEqual('UF ASC, COD_IBGE ASC', LResult);
  // tiebreaker é o último fragmento
  Assert.IsTrue(LResult.EndsWith('COD_IBGE ASC'));
end;

procedure TOrderByTests.Build_CaseInsensitiveNoCampo;
begin
  // TryFind usa SameText — maiúsculas e minúsculas devem funcionar igual
  Assert.AreEqual('NOME ASC, COD_IBGE ASC', Spec.Build('NOME'));
  Assert.AreEqual('UF DESC, COD_IBGE ASC',  Spec.Build('-UF'));
end;

procedure TOrderByTests.Build_SemDefaultNemTiebreaker_LevantaExcecao;
var
  LSpec: TOrderBySpec;
begin
  LSpec := TOrderBySpec.New.Allow('nome', 'NOME');
  Assert.WillRaise(
    procedure begin LSpec.Build('') end,
    Exception);
end;

procedure TOrderByTests.Build_DefaultDesc;
var
  LSpec: TOrderBySpec;
begin
  LSpec := TOrderBySpec.New
    .Allow('nome', 'NOME')
    .Default('-nome');
  Assert.AreEqual('NOME DESC', LSpec.Build(''));
end;

procedure TOrderByTests.DocHint_TiebreakerUsaNomeCliente;
var
  LHint: string;
begin
  LHint := Spec.DocHint;
  Assert.IsTrue(LHint.Contains('codIbge ASC'),
    'Tiebreaker deve usar o nome cliente "codIbge"');
end;

procedure TOrderByTests.DocHint_NaoExpoeColunaSQL;
var
  LHint: string;
begin
  LHint := Spec.DocHint;
  // COD_IBGE é o nome SQL interno — não deve aparecer no hint
  Assert.IsFalse(LHint.Contains('COD_IBGE'),
    'DocHint não deve expor nomes de colunas SQL');
end;

procedure TOrderByTests.DocHint_ListaCamposDisponiveis;
var
  LHint: string;
begin
  LHint := Spec.DocHint;
  Assert.IsTrue(LHint.Contains('nome'));
  Assert.IsTrue(LHint.Contains('codIbge'));
  Assert.IsTrue(LHint.Contains('uf'));
end;

procedure TOrderByTests.DocHint_MostraDefault;
var
  LHint: string;
begin
  LHint := Spec.DocHint;
  Assert.IsTrue(LHint.Contains('nome'), 'Default deve aparecer no hint');
end;

end.
