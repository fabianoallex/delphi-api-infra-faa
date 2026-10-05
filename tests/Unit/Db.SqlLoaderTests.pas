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

    // Portados de pascal-db-faa 0.10.0 (16d1649): marcadores com espaços
    // opcionais nos dois lados, pareamento e erro para bloco malformado.

    (* ProcessTag: o fechamento aceita nenhum ou vários espaços, como a
       abertura: [}FILTRO], [}   FILTRO ] *)
    [Test] procedure Test_ProcessTag_EspacosNoFechamento_False;
    [Test] procedure Test_ProcessTag_EspacosNoFechamento_True;

    (* ProcessTag: espaços depois do colchete de abertura: [ FILTRO{] *)
    [Test] procedure Test_ProcessTag_EspacoAposColcheteDeAbertura;

    { ProcessTag: uma tag cujo nome começa com o de outra não é tocada }
    [Test] procedure Test_ProcessTag_TagDeNomeMaiorIntacta;

    { ProcessTag(False): remove cada bloco, nunca o SQL entre dois blocos }
    [Test] procedure Test_ProcessTag_MantemSqlEntreBlocos;

    { GetSQL: marcadores que sobraram saem com qualquer espaçamento }
    [Test] procedure Test_GetSQL_LimpaTagsResiduo_QualquerEspacamento;

    { ProcessTag: fechamento antes de qualquer abertura lança exceção (antes entrava em laço infinito) }
    [Test] procedure Test_ProcessTag_FechamentoAntesDaAbertura_Lanca;

    { ProcessTag: abertura sem fechamento lança exceção }
    [Test] procedure Test_ProcessTag_SemFechamento_Lanca;

    { ProcessTag: bloco aninhado em outro da mesma tag lança exceção }
    [Test] procedure Test_ProcessTag_Aninhado_Lanca;

    (* Caso real (api-test, PRODUTO.UPDATE.sql): "[NOME{] , NOME = :NOME [}NOME]"
       deixava as chaves no SQL e o FireDAC respondia com o erro -307 *)
    [Test] procedure Test_ProcessTag_UpdateSemEspacos_RemoveMarcadores;
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

// Mensagem da ESQLLoaderException que o ProcessTag lançou, ou '' se nenhuma.
function ProcessTagError(const ASql, ATag: string; AKeep: Boolean): string;
begin
  Result := '';
  try
    TSQLResult.From(ASql).ProcessTag(ATag, AKeep);
  except
    on E: ESQLLoaderException do
      Result := E.Message;
  end;
end;

procedure TSQLLoaderTests.Test_ProcessTag_EspacosNoFechamento_False;
begin
  Assert.AreEqual('W  X  Y',
    TSQLResult.From('W [FILTRO {]A[}FILTRO] X [FILTRO {]B[}   FILTRO ] Y')
      .ProcessTag('FILTRO', False).SQL,
    'ProcessTag(False) deve reconhecer fechamentos sem espaço ou com vários');
end;

procedure TSQLLoaderTests.Test_ProcessTag_EspacosNoFechamento_True;
begin
  Assert.AreEqual('W A X B Y',
    TSQLResult.From('W [FILTRO {]A[}FILTRO] X [FILTRO {]B[}   FILTRO ] Y')
      .ProcessTag('FILTRO', True).SQL,
    'ProcessTag(True) deve remover fechamentos sem espaço ou com vários');
end;

procedure TSQLLoaderTests.Test_ProcessTag_EspacoAposColcheteDeAbertura;
begin
  Assert.AreEqual('W A Y',
    TSQLResult.From('W [ FILTRO{]A[} FILTRO] Y').ProcessTag('FILTRO', True).SQL,
    'ProcessTag deve aceitar espaços entre [ e o nome da tag');
end;

procedure TSQLLoaderTests.Test_ProcessTag_TagDeNomeMaiorIntacta;
begin
  Assert.AreEqual('W A Y',
    TSQLResult.From('W [FILTRO_X {]A[} FILTRO_X] Y').ProcessTag('FILTRO', False).SQL,
    'ProcessTag(FILTRO) não pode mexer num bloco FILTRO_X');
end;

procedure TSQLLoaderTests.Test_ProcessTag_MantemSqlEntreBlocos;
begin
  Assert.AreEqual('W  X  Y',
    TSQLResult.From('W [F {]A[}F] X [F {]B[} F] Y').ProcessTag('F', False).SQL,
    'ProcessTag(False) deve manter o SQL entre dois blocos');
end;

procedure TSQLLoaderTests.Test_GetSQL_LimpaTagsResiduo_QualquerEspacamento;
begin
  Assert.AreEqual('W A X B Y',
    TSQLResult.From('W [FILTRO{]A[}FILTRO] X [ OUTRA  {]B[}  OUTRA ] Y').SQL,
    'GetSQL deve remover marcadores que sobraram, com qualquer espaçamento');
end;

procedure TSQLLoaderTests.Test_ProcessTag_FechamentoAntesDaAbertura_Lanca;
var
  LMessage: string;
begin
  LMessage := ProcessTagError('W [} F] X [F {]B[} F] Y', 'F', False);
  Assert.IsTrue(LMessage <> '', 'Fechamento antes de qualquer abertura deve lançar ESQLLoaderException');
  Assert.IsTrue(Pos('Tag SQL F:', LMessage) > 0, 'A mensagem deve citar a tag');
end;

procedure TSQLLoaderTests.Test_ProcessTag_SemFechamento_Lanca;
var
  LMessage: string;
begin
  LMessage := ProcessTagError('W [F {]A[} F] X [F {]B Y', 'F', True);
  Assert.IsTrue(LMessage <> '', 'Abertura sem fechamento deve lançar ESQLLoaderException');
  Assert.IsTrue(Pos('sem fechamento', LMessage) > 0, 'A mensagem deve dizer que falta o fechamento');
end;

procedure TSQLLoaderTests.Test_ProcessTag_Aninhado_Lanca;
var
  LMessage: string;
begin
  LMessage := ProcessTagError('W [F {]A [F {]B[} F] C[} F] Y', 'F', False);
  Assert.IsTrue(LMessage <> '', 'Bloco aninhado em outro da mesma tag deve lançar ESQLLoaderException');
  Assert.IsTrue(Pos('aninhado', LMessage) > 0, 'A mensagem deve dizer que o bloco está aninhado');
end;

procedure TSQLLoaderTests.Test_ProcessTag_UpdateSemEspacos_RemoveMarcadores;
const
  SQL_UPDATE = 'UPDATE PRODUTO SET ID = :ID [NOME{] , NOME = :NOME [}NOME] WHERE ID = :ID';
begin
  Assert.AreEqual('UPDATE PRODUTO SET ID = :ID  , NOME = :NOME  WHERE ID = :ID',
    TSQLResult.From(SQL_UPDATE).ProcessTag('NOME', True).SQL,
    'ProcessTag(True) deve tirar os dois marcadores, sem deixar chaves para o FireDAC');
  Assert.AreEqual('UPDATE PRODUTO SET ID = :ID  WHERE ID = :ID',
    TSQLResult.From(SQL_UPDATE).ProcessTag('NOME', False).SQL,
    'ProcessTag(False) deve tirar o bloco inteiro');
end;

initialization
  TDUnitX.RegisterTestFixture(TSQLLoaderTests);

end.
