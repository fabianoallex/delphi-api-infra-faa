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
    function GetIdleTimeoutSeconds: Integer;
    function GetIdleCheckIntervalMs: Integer;
    procedure SetIniConnections(AValue: Integer);
    procedure SetMaxConnections(AValue: Integer);
    procedure SetWaitMaxAttemps(AValue: Integer);
    procedure SetWaitMilliseconds(AValue: Integer);
    procedure SetIdleTimeoutSeconds(AValue: Integer);
    procedure SetIdleCheckIntervalMs(AValue: Integer);
    property IniConnections: Integer read GetIniConnections write SetIniConnections;
    property MaxConnections: Integer read GetMaxConnections write SetMaxConnections;
    property WaitMaxAttemps: Integer read GetWaitMaxAttemps write SetWaitMaxAttemps;
    property WaitMilliseconds: Integer read GetWaitMilliseconds write SetWaitMilliseconds;
    /// Segundos que uma conexão pode ficar ociosa no pool antes de ser
    /// fechada (nunca abaixo de IniConnections). 0 (padrão) = desligado.
    property IdleTimeoutSeconds: Integer read GetIdleTimeoutSeconds write SetIdleTimeoutSeconds;
    /// Intervalo entre varreduras de ociosidade. Só importa quando
    /// IdleTimeoutSeconds > 0. Valores <= 0 caem no padrão (30000ms).
    property IdleCheckIntervalMs: Integer read GetIdleCheckIntervalMs write SetIdleCheckIntervalMs;
  end;

  { TConnectionPoolConfig }

  TConnectionPoolConfig = class(TInterfacedObject, IConnectionPoolConfig)
  private
    FIniConnections: Integer;
    FMaxConnections: Integer;
    FWaitMaxAttemps: Integer;
    FWaitMilliseconds: Integer;
    FIdleTimeoutSeconds: Integer;
    FIdleCheckIntervalMs: Integer;
    function GetIniConnections: Integer;
    function GetMaxConnections: Integer;
    procedure SetIniConnections(AValue: Integer);
    procedure SetMaxConnections(AValue: Integer);
  public
    constructor Create;
    function GetWaitMaxAttemps: Integer;
    function GetWaitMilliseconds: Integer;
    function GetIdleTimeoutSeconds: Integer;
    function GetIdleCheckIntervalMs: Integer;
    procedure SetWaitMaxAttemps(AValue: Integer);
    procedure SetWaitMilliseconds(AValue: Integer);
    procedure SetIdleTimeoutSeconds(AValue: Integer);
    procedure SetIdleCheckIntervalMs(AValue: Integer);
  end;

  // Eventos do pool cobrem só o que é sinal de operação anormal ou de
  // crescimento de capacidade — nunca o caminho feliz (acquire/release de uma
  // conexão já pronta no pool, que acontece em toda requisição). Diferente de
  // TMigrationEvent (Db.Migrations, que roda poucas vezes no startup), aqui
  // NÃO existe fallback de log no console quando AOnEvent não é informado:
  // silêncio é o comportamento correto de um pool saudável, e notificar em
  // toda acquire/release geraria uma linha de log por requisição.
  TPoolEventKind = (
    pekConnectionCreated,    // nova conexão física criada (ramp-up inicial ou crescimento sob carga)
    pekConnectionDiscarded,  // uma conexão do pool foi descartada (falhou reconectar, falhou o teste
                             // de vivacidade, ou saiu marcada como quebrada durante o uso — ver TPoolDiscardReason)
    pekAcquireThrottled,     // AcquireConnection precisou esperar (pool no limite) antes de conseguir uma conexão
    pekAcquireTimeout,       // esgotou as tentativas de espera; EPoolTimeoutException será lançada em seguida
    pekIdleSweepClosed       // a varredura de ociosidade fechou uma ou mais conexões
  );

  TPoolDiscardReason = (
    pdrConnectFailed,     // ConnectionItem.Connection.Connect falhou ao reconectar
    pdrStaleCheckFailed,  // FFactory.TestConnection retornou False (conexão parada/morta)
    pdrBrokenAfterUse     // IsConnectionBrokenError (Db.Interfaces) marcou a conexão via
                           // IDiscardableConnection durante o uso (Query/Commit/Rollback) —
                           // descartada no release, nunca volta ociosa ao pool
  );

  TPoolEvent = record
    Kind: TPoolEventKind;
    ActiveConnections: Integer;  // FActiveConnections no momento do evento
    PoolSize: Integer;           // conexões ociosas na fila no momento do evento
    MaxConnections: Integer;
    IniConnections: Integer;
    WaitAttempts: Integer;             // pekAcquireThrottled / pekAcquireTimeout
    ClosedCount: Integer;              // pekIdleSweepClosed
    DiscardReason: TPoolDiscardReason; // pekConnectionDiscarded
    ErrorMessage: string;              // pekConnectionDiscarded (mensagem da exceção de Connect, se houver)
  end;

  TPoolEventProc = reference to procedure(const AEvent: TPoolEvent);

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
    FIdleTimeoutSeconds: Integer;
    FIdleCheckIntervalMs: Integer;
    FIdleSweepThread: TThread;
    FIdleSweepWake: TEvent;
    FOnEvent: TPoolEventProc;
    FTotalCreated: Int64;
    FTotalDiscarded: Int64;
    FTotalTimeouts: Int64;
    FTotalIdleSwept: Int64;
    procedure CreateInitialConnections;
    procedure IncrementActiveConnections;
    procedure DecrementActiveConnections;
    function NewConnection: IDBConnection;
    procedure StartIdleSweep;
    procedure StopIdleSweep;
    function BaseEvent(AKind: TPoolEventKind): TPoolEvent;
    procedure Notify(const AEvent: TPoolEvent);
  protected
    procedure ReleaseConnection(AConn: IDBConnection);
    procedure DiscardConnection(AConn: IDBConnection);
    procedure ReleaseQuery(var AQuery: IQuery);
  public
    // AOnEvent é opcional — sem ele, o pool simplesmente não notifica nada
    // (ver comentário em TPoolEventKind sobre por que não há fallback de
    // console aqui, ao contrário de TDBMigrationEngine).
    constructor Create(AFactory: IDBFactory; AConfig: IConnectionPoolConfig = nil;
      AOnEvent: TPoolEventProc = nil);
    destructor Destroy; override;
    function AcquireConnection: IDBConnection;
    function AcquireQuery(out AQuery: IQuery; ATransaction: ITransaction = nil): IScopeTransaction;
    function GetActiveConnections: Integer;
    function GetPoolSize: Integer;
    function GetWaitMaxAttemps: Integer;
    function GetWaitMilliseconds: Integer;
    // Estado atual + contadores acumulados desde a criação do pool — ver
    // TPoolSnapshot (Db.Interfaces) para o propósito de cada campo.
    function GetSnapshot: TPoolSnapshot;
    /// Fecha, imediatamente, as conexões ociosas mais antigas do pool que
    /// ultrapassarem IdleTimeoutSeconds, nunca abaixo de IniConnections.
    /// A thread de varredura automática chama a versão sem parâmetro
    /// periodicamente quando IdleTimeoutSeconds > 0.
    /// Ambas são públicas principalmente para permitir testes determinísticos
    /// (com IClock fake) sem esperar o intervalo real nem depender da thread
    /// de fundo — a versão com parâmetro nem precisa de IdleTimeoutSeconds
    /// configurado (nem, portanto, de nenhuma thread ter sido iniciada).
    procedure SweepIdleConnections; overload;
    procedure SweepIdleConnections(AIdleTimeoutSeconds: Integer); overload;
  end;

