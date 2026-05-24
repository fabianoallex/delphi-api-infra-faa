unit Db.Adapters.FireDAC;

interface

uses
  System.Classes,
  System.SysUtils,
  System.DateUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  System.StrUtils,
  Db.Interfaces,
  Db.Connection.Pool,
  Db.Adapters.Registry,
  Db.SqlLoader,
  Db.SqlDialect,
  Common.Helpers,
  Common.Optionals;

type

  { TFDConnectionAdapter }

  TFDConnectionAdapter = class(TInterfacedObject, IDBConnection)
  private
    FConnection: TFDConnection;
    FSQLDialect: ISQLDialect;
  public
    constructor Create(AConnection: TFDConnection; ASQLDialect: ISQLDialect);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect(Force: Boolean = False);
    function GetNativeConnection: TObject;
    function GetSQLDialect: ISQLDialect;
    function IsConnected: Boolean;
    // Commit/Rollback no nível de conexão são no-op nesta arquitetura;
    // o ciclo de vida das transações é gerenciado exclusivamente via ITransaction.
    procedure Commit;
    procedure Rollback;
  end;

  { TFDTransactionAdapter }

  TFDTransactionAdapter = class(TInterfacedObject, ITransaction)
  private
    FTransaction: TFDTransaction;
    FConn: IDBConnection;
    FInTransaction: Boolean;
  public
    constructor Create(AConn: IDBConnection; ATransaction: TFDTransaction);
    destructor Destroy; override;
    procedure ExecSql(const ASql: string);
    function InTransaction: Boolean;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function GetConnection: IDBConnection;
    function GetNativeTransaction: TObject;
  end;

  { TFDScopeTransactionAdapter }

  TFDScopeTransactionAdapter = class(TInterfacedObject, IScopeTransaction)
  private
    FOriginalTransaction: ITransaction;
    FSavepointName: string;
    FIsMain: Boolean;
    FStarted: Boolean;
    FContextTransaction: IContextTransaction;
  public
    constructor Create(AOriginalTransaction: ITransaction; AContextTransaction: IContextTransaction);
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function IsMain: Boolean;
    function GetOriginalTransaction: ITransaction;
  end;

  { TFDParamsAdapter }

  TFDParamsAdapter = class(TInterfacedObject, IParams)
  private
    FQuery: TFDQuery;
    function FindParam(const AName: string): TFDParam;
  public
    constructor Create(AQuery: TFDQuery);

    function GetString(const AName: string): string;
    function GetBoolean(const AName: string): Boolean;
    function GetDateTime(const AName: string): TDateTime;
    function GetDouble(const AName: string): Double;
    function GetInteger(const AName: string): Integer;
    function GetInt64(const AName: string): Int64;
    function GetCurrency(const AName: string): Currency;

    function GetOptNullString(const AName: string): IOptNullString;
    function GetOptNullBoolean(const AName: string): IOptNullBoolean;
    function GetOptNullDateTime(const AName: string): IOptNullDateTime;
    function GetOptNullInteger(const AName: string): IOptNullInteger;
    function GetOptNullInt64(const AName: string): IOptNullInt64;
    function GetOptNullDouble(const AName: string): IOptNullDouble;
    function GetOptNullCurrency(const AName: string): IOptNullCurrency;

    function GetNullString(const AName: string): INullString;
    function GetNullBoolean(const AName: string): INullBoolean;
    function GetNullDateTime(const AName: string): INullDateTime;
    function GetNullInteger(const AName: string): INullInteger;
    function GetNullInt64(const AName: string): INullInt64;
    function GetNullDouble(const AName: string): INullDouble;
    function GetNullCurrency(const AName: string): INullCurrency;

    function GetOptString(const AName: string): IOptString;
    function GetOptBoolean(const AName: string): IOptBoolean;
    function GetOptDateTime(const AName: string): IOptDateTime;
    function GetOptInteger(const AName: string): IOptInteger;
    function GetOptInt64(const AName: string): IOptInt64;
    function GetOptDouble(const AName: string): IOptDouble;
    function GetOptCurrency(const AName: string): IOptCurrency;

    procedure SetString(const AName: string; AValue: string);
    procedure SetBoolean(const AName: string; AValue: Boolean);
    procedure SetDateTime(const AName: string; AValue: TDateTime);
    procedure SetDouble(const AName: string; AValue: Double);
    procedure SetInteger(const AName: string; AValue: Integer);
    procedure SetInt64(const AName: string; AValue: Int64);
    procedure SetCurrency(const AName: string; AValue: Currency);

    procedure SetOptNullBoolean(const AName: string; AValue: IOptNullBoolean);
    procedure SetOptNullDateTime(const AName: string; AValue: IOptNullDateTime);
    procedure SetOptNullInteger(const AName: string; AValue: IOptNullInteger);
    procedure SetOptNullInt64(const AName: string; AValue: IOptNullInt64);
    procedure SetOptNullString(const AName: string; AValue: IOptNullString);
    procedure SetOptNullDouble(const AName: string; AValue: IOptNullDouble);
    procedure SetOptNullCurrency(const AName: string; AValue: IOptNullCurrency);

    procedure SetNullBoolean(const AName: string; AValue: INullBoolean);
    procedure SetNullDateTime(const AName: string; AValue: INullDateTime);
    procedure SetNullInteger(const AName: string; AValue: INullInteger);
    procedure SetNullInt64(const AName: string; AValue: INullInt64);
    procedure SetNullString(const AName: string; AValue: INullString);
    procedure SetNullDouble(const AName: string; AValue: INullDouble);
    procedure SetNullCurrency(const AName: string; AValue: INullCurrency);

    procedure SetOptBoolean(const AName: string; AValue: IOptBoolean);
    procedure SetOptDateTime(const AName: string; AValue: IOptDateTime);
    procedure SetOptInteger(const AName: string; AValue: IOptInteger);
    procedure SetOptInt64(const AName: string; AValue: IOptInt64);
    procedure SetOptString(const AName: string; AValue: IOptString);
    procedure SetOptDouble(const AName: string; AValue: IOptDouble);
    procedure SetOptCurrency(const AName: string; AValue: IOptCurrency);
  end;

  { TFDQueryAdapter }

  TFDQueryAdapter = class(TInterfacedObject, IQuery, IQueryResult)
  private
    FQuery: TFDQuery;
    FConn: IDBConnection;
    FTransaction: ITransaction;
    FParams: IParams;
    function FieldByName(const AName: string): Variant;
  public
    constructor Create(AQuery: TFDQuery; AConn: IDBConnection; ATransaction: ITransaction);
    destructor Destroy; override;
    procedure Close;
    function Eof: Boolean;
    procedure ExecSql;
    function FieldCount: Integer;
    function FieldValue(AIndex: Integer): Variant;
    function GetAsBoolean(const AName: string): Boolean;
    function GetAsDateTime(const AName: string): TDateTime;
    function GetAsInteger(const AName: string): Integer;
    function GetAsInt64(const AName: string): Int64;
    function GetAsString(const AName: string): string;
    function GetAsCurrency(const AName: string): Currency;
    function GetConnection: IDBConnection;
    function GetNullableBoolean(const AName: string): INullBoolean;
    function GetNullableDateTime(const AName: string): INullDateTime;
    function GetNullableInteger(const AName: string): INullInteger;
    function GetNullableInt64(const AName: string): INullInt64;
    function GetNullableString(const AName: string): INullString;
    function GetNullableCurrency(const AName: string): INullCurrency;
    function GetParams: IParams;
    function GetTransaction: ITransaction;
    function IsEmpty: Boolean;
    procedure Next;
    function Open: IQueryResult;
    function RecordCount: Integer;
    procedure SetSql(const ASql: string);
    function GetSql: string;
  end;

  { TFDScriptAdapter }

  TFDScriptAdapter = class(TInterfacedObject, ISqlScript)
  private
    FScript: TStringList;
    FConn: IDBConnection;
    FTransaction: ITransaction;
  public
    constructor Create(AConn: IDBConnection; ATransaction: ITransaction);
    destructor Destroy; override;
    procedure ExecuteScript(ATerminator: string = ';');
    function GetConnection: IDBConnection;
    function GetScript: TStrings;
    function GetTransaction: ITransaction;
    procedure SetScript(AValue: TStrings);
  end;

  { TFDConfig }

  TFDConfig = class(TInterfacedObject, IDatabaseConfig)
  private
    FConnectionParams: TStrings;
    FSQLDirectory: string;
    FSQLDialect: string;
    FPoolWaitMaxAttemps: Integer;
    FPoolWaitMilliseconds: Integer;
    FPoolMaxConnections: Integer;
    FPoolIniConnections: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function GetPoolIniConnections: Integer;
    function GetPoolMaxConnections: Integer;
    function GetPoolWaitMaxAttemps: Integer;
    function GetPoolWaitMilliseconds: Integer;
    function GetSQLDialect: string;
    procedure SetPoolIniConnections(AValue: Integer);
    procedure SetPoolMaxConnections(AValue: Integer);
    procedure SetPoolWaitMaxAttemps(AValue: Integer);
    procedure SetPoolWaitMilliseconds(AValue: Integer);
    procedure SetSQLDialect(AValue: string);
    // Parâmetros de conexão FireDAC em formato chave=valor
    // Ex: DriverID=FB, Database=..., User_Name=..., Password=...
    property ConnectionParams: TStrings read FConnectionParams;
    property SQLDirectory: string read FSQLDirectory write FSQLDirectory;
    property SQLDialect: string read GetSQLDialect write SetSQLDialect;
  end;

  { TFDProvider }

  TFDProvider = class(TInterfacedObject, IDBComponentProvider)
  public
    function BuildConnection(AConfig: IDatabaseConfig): IDBConnection;
    function BuildTransaction(AConn: IDBConnection): ITransaction;
    function BuildScopeTransaction(ATransaction: ITransaction; AContextTransaction: IContextTransaction): IScopeTransaction;
    function BuildQuery(AConn: IDBConnection; ATransaction: ITransaction): IQuery;
    function BuildSqlScript(AConn: IDBConnection; ATransaction: ITransaction): ISqlScript;
  end;

  { TFDFactory }

  TFDFactory = class(TInterfacedObject, IDBFactory, IDBComponentProviderSupport)
  private
    FSqlLoader: TSQLLoader;
    FPool: IDBConnectionPool;
    FConfig: IDatabaseConfig;
    FComponentProvider: IDBComponentProvider;
    FContextTransactionProvider: IContextTransactionProvider;
  public
    constructor Create(AConfig: IDatabaseConfig; AContextTransactionProvider: IContextTransactionProvider);
    destructor Destroy; override;
    function GetProvider: IDBComponentProvider;
    procedure SetProvider(AProvider: IDBComponentProvider);
    function SqlLoader: TSQLLoader;
    function GetPool: IDBConnectionPool;
    function CreateConnection: IDBConnection;
    function CreateTransaction(AConn: IDBConnection): ITransaction;
    function CreateScopeTransaction(ATransaction: ITransaction): IScopeTransaction;
    function CreateQuery(AConn: IDBConnection; ATransaction: ITransaction): IQuery;
    function CreateSqlScript(AConn: IDBConnection; ATransaction: ITransaction): ISqlScript;
    function TestConnection(AConn: IDBConnection): Boolean;
  end;

