unit Db.PoolTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Threading,
  System.Diagnostics,
  Db.Interfaces,
  Db.Connection.Pool,
  Db.SqlLoader,
  Common.SystemContext;

type

  { ITestableTransaction — extensão de teste para verificar comandos gravados }

  ITestableTransaction = interface(ITransaction)
    ['{AEB38845-ABBF-4DC2-808F-2EACAC280440}']
    function GetCommands: TStringList;
    function GetCommitCount: Integer;
    function GetRollbackCount: Integer;
  end;

  { TFakeSleep }

  TFakeSleep = class(TInterfacedObject, ISleep)
  public
    procedure Sleep(milliseconds: Cardinal);
  end;

  { TFakeClock }

  TFakeClock = class(TInterfacedObject, IClock)
  private
    FTimes: TQueue<TDateTime>;
    FDefaultTime: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    function Now: TDateTime;
    function Date: TDateTime;
    procedure EnqueueTime(ADateTime: TDateTime);
    procedure SetDefaultTime(ADateTime: TDateTime);
  end;

  { TFakeDBConnection }

  TFakeDBConnection = class(TInterfacedObject, IDBConnection)
  public
    procedure Commit;
    procedure Connect;
    procedure Disconnect(Force: Boolean = False);
    function GetNativeConnection: TObject;
    function GetSQLDialect: ISQLDialect;
    function IsConnected: Boolean;
    procedure Rollback;
  end;

  { TFakeTransaction }

  TFakeTransaction = class(TInterfacedObject, ITransaction, ITestableTransaction)
  private
    FCommands: TStringList;
    FCommitCount: Integer;
    FRollbackCount: Integer;
    FConnection: IDBConnection;
  public
    constructor Create(AConn: IDBConnection);
    destructor Destroy; override;
    // ITransaction
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function GetConnection: IDBConnection;
    function GetNativeTransaction: TObject;
    procedure ExecSql(const ASql: string);
    // ITestableTransaction
    function GetCommands: TStringList;
    function GetCommitCount: Integer;
    function GetRollbackCount: Integer;
  end;

  { TFakeScopeTransaction }

  TFakeScopeTransaction = class(TInterfacedObject, IScopeTransaction)
  private
    FOriginalTransaction: ITransaction;
  public
    constructor Create(AOriginalTransaction: ITransaction);
    procedure Commit;
    function GetOriginalTransaction: ITransaction;
    function InTransaction: Boolean;
    function IsMain: Boolean;
    procedure Rollback;
    procedure StartTransaction;
  end;

  { TFakeQuery }

  TFakeQuery = class(TInterfacedObject, IQuery)
  private
    FSql: string;
    FTransaction: ITransaction;
    FConnection: IDBConnection;
  public
    constructor Create(AConn: IDBConnection; ATrans: ITransaction);
    procedure Close;
    procedure ExecSql;
    function GetConnection: IDBConnection;
    function GetParams: IParams;
    function GetSql: string;
    function GetTransaction: ITransaction;
    function Open: IQueryResult;
    procedure SetSql(const ASql: string);
  end;

  { TDBFactoryMock }

  TDBFactoryMock = class(TInterfacedObject, IDBFactory)
  private
    FSimulateTestConnectionFail: Boolean;
    FTestedConnections: TList<IDBConnection>;
  public
    constructor Create;
    destructor Destroy; override;
    function CreateConnection: IDBConnection;
    function CreateQuery(AConn: IDBConnection; ATransaction: ITransaction): IQuery;
    function CreateScopeTransaction(ATransaction: ITransaction): IScopeTransaction;
    function CreateSqlScript(AConn: IDBConnection; ATransaction: ITransaction): ISqlScript;
    function CreateTransaction(AConn: IDBConnection): ITransaction;
    function GetPool: IDBConnectionPool;
    function SqlLoader: TSQLLoader;
    function TestConnection(AConn: IDBConnection): Boolean;
    property SimulateTestConnectionFail: Boolean
      read FSimulateTestConnectionFail write FSimulateTestConnectionFail;
    property TestedConnections: TList<IDBConnection> read FTestedConnections;
  end;

  { TPoolStressThread
    Adquire e libera conexões do pool repetidamente para testar concorrência. }

  TPoolStressThread = class(TThread)
  private
    FPool: IDBConnectionPool;
    FIterations: Integer;
    FErrorOccurred: Boolean;
    FErrorMessage: string;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: IDBConnectionPool; AIterations: Integer);
    property ErrorOccurred: Boolean read FErrorOccurred;
    property ErrorMessage: string read FErrorMessage;
  end;

  { TPoolTests }

  [TestFixture]
  TPoolTests = class
  public
    [Test] procedure Test_Pool_InicioVazio;
    [Test] procedure Test_Pool_InicialConnections;
    [Test] procedure Test_Pool_MaxConnections_Estoura;
    [Test] procedure Test_Pool_AquireELibera;
    [Test] procedure Test_Pool_CriaNovaCon_QuandoVazio;
    [Test] procedure Test_Pool_AcquireQuery;
    [Test] procedure Test_Pool_AcquireQueries_MesmaTransacao;
    [Test] procedure Test_Pool_AcquireQueries_TransacoesDiferentes;
    [Test] procedure Test_Pool_SharedTransaction_RegistraComandos;
    [Test] procedure Test_Pool_TransacoesDiferentes_RegistraComandosSeparados;
    [Test] procedure Test_Pool_ConexaoInativa120s;
    [Test] procedure Test_Pool_ConexaoInativaFalha;
    [Test] procedure Test_Pool_Concorrencia;
    [Test] procedure Test_Pool_IdleTimeout_Desligado_NaoEvictaNada;
    [Test] procedure Test_Pool_IdleTimeout_EvictaSoOsMaisAntigos;
    [Test] procedure Test_Pool_IdleTimeout_RespeitaPiso_IniConnections;
    [Test] procedure Test_Pool_IdleTimeoutConfig_ValoresPadraoEValidacao;
    [Test] procedure Test_Pool_IdleSweep_DestroyNaoTrava;
    [Test] procedure Test_Pool_Concorrencia_ComIdleSweepAtivo;
  private
    procedure MaxConnectionsEstoura_Method;
  end;