implementation

type

  { TConnectionWrapper
    Auto-devolve a conexão ao pool quando destruído. }

  TConnectionWrapper = class(TInterfacedObject, IDBConnection, IUnwrapDBConnection, IDiscardableConnection)
  private
    FPool: IDBConnectionPoolInternalActions;
    FInternalConn: IDBConnection;
    FDiscard: Boolean;
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
    // IDiscardableConnection — ver comentário na declaração da interface
    // (Db.Interfaces) e MarkConnectionBrokenIfNeeded, chamado a partir de
    // TQueryWrapper.Open/ExecSql e TFDTransactionAdapter.Commit/Rollback.
    procedure MarkForDiscard;
    function ShouldDiscard: Boolean;
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
  try
    FInternalQuery.ExecSql;
  except
    on E: Exception do
    begin
      MarkConnectionBrokenIfNeeded(FInternalQuery.GetConnection, E);
      raise;
    end;
  end;
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
  try
    Result := FInternalQuery.Open;
  except
    on E: Exception do
    begin
      // Ver IsConnectionBrokenError (Db.Interfaces): só marca a conexão para
      // descarte em EExternal (ex.: Access Violation dentro da chamada
      // nativa) ou se IsConnected virou False — violação de constraint e
      // outros erros de dados normais deixam a conexão intocada.
      MarkConnectionBrokenIfNeeded(FInternalQuery.GetConnection, E);
      raise;
    end;
  end;
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
  begin
    if FDiscard then
      FPool.DiscardConnection(FInternalConn)
    else
      FPool.ReleaseConnection(FInternalConn);
  end;
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

