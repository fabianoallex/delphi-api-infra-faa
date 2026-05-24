unit Db.Connection.Pool;

interface

uses
  System.Classes,
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.SyncObjs,
  Db.Interfaces,
  Common.SystemContext,
  Common.Optionals;

type

  { EPoolTimeoutException }

  EPoolTimeoutException = class(Exception)
  public
    constructor Create(Active, Max, InQueue, Attempts: Integer);
  end;

  { TConnectionItem }

  TConnectionItem = record
    Connection: IDBConnection;
    LastRelease: TDateTime;
    class function New(AConn: IDBConnection): TConnectionItem; static;
  end;

  { IConnectionPoolConfig }

  IConnectionPoolConfig = interface
    ['{2AD13457-7932-46C0-B2C4-A9CE804A9672}']
    function GetIniConnections: Integer;
    function GetMaxConnections: Integer;
    function GetWaitMaxAttemps: Integer;
    function GetWaitMilliseconds: Integer;
    procedure SetIniConnections(AValue: Integer);
    procedure SetMaxConnections(AValue: Integer);
    procedure SetWaitMaxAttemps(AValue: Integer);
    procedure SetWaitMilliseconds(AValue: Integer);
    property IniConnections: Integer read GetIniConnections write SetIniConnections;
    property MaxConnections: Integer read GetMaxConnections write SetMaxConnections;
    property WaitMaxAttemps: Integer read GetWaitMaxAttemps write SetWaitMaxAttemps;
    property WaitMilliseconds: Integer read GetWaitMilliseconds write SetWaitMilliseconds;
  end;

  { TConnectionPoolConfig }

  TConnectionPoolConfig = class(TInterfacedObject, IConnectionPoolConfig)
  private
    FIniConnections: Integer;
    FMaxConnections: Integer;
    FWaitMaxAttemps: Integer;
    FWaitMilliseconds: Integer;
    function GetIniConnections: Integer;
    function GetMaxConnections: Integer;
    procedure SetIniConnections(AValue: Integer);
    procedure SetMaxConnections(AValue: Integer);
  public
    function GetWaitMaxAttemps: Integer;
    function GetWaitMilliseconds: Integer;
    procedure SetWaitMaxAttemps(AValue: Integer);
    procedure SetWaitMilliseconds(AValue: Integer);
  end;

  { TConnectionPool }

  TConnectionPool = class(TInterfacedObject, IDBConnectionPool, IDBConnectionPoolInternalActions)
  private
    FFactory: IDBFactory;
    FMaxConnections: Integer;
    FIniConnections: Integer;
    FPool: TQueue<TConnectionItem>;
    FLockPool: TCriticalSection;
    FActiveConnections: Integer;
    FWaitMaxAttemps: Integer;
    FWaitMilliseconds: Integer;
    procedure CreateInitialConnections;
    procedure IncrementActiveConnections;
    procedure DecrementActiveConnections;
    function NewConnection: IDBConnection;
  protected
    procedure ReleaseConnection(AConn: IDBConnection);
    procedure ReleaseQuery(var AQuery: IQuery);
  public
    constructor Create(AFactory: IDBFactory; AConfig: IConnectionPoolConfig = nil);
    destructor Destroy; override;
    function AcquireConnection: IDBConnection;
    function AcquireQuery(out AQuery: IQuery; ATransaction: ITransaction = nil): IScopeTransaction;
    function GetActiveConnections: Integer;
    function GetPoolSize: Integer;
    function GetWaitMaxAttemps: Integer;
    function GetWaitMilliseconds: Integer;
  end;

implementation

