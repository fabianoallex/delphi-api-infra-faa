unit Db.MockTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Variants,
  Common.Optionals,
  Db.Interfaces,
  Db.SqlLoader,
  Db.Mock;

type
  [TestFixture]
  TMockQueryResultTests = class
  public
    [Test] procedure Empty_IsEmpty_True;
    [Test] procedure Empty_Eof_True;
    [Test] procedure SingleRow_IsEmpty_False;
    [Test] procedure SingleRow_FieldCount;
    [Test] procedure SingleRow_ReadValues;
    [Test] procedure SingleRow_Eof_AfterNext;
    [Test] procedure MultiRows_RecordCount;
    [Test] procedure MultiRows_CursorNavigation;
    [Test] procedure MultiRows_GetNullableString_Null;
    [Test] procedure MultiRows_ColumnNameCaseInsensitive;
    [Test] procedure UnknownColumn_Raises;
  end;

  [TestFixture]
  TMockParamsTests = class
  public
    [Test] procedure SetGetString;
    [Test] procedure SetGetInteger;
    [Test] procedure SetGetInt64;
    [Test] procedure SetGetBoolean;
    [Test] procedure SetGetCurrency;
    [Test] procedure SetGetDateTime;
    [Test] procedure SetOptString_HasValue_Stores;
    [Test] procedure SetOptString_Undefined_DoesNotStore;
    [Test] procedure SetNullString_Null_StoresNull;
    [Test] procedure SetNullString_WithValue_Stores;
    [Test] procedure SetOptNullString_Undefined_DoesNotStore;
    [Test] procedure SetOptNullString_Null_StoresNull;
    [Test] procedure SetOptNullString_WithValue_Stores;
    [Test] procedure KeyNormalization_CaseInsensitive;
  end;

  [TestFixture]
  TMockSQLLoaderTests = class
  public
    [Test] procedure GetSql_ReturnsKeyAsSQL;
    [Test] procedure GetSql_ReplaceLiteralNoOp;
    [Test] procedure GetSql_ProcessTagNoOp;
  end;

  [TestFixture]
  TMockDBFactoryTests = class
  public
    [Test] procedure AddResult_OpenReturnsConfiguredResult;
    [Test] procedure Open_NoResultConfigured_Raises;
    [Test] procedure ExecSql_RecordsExecution;
    [Test] procedure Open_RecordsExecution_WasOpen_True;
    [Test] procedure ExecSql_WasOpen_False;
    [Test] procedure ExecutionCount_MultipleCalls;
    [Test] procedure LastExecution_ReturnsLast;
    [Test] procedure LastExecution_UnknownKey_ReturnsNil;
    [Test] procedure RecordExecution_CapturesParams;
    [Test] procedure SqlLoader_ReturnsMockLoader;
    [Test] procedure TestConnection_ReturnsTrue;
    [Test] procedure AcquireQuery_ReturnsQuery;
  end;

implementation

{ TMockQueryResultTests }

procedure TMockQueryResultTests.Empty_IsEmpty_True;
begin
  Assert.IsTrue(TMockQueryResult.Empty.IsEmpty, 'Empty deve ser IsEmpty=True');
end;

procedure TMockQueryResultTests.Empty_Eof_True;
begin
  Assert.IsTrue(TMockQueryResult.Empty.Eof, 'Empty deve ser Eof=True imediatamente');
end;

procedure TMockQueryResultTests.SingleRow_IsEmpty_False;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['ID'], [42]);
  Assert.IsFalse(R.IsEmpty, 'SingleRow não deve ser IsEmpty');
end;

procedure TMockQueryResultTests.SingleRow_FieldCount;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['ID', 'NOME', 'ATIVO'], [1, 'Teste', True]);
  Assert.AreEqual(3, R.FieldCount, 'FieldCount deve ser 3');
end;

procedure TMockQueryResultTests.SingleRow_ReadValues;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['ID', 'NOME'], [7, 'São Paulo']);
  Assert.AreEqual(7,          R.GetAsInteger('ID'),   'ID deve ser 7');
  Assert.AreEqual('São Paulo', R.GetAsString('NOME'),  'NOME deve ser São Paulo');
end;

