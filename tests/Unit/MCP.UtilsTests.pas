unit MCP.UtilsTests;

{$CODEPAGE UTF8}

interface

uses
  DUnitX.TestFramework,
  MCP.Utils;

type
  [TestFixture]
  TMcpUtilsTests = class
  public
    // --- McpDeriveName ---

    [Test]
    procedure DeriveName_GET_SemId_ListRecurso;

    [Test]
    procedure DeriveName_GET_ComId_GetRecurso;

    [Test]
    procedure DeriveName_POST_CreateRecurso;

    [Test]
    procedure DeriveName_PATCH_UpdateRecurso;

    [Test]
    procedure DeriveName_PUT_UpdateRecurso;

    [Test]
    procedure DeriveName_DELETE_DeleteRecurso;

    [Test]
    procedure DeriveName_UsoUltimoSegmentoDoPath;

    [Test]
    procedure DeriveName_HifenViraUnderscore;

    [Test]
    procedure DeriveName_CaseInsensitiveNoMetodo;

    [Test]
    procedure DeriveName_PluralRemoveS;

    // --- McpMatchesTags ---

    [Test]
    procedure MatchesTags_FilterNil_SempreTrue;

    [Test]
    procedure MatchesTags_FilterVazio_SempreTrue;

    [Test]
    procedure MatchesTags_TagEncontrada_True;

    [Test]
    procedure MatchesTags_TagNaoEncontrada_False;

    [Test]
    procedure MatchesTags_OpSemTags_ComFiltro_False;

    [Test]
    procedure MatchesTags_MultiplasTagsOp_UmaCoincide_True;
  end;

implementation

uses
  System.Classes;

{ McpDeriveName }

procedure TMcpUtilsTests.DeriveName_GET_SemId_ListRecurso;
begin
  Assert.AreEqual('list_produto',  McpDeriveName('GET', '/produtos'));
  Assert.AreEqual('list_cidade',   McpDeriveName('GET', '/cidades'));
end;

procedure TMcpUtilsTests.DeriveName_GET_ComId_GetRecurso;
begin
  Assert.AreEqual('get_produto', McpDeriveName('GET', '/produtos/{id}'));
  Assert.AreEqual('get_cidade',  McpDeriveName('GET', '/cidades/{cod_ibge}'));
end;

procedure TMcpUtilsTests.DeriveName_POST_CreateRecurso;
begin
  Assert.AreEqual('create_produto', McpDeriveName('POST', '/produtos'));
end;

procedure TMcpUtilsTests.DeriveName_PATCH_UpdateRecurso;
begin
  Assert.AreEqual('update_produto', McpDeriveName('PATCH', '/produtos/{id}'));
end;

procedure TMcpUtilsTests.DeriveName_PUT_UpdateRecurso;
begin
  Assert.AreEqual('update_produto', McpDeriveName('PUT', '/produtos/{id}'));
end;

procedure TMcpUtilsTests.DeriveName_DELETE_DeleteRecurso;
begin
  Assert.AreEqual('delete_produto', McpDeriveName('DELETE', '/produtos/{id}'));
end;

procedure TMcpUtilsTests.DeriveName_UsoUltimoSegmentoDoPath;
begin
  // Ignora segmentos de versão/prefixo; usa o último não-parametrizado
  Assert.AreEqual('list_produto', McpDeriveName('GET', '/v1/api/produtos'));
end;

procedure TMcpUtilsTests.DeriveName_HifenViraUnderscore;
begin
  // Hifens no segmento são trocados por underscore
  Assert.AreEqual('list_meu_recurso', McpDeriveName('GET', '/meus-recursos'));
end;

procedure TMcpUtilsTests.DeriveName_CaseInsensitiveNoMetodo;
begin
  Assert.AreEqual('list_produto',   McpDeriveName('get',    '/produtos'));
  Assert.AreEqual('create_produto', McpDeriveName('post',   '/produtos'));
  Assert.AreEqual('update_produto', McpDeriveName('patch',  '/produtos/{id}'));
  Assert.AreEqual('delete_produto', McpDeriveName('delete', '/produtos/{id}'));
end;

procedure TMcpUtilsTests.DeriveName_PluralRemoveS;
begin
  // Plural em "s" é removido para gerar o nome singular da tool
  Assert.AreEqual('list_cidade',  McpDeriveName('GET', '/cidades'));
  Assert.AreEqual('list_produto', McpDeriveName('GET', '/produtos'));
  Assert.AreEqual('list_pedido',  McpDeriveName('GET', '/pedidos'));
end;

{ McpMatchesTags }

procedure TMcpUtilsTests.MatchesTags_FilterNil_SempreTrue;
begin
  Assert.IsTrue(McpMatchesTags(['cidades', 'admin'], nil));
  Assert.IsTrue(McpMatchesTags([], nil));
end;

procedure TMcpUtilsTests.MatchesTags_FilterVazio_SempreTrue;
var
  LFilter: TStringList;
begin
  LFilter := TStringList.Create;
  try
    Assert.IsTrue(McpMatchesTags(['cidades'], LFilter));
    Assert.IsTrue(McpMatchesTags([], LFilter));
  finally
    LFilter.Free;
  end;
end;

procedure TMcpUtilsTests.MatchesTags_TagEncontrada_True;
var
  LFilter: TStringList;
begin
  LFilter := TStringList.Create;
  try
    LFilter.Add('cidades');
    Assert.IsTrue(McpMatchesTags(['cidades'], LFilter));
  finally
    LFilter.Free;
  end;
end;

procedure TMcpUtilsTests.MatchesTags_TagNaoEncontrada_False;
var
  LFilter: TStringList;
begin
  LFilter := TStringList.Create;
  try
    LFilter.Add('cidades');
    Assert.IsFalse(McpMatchesTags(['produtos'], LFilter));
  finally
    LFilter.Free;
  end;
end;

procedure TMcpUtilsTests.MatchesTags_OpSemTags_ComFiltro_False;
var
  LFilter: TStringList;
begin
  LFilter := TStringList.Create;
  try
    LFilter.Add('cidades');
    Assert.IsFalse(McpMatchesTags([], LFilter));
  finally
    LFilter.Free;
  end;
end;

procedure TMcpUtilsTests.MatchesTags_MultiplasTagsOp_UmaCoincide_True;
var
  LFilter: TStringList;
begin
  LFilter := TStringList.Create;
  try
    LFilter.Add('admin');
    Assert.IsTrue(McpMatchesTags(['cidades', 'admin', 'geo'], LFilter));
  finally
    LFilter.Free;
  end;
end;

end.