implementation

{ TFDConnectionAdapter }

constructor TFDConnectionAdapter.Create(AConnection: TFDConnection; ASQLDialect: ISQLDialect);
begin
  FConnection := AConnection;
  FSQLDialect := ASQLDialect;
end;

destructor TFDConnectionAdapter.Destroy;
begin
  FConnection.Free;
  inherited Destroy;
end;

procedure TFDConnectionAdapter.Connect;
begin
  FConnection.Open;
end;

procedure TFDConnectionAdapter.Disconnect(Force: Boolean);
begin
  FConnection.Close;
end;

function TFDConnectionAdapter.GetNativeConnection: TObject;
begin
  Result := FConnection;
end;

function TFDConnectionAdapter.GetSQLDialect: ISQLDialect;
begin
  Result := FSQLDialect;
end;

function TFDConnectionAdapter.IsConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

procedure TFDConnectionAdapter.Commit;
begin
  // no-op: transações gerenciadas via ITransaction
end;

procedure TFDConnectionAdapter.Rollback;
begin
  // no-op: transações gerenciadas via ITransaction
end;

{ TFDTransactionAdapter }

constructor TFDTransactionAdapter.Create(AConn: IDBConnection; ATransaction: TFDTransaction);
begin
  FConn := AConn;
  FTransaction := ATransaction;
  FInTransaction := False;