procedure TMockQueryResultTests.SingleRow_Eof_AfterNext;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['ID'], [1]);
  Assert.IsFalse(R.Eof, 'Não deve ser Eof antes de Next');
  R.Next;
  Assert.IsTrue(R.Eof, 'Deve ser Eof após Next na única linha');
end;

procedure TMockQueryResultTests.MultiRows_RecordCount;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.MultiRows(
    ['ID', 'NOME'],
    [TArray<Variant>.Create(1, 'Alpha'),
     TArray<Variant>.Create(2, 'Beta'),
     TArray<Variant>.Create(3, 'Gamma')]);
  Assert.AreEqual(3, R.RecordCount, 'RecordCount deve ser 3');
end;

procedure TMockQueryResultTests.MultiRows_CursorNavigation;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.MultiRows(
    ['ID'],
    [TArray<Variant>.Create(10),
     TArray<Variant>.Create(20)]);
  Assert.AreEqual(10, R.GetAsInteger('ID'), 'Cursor na linha 0 deve retornar 10');
  R.Next;
  Assert.AreEqual(20, R.GetAsInteger('ID'), 'Cursor na linha 1 deve retornar 20');
  R.Next;
  Assert.IsTrue(R.Eof, 'Após 2 nexts deve ser Eof');
end;

procedure TMockQueryResultTests.MultiRows_GetNullableString_Null;
var
  R: IQueryResult;
  V: INullString;
begin
  R := TMockQueryResult.SingleRow(['NOME'], [Null]);
  V := R.GetNullableString('NOME');
  Assert.IsTrue(V.IsNull, 'Variant Null deve retornar INullString.IsNull=True');
end;

procedure TMockQueryResultTests.MultiRows_ColumnNameCaseInsensitive;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['nome'], ['Valor']);
  Assert.AreEqual('Valor', R.GetAsString('NOME'), 'Coluna deve ser acessível em maiúsculas');
  Assert.AreEqual('Valor', R.GetAsString('nome'), 'Coluna deve ser acessível em minúsculas');
end;

procedure TMockQueryResultTests.UnknownColumn_Raises;
var
  R: IQueryResult;
begin
  R := TMockQueryResult.SingleRow(['ID'], [1]);
  Assert.WillRaise(
    procedure begin R.GetAsString('INEXISTENTE'); end,
    Exception,
    'Coluna inexistente deve lançar exceção');
end;

{ TMockParamsTests }

procedure TMockParamsTests.SetGetString;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetString('NOME', 'Fabiano');
  Assert.AreEqual('Fabiano', P.GetString('NOME'));
end;

procedure TMockParamsTests.SetGetInteger;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetInteger('ID', 42);
  Assert.AreEqual(42, P.GetInteger('ID'));
end;

procedure TMockParamsTests.SetGetInt64;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetInt64('BIG', 9999999999);
  Assert.AreEqual(Int64(9999999999), P.GetInt64('BIG'));
end;

procedure TMockParamsTests.SetGetBoolean;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetBoolean('ATIVO', True);
  Assert.IsTrue(P.GetBoolean('ATIVO'));
end;

procedure TMockParamsTests.SetGetCurrency;
var
  P: IParams;
  V: Currency;
begin
  P := TMockParams.Create;
  P.SetCurrency('PRECO', 19.99);
  V := P.GetCurrency('PRECO');
  Assert.AreEqual(Currency(19.99), V, 'Valor Currency deve ser preservado');
end;

procedure TMockParamsTests.SetGetDateTime;
var
  P: IParams;
  D: TDateTime;
begin
  P := TMockParams.Create;
  D := EncodeDate(2025, 5, 26);
  P.SetDateTime('DT', D);
  Assert.AreEqual(D, P.GetDateTime('DT'), 'TDateTime deve ser preservado');
end;

procedure TMockParamsTests.SetOptString_HasValue_Stores;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetOptString('CAMPO', TOptNullString.From('ok'));
  Assert.AreEqual('ok', P.GetOptString('CAMPO').Value);
end;

procedure TMockParamsTests.SetOptString_Undefined_DoesNotStore;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetOptString('CAMPO', TOptNullString.Undefined);
  Assert.IsFalse(P.GetOptString('CAMPO').HasValue, 'Undefined não deve ser armazenado');
end;