type

  { TConnectionWrapper
    Auto-devolve a conexão ao pool quando destruído. }

  TConnectionWrapper = class(TInterfacedObject, IDBConnection, IUnwrapDBConnection)
  private
    FPool: IDBConnectionPoolInternalActions;
    FInternalConn: IDBConnection;
  public
    constructor Create(APool: IDBConnectionPoolInternalActions; ARealConn: IDBConnection);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect(Force: Boolean = False);
    function GetNativeConnection: TObject;
    function GetRealConnection: IDBConnection;
    function GetSQLDialect: ISQLDialect;
    function IsConnected: Boolean;
    procedure Commit;
    procedure Rollback;
  end;

  { TQueryWrapper
    Auto-devolve a query ao pool quando destruído. }

  TQueryWrapper = class(TInterfacedObject, IQuery)
  private
    FPool: IDBConnectionPoolInternalActions;
    FInternalQuery: IQuery;
  public
    constructor Create(APool: IDBConnectionPoolInternalActions; ARealQuery: IQuery);
    destructor Destroy; override;
    procedure Close;
    procedure ExecSql;
    function GetConnection: IDBConnection;
    function GetParams: IParams;
    function GetSql: string;
    function GetTransaction: ITransaction;
    function Open: IQueryResult;
    procedure SetSql(const ASql: string);
  end;

{ TQueryWrapper }

constructor TQueryWrapper.Create(APool: IDBConnectionPoolInternalActions; ARealQuery: IQuery);
begin
  FPool := APool;
  FInternalQuery := ARealQuery;
end;

destructor TQueryWrapper.Destroy;
begin
  if Assigned(FPool) then
    FPool.ReleaseQuery(FInternalQuery);
  inherited Destroy;
end;

procedure TQueryWrapper.Close;
begin
  FInternalQuery.Close;
end;

procedure TQueryWrapper.ExecSql;
begin
  FInternalQuery.ExecSql;
end;

function TQueryWrapper.GetConnection: IDBConnection;
begin
  Result := FInternalQuery.GetConnection;
end;

function TQueryWrapper.GetParams: IParams;
begin
  Result := FInternalQuery.GetParams;
end;

function TQueryWrapper.GetSql: string;
begin
  Result := FInternalQuery.GetSql;
end;

function TQueryWrapper.GetTransaction: ITransaction;
begin
  Result := FInternalQuery.GetTransaction;
end;

function TQueryWrapper.Open: IQueryResult;
begin
  Result := FInternalQuery.Open;
end;

procedure TQueryWrapper.SetSql(const ASql: string);
begin
  FInternalQuery.SetSql(ASql);
end;

{ TConnectionWrapper }

constructor TConnectionWrapper.Create(APool: IDBConnectionPoolInternalActions;
  ARealConn: IDBConnection);
begin
  FPool := APool;
  FInternalConn := ARealConn;
end;

destructor TConnectionWrapper.Destroy;
begin
  if Assigned(FPool) then
    FPool.ReleaseConnection(FInternalConn);
  inherited Destroy;
end;

procedure TConnectionWrapper.Commit;
begin
  FInternalConn.Commit;
end;

procedure TConnectionWrapper.Connect;
begin
  FInternalConn.Connect;
end;

procedure TConnectionWrapper.Disconnect(Force: Boolean);
begin
  FInternalConn.Disconnect(Force);
end;

function TConnectionWrapper.GetNativeConnection: TObject;
begin
  Result := FInternalConn.GetNativeConnection;
end;

function TConnectionWrapper.GetRealConnection: IDBConnection;
begin
  Result := FInternalConn;
end;

function TConnectionWrapper.GetSQLDialect: ISQLDialect;
begin
  Result := FInternalConn.GetSQLDialect;
end;

function TConnectionWrapper.IsConnected: Boolean;
begin
  Result := FInternalConn.IsConnected;
end;

procedure TConnectionWrapper.Rollback;
begin
  FInternalConn.Rollback;
end;

{ EPoolTimeoutException }

constructor EPoolTimeoutException.Create(Active, Max, InQueue, Attempts: Integer);
begin
  inherited CreateFmt(
    'Timeout ao aguardar conexão. Pool: %d/%d ativas, %d na fila. Tentativas: %d',
    [Active, Max, InQueue, Attempts]
  );
end;

{ TConnectionItem }

class function TConnectionItem.New(AConn: IDBConnection): TConnectionItem;
begin
  Result.Connection := AConn;
  Result.LastRelease := TClock.Now;
end;

{ TConnectionPoolConfig }

function TConnectionPoolConfig.GetIniConnections: Integer;
begin
  Result := FIniConnections;
end;