implementation

{ TFakeSleep }

procedure TFakeSleep.Sleep(milliseconds: Cardinal);
begin
end;

{ TFakeClock }

constructor TFakeClock.Create;
begin
  FTimes := TQueue<TDateTime>.Create;
  FDefaultTime := 0;
end;

destructor TFakeClock.Destroy;
begin
  FTimes.Free;
  inherited Destroy;
end;

function TFakeClock.Now: TDateTime;
begin
  if FTimes.Count > 0 then
    Result := FTimes.Dequeue
  else
    Result := FDefaultTime;
end;

function TFakeClock.Date: TDateTime;
begin
  Result := Trunc(Now);
end;

procedure TFakeClock.EnqueueTime(ADateTime: TDateTime);
begin
  FTimes.Enqueue(ADateTime);
end;

procedure TFakeClock.SetDefaultTime(ADateTime: TDateTime);
begin
  FDefaultTime := ADateTime;
end;

{ TFakeDBConnection }

procedure TFakeDBConnection.Commit;   begin end;
procedure TFakeDBConnection.Connect;  begin end;
procedure TFakeDBConnection.Disconnect(Force: Boolean); begin end;

function TFakeDBConnection.GetNativeConnection: TObject;
begin
  Result := nil;
end;

function TFakeDBConnection.GetSQLDialect: ISQLDialect;
begin
  Result := nil;
end;

function TFakeDBConnection.IsConnected: Boolean;
begin
  Result := True;
end;

procedure TFakeDBConnection.Rollback; begin end;

{ TFakeTransaction }

constructor TFakeTransaction.Create(AConn: IDBConnection);
begin
  FConnection := AConn;
  FCommands := TStringList.Create;
  FCommitCount := 0;
  FRollbackCount := 0;
end;

destructor TFakeTransaction.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

procedure TFakeTransaction.StartTransaction; begin end;

procedure TFakeTransaction.Commit;
begin
  Inc(FCommitCount);
end;

procedure TFakeTransaction.Rollback;
begin
  Inc(FRollbackCount);
end;

function TFakeTransaction.InTransaction: Boolean;
begin
  Result := False;
end;

function TFakeTransaction.GetConnection: IDBConnection;
begin
  Result := FConnection;
end;

function TFakeTransaction.GetNativeTransaction: TObject;
begin
  Result := nil;
end;

procedure TFakeTransaction.ExecSql(const ASql: string);
begin
end;

function TFakeTransaction.GetCommands: TStringList;
begin
  Result := FCommands;
end;

function TFakeTransaction.GetCommitCount: Integer;
begin
  Result := FCommitCount;
end;

function TFakeTransaction.GetRollbackCount: Integer;
begin
  Result := FRollbackCount;
end;

{ TFakeScopeTransaction }

constructor TFakeScopeTransaction.Create(AOriginalTransaction: ITransaction);
begin
  FOriginalTransaction := AOriginalTransaction;
end;

procedure TFakeScopeTransaction.Commit;    begin end;
procedure TFakeScopeTransaction.Rollback;  begin end;
procedure TFakeScopeTransaction.StartTransaction; begin end;

function TFakeScopeTransaction.GetOriginalTransaction: ITransaction;
begin
  Result := FOriginalTransaction;