end;

destructor TFDTransactionAdapter.Destroy;
begin
  FTransaction.Free;
  inherited Destroy;
end;

procedure TFDTransactionAdapter.ExecSql(const ASql: string);
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConn.GetNativeConnection as TFDConnection;
    LQuery.Transaction := FTransaction;
    LQuery.SQL.Text := ASql;
    LQuery.ExecSQL;
  finally
    LQuery.Free;
  end;
end;

function TFDTransactionAdapter.InTransaction: Boolean;
begin
  Result := FInTransaction;
end;

procedure TFDTransactionAdapter.StartTransaction;
begin
  if not FInTransaction then
  begin
    FTransaction.StartTransaction;
    FInTransaction := True;
  end;
end;

procedure TFDTransactionAdapter.Commit;
begin
  FTransaction.Commit;
  FInTransaction := False;
end;

procedure TFDTransactionAdapter.Rollback;
begin
  FTransaction.Rollback;
  FInTransaction := False;
end;

function TFDTransactionAdapter.GetConnection: IDBConnection;
begin
  Result := FConn;
end;

function TFDTransactionAdapter.GetNativeTransaction: TObject;
begin
  Result := FTransaction;
end;

{ TFDScopeTransactionAdapter }

constructor TFDScopeTransactionAdapter.Create(AOriginalTransaction: ITransaction;
  AContextTransaction: IContextTransaction);
begin
  FContextTransaction := AContextTransaction;
  FOriginalTransaction := AOriginalTransaction;
  FIsMain := not AOriginalTransaction.InTransaction;
  FStarted := False;
end;

procedure TFDScopeTransactionAdapter.StartTransaction;
var
  LSql: string;