function TConnectionPoolConfig.GetMaxConnections: Integer;
begin
  Result := FMaxConnections;
end;

procedure TConnectionPoolConfig.SetIniConnections(AValue: Integer);
begin
  if AValue >= 0 then
    FIniConnections := AValue;
end;

procedure TConnectionPoolConfig.SetMaxConnections(AValue: Integer);
begin
  if AValue > 0 then
    FMaxConnections := AValue;
end;

function TConnectionPoolConfig.GetWaitMaxAttemps: Integer;
begin
  Result := FWaitMaxAttemps;
end;

function TConnectionPoolConfig.GetWaitMilliseconds: Integer;
begin
  Result := FWaitMilliseconds;
end;

procedure TConnectionPoolConfig.SetWaitMaxAttemps(AValue: Integer);
begin
  FWaitMaxAttemps := AValue;
end;

procedure TConnectionPoolConfig.SetWaitMilliseconds(AValue: Integer);
begin
  FWaitMilliseconds := AValue;
end;

{ TConnectionPool }

constructor TConnectionPool.Create(AFactory: IDBFactory; AConfig: IConnectionPoolConfig);

  // Referência fraca para quebrar ciclo circular TConnectionPool <-> IDBFactory
  procedure SetWeak(aInterfaceField: PInterface; const aValue: IInterface);
  begin
    PPointer(aInterfaceField)^ := Pointer(aValue);
  end;

begin
  if Assigned(AConfig) then
  begin
    FIniConnections  := AConfig.IniConnections;
    FMaxConnections  := AConfig.MaxConnections;
    FWaitMilliseconds := AConfig.WaitMilliseconds;
    FWaitMaxAttemps  := AConfig.WaitMaxAttemps;
  end
  else
  begin
    FIniConnections  := 3;
    FMaxConnections  := 20;
    FWaitMilliseconds := 20;
    FWaitMaxAttemps  := 50;
  end;

  FActiveConnections := 0;

  SetWeak(@FFactory, AFactory);

  FPool     := TQueue<TConnectionItem>.Create;
  FLockPool := TCriticalSection.Create;

  CreateInitialConnections;
end;

destructor TConnectionPool.Destroy;
begin
  // Anula a referência fraca antes do Release automático gerado pelo compilador
  PPointer(@FFactory)^ := nil;

  FLockPool.Enter;
  try
    while FPool.Count > 0 do
      FPool.Dequeue;
    FPool.Free;
  finally
    FLockPool.Leave;
    FLockPool.Free;
  end;

  inherited Destroy;
end;

procedure TConnectionPool.CreateInitialConnections;
var
  I: Integer;
  { Holders mantém os Wrappers vivos durante o loop para forçar o pool a
    criar conexões físicas novas. Ao sair do procedure, o array sai de escopo,
    todos os Wrappers são liberados e as conexões voltam ao pool. }
  Holders: TArray<IDBConnection>;
begin
  if FIniConnections <= 0 then
    Exit;

  SetLength(Holders, FIniConnections);
  for I := 0 to FIniConnections - 1 do
    Holders[I] := AcquireConnection;
end;

procedure TConnectionPool.IncrementActiveConnections;
begin
  FLockPool.Enter;
  try
    Inc(FActiveConnections);
  finally
    FLockPool.Leave;
  end;
end;

procedure TConnectionPool.DecrementActiveConnections;
begin
  FLockPool.Enter;
  try
    Dec(FActiveConnections);
  finally
    FLockPool.Leave;
  end;
end;

function TConnectionPool.NewConnection: IDBConnection;
begin
  Result := FFactory.CreateConnection;
end;