end;

function TFakeScopeTransaction.InTransaction: Boolean;
begin
  Result := False;
end;

function TFakeScopeTransaction.IsMain: Boolean;
begin
  Result := True;
end;

{ TFakeQuery }

constructor TFakeQuery.Create(AConn: IDBConnection; ATrans: ITransaction);
begin
  FConnection := AConn;
  FTransaction := ATrans;
end;

procedure TFakeQuery.Close; begin end;

procedure TFakeQuery.ExecSql;
var
  LTestable: ITestableTransaction;
begin
  if Assigned(FTransaction) and Supports(FTransaction, ITestableTransaction, LTestable) then
    LTestable.GetCommands.Add(FSql);
end;

function TFakeQuery.GetConnection: IDBConnection;
begin
  Result := FConnection;
end;

function TFakeQuery.GetParams: IParams;
begin
  Result := nil;
end;

function TFakeQuery.GetSql: string;
begin
  Result := FSql;
end;

function TFakeQuery.GetTransaction: ITransaction;
begin
  Result := FTransaction;
end;

function TFakeQuery.Open: IQueryResult;
begin
  Result := nil;
end;

procedure TFakeQuery.SetSql(const ASql: string);
begin
  FSql := ASql;
end;

{ TDBFactoryMock }

constructor TDBFactoryMock.Create;
begin
  FSimulateTestConnectionFail := False;
  FTestedConnections := TList<IDBConnection>.Create;
end;

destructor TDBFactoryMock.Destroy;
begin
  FTestedConnections.Free;
  inherited Destroy;
end;

function TDBFactoryMock.CreateConnection: IDBConnection;
begin
  Result := TFakeDBConnection.Create;
end;

function TDBFactoryMock.CreateQuery(AConn: IDBConnection;
  ATransaction: ITransaction): IQuery;
begin
  Result := TFakeQuery.Create(AConn, ATransaction);
end;

function TDBFactoryMock.CreateScopeTransaction(
  ATransaction: ITransaction): IScopeTransaction;
begin
  Result := TFakeScopeTransaction.Create(ATransaction);
end;

function TDBFactoryMock.CreateSqlScript(AConn: IDBConnection;
  ATransaction: ITransaction): ISqlScript;
begin
  Result := nil;
end;

function TDBFactoryMock.CreateTransaction(AConn: IDBConnection): ITransaction;
begin
  Result := TFakeTransaction.Create(AConn);
end;

function TDBFactoryMock.GetPool: IDBConnectionPool;
begin
  Result := nil;
end;

function TDBFactoryMock.SqlLoader: TSQLLoader;
begin
  Result := nil;
end;

function TDBFactoryMock.TestConnection(AConn: IDBConnection): Boolean;
begin
  FTestedConnections.Add(AConn);
  Result := not FSimulateTestConnectionFail;
end;

{ TPoolTests }

procedure TPoolTests.MaxConnectionsEstoura_Method;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: TConnectionPool;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.MaxConnections := 3;
  LConfig.IniConnections := 5;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);
  try
  finally
    LPool.Free;
  end;
end;

procedure TPoolTests.Test_Pool_InicioVazio;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  Assert.AreEqual(0, LPool.GetPoolSize,
    'Pool vazio: GetPoolSize deve ser 0 quando IniConnections = 0');
end;

procedure TPoolTests.Test_Pool_InicialConnections;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 5;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  Assert.AreEqual(5, LPool.GetPoolSize,
    'Pool deve ter 5 conexões iniciais');
end;

procedure TPoolTests.Test_Pool_MaxConnections_Estoura;
begin
  TSleep.SetSleep(TFakeSleep.Create);
  try
    Assert.WillRaise(MaxConnectionsEstoura_Method, EPoolTimeoutException,
      'Deve lançar EPoolTimeoutException quando IniConnections > MaxConnections');
  finally
    TSleep.Reset;
  end;
end;

procedure TPoolTests.Test_Pool_AquireELibera;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LConn1, LConn2: IDBConnection;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 3;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  Assert.AreEqual(3, LPool.GetPoolSize, '1. Pool deve ter 3 conexões');

  LConn1 := LPool.AcquireConnection;
  Assert.AreEqual(2, LPool.GetPoolSize, '2. Pool deve ter 2 conexões após 1 acquire');

  LConn2 := LPool.AcquireConnection;
  Assert.AreEqual(1, LPool.GetPoolSize, '3. Pool deve ter 1 conexão após 2 acquires');

  LConn2 := nil;
  Assert.AreEqual(2, LPool.GetPoolSize, '4. Pool deve ter 2 conexões após release de LConn2');

  LConn1 := nil;
  Assert.AreEqual(3, LPool.GetPoolSize, '5. Pool deve ter 3 conexões após release de LConn1');