begin
  FOriginalTransaction.StartTransaction;

  if Assigned(FContextTransaction) then
    FContextTransaction.Apply(FOriginalTransaction);

  if not FIsMain then
  begin
    FSavepointName := 'sp_' + IntToHex(NativeInt(Self), 8);
    LSql := FOriginalTransaction.GetConnection.GetSQLDialect.GetSavepointSQL(FSavepointName);
    FOriginalTransaction.ExecSql(LSql);
  end;

  FStarted := True;
end;

procedure TFDScopeTransactionAdapter.Commit;
var
  LSql: string;
begin
  if not FStarted then
    Exit;

  if FIsMain then
    FOriginalTransaction.Commit
  else if FOriginalTransaction.GetConnection.GetSQLDialect.SupportsRelease then
  begin
    LSql := FOriginalTransaction.GetConnection.GetSQLDialect.GetReleaseSavepointSQL(FSavepointName);
    FOriginalTransaction.ExecSql(LSql);
    FStarted := False;
  end;
end;

procedure TFDScopeTransactionAdapter.Rollback;
var
  LSql: string;
begin
  if not FStarted then
    Exit;

  if FIsMain then
    FOriginalTransaction.Rollback
  else
  begin
    LSql := FOriginalTransaction.GetConnection.GetSQLDialect.GetRollbackToSavepointSQL(FSavepointName);
    FOriginalTransaction.ExecSql(LSql);
    FStarted := False;
  end;
end;

function TFDScopeTransactionAdapter.InTransaction: Boolean;
begin
  Result := FOriginalTransaction.InTransaction;
end;

function TFDScopeTransactionAdapter.IsMain: Boolean;
begin
  Result := FIsMain;
end;

function TFDScopeTransactionAdapter.GetOriginalTransaction: ITransaction;
begin
  Result := FOriginalTransaction;
end;

{ TFDParamsAdapter }

constructor TFDParamsAdapter.Create(AQuery: TFDQuery);
begin
  FQuery := AQuery;
end;

function TFDParamsAdapter.FindParam(const AName: string): TFDParam;
begin
  Result := FQuery.Params.FindParam(AName);
end;

function TFDParamsAdapter.GetString(const AName: string): string;
begin
  Result := FQuery.ParamByName(AName).AsString;
end;

function TFDParamsAdapter.GetBoolean(const AName: string): Boolean;
begin
  Result := FQuery.ParamByName(AName).AsBoolean;
end;

function TFDParamsAdapter.GetDateTime(const AName: string): TDateTime;
begin
  Result := FQuery.ParamByName(AName).AsDateTime;
end;

function TFDParamsAdapter.GetDouble(const AName: string): Double;
begin
  Result := FQuery.ParamByName(AName).AsFloat;
end;

function TFDParamsAdapter.GetInteger(const AName: string): Integer;
begin
  Result := FQuery.ParamByName(AName).AsInteger;
end;

function TFDParamsAdapter.GetInt64(const AName: string): Int64;
begin
  Result := FQuery.ParamByName(AName).AsLargeInt;
end;

function TFDParamsAdapter.GetCurrency(const AName: string): Currency;
begin
  Result := FQuery.ParamByName(AName).AsCurrency;
end;

procedure TFDParamsAdapter.SetString(const AName: string; AValue: string);
begin
  FQuery.ParamByName(AName).AsString := AValue;
end;

procedure TFDParamsAdapter.SetBoolean(const AName: string; AValue: Boolean);
begin
  FQuery.ParamByName(AName).AsBoolean := AValue;
end;

procedure TFDParamsAdapter.SetDateTime(const AName: string; AValue: TDateTime);
begin
  FQuery.ParamByName(AName).AsDateTime := AValue;
end;

procedure TFDParamsAdapter.SetDouble(const AName: string; AValue: Double);
begin
  FQuery.ParamByName(AName).AsFloat := AValue;
end;

procedure TFDParamsAdapter.SetInteger(const AName: string; AValue: Integer);
begin
  FQuery.ParamByName(AName).AsInteger := AValue;
end;

procedure TFDParamsAdapter.SetInt64(const AName: string; AValue: Int64);
begin
  FQuery.ParamByName(AName).AsLargeInt := AValue;
end;

procedure TFDParamsAdapter.SetCurrency(const AName: string; AValue: Currency);
begin
  FQuery.ParamByName(AName).AsCurrency := AValue;
end;

// --- OptNull getters ---

function TFDParamsAdapter.GetOptNullString(const AName: string): IOptNullString;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullString.Undefined);
  if LParam.IsNull then Exit(TOptNullString.Null);
  Result := TOptNullString.From(LParam.AsString);
end;

function TFDParamsAdapter.GetOptNullBoolean(const AName: string): IOptNullBoolean;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullBoolean.Undefined);
  if LParam.IsNull then Exit(TOptNullBoolean.Null);
  Result := TOptNullBoolean.From(LParam.AsBoolean);