procedure TConnectionWrapper.MarkForDiscard;
begin
  FDiscard := True;
end;

function TConnectionWrapper.ShouldDiscard: Boolean;
begin
  Result := FDiscard;
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

constructor TConnectionPoolConfig.Create;
begin
  inherited Create;
  FIdleCheckIntervalMs := 30000; // só importa se IdleTimeoutSeconds > 0
end;

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

function TConnectionPoolConfig.GetIdleTimeoutSeconds: Integer;
begin
  Result := FIdleTimeoutSeconds;
end;

function TConnectionPoolConfig.GetIdleCheckIntervalMs: Integer;
begin
  Result := FIdleCheckIntervalMs;
end;

procedure TConnectionPoolConfig.SetIdleTimeoutSeconds(AValue: Integer);
begin
  if AValue >= 0 then
    FIdleTimeoutSeconds := AValue;
end;

procedure TConnectionPoolConfig.SetIdleCheckIntervalMs(AValue: Integer);
begin
  if AValue > 0 then
    FIdleCheckIntervalMs := AValue;
end;

{ TConnectionPool }

constructor TConnectionPool.Create(AFactory: IDBFactory; AConfig: IConnectionPoolConfig;
  AOnEvent: TPoolEventProc);

  // Referência fraca para quebrar ciclo circular TConnectionPool <-> IDBFactory
  procedure SetWeak(aInterfaceField: PInterface; const aValue: IInterface);
  begin
    PPointer(aInterfaceField)^ := Pointer(aValue);
  end;

begin
  FOnEvent := AOnEvent;

  if Assigned(AConfig) then
  begin
    FIniConnections  := AConfig.IniConnections;
    FMaxConnections  := AConfig.MaxConnections;
    FWaitMilliseconds := AConfig.WaitMilliseconds;
    FWaitMaxAttemps  := AConfig.WaitMaxAttemps;
    FIdleTimeoutSeconds := AConfig.IdleTimeoutSeconds;
    FIdleCheckIntervalMs := AConfig.IdleCheckIntervalMs;
  end
  else
  begin
    FIniConnections  := 3;
    FMaxConnections  := 20;
    FWaitMilliseconds := 20;
    FWaitMaxAttemps  := 50;
    FIdleTimeoutSeconds := 0; // desligado por padrão
    FIdleCheckIntervalMs := 30000;
  end;

  if FIdleCheckIntervalMs <= 0 then
    FIdleCheckIntervalMs := 30000; // config já validava isso, mas o branch "sem AConfig" não

  FActiveConnections := 0;

  SetWeak(@FFactory, AFactory);

  FPool     := TQueue<TConnectionItem>.Create;
  FLockPool := TCriticalSection.Create;

  CreateInitialConnections;

  if FIdleTimeoutSeconds > 0 then
    StartIdleSweep;