function TConnectionPool.AcquireConnection: IDBConnection;
var
  WaitAttempts: Integer;
  ConnectionItem: TConnectionItem;
  ShouldCreateNew: Boolean;
  ShouldUseFromPool: Boolean;
  RealConnection: IDBConnection;

  procedure CheckPool;
  begin
    FLockPool.Enter;
    try
      if FPool.Count > 0 then
      begin
        ShouldUseFromPool := True;
        ConnectionItem := FPool.Dequeue;
      end
      else if FActiveConnections < FMaxConnections then
      begin
        ShouldCreateNew := True;
        IncrementActiveConnections;
      end;
    finally
      FLockPool.Leave;
    end;
  end;

  function TryGetNewConnection(out AConnection: IDBConnection): Boolean;
  begin
    Result := True;
    try
      AConnection := NewConnection;
    except
      Result := False;
      DecrementActiveConnections;
      raise;
    end;
  end;

  function TryGetConnectionFromPool(out AConnection: IDBConnection): Boolean;
  begin
    Result := False;

    if not ConnectionItem.Connection.IsConnected then
    begin
      try
        ConnectionItem.Connection.Connect;
      except
        try
          ConnectionItem.Connection.Disconnect(True);
        finally
          DecrementActiveConnections;
        end;
        Exit;
      end;
    end;

    if SecondsBetween(TClock.Now, ConnectionItem.LastRelease) >= 120 then
    begin
      if not FFactory.TestConnection(ConnectionItem.Connection) then
      begin
        try
          ConnectionItem.Connection.Disconnect(True);
        finally
          DecrementActiveConnections;
        end;
        Exit;
      end;
    end;

    Result := True;
    AConnection := ConnectionItem.Connection;
  end;

begin
  WaitAttempts := 0;
  while True do
  begin
    ShouldCreateNew  := False;
    ShouldUseFromPool := False;

    CheckPool;

    if ShouldCreateNew then
    begin
      if TryGetNewConnection(RealConnection) then
      begin
        Result := TConnectionWrapper.Create(Self, RealConnection);
        Exit;
      end;
      Result := nil;
    end;

    if ShouldUseFromPool then
    begin
      if not TryGetConnectionFromPool(RealConnection) then
      begin
        Result := nil;
        Continue;
      end;
      Result := TConnectionWrapper.Create(Self, RealConnection);
      Exit;
    end;

    if WaitAttempts >= FWaitMaxAttemps then
      raise EPoolTimeoutException.Create(
        FActiveConnections, FMaxConnections, FPool.Count, WaitAttempts
      );

    TSleep.Sleep(FWaitMilliseconds);
    Inc(WaitAttempts);
  end;
end;

function TConnectionPool.AcquireQuery(out AQuery: IQuery; ATransaction: ITransaction): IScopeTransaction;
var
  LConn: IDBConnection;
  RealQuery: IQuery;
  LTransaction: ITransaction;
begin
  if Assigned(ATransaction) then
  begin
    LTransaction := ATransaction;
    LConn := ATransaction.GetConnection;
  end
  else
  begin
    LConn := AcquireConnection;
    LTransaction := FFactory.CreateTransaction(LConn);
  end;

  RealQuery := FFactory.CreateQuery(LConn, LTransaction);
  AQuery := TQueryWrapper.Create(Self, RealQuery);
  Result := FFactory.CreateScopeTransaction(LTransaction);
end;

function TConnectionPool.GetActiveConnections: Integer;
begin
  Result := FActiveConnections;
end;

function TConnectionPool.GetPoolSize: Integer;
begin
  Result := FPool.Count;
end;

function TConnectionPool.GetWaitMaxAttemps: Integer;
begin
  Result := FWaitMaxAttemps;
end;

function TConnectionPool.GetWaitMilliseconds: Integer;
begin
  Result := FWaitMilliseconds;
end;

procedure TConnectionPool.ReleaseConnection(AConn: IDBConnection);
var
  LUnwrapper: IUnwrapDBConnection;
  LRealConn: IDBConnection;
begin
  if AConn = nil then
    Exit;

  if Supports(AConn, IUnwrapDBConnection, LUnwrapper) then
    LRealConn := LUnwrapper.GetRealConnection
  else
    LRealConn := AConn;

  LRealConn.Rollback;

  FLockPool.Enter;
  try
    FPool.Enqueue(TConnectionItem.New(LRealConn));
  finally
    FLockPool.Leave;
  end;
end;

procedure TConnectionPool.ReleaseQuery(var AQuery: IQuery);
begin
  if not Assigned(AQuery) then
    Exit;

  AQuery.Close;
  AQuery := nil;
end;

end.