end;

function TFDParamsAdapter.GetOptNullDateTime(const AName: string): IOptNullDateTime;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullDateTime.Undefined);
  if LParam.IsNull then Exit(TOptNullDateTime.Null);
  Result := TOptNullDateTime.From(LParam.AsDateTime);
end;

function TFDParamsAdapter.GetOptNullInteger(const AName: string): IOptNullInteger;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullInteger.Undefined);
  if LParam.IsNull then Exit(TOptNullInteger.Null);
  Result := TOptNullInteger.From(LParam.AsInteger);
end;

function TFDParamsAdapter.GetOptNullInt64(const AName: string): IOptNullInt64;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullInt64.Undefined);
  if LParam.IsNull then Exit(TOptNullInt64.Null);
  Result := TOptNullInt64.From(LParam.AsLargeInt);
end;

function TFDParamsAdapter.GetOptNullDouble(const AName: string): IOptNullDouble;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullDouble.Undefined);
  if LParam.IsNull then Exit(TOptNullDouble.Null);
  Result := TOptNullDouble.From(LParam.AsFloat);
end;

function TFDParamsAdapter.GetOptNullCurrency(const AName: string): IOptNullCurrency;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) then Exit(TOptNullCurrency.Undefined);
  if LParam.IsNull then Exit(TOptNullCurrency.Null);
  Result := TOptNullCurrency.From(LParam.AsCurrency);
end;

// --- Null getters ---

function TFDParamsAdapter.GetNullString(const AName: string): INullString;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullString.Null);
  Result := TOptNullString.From(LParam.AsString);
end;

function TFDParamsAdapter.GetNullBoolean(const AName: string): INullBoolean;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullBoolean.Null);
  Result := TOptNullBoolean.From(LParam.AsBoolean) as INullBoolean;
end;

function TFDParamsAdapter.GetNullDateTime(const AName: string): INullDateTime;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullDateTime.Null);
  Result := TOptNullDateTime.From(LParam.AsDateTime);
end;

function TFDParamsAdapter.GetNullInteger(const AName: string): INullInteger;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullInteger.Null);
  Result := TOptNullInteger.From(LParam.AsInteger);
end;

function TFDParamsAdapter.GetNullInt64(const AName: string): INullInt64;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullInt64.Null);
  Result := TOptNullInt64.From(LParam.AsLargeInt);
end;

function TFDParamsAdapter.GetNullDouble(const AName: string): INullDouble;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullDouble.Null);
  Result := TOptNullDouble.From(LParam.AsFloat);
end;

function TFDParamsAdapter.GetNullCurrency(const AName: string): INullCurrency;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullCurrency.Null);
  Result := TOptNullCurrency.From(LParam.AsCurrency);
end;

// --- Opt (non-null optional) getters ---

function TFDParamsAdapter.GetOptString(const AName: string): IOptString;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullString.Undefined);
  Result := TOptNullString.From(LParam.AsString);
end;

function TFDParamsAdapter.GetOptBoolean(const AName: string): IOptBoolean;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullBoolean.Undefined);
  Result := TOptNullBoolean.From(LParam.AsBoolean) as IOptBoolean;
end;

function TFDParamsAdapter.GetOptDateTime(const AName: string): IOptDateTime;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullDateTime.Undefined);
  Result := TOptNullDateTime.From(LParam.AsDateTime);
end;

function TFDParamsAdapter.GetOptInteger(const AName: string): IOptInteger;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullInteger.Undefined);
  Result := TOptNullInteger.From(LParam.AsInteger);
end;

function TFDParamsAdapter.GetOptInt64(const AName: string): IOptInt64;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullInt64.Undefined);
  Result := TOptNullInt64.From(LParam.AsLargeInt);
end;

function TFDParamsAdapter.GetOptDouble(const AName: string): IOptDouble;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullDouble.Undefined);
  Result := TOptNullDouble.From(LParam.AsFloat);
end;

function TFDParamsAdapter.GetOptCurrency(const AName: string): IOptCurrency;
var
  LParam: TFDParam;
begin
  LParam := FindParam(AName);
  if not Assigned(LParam) or LParam.IsNull then Exit(TOptNullCurrency.Undefined);
  Result := TOptNullCurrency.From(LParam.AsCurrency);
end;

// --- OptNull setters (Undefined → skip, Null → Clear, valor → set) ---

procedure TFDParamsAdapter.SetOptNullString(const AName: string; AValue: IOptNullString);
begin
  FQuery.Params.ParamByNameOptional(AName, AValue);
end;

procedure TFDParamsAdapter.SetOptNullBoolean(const AName: string; AValue: IOptNullBoolean);
begin
  if not AValue.HasValue then Exit;
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsBoolean := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptNullDateTime(const AName: string; AValue: IOptNullDateTime);
begin
  FQuery.Params.ParamByNameOptional(AName, AValue);