end;

destructor TConnectionPool.Destroy;
begin
  // Precisa parar ANTES de mexer em FPool/FLockPool — senão a thread de
  // varredura pode disparar em cima de campos já liberados.
  StopIdleSweep;

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

function TConnectionPool.BaseEvent(AKind: TPoolEventKind): TPoolEvent;
begin
  Result := Default(TPoolEvent);
  Result.Kind := AKind;
  Result.ActiveConnections := FActiveConnections;
  Result.PoolSize := FPool.Count;
  Result.MaxConnections := FMaxConnections;
  Result.IniConnections := FIniConnections;
end;

procedure TConnectionPool.Notify(const AEvent: TPoolEvent);
begin
  if Assigned(FOnEvent) then
    FOnEvent(AEvent);
end;

function TConnectionPool.GetSnapshot: TPoolSnapshot;
begin
  Result.ActiveConnections := FActiveConnections;
  Result.PoolSize := FPool.Count;
  Result.MaxConnections := FMaxConnections;
  Result.IniConnections := FIniConnections;
  Result.TotalCreated := FTotalCreated;
  Result.TotalDiscarded := FTotalDiscarded;
  Result.TotalTimeouts := FTotalTimeouts;
  Result.TotalIdleSwept := FTotalIdleSwept;
end;

procedure TConnectionPool.StartIdleSweep;
begin
  // Evento manual-reset: SetEvent no Terminate acorda a thread na hora,
  // sem esperar o intervalo cheio — mesmo padrão usado no reconnect thread
  // do pascal-named-pipes-faa (TPipeClient.FReconnectAbort).
  FIdleSweepWake := TEvent.Create(nil, True, False, '');
  FIdleSweepThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while FIdleSweepWake.WaitFor(FIdleCheckIntervalMs) = wrTimeout do
        SweepIdleConnections;
    end);
  FIdleSweepThread.FreeOnTerminate := False;
  FIdleSweepThread.Start;
end;

procedure TConnectionPool.StopIdleSweep;
begin
  if not Assigned(FIdleSweepThread) then
    Exit;

  FIdleSweepWake.SetEvent;
  FIdleSweepThread.WaitFor;
  FreeAndNil(FIdleSweepThread);
  FreeAndNil(FIdleSweepWake);
end;

procedure TConnectionPool.SweepIdleConnections;
begin
  SweepIdleConnections(FIdleTimeoutSeconds);
end;

procedure TConnectionPool.SweepIdleConnections(AIdleTimeoutSeconds: Integer);
var
  LToClose: TList<IDBConnection>;
  LItem: TConnectionItem;
  LConn: IDBConnection;
  LEvent: TPoolEvent;
