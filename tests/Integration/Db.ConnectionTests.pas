unit Db.ConnectionTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  Db.Interfaces,
  Db.Adapters.FireDAC,
  TestConfig;

type
  [TestFixture]
  TConnectionTests = class
  private
    FFactory: IDBFactory;
    FPool: IDBConnectionPool;
    function IsReady: Boolean;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;

    { Verifica que AcquireConnection retorna uma conexão viva }
    [Test] procedure Test_AcquireConnection_RetornaConexaoAtiva;

    { Executa SELECT no catálogo do Firebird (RDB$DATABASE) }
    [Test] procedure Test_SimpleQuery_RetornaResultado;

    { Verifica que StartTransaction/Commit afeta o estado InTransaction }
    [Test] procedure Test_Transacao_CommitAlteraEstado;

    { Verifica que a conexão volta ao pool quando a interface é liberada }
    [Test] procedure Test_Pool_DevolveConexaoAoLiberar;
  end;

implementation

{ TConnectionTests }

function TConnectionTests.IsReady: Boolean;
begin
  Result := Assigned(FPool);
end;

procedure TConnectionTests.SetupFixture;
var
  LConfig: TFDConfig;
  LParams: TStrings;
begin
  if not TTestConfig.IsConfigured then
  begin
    FFactory := nil;
    FPool    := nil;
    Exit;
  end;

  LConfig := TFDConfig.Create;
  LParams := TTestConfig.GetConnectionParams;
  try
    LConfig.ConnectionParams.AddStrings(LParams);
  finally
    LParams.Free;
  end;

  LConfig.SQLDialect := TTestConfig.GetSQLDialect;

  // Garante que o FireDAC use a fbclient.dll 32-bit correta quando
  // VendorLib não estiver definido no ini (comum em instalações 64-bit)
  if LConfig.ConnectionParams.Values['VendorLib'] = '' then
  begin
    var LVendorLib := TTestConfig.DetectFirebirdVendorLib;
    if LVendorLib <> '' then
      LConfig.ConnectionParams.Values['VendorLib'] := LVendorLib;
  end;

  // Pool mínimo para testes: 1 conexão inicial, máx 5, espera rápida
  LConfig.SetPoolIniConnections(1);
  LConfig.SetPoolMaxConnections(5);
  LConfig.SetPoolWaitMaxAttemps(10);
  LConfig.SetPoolWaitMilliseconds(20);

  FFactory := TFDFactory.Create(LConfig, nil);
  FPool    := FFactory.GetPool;
end;

procedure TConnectionTests.TearDownFixture;
begin
  FPool    := nil;
  FFactory := nil;
end;

procedure TConnectionTests.Test_AcquireConnection_RetornaConexaoAtiva;
var
  LConn: IDBConnection;
begin
  if not IsReady then
    Exit; // integration_test.ini ausente — sem banco configurado

  LConn := FPool.AcquireConnection;

  Assert.IsNotNull(LConn, 'AcquireConnection não deve retornar nil');
  Assert.IsTrue(LConn.IsConnected, 'A conexão deve estar ativa (IsConnected = True)');
end;

procedure TConnectionTests.Test_SimpleQuery_RetornaResultado;
var
  LQuery: IQuery;
  LScope: IScopeTransaction;
  LResult: IQueryResult;
  LTimestamp: TDateTime;
begin
  if not IsReady then
    Exit; // integration_test.ini ausente — sem banco configurado

  LScope := FPool.AcquireQuery(LQuery);
  LScope.StartTransaction;
  try
    // RDB$DATABASE é a tabela de sistema do Firebird com exatamente 1 linha
    LQuery.SetSql('SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE');
    LResult := LQuery.Open;

    Assert.IsFalse(LResult.IsEmpty,
      'SELECT FROM RDB$DATABASE deve retornar exatamente 1 linha');

    LTimestamp := LResult.GetAsDateTime('CURRENT_TIMESTAMP');
    Assert.IsTrue(LTimestamp > 0, 'CURRENT_TIMESTAMP deve ser maior que zero');

    LScope.Commit;
  except
    LScope.Rollback;
    raise;
  end;
end;

procedure TConnectionTests.Test_Transacao_CommitAlteraEstado;
var
  LQuery: IQuery;
  LScope: IScopeTransaction;
begin
  if not IsReady then
  begin
    Exit; // integration_test.ini ausente — sem banco configurado
  end;

  LScope := FPool.AcquireQuery(LQuery);

  Assert.IsFalse(LQuery.GetTransaction.InTransaction,
    'Não deve haver transação ativa antes de StartTransaction');

  LScope.StartTransaction;

  Assert.IsTrue(LQuery.GetTransaction.InTransaction,
    'InTransaction deve ser True após StartTransaction');

  LScope.Commit;

  Assert.IsFalse(LQuery.GetTransaction.InTransaction,
    'InTransaction deve ser False após Commit');
end;

procedure TConnectionTests.Test_Pool_DevolveConexaoAoLiberar;
var
  LConn: IDBConnection;
  LAtivesAntes: Integer;
  LPoolAntes: Integer;
  LPoolDepois: Integer;
begin
  if not IsReady then
  begin
    Exit; // integration_test.ini ausente — sem banco configurado
  end;

  LAtivesAntes := FPool.GetActiveConnections;
  LPoolAntes   := FPool.GetPoolSize;

  LConn := FPool.AcquireConnection;

  // Enquanto a conexão está em uso ela saiu do pool ocioso
  Assert.IsTrue(FPool.GetPoolSize < LAtivesAntes,
    'Pool ocioso deve diminuir enquanto a conexão está em uso');

  LConn := nil; // libera o wrapper → devolve ao pool

  LPoolDepois := FPool.GetPoolSize;

  Assert.IsTrue(LPoolDepois >= LPoolAntes,
    'Conexão deve ter voltado ao pool após liberar a interface');

  // O total de conexões físicas não muda ao devolver ao pool
  Assert.AreEqual(LAtivesAntes, FPool.GetActiveConnections,
    'GetActiveConnections não deve mudar ao devolver ao pool (conta físicas)');
end;

initialization
  TDUnitX.RegisterTestFixture(TConnectionTests);

end.