end;

procedure TFDParamsAdapter.SetOptNullInteger(const AName: string; AValue: IOptNullInteger);
begin
  FQuery.Params.ParamByNameOptional(AName, AValue);
end;

procedure TFDParamsAdapter.SetOptNullInt64(const AName: string; AValue: IOptNullInt64);
begin
  FQuery.Params.ParamByNameOptional(AName, AValue);
end;

procedure TFDParamsAdapter.SetOptNullDouble(const AName: string; AValue: IOptNullDouble);
begin
  if not AValue.HasValue then Exit;
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsFloat := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptNullCurrency(const AName: string; AValue: IOptNullCurrency);
begin
  FQuery.Params.ParamByNameOptional(AName, AValue);
end;

// --- Null setters (sempre Null ou valor, nunca Undefined) ---

procedure TFDParamsAdapter.SetNullString(const AName: string; AValue: INullString);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsString := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullBoolean(const AName: string; AValue: INullBoolean);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsBoolean := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullDateTime(const AName: string; AValue: INullDateTime);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsDateTime := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullInteger(const AName: string; AValue: INullInteger);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsInteger := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullInt64(const AName: string; AValue: INullInt64);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsLargeInt := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullDouble(const AName: string; AValue: INullDouble);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsFloat := AValue.Value;
end;

procedure TFDParamsAdapter.SetNullCurrency(const AName: string; AValue: INullCurrency);
begin
  if AValue.IsNull then FQuery.ParamByName(AName).Clear
  else FQuery.ParamByName(AName).AsCurrency := AValue.Value;
end;

// --- Opt setters (Undefined → skip, valor → set; IsNull não se aplica) ---

procedure TFDParamsAdapter.SetOptString(const AName: string; AValue: IOptString);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsString := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptBoolean(const AName: string; AValue: IOptBoolean);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsBoolean := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptDateTime(const AName: string; AValue: IOptDateTime);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsDateTime := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptInteger(const AName: string; AValue: IOptInteger);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsInteger := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptInt64(const AName: string; AValue: IOptInt64);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsLargeInt := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptDouble(const AName: string; AValue: IOptDouble);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsFloat := AValue.Value;
end;

procedure TFDParamsAdapter.SetOptCurrency(const AName: string; AValue: IOptCurrency);
begin
  if not AValue.HasValue then Exit;
  FQuery.ParamByName(AName).AsCurrency := AValue.Value;
end;

{ TFDQueryAdapter }

constructor TFDQueryAdapter.Create(AQuery: TFDQuery; AConn: IDBConnection; ATransaction: ITransaction);
begin
  FQuery := AQuery;
  FConn := AConn;
  FTransaction := ATransaction;
  FParams := TFDParamsAdapter.Create(FQuery);
end;

destructor TFDQueryAdapter.Destroy;
begin
  FQuery.Free;
  inherited Destroy;
end;

function TFDQueryAdapter.FieldByName(const AName: string): Variant;
begin
  Result := FQuery.FieldByName(AName).AsVariant;
end;

procedure TFDQueryAdapter.Close;
begin
  if FQuery.Active then
    FQuery.Close;
end;

function TFDQueryAdapter.Eof: Boolean;
begin
  Result := FQuery.Eof;
end;

procedure TFDQueryAdapter.ExecSql;
begin
  FQuery.ExecSQL;
end;

function TFDQueryAdapter.FieldCount: Integer;
begin
  Result := FQuery.FieldCount;
end;

function TFDQueryAdapter.FieldValue(AIndex: Integer): Variant;
begin
  Result := FQuery.Fields[AIndex].AsVariant;
end;

function TFDQueryAdapter.GetAsBoolean(const AName: string): Boolean;
begin
  Result := FieldByName(AName);
end;

function TFDQueryAdapter.GetAsDateTime(const AName: string): TDateTime;
begin
  Result := FieldByName(AName);
end;

function TFDQueryAdapter.GetAsInteger(const AName: string): Integer;
begin
  Result := FieldByName(AName);
end;

function TFDQueryAdapter.GetAsInt64(const AName: string): Int64;
begin
  Result := FieldByName(AName);
end;

function TFDQueryAdapter.GetAsString(const AName: string): string;
begin
  Result := FieldByName(AName);
end;

function TFDQueryAdapter.GetAsCurrency(const AName: string): Currency;
begin
  Result := FQuery.FieldByName(AName).AsCurrency;
end;

function TFDQueryAdapter.GetConnection: IDBConnection;
begin
  Result := FConn;
end;

function TFDQueryAdapter.GetNullableBoolean(const AName: string): INullBoolean;
begin
  Result := FieldByName(AName).ToNullableBoolean;
end;