begin
  if AIdleTimeoutSeconds <= 0 then
    Exit;

  LToClose := TList<IDBConnection>.Create;
  try
    // Fase 1 (rápida, sob lock): decidir o que sai. FPool é FIFO por
    // LastRelease crescente, então o item da frente é sempre o mais antigo —
    // basta espiar e parar no primeiro que ainda não está ocioso o bastante.
    FLockPool.Enter;
    try
      while (FPool.Count > FIniConnections) and (FPool.Count > 0) do
      begin
        LItem := FPool.Peek;
        if SecondsBetween(TClock.Now, LItem.LastRelease) < AIdleTimeoutSeconds then
          Break;

        FPool.Dequeue;
        LToClose.Add(LItem.Connection);
        Dec(FActiveConnections); // já estamos sob FLockPool; ver DecrementActiveConnections
      end;
    finally
      FLockPool.Leave;
    end;

    // Fase 2 (lenta, fora do lock): desconectar de fato. Nunca fazer IO de
    // rede com FLockPool preso — bloquearia todo AcquireConnection/
    // ReleaseConnection concorrente da aplicação até o Disconnect terminar.
    for LConn in LToClose do
    begin
      try
        LConn.Disconnect(True);
      except
        // ignora — a conexão está sendo descartada de qualquer forma
      end;
    end;

    if LToClose.Count > 0 then
    begin
      Inc(FTotalIdleSwept, LToClose.Count);
      LEvent := BaseEvent(pekIdleSweepClosed);
      LEvent.ClosedCount := LToClose.Count;
      Notify(LEvent);
    end;
  finally
    LToClose.Free;
  end;
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
  LThrottleEvent: TPoolEvent;

  procedure NotifyThrottledIfWaited;
  begin
    if WaitAttempts = 0 then
      Exit;
    LThrottleEvent := BaseEvent(pekAcquireThrottled);
    LThrottleEvent.WaitAttempts := WaitAttempts;
    Notify(LThrottleEvent);
  end;

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
    Inc(FTotalCreated);
    Notify(BaseEvent(pekConnectionCreated));
  end;

  function TryGetConnectionFromPool(out AConnection: IDBConnection): Boolean;
  var
    LEvent: TPoolEvent;
  begin
    Result := False;

    if not ConnectionItem.Connection.IsConnected then
    begin
      try
        ConnectionItem.Connection.Connect;
      except
        on E: Exception do
        begin
          try
            ConnectionItem.Connection.Disconnect(True);
          finally
            DecrementActiveConnections;
          end;
          Inc(FTotalDiscarded);
          LEvent := BaseEvent(pekConnectionDiscarded);
          LEvent.DiscardReason := pdrConnectFailed;
          LEvent.ErrorMessage := E.Message;
          Notify(LEvent);
          Exit;
        end;
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
        Inc(FTotalDiscarded);
        LEvent := BaseEvent(pekConnectionDiscarded);
        LEvent.DiscardReason := pdrStaleCheckFailed;
        Notify(LEvent);
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
        NotifyThrottledIfWaited;
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
      NotifyThrottledIfWaited;
      Result := TConnectionWrapper.Create(Self, RealConnection);
      Exit;
    end;

    if WaitAttempts >= FWaitMaxAttemps then
    begin
      Inc(FTotalTimeouts);
      LThrottleEvent := BaseEvent(pekAcquireTimeout);
      LThrottleEvent.WaitAttempts := WaitAttempts;
      Notify(LThrottleEvent);
      raise EPoolTimeoutException.Create(
        FActiveConnections, FMaxConnections, FPool.Count, WaitAttempts
      );
    end;

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

  try
    LRealConn.Rollback;
  except
    // Chamado a partir de TConnectionWrapper.Destroy (um destructor) — nunca
    // deixa a exceção escapar daqui. Uma conexão que falha no Rollback não
    // parecia quebrada até agora (senão já teria vindo com FDiscard=True);
    // não arrisca reenfileirar mesmo assim, descarta.
    DiscardConnection(LRealConn);
    Exit;
  end;

  FLockPool.Enter;
  try
    FPool.Enqueue(TConnectionItem.New(LRealConn));
  finally
    FLockPool.Leave;
  end;
end;

procedure TConnectionPool.DiscardConnection(AConn: IDBConnection);
var
  LUnwrapper: IUnwrapDBConnection;
  LRealConn: IDBConnection;
  LEvent: TPoolEvent;
begin
  if AConn = nil then
    Exit;

  if Supports(AConn, IUnwrapDBConnection, LUnwrapper) then
    LRealConn := LUnwrapper.GetRealConnection
  else
    LRealConn := AConn;

  try
    LRealConn.Disconnect(True);
  except
    // ignora — a conexão está sendo descartada de qualquer forma
  end;

  DecrementActiveConnections;
  Inc(FTotalDiscarded);
  LEvent := BaseEvent(pekConnectionDiscarded);
  LEvent.DiscardReason := pdrBrokenAfterUse;
  Notify(LEvent);
end;

procedure TConnectionPool.ReleaseQuery(var AQuery: IQuery);
begin
  if not Assigned(AQuery) then
    Exit;

  AQuery.Close;
  AQuery := nil;
end;

end.