end;

procedure TPoolTests.Test_Pool_CriaNovaCon_QuandoVazio;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LConn: IDBConnection;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  Assert.AreEqual(0, LPool.GetPoolSize,
    '1. Pool deve ter 0 conexões ociosas');
  Assert.AreEqual(0, LPool.GetActiveConnections,
    '2. Pool deve ter 0 conexões ativas');

  LConn := LPool.AcquireConnection;

  Assert.AreEqual(0, LPool.GetPoolSize,
    '3. Pool ainda deve ter 0 conexões ociosas');
  Assert.AreEqual(1, LPool.GetActiveConnections,
    '4. Pool deve ter 1 conexão ativa');

  Assert.IsNotNull(LConn, 'Conexão não deve ser nil');
end;

procedure TPoolTests.Test_Pool_AcquireQuery;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LQuery: IQuery;
  LScope: IScopeTransaction;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LQuery := nil;
  LScope := LPool.AcquireQuery(LQuery);

  Assert.IsNotNull(LQuery, 'Query não deve ser nil');
  Assert.IsNotNull(LScope, 'IScopeTransaction não deve ser nil');
end;

procedure TPoolTests.Test_Pool_AcquireQueries_MesmaTransacao;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LQuery1, LQuery2: IQuery;
  LScope1, LScope2: IScopeTransaction;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LQuery1 := nil;
  LScope1 := LPool.AcquireQuery(LQuery1);
  LScope2 := LPool.AcquireQuery(LQuery2, LScope1.GetOriginalTransaction);

  Assert.IsNotNull(LQuery1, 'Query1 não deve ser nil');
  Assert.IsNotNull(LQuery2, 'Query2 não deve ser nil');
  Assert.AreSame(
    LScope1.GetOriginalTransaction,
    LScope2.GetOriginalTransaction,
    'As transações das duas queries devem ser a mesma instância'
  );
end;

procedure TPoolTests.Test_Pool_AcquireQueries_TransacoesDiferentes;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LQuery1, LQuery2: IQuery;
  LScope1, LScope2: IScopeTransaction;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LQuery1 := nil;
  LScope1 := LPool.AcquireQuery(LQuery1);
  LScope2 := LPool.AcquireQuery(LQuery2);

  Assert.IsNotNull(LQuery1, 'Query1 não deve ser nil');
  Assert.IsNotNull(LQuery2, 'Query2 não deve ser nil');
  Assert.IsNotNull(LScope1, 'Scope1 não deve ser nil');
  Assert.IsNotNull(LScope2, 'Scope2 não deve ser nil');
  Assert.AreNotSame(
    LScope1.GetOriginalTransaction,
    LScope2.GetOriginalTransaction,
    'As transações das duas queries devem ser instâncias diferentes'
  );
end;

procedure TPoolTests.Test_Pool_SharedTransaction_RegistraComandos;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LQuery1, LQuery2: IQuery;
  LScope: IScopeTransaction;
  LTestable: ITestableTransaction;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LScope := LPool.AcquireQuery(LQuery1);
  LPool.AcquireQuery(LQuery2, LScope.GetOriginalTransaction);

  LQuery1.SetSql('CMD1');
  LQuery1.ExecSql;
  LQuery2.SetSql('CMD2');
  LQuery2.ExecSql;

  Assert.IsTrue(
    Supports(LScope.GetOriginalTransaction, ITestableTransaction, LTestable),
    'Transação deve implementar ITestableTransaction'
  );
  Assert.AreEqual(2, LTestable.GetCommands.Count,
    'Ambos os comandos devem estar registrados na mesma transação compartilhada');
end;

procedure TPoolTests.Test_Pool_TransacoesDiferentes_RegistraComandosSeparados;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LQuery1, LQuery2: IQuery;
  LScope1, LScope2: IScopeTransaction;
  LTestable1, LTestable2: ITestableTransaction;
begin
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 0;
  LConfig.MaxConnections := 10;

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LScope1 := LPool.AcquireQuery(LQuery1);
  LScope2 := LPool.AcquireQuery(LQuery2);

  LQuery1.SetSql('CMD1');
  LQuery1.ExecSql;

  LQuery2.SetSql('CMD2');
  LQuery2.ExecSql;
  LQuery2.SetSql('CMD3');
  LQuery2.ExecSql;

  Supports(LScope1.GetOriginalTransaction, ITestableTransaction, LTestable1);
  Supports(LScope2.GetOriginalTransaction, ITestableTransaction, LTestable2);

  Assert.AreEqual(1, LTestable1.GetCommands.Count,
    'Transação 1 deve ter somente 1 comando');
  Assert.AreEqual(2, LTestable2.GetCommands.Count,
    'Transação 2 deve ter 2 comandos');