function TFDQueryAdapter.GetNullableDateTime(const AName: string): INullDateTime;
begin
  Result := FieldByName(AName).ToNullableDateTime;
end;

function TFDQueryAdapter.GetNullableInteger(const AName: string): INullInteger;
begin
  Result := FieldByName(AName).ToNullableInteger;
end;

function TFDQueryAdapter.GetNullableInt64(const AName: string): INullInt64;
begin
  Result := FieldByName(AName).ToNullableInt64;
end;

function TFDQueryAdapter.GetNullableString(const AName: string): INullString;
begin
  Result := FieldByName(AName).ToNullableString;
end;

function TFDQueryAdapter.GetNullableCurrency(const AName: string): INullCurrency;
begin
  Result := FieldByName(AName).ToNullableCurrency;
end;

function TFDQueryAdapter.GetParams: IParams;
begin
  Result := FParams;
end;

function TFDQueryAdapter.GetTransaction: ITransaction;
begin
  Result := FTransaction;
end;

function TFDQueryAdapter.IsEmpty: Boolean;
begin
  Result := FQuery.RecordCount <= 0;
end;

procedure TFDQueryAdapter.Next;
begin
  FQuery.Next;
end;

function TFDQueryAdapter.Open: IQueryResult;
begin
  if not FTransaction.InTransaction then
    FTransaction.StartTransaction;

  if FQuery.Active then
    FQuery.Close;

  FQuery.Open;
  Result := Self;
end;

function TFDQueryAdapter.RecordCount: Integer;
begin
  Result := FQuery.RecordCount;
end;

procedure TFDQueryAdapter.SetSql(const ASql: string);
begin
  if FQuery.Active then
    FQuery.Close;

  FQuery.Params.Clear;
  FQuery.SQL.Text := ASql;
end;

function TFDQueryAdapter.GetSql: string;
begin
  Result := FQuery.SQL.Text;
end;

{ TFDScriptAdapter }

constructor TFDScriptAdapter.Create(AConn: IDBConnection; ATransaction: ITransaction);
begin
  FScript := TStringList.Create;
  FConn := AConn;
  FTransaction := ATransaction;
end;

destructor TFDScriptAdapter.Destroy;
begin
  FScript.Free;
  inherited Destroy;
end;

procedure TFDScriptAdapter.ExecuteScript(ATerminator: string);
var
  LParts: TArray<string>;
  LStatement: string;
  LQuery: TFDQuery;
begin
  if ATerminator = '' then
    ATerminator := ';';

  LParts := FScript.Text.Split([ATerminator]);
  for LStatement in LParts do
  begin
    if Trim(LStatement) = '' then
      Continue;

    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := FConn.GetNativeConnection as TFDConnection;
      LQuery.Transaction := FTransaction.GetNativeTransaction as TFDTransaction;
      LQuery.SQL.Text := Trim(LStatement);
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;
  end;
end;

function TFDScriptAdapter.GetConnection: IDBConnection;
begin
  Result := FConn;
end;

function TFDScriptAdapter.GetScript: TStrings;
begin
  Result := FScript;
end;

function TFDScriptAdapter.GetTransaction: ITransaction;
begin
  Result := FTransaction;
end;

procedure TFDScriptAdapter.SetScript(AValue: TStrings);
begin
  FScript.Assign(AValue);
end;

{ TFDConfig }

constructor TFDConfig.Create;
begin
  FConnectionParams := TStringList.Create;
end;

destructor TFDConfig.Destroy;
begin
  FConnectionParams.Free;
  inherited Destroy;
end;

function TFDConfig.GetPoolIniConnections: Integer;
begin
  Result := FPoolIniConnections;
end;

function TFDConfig.GetPoolMaxConnections: Integer;
begin
  Result := FPoolMaxConnections;
end;

function TFDConfig.GetPoolWaitMaxAttemps: Integer;
begin
  Result := FPoolWaitMaxAttemps;
end;

function TFDConfig.GetPoolWaitMilliseconds: Integer;
begin
  Result := FPoolWaitMilliseconds;
end;

function TFDConfig.GetSQLDialect: string;
begin
  Result := FSQLDialect;
end;

procedure TFDConfig.SetPoolIniConnections(AValue: Integer);
begin
  FPoolIniConnections := AValue;
end;

procedure TFDConfig.SetPoolMaxConnections(AValue: Integer);
begin
  FPoolMaxConnections := AValue;
end;

procedure TFDConfig.SetPoolWaitMaxAttemps(AValue: Integer);
begin
  FPoolWaitMaxAttemps := AValue;
end;

procedure TFDConfig.SetPoolWaitMilliseconds(AValue: Integer);
begin
  FPoolWaitMilliseconds := AValue;
end;

procedure TFDConfig.SetSQLDialect(AValue: string);
begin
  FSQLDialect := AValue;
end;

{ TFDProvider }