procedure TMockParamsTests.SetNullString_Null_StoresNull;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetNullString('CAMPO', TOptNullString.Null);
  Assert.IsTrue(P.GetNullString('CAMPO').IsNull, 'Null deve ser armazenado como IsNull=True');
end;

procedure TMockParamsTests.SetNullString_WithValue_Stores;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetNullString('CAMPO', TOptNullString.From('texto'));
  Assert.AreEqual('texto', P.GetNullString('CAMPO').Value);
end;

procedure TMockParamsTests.SetOptNullString_Undefined_DoesNotStore;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetOptNullString('CAMPO', TOptNullString.Undefined);
  Assert.IsFalse(P.GetOptNullString('CAMPO').HasValue, 'Undefined não deve ser armazenado');
end;

procedure TMockParamsTests.SetOptNullString_Null_StoresNull;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetOptNullString('CAMPO', TOptNullString.Null);
  Assert.IsTrue(P.GetOptNullString('CAMPO').IsNull, 'OptNull Null deve ser armazenado');
end;

procedure TMockParamsTests.SetOptNullString_WithValue_Stores;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetOptNullString('CAMPO', TOptNullString.From('valor'));
  Assert.AreEqual('valor', P.GetOptNullString('CAMPO').Value);
end;

procedure TMockParamsTests.KeyNormalization_CaseInsensitive;
var
  P: IParams;
begin
  P := TMockParams.Create;
  P.SetString('nome', 'x');
  Assert.AreEqual('x', P.GetString('NOME'), 'Chave deve ser case-insensitive');
  Assert.AreEqual('x', P.GetString('Nome'), 'Chave deve ser case-insensitive');
end;

{ TMockSQLLoaderTests }

procedure TMockSQLLoaderTests.GetSql_ReturnsKeyAsSQL;
var
  L: TMockSQLLoader;
  S: TSQLResult;
begin
  L := TMockSQLLoader.Create;
  try
    S := L.Sql['PEDIDO.FIND'];
    Assert.AreEqual('PEDIDO.FIND', S.SQL, 'TMockSQLLoader deve retornar o nome da chave como SQL');
  finally
    L.Free;
  end;
end;

procedure TMockSQLLoaderTests.GetSql_ReplaceLiteralNoOp;
var
  L: TMockSQLLoader;
  S: string;
begin
  L := TMockSQLLoader.Create;
  try
    S := L.Sql['PEDIDO.FIND'].ReplaceLiteral('LIMIT', '20').SQL;
    Assert.AreEqual('PEDIDO.FIND', S,
      'ReplaceLiteral sem ${...} no nome da chave não deve alterar nada');
  finally
    L.Free;
  end;
end;

procedure TMockSQLLoaderTests.GetSql_ProcessTagNoOp;
var
  L: TMockSQLLoader;
  S: string;
begin
  L := TMockSQLLoader.Create;
  try
    S := L.Sql['PEDIDO.FIND'].ProcessTag('SEARCH', True).SQL;
    Assert.AreEqual('PEDIDO.FIND', S,
      'ProcessTag sem tags no nome da chave não deve alterar nada');
  finally
    L.Free;
  end;
end;

{ TMockDBFactoryTests }

procedure TMockDBFactoryTests.AddResult_OpenReturnsConfiguredResult;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
  R: IQueryResult;
begin
  F := TMockDBFactory.Create;
  try
    F.AddResult('CIDADE.FIND', TMockQueryResult.SingleRow(['TOTAL'], [5]));
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('CIDADE.FIND');
    R := Q.Open;
    Assert.IsNotNull(R, 'Open deve retornar IQueryResult configurado');
    Assert.AreEqual(5, R.GetAsInteger('TOTAL'));
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.Open_NoResultConfigured_Raises;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('NAO.EXISTE');
    Assert.WillRaise(
      procedure begin Q.Open; end,
      Exception,
      'Open sem AddResult deve lançar exceção descritiva');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.ExecSql_RecordsExecution;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('CIDADE.INSERT');
    Q.Params.SetString('NOME', 'Curitiba');
    Q.ExecSql;
    Assert.AreEqual(1, F.ExecutionCount('CIDADE.INSERT'), 'ExecSql deve registrar 1 execução');
    Assert.AreEqual('Curitiba', F.LastExecution('CIDADE.INSERT').AsString('NOME'));
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.Open_RecordsExecution_WasOpen_True;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    F.AddResult('X.FIND', TMockQueryResult.Empty);
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('X.FIND');
    Q.Open;
    Assert.IsTrue(F.LastExecution('X.FIND').WasOpen, 'Open deve registrar WasOpen=True');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.ExecSql_WasOpen_False;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('X.DEL');
    Q.ExecSql;
    Assert.IsFalse(F.LastExecution('X.DEL').WasOpen, 'ExecSql deve registrar WasOpen=False');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.ExecutionCount_MultipleCalls;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
  I: Integer;
