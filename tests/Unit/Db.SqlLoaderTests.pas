unit Db.SqlLoaderTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Db.SqlLoader;

type
  [TestFixture]
  TSQLLoaderTests = class
  public
    { ProcessTag: remove o bloco quando Keep=False }
    [Test] procedure Test_ProcessTag_False_RemoveBloco;

    { ProcessTag: mantém o conteúdo e remove apenas as tags quando Keep=True }
    [Test] procedure Test_ProcessTag_True_MantemConteudo;

    { GetSQL: tags não processadas são removidas automaticamente }
    [Test] procedure Test_GetSQL_LimpaTagsResiduo;

    { ProcessTag: mesma tag aparecendo duas vezes no SQL }
    [Test] procedure Test_ProcessTag_DuasVezes_Keep;

    { GetSQL: tag COMMENTS é sempre removida }
    [Test] procedure Test_GetSQL_ComentarioRemovido;

    { ProcessTag: tag de abertura com múltiplos espaços, Keep=False }
    [Test] procedure Test_ProcessTag_MultiEspacos_False;

    { ProcessTag: tag de abertura com múltiplos espaços, Keep=True }
    [Test] procedure Test_ProcessTag_MultiEspacos_True;

    (* ReplaceLiteral: substitui ${TAG} pelo valor fornecido *)
    [Test] procedure Test_ReplaceLiteral_Simples;

    (* ApplyOperator: substitui ${TAG_OP} pelo operador *)
    [Test] procedure Test_ApplyOperator;

    { ApplyFilter: combina ProcessTag + ReplaceLiteral quando HasValue=True }
    [Test] procedure Test_ApplyFilter_ComValor;

    { ApplyFilter: remove o bloco quando HasValue=False }
    [Test] procedure Test_ApplyFilter_SemValor;
  end;

implementation

const
  SQL_TAGS =
    'SELECT * FROM CLIENTES WHERE 1=1 [FILTRO {]AND ATIVO = ''S''[} FILTRO]';

  SQL_TAGS_MULTISPACE =
    'SELECT * FROM CLIENTES WHERE 1=1 [FILTRO    {]AND ATIVO = ''S''[} FILTRO]';

  SQL_MESMA_TAG_DUAS_VEZES =
    'SELECT * FROM CLIENTES WHERE 1=1 [FILTRO {] AND 2=2 [} FILTRO] [FILTRO {] AND 3=3 [} FILTRO]';

  SQL_COMMENTS =
    'SELECT * FROM CLIENTES [COMMENTS {] Isso e um comentario [} COMMENTS]';

  SQL_LITERAL =
    'SELECT * FROM ${TABELA} WHERE CAMPO ${CAMPO_OP} :CAMPO';

{ TSQLLoaderTests }

procedure TSQLLoaderTests.Test_ProcessTag_False_RemoveBloco;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_TAGS).ProcessTag('FILTRO', False).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1',
    Trim(LResult),
    'ProcessTag(False) deve remover o bloco completamente'
  );
end;

procedure TSQLLoaderTests.Test_ProcessTag_True_MantemConteudo;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_TAGS).ProcessTag('FILTRO', True).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1 AND ATIVO = ''S''',
    Trim(LResult),
    'ProcessTag(True) deve manter o conteúdo e remover as tags'
  );
end;

procedure TSQLLoaderTests.Test_GetSQL_LimpaTagsResiduo;
var
  LResult: string;
begin
  // Sem chamar ProcessTag: GetSQL deve remover as tags residuais mantendo o conteúdo
  LResult := TSQLResult.From(SQL_TAGS).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1 AND ATIVO = ''S''',
    Trim(LResult),
    'GetSQL deve limpar tags não processadas, mantendo o conteúdo'
  );
end;

procedure TSQLLoaderTests.Test_ProcessTag_DuasVezes_Keep;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_MESMA_TAG_DUAS_VEZES)
    .ProcessTag('FILTRO', True)
    .SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1  AND 2=2   AND 3=3',
    Trim(LResult),
    'ProcessTag(True) deve processar todas as ocorrências da mesma tag'
  );
end;

procedure TSQLLoaderTests.Test_GetSQL_ComentarioRemovido;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_COMMENTS).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES',
    Trim(LResult),
    'Bloco COMMENTS deve ser automaticamente removido por GetSQL'
  );
end;

procedure TSQLLoaderTests.Test_ProcessTag_MultiEspacos_False;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_TAGS_MULTISPACE).ProcessTag('FILTRO', False).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1',
    Trim(LResult),
    'ProcessTag(False) deve reconhecer tags com espaços extras antes do {]'
  );
end;

procedure TSQLLoaderTests.Test_ProcessTag_MultiEspacos_True;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_TAGS_MULTISPACE).ProcessTag('FILTRO', True).SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1 AND ATIVO = ''S''',
    Trim(LResult),
    'ProcessTag(True) deve manter conteúdo mesmo com espaços extras na tag de abertura'
  );
end;

procedure TSQLLoaderTests.Test_ReplaceLiteral_Simples;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_LITERAL)
    .ReplaceLiteral('TABELA', 'TB_CLIENTES')
    .SQL;
  Assert.IsTrue(
    Pos('TB_CLIENTES', LResult) > 0,
    'ReplaceLiteral deve substituir ${TABELA} por TB_CLIENTES'
  );
  Assert.IsTrue(
    Pos('${TABELA}', LResult) = 0,
    'Marcador ${TABELA} não deve mais existir após ReplaceLiteral'
  );
end;

procedure TSQLLoaderTests.Test_ApplyOperator;
var
  LResult: string;
begin
  LResult := TSQLResult.From(SQL_LITERAL)
    .ApplyOperator('CAMPO', '=')
    .SQL;
  Assert.IsTrue(
    Pos('${CAMPO_OP}', LResult) = 0,
    'ApplyOperator deve substituir ${CAMPO_OP}'
  );
  Assert.IsTrue(
    Pos('= :CAMPO', LResult) > 0,
    'Operador = deve ter sido inserido'
  );
end;

procedure TSQLLoaderTests.Test_ApplyFilter_ComValor;
var
  LResult: string;
begin
  // HasValue=True: mantém o bloco e substitui o operador
  LResult := TSQLResult.From(SQL_TAGS)
    .ApplyFilter('FILTRO', '=', True)
    .SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1 AND ATIVO = ''S''',
    Trim(LResult),
    'ApplyFilter(True) deve manter o bloco FILTRO'
  );
end;

procedure TSQLLoaderTests.Test_ApplyFilter_SemValor;
var
  LResult: string;
begin
  // HasValue=False: remove o bloco completamente
  LResult := TSQLResult.From(SQL_TAGS)
    .ApplyFilter('FILTRO', '=', False)
    .SQL;
  Assert.AreEqual(
    'SELECT * FROM CLIENTES WHERE 1=1',
    Trim(LResult),
    'ApplyFilter(False) deve remover o bloco FILTRO'
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TSQLLoaderTests);

end.