function TFDProvider.BuildConnection(AConfig: IDatabaseConfig): IDBConnection;
var
  LConn: TFDConnection;
begin
  LConn := TFDConnection.Create(nil);
  LConn.LoginPrompt := False;
  LConn.Params.AddStrings((AConfig as TFDConfig).ConnectionParams);
  LConn.Connected := True;
  Result := TFDConnectionAdapter.Create(
    LConn,
    TSQLDialectFactory.GetDialect(AConfig.SQLDialect)
  );
end;

function TFDProvider.BuildTransaction(AConn: IDBConnection): ITransaction;
var
  LTrans: TFDTransaction;
begin
  LTrans := TFDTransaction.Create(nil);
  LTrans.Connection := AConn.GetNativeConnection as TFDConnection;
  Result := TFDTransactionAdapter.Create(AConn, LTrans);
end;

function TFDProvider.BuildScopeTransaction(ATransaction: ITransaction;
  AContextTransaction: IContextTransaction): IScopeTransaction;
begin
  Result := TFDScopeTransactionAdapter.Create(ATransaction, AContextTransaction);
end;

function TFDProvider.BuildQuery(AConn: IDBConnection; ATransaction: ITransaction): IQuery;
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  LQuery.Connection := AConn.GetNativeConnection as TFDConnection;
  LQuery.Transaction := ATransaction.GetNativeTransaction as TFDTransaction;
  Result := TFDQueryAdapter.Create(LQuery, AConn, ATransaction);
end;

function TFDProvider.BuildSqlScript(AConn: IDBConnection; ATransaction: ITransaction): ISqlScript;
begin
  Result := TFDScriptAdapter.Create(AConn, ATransaction);
end;

{ TFDFactory }

constructor TFDFactory.Create(AConfig: IDatabaseConfig;
  AContextTransactionProvider: IContextTransactionProvider);
var
  LPoolConfig: IConnectionPoolConfig;
begin
  FConfig := AConfig;
  FComponentProvider := TFDProvider.Create;

  LPoolConfig := TConnectionPoolConfig.Create;
  LPoolConfig.WaitMaxAttemps  := FConfig.PoolWaitMaxAttemps;
  LPoolConfig.WaitMilliseconds := FConfig.PoolWaitMilliseconds;
  LPoolConfig.IniConnections  := FConfig.PoolIniConnections;
  LPoolConfig.MaxConnections  := FConfig.PoolMaxConnections;

  FPool := TConnectionPool.Create(Self, LPoolConfig);
  FSqlLoader := TSQLLoader.Create((AConfig as TFDConfig).SQLDirectory);

  FContextTransactionProvider := AContextTransactionProvider;
end;

destructor TFDFactory.Destroy;
begin
  FSqlLoader.Free;
  inherited Destroy;
end;

function TFDFactory.GetProvider: IDBComponentProvider;
begin
  Result := FComponentProvider;
end;

procedure TFDFactory.SetProvider(AProvider: IDBComponentProvider);
begin
  if not Assigned(AProvider) then
    Exit;
  FComponentProvider := AProvider;
end;

function TFDFactory.SqlLoader: TSQLLoader;
begin
  Result := FSqlLoader;
end;

function TFDFactory.GetPool: IDBConnectionPool;
begin
  Result := FPool;
end;

function TFDFactory.CreateConnection: IDBConnection;
begin
  Result := FComponentProvider.BuildConnection(FConfig);
end;

function TFDFactory.CreateTransaction(AConn: IDBConnection): ITransaction;
begin
  Result := FComponentProvider.BuildTransaction(AConn);
end;

function TFDFactory.CreateScopeTransaction(ATransaction: ITransaction): IScopeTransaction;
begin
  if Assigned(FContextTransactionProvider) then
    Result := FComponentProvider.BuildScopeTransaction(
      ATransaction,
      FContextTransactionProvider.GetContextTransaction
    )
  else
    Result := FComponentProvider.BuildScopeTransaction(ATransaction, nil);
end;

function TFDFactory.CreateQuery(AConn: IDBConnection; ATransaction: ITransaction): IQuery;
begin
  Result := FComponentProvider.BuildQuery(AConn, ATransaction);
end;

function TFDFactory.CreateSqlScript(AConn: IDBConnection; ATransaction: ITransaction): ISqlScript;
begin
  Result := FComponentProvider.BuildSqlScript(AConn, ATransaction);
end;

function TFDFactory.TestConnection(AConn: IDBConnection): Boolean;
begin
  Result := False;
  try
    if not AConn.IsConnected then
      AConn.Connect;
    // TFDConnection.Ping envia um roundtrip ao servidor e lança exceção se morto
    (AConn.GetNativeConnection as TFDConnection).Ping;
    Result := True;
  except
    on E: Exception do
      Writeln('>>> Conexão morta detectada: ' + E.Message);
  end;
end;

end.