begin
  F := TMockDBFactory.Create;
  try
    F.AddResult('X.FIND', TMockQueryResult.Empty);
    for I := 1 to 3 do
    begin
      Scope := F.GetPool.AcquireQuery(Q);
      Q.SetSql('X.FIND');
      Q.Open;
    end;
    Assert.AreEqual(3, F.ExecutionCount('X.FIND'), 'Deve contar 3 execuções');
    Assert.AreEqual(0, F.ExecutionCount('OUTRO'),   'Chave diferente deve ser 0');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.LastExecution_ReturnsLast;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('X.UPD'); Q.Params.SetString('NOME', 'Primeiro'); Q.ExecSql;
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('X.UPD'); Q.Params.SetString('NOME', 'Ultimo');   Q.ExecSql;
    Assert.AreEqual('Ultimo', F.LastExecution('X.UPD').AsString('NOME'),
      'LastExecution deve retornar a execução mais recente');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.LastExecution_UnknownKey_ReturnsNil;
var
  F: TMockDBFactory;
begin
  F := TMockDBFactory.Create;
  try
    Assert.IsNull(F.LastExecution('NUNCA.EXECUTADO'), 'Chave inexistente deve retornar nil');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.RecordExecution_CapturesParams;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
  Ex: TMockExecution;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Q.SetSql('PRODUTO.INSERT');
    Q.Params.SetString('NOME',   'Caneta');
    Q.Params.SetInteger('QTD',   10);
    Q.Params.SetCurrency('PRECO', 2.50);
    Q.ExecSql;

    Ex := F.LastExecution('PRODUTO.INSERT');
    Assert.IsNotNull(Ex);
    Assert.IsTrue(Ex.HasParam('NOME'),  'Snapshot deve ter NOME');
    Assert.IsTrue(Ex.HasParam('QTD'),   'Snapshot deve ter QTD');
    Assert.IsTrue(Ex.HasParam('PRECO'), 'Snapshot deve ter PRECO');
    Assert.AreEqual('Caneta', Ex.AsString('NOME'));
    Assert.AreEqual(10,       Ex.AsInteger('QTD'));
    Assert.AreEqual(Currency(2.50), Ex.AsCurrency('PRECO'), 'Preço deve ser preservado');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.SqlLoader_ReturnsMockLoader;
var
  F: TMockDBFactory;
  L: TSQLLoader;
begin
  F := TMockDBFactory.Create;
  try
    L := F.SqlLoader;
    Assert.IsNotNull(L, 'SqlLoader não deve retornar nil');
    Assert.IsTrue(L is TMockSQLLoader, 'SqlLoader deve ser TMockSQLLoader');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.TestConnection_ReturnsTrue;
var
  F: TMockDBFactory;
begin
  F := TMockDBFactory.Create;
  try
    Assert.IsTrue(F.TestConnection(nil), 'TestConnection no mock deve retornar True');
  finally
    F.Free;
  end;
end;

procedure TMockDBFactoryTests.AcquireQuery_ReturnsQuery;
var
  F: TMockDBFactory;
  Q: IQuery;
  Scope: IScopeTransaction;
begin
  F := TMockDBFactory.Create;
  try
    Scope := F.GetPool.AcquireQuery(Q);
    Assert.IsNotNull(Q,     'AcquireQuery deve retornar IQuery');
    Assert.IsNotNull(Scope, 'AcquireQuery deve retornar IScopeTransaction');
    Assert.IsNotNull(Q.Params, 'IQuery.Params não deve ser nil');
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMockQueryResultTests);
  TDUnitX.RegisterTestFixture(TMockParamsTests);
  TDUnitX.RegisterTestFixture(TMockSQLLoaderTests);
  TDUnitX.RegisterTestFixture(TMockDBFactoryTests);

end.