end;

procedure TPoolTests.Test_Pool_ConexaoInativa120s;

  procedure TestarSegundos(const AMensagem: string; ASegundos: Integer;
    ATestedCountEsperado: Integer);
  var
    LConfig: IConnectionPoolConfig;
    LFactory: IDBFactory;
    LMockFactory: TDBFactoryMock;
    LPool: IDBConnectionPool;
    LConn: IDBConnection;
    LClock: TFakeClock;
    BaseTime: TDateTime;
  begin
    BaseTime := StrToDateTime('28/12/2025 11:44:18');

    LClock := TFakeClock.Create;
    LClock.SetDefaultTime(BaseTime);
    LClock.EnqueueTime(BaseTime);                                // liberação em CreateInitialConnections
    LClock.EnqueueTime(BaseTime + (ASegundos / 86400));          // verificação em AcquireConnection

    TClock.SetClock(LClock);
    try
      LConfig := TConnectionPoolConfig.Create;
      LConfig.IniConnections := 1;
      LConfig.MaxConnections := 10;

      LMockFactory := TDBFactoryMock.Create;
      LFactory := LMockFactory;
      LPool := TConnectionPool.Create(LFactory, LConfig);

      Assert.AreEqual(0, LMockFactory.TestedConnections.Count,
        'Antes do acquire não deve haver conexões testadas');

      LConn := LPool.AcquireConnection;

      Assert.AreEqual(ATestedCountEsperado, LMockFactory.TestedConnections.Count, AMensagem);
    finally
      TClock.Reset;
    end;
  end;

begin
  TestarSegundos('Com 120s: deve testar a conexão (Count=1)',  120, 1);
  TestarSegundos('Com 119s: não deve testar (Count=0)',        119, 0);
  TestarSegundos('Com 1s: não deve testar (Count=0)',            1, 0);
  TestarSegundos('Com 5280s: deve testar a conexão (Count=1)', 5280, 1);
end;

procedure TPoolTests.Test_Pool_ConexaoInativaFalha;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LMockFactory: TDBFactoryMock;
  LPool: IDBConnectionPool;
  LConn: IDBConnection;
  LClock: TFakeClock;
  BaseTime: TDateTime;
begin
  BaseTime := StrToDateTime('28/12/2025 11:44:18');

  LClock := TFakeClock.Create;
  LClock.SetDefaultTime(BaseTime);
  // Liberações durante CreateInitialConnections (2 conexões, em ordem de índice)
  LClock.EnqueueTime(BaseTime);                      // LastRelease conn1
  LClock.EnqueueTime(BaseTime + (50 / 86400));       // LastRelease conn2
  // Verificações em AcquireConnection
  LClock.EnqueueTime(BaseTime + (121 / 86400));      // 121s p/ conn1 → testa → falha → remove
  LClock.EnqueueTime(BaseTime + (130 / 86400));      // 80s p/ conn2 → não testa → usa

  TClock.SetClock(LClock);
  try
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections := 2;
    LConfig.MaxConnections := 10;

    LMockFactory := TDBFactoryMock.Create;
    LFactory := LMockFactory;
    LPool := TConnectionPool.Create(LFactory, LConfig);

    Assert.AreEqual(2, LPool.GetActiveConnections,
      'Pool deve ter 2 conexões ativas após inicialização');

    LMockFactory.SimulateTestConnectionFail := True;

    LConn := LPool.AcquireConnection;

    Assert.AreEqual(1, LPool.GetActiveConnections,
      'Após remover a conexão falha, deve restar 1 conexão ativa');

    Assert.IsNotNull(LConn, 'Deve retornar a segunda conexão (saudável)');
  finally
    TClock.Reset;
  end;
end;

{ TPoolStressThread }

constructor TPoolStressThread.Create(APool: IDBConnectionPool; AIterations: Integer);
begin
  inherited Create(True); // suspenso — aguarda chamada explícita de Start
  FPool := APool;
  FIterations := AIterations;
  FreeOnTerminate := False;
  FErrorOccurred := False;
end;

procedure TPoolStressThread.Execute;
var
  I: Integer;
  LConn: IDBConnection;
begin
  try
    for I := 1 to FIterations do
    begin
      LConn := FPool.AcquireConnection;
      LConn := nil; // libera imediatamente → devolve ao pool
    end;
  except
    on E: Exception do
    begin
      FErrorOccurred := True;
      FErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure TPoolTests.Test_Pool_Concorrencia;
const
  NUM_THREADS = 20;
  ITERACOES   = 50;
  MAX_CONNS   = 5;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LThreads: array[1..NUM_THREADS] of TPoolStressThread;
  I: Integer;
begin
  // TFakeSleep evita espera real: threads em contenção reentram imediatamente
  TSleep.SetSleep(TFakeSleep.Create);
  try
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections  := 0;
    LConfig.MaxConnections  := MAX_CONNS;
    LConfig.WaitMaxAttemps  := 2000; // suficiente para 20 threads × 50 iterações
    LConfig.WaitMilliseconds := 0;

    LFactory := TDBFactoryMock.Create;
    LPool := TConnectionPool.Create(LFactory, LConfig);

    // Cria todas as threads suspensas
    for I := 1 to NUM_THREADS do
      LThreads[I] := TPoolStressThread.Create(LPool, ITERACOES);

    // Dispara todas de uma vez para forçar concorrência real
    for I := 1 to NUM_THREADS do
      LThreads[I].Start;

    // Aguarda cada thread e verifica que não gerou erro
    for I := 1 to NUM_THREADS do
    begin
      LThreads[I].WaitFor;
      Assert.IsFalse(
        LThreads[I].ErrorOccurred,
        Format('Thread %d reportou erro: %s', [I, LThreads[I].ErrorMessage])
      );
      LThreads[I].Free;
    end;

    // Após todas as threads terminarem, nenhuma conexão deve estar em uso:
    // GetPoolSize (ociosas) deve igualar GetActiveConnections (total físico criado)
    Assert.AreEqual(
      LPool.GetActiveConnections,
      LPool.GetPoolSize,
      'Todas as conexões físicas devem ter voltado ao pool — nenhum vazamento'
    );

    Assert.IsTrue(
      LPool.GetActiveConnections <= MAX_CONNS,
      'O pool nunca deve ter criado mais conexões do que o limite máximo'
    );
  finally
    TSleep.Reset;
  end;
end;

{ TPoolTests — idle timeout }

procedure TPoolTests.Test_Pool_IdleTimeout_Desligado_NaoEvictaNada;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  // LPoolIntf segura a referência contada do início ao fim (mesmo padrão dos
  // testes originais, ex. Test_Pool_AquireELibera) — sem isso, os ciclos de
  // Acquire/libera abaixo derrubam a contagem de TConnectionPool a zero no
  // meio do teste e o _Release automático do TInterfacedObject destrói o
  // pool ali mesmo; o LPool.Free explícito no final vira free duplo.
  // LPool é só uma "view" da classe concreta, pra chamar SweepIdleConnections
  // (que não faz parte de IDBConnectionPool) — nunca dar Free nela.
  LPoolIntf: IDBConnectionPool;
  LPool: TConnectionPool;
  LClock: TFakeClock;
  LConn1, LConn2: IDBConnection;
  BaseTime: TDateTime;
begin
  BaseTime := StrToDateTime('28/12/2025 11:44:18');
  LClock := TFakeClock.Create;
  LClock.SetDefaultTime(BaseTime);
  TClock.SetClock(LClock);
  try
    // IdleTimeoutSeconds não configurado -> fica 0 = desligado (padrão)
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections := 0;
    LConfig.MaxConnections := 10;

    LFactory := TDBFactoryMock.Create;
    LPoolIntf := TConnectionPool.Create(LFactory, LConfig);
    LPool := LPoolIntf as TConnectionPool;

    LConn1 := LPoolIntf.AcquireConnection;
    LConn2 := LPoolIntf.AcquireConnection;
    LConn1 := nil;
    LConn2 := nil; // 2 conexões ociosas no pool

    Assert.AreEqual(2, LPoolIntf.GetPoolSize, 'Pré-condição: 2 conexões ociosas');

    LClock.SetDefaultTime(BaseTime + (100000 / 86400)); // bem além de qualquer limite razoável
    LPool.SweepIdleConnections;

    Assert.AreEqual(2, LPoolIntf.GetPoolSize,
      'IdleTimeoutSeconds=0 (padrão): SweepIdleConnections não deve remover nada');
    Assert.AreEqual(2, LPoolIntf.GetActiveConnections,
      'IdleTimeoutSeconds=0 (padrão): contagem de ativas não deve mudar');
  finally
    TClock.Reset;
  end;
end;

procedure TPoolTests.Test_Pool_IdleTimeout_EvictaSoOsMaisAntigos;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPoolIntf: IDBConnectionPool; // ver comentário em Test_Pool_IdleTimeout_Desligado_NaoEvictaNada
  LPool: TConnectionPool;
  LClock: TFakeClock;
  LConn1, LConn2, LConn3: IDBConnection;
  BaseTime: TDateTime;
begin
  BaseTime := StrToDateTime('28/12/2025 11:44:18');
  LClock := TFakeClock.Create;
  LClock.SetDefaultTime(BaseTime);
  TClock.SetClock(LClock);
  try
    // IdleTimeoutSeconds fica 0 (padrão) de propósito: assim NENHUMA thread
    // de varredura é criada — o teste chama SweepIdleConnections(60)
    // diretamente, na thread do próprio teste, com TFakeClock. Determinístico,
    // sem concorrência nenhuma envolvida.
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections := 0;
    LConfig.MaxConnections := 10;

    LFactory := TDBFactoryMock.Create;
    LPoolIntf := TConnectionPool.Create(LFactory, LConfig);
    LPool := LPoolIntf as TConnectionPool;

    LConn1 := LPoolIntf.AcquireConnection;
    LConn2 := LPoolIntf.AcquireConnection;
    LConn3 := LPoolIntf.AcquireConnection;
    Assert.AreEqual(3, LPoolIntf.GetActiveConnections, 'Pré-condição: 3 conexões ativas');

    LClock.SetDefaultTime(BaseTime);
    LConn1 := nil; // LastRelease = T0        (65s de idade no sweep abaixo)
    LClock.SetDefaultTime(BaseTime + (10 / 86400));
    LConn2 := nil; // LastRelease = T0+10s     (55s de idade — NÃO deve sair)
    LClock.SetDefaultTime(BaseTime + (20 / 86400));
    LConn3 := nil; // LastRelease = T0+20s     (45s de idade — NÃO deve sair)

    Assert.AreEqual(3, LPoolIntf.GetPoolSize, 'Pré-condição: 3 conexões ociosas no pool');

    LClock.SetDefaultTime(BaseTime + (65 / 86400)); // "agora" = T0+65s
    LPool.SweepIdleConnections(60);

    Assert.AreEqual(2, LPoolIntf.GetPoolSize,
      'Só a conexão liberada em T0 (65s de idade, >=60) deve ser removida');
    Assert.AreEqual(2, LPoolIntf.GetActiveConnections,
      'FActiveConnections deve acompanhar a remoção');
  finally
    TClock.Reset;
  end;
end;

procedure TPoolTests.Test_Pool_IdleTimeout_RespeitaPiso_IniConnections;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPoolIntf: IDBConnectionPool; // ver comentário em Test_Pool_IdleTimeout_Desligado_NaoEvictaNada
  LPool: TConnectionPool;
  LClock: TFakeClock;
  LConn1, LConn2, LConn3: IDBConnection;
  BaseTime: TDateTime;
begin
  BaseTime := StrToDateTime('28/12/2025 11:44:18');
  LClock := TFakeClock.Create;
  LClock.SetDefaultTime(BaseTime);
  TClock.SetClock(LClock);
  try
    // IdleTimeoutSeconds fica 0 (padrão) de propósito — ver comentário no
    // teste Test_Pool_IdleTimeout_EvictaSoOsMaisAntigos.
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections := 2; // piso: nunca evictar abaixo disso
    LConfig.MaxConnections := 10;

    LFactory := TDBFactoryMock.Create;
    LPoolIntf := TConnectionPool.Create(LFactory, LConfig);
    LPool := LPoolIntf as TConnectionPool;

    // CreateInitialConnections já deixou 2 ociosas (LastRelease = BaseTime).
    // Esvazia as 2 (reuso) e força a criação de uma 3ª nova, depois libera
    // as 3 — pra ter 3 conexões ociosas de verdade, todas velhas o bastante.
    LConn1 := LPoolIntf.AcquireConnection; // reusa uma das 2 do pool
    LConn2 := LPoolIntf.AcquireConnection; // reusa a outra
    LConn3 := LPoolIntf.AcquireConnection; // pool vazio agora -> cria nova (3ª física)
    LConn1 := nil;
    LConn2 := nil;
    LConn3 := nil;
    Assert.AreEqual(3, LPoolIntf.GetPoolSize, 'Pré-condição: 3 conexões ociosas');

    // Todas MUITO além do limite de 60s — sem piso, evictaria tudo.
    LClock.SetDefaultTime(BaseTime + (100000 / 86400));
    LPool.SweepIdleConnections(60);

    Assert.AreEqual(2, LPoolIntf.GetPoolSize,
      'Nunca deve evictar abaixo de IniConnections, mesmo com todas idosas');
    Assert.AreEqual(2, LPoolIntf.GetActiveConnections,
      'FActiveConnections deve parar no piso também');
  finally
    TClock.Reset;
  end;
end;

procedure TPoolTests.Test_Pool_IdleTimeoutConfig_ValoresPadraoEValidacao;
var
  LConfig: IConnectionPoolConfig;
begin
  LConfig := TConnectionPoolConfig.Create;

  Assert.AreEqual(0, LConfig.IdleTimeoutSeconds,
    'Padrão de IdleTimeoutSeconds deve ser 0 (desligado)');
  Assert.AreEqual(30000, LConfig.IdleCheckIntervalMs,
    'Padrão de IdleCheckIntervalMs deve ser 30000ms');

  LConfig.IdleCheckIntervalMs := 0;
  Assert.AreEqual(30000, LConfig.IdleCheckIntervalMs,
    'IdleCheckIntervalMs <= 0 deve ser ignorado (mantém o padrão)');

  LConfig.IdleCheckIntervalMs := -5;
  Assert.AreEqual(30000, LConfig.IdleCheckIntervalMs,
    'IdleCheckIntervalMs negativo deve ser ignorado');

  LConfig.IdleCheckIntervalMs := 5000;
  Assert.AreEqual(5000, LConfig.IdleCheckIntervalMs,
    'IdleCheckIntervalMs válido deve ser aceito');

  LConfig.IdleTimeoutSeconds := -1;
  Assert.AreEqual(0, LConfig.IdleTimeoutSeconds,
    'IdleTimeoutSeconds negativo deve ser ignorado');

  LConfig.IdleTimeoutSeconds := 45;
  Assert.AreEqual(45, LConfig.IdleTimeoutSeconds,
    'IdleTimeoutSeconds válido (>=0) deve ser aceito');
end;

procedure TPoolTests.Test_Pool_IdleSweep_DestroyNaoTrava;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: TConnectionPool;
  LStopwatch: TStopwatch;
begin
  // Sem TFakeClock/TFakeSleep aqui de propósito: quer a thread de varredura
  // REAL rodando, pra provar que Destroy não trava nem AV mesmo com ela viva.
  LConfig := TConnectionPoolConfig.Create;
  LConfig.IniConnections := 1;
  LConfig.MaxConnections := 10;
  LConfig.IdleTimeoutSeconds := 1;
  LConfig.IdleCheckIntervalMs := 5000; // não importa: SetEvent acorda na hora, não espera isso

  LFactory := TDBFactoryMock.Create;
  LPool := TConnectionPool.Create(LFactory, LConfig);

  LStopwatch := TStopwatch.StartNew;
  LPool.Free;
  LStopwatch.Stop;

  Assert.IsTrue(LStopwatch.ElapsedMilliseconds < 2000,
    Format('Destroy com sweep ativo deveria ser quase instantâneo (SetEvent), levou %dms',
      [LStopwatch.ElapsedMilliseconds]));
end;

procedure TPoolTests.Test_Pool_Concorrencia_ComIdleSweepAtivo;
const
  NUM_THREADS = 20;
  ITERACOES   = 50;
  MAX_CONNS   = 5;
var
  LConfig: IConnectionPoolConfig;
  LFactory: IDBFactory;
  LPool: IDBConnectionPool;
  LThreads: array[1..NUM_THREADS] of TPoolStressThread;
  I: Integer;
begin
  // Igual Test_Pool_Concorrencia, mas com a thread de varredura REAL ativa e
  // rodando em paralelo (intervalo curto) — cobre o lock entre
  // Acquire/Release concorrentes e SweepIdleConnections ao mesmo tempo.
  TSleep.SetSleep(TFakeSleep.Create);
  try
    LConfig := TConnectionPoolConfig.Create;
    LConfig.IniConnections  := 0;
    LConfig.MaxConnections  := MAX_CONNS;
    LConfig.WaitMaxAttemps  := 2000;
    LConfig.WaitMilliseconds := 0;
    LConfig.IdleTimeoutSeconds := 1;
    LConfig.IdleCheckIntervalMs := 5;

    LFactory := TDBFactoryMock.Create;
    LPool := TConnectionPool.Create(LFactory, LConfig);

    for I := 1 to NUM_THREADS do
      LThreads[I] := TPoolStressThread.Create(LPool, ITERACOES);

    for I := 1 to NUM_THREADS do
      LThreads[I].Start;

    for I := 1 to NUM_THREADS do
    begin
      LThreads[I].WaitFor;
      Assert.IsFalse(
        LThreads[I].ErrorOccurred,
        Format('Thread %d reportou erro: %s', [I, LThreads[I].ErrorMessage])
      );
      LThreads[I].Free;
    end;

    Assert.AreEqual(
      LPool.GetActiveConnections,
      LPool.GetPoolSize,
      'Mesmo com sweep concorrente, toda conexão física deve estar ou ativa ou no pool — sem vazamento'
    );
    Assert.IsTrue(
      LPool.GetActiveConnections <= MAX_CONNS,
      'O pool nunca deve ter criado mais conexões do que o limite máximo'
    );
  finally
    TSleep.Reset;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPoolTests);

end.
