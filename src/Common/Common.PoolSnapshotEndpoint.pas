unit Common.PoolSnapshotEndpoint;

interface

uses
  System.JSON,
  Db.Interfaces;

type
  /// Um acesso a banco nomeado, para o overload multi-pool de
  /// TPoolSnapshotEndpoint.Register — aplicações com mais de um IDBFactory
  /// (bancos diferentes, ou o mesmo banco com pools separados) usam o nome
  /// para distinguir cada um na resposta.
  TNamedPool = record
    Name: string;
    Factory: IDBFactory;
    class function New(const AName: string; AFactory: IDBFactory): TNamedPool; static;
  end;

  /// Registra GET /pool/snapshot no Horse (fora do Swagger e do MCP), expondo
  /// o mesmo TPoolSnapshot (IDBFactory.GetPool.GetSnapshot) que
  /// TSnapshotPoolLogger grava periodicamente em arquivo — mesmos números,
  /// mas para acompanhamento online (dashboard, curl, etc.) em vez de log.
  ///
  /// Diferente de THealthCheck, este endpoint expõe métricas internas do
  /// pool (não é um probe de infraestrutura) — se precisar de autenticação,
  /// registre-o DEPOIS do middleware de auth (TAuthMiddleware/TJwtMiddleware)
  /// no DPR, ao contrário do padrão "health check antes dos middlewares".
  ///
  /// Uso no DPR com um único acesso a banco (após criar LFactory):
  ///   TPoolSnapshotEndpoint.Register(LFactory);
  ///
  /// Resposta (200) — overload de um único factory:
  ///   {
  ///     "activeConnections": 2,
  ///     "idleConnections": 1,
  ///     "maxConnections": 20,
  ///     "iniConnections": 3,
  ///     "totalCreated": 5,
  ///     "totalDiscarded": 0,
  ///     "totalTimeouts": 0,
  ///     "totalIdleSwept": 0,
  ///     "timestamp": "2026-08-25T14:03:10"
  ///   }
  ///
  /// Uso no DPR com múltiplos acessos a banco (ex.: principal + fiscal + logs):
  ///   TPoolSnapshotEndpoint.Register([
  ///     TNamedPool.New('principal', LFactoryPrincipal),
  ///     TNamedPool.New('fiscal',    LFactoryFiscal),
  ///     TNamedPool.New('logs',      LFactoryLogs)
  ///   ]);
  ///
  /// Resposta (200) — overload multi-pool: mesmos campos de cada pool,
  /// agrupados por nome em "pools":
  ///   {
  ///     "pools": {
  ///       "principal": { "activeConnections": 2, "idleConnections": 1, ... },
  ///       "fiscal":    { "activeConnections": 0, "idleConnections": 3, ... },
  ///       "logs":      { "activeConnections": 1, "idleConnections": 0, ... }
  ///     },
  ///     "timestamp": "2026-08-25T14:03:10"
  ///   }
  TPoolSnapshotEndpoint = class
  private
    class function BuildSnapshotJson(AFactory: IDBFactory): TJSONObject;
  public
    class procedure Register(AFactory: IDBFactory;
      const APath: string = '/pool/snapshot'); overload;
    class procedure Register(const APools: array of TNamedPool;
      const APath: string = '/pool/snapshot'); overload;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Horse;

{ TNamedPool }

class function TNamedPool.New(const AName: string; AFactory: IDBFactory): TNamedPool;
begin
  Result.Name    := AName;
  Result.Factory := AFactory;
end;

{ TPoolSnapshotEndpoint }

class function TPoolSnapshotEndpoint.BuildSnapshotJson(AFactory: IDBFactory): TJSONObject;
var
  LSnap: TPoolSnapshot;
  LJson: TJSONObject;
begin
  LSnap := AFactory.GetPool.GetSnapshot;

  LJson := TJSONObject.Create;
  LJson.AddPair('activeConnections', TJSONNumber.Create(LSnap.ActiveConnections));
  LJson.AddPair('idleConnections',   TJSONNumber.Create(LSnap.PoolSize));
  LJson.AddPair('maxConnections',    TJSONNumber.Create(LSnap.MaxConnections));
  LJson.AddPair('iniConnections',    TJSONNumber.Create(LSnap.IniConnections));
  LJson.AddPair('totalCreated',      TJSONNumber.Create(LSnap.TotalCreated));
  LJson.AddPair('totalDiscarded',    TJSONNumber.Create(LSnap.TotalDiscarded));
  LJson.AddPair('totalTimeouts',     TJSONNumber.Create(LSnap.TotalTimeouts));
  LJson.AddPair('totalIdleSwept',    TJSONNumber.Create(LSnap.TotalIdleSwept));
  Result := LJson;
end;

class procedure TPoolSnapshotEndpoint.Register(AFactory: IDBFactory;
  const APath: string);
begin
  THorse.Get(APath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LJson: TJSONObject;
    begin
      LJson := BuildSnapshotJson(AFactory);
      try
        LJson.AddPair('timestamp', DateToISO8601(Now, False));

        Res.Status(200)
           .ContentType('application/json; charset=utf-8')
           .Send(LJson.ToJSON);
      finally
        LJson.Free;
      end;
    end);
end;

class procedure TPoolSnapshotEndpoint.Register(const APools: array of TNamedPool;
  const APath: string);
var
  LNamedPools: TArray<TNamedPool>;
  I: Integer;
begin
  // captura por valor, fora da closure — Register pode ser chamado com um
  // array literal cujo storage não sobrevive além desta chamada; array of T
  // (parâmetro open array) não é assignment-compatible com TArray<T>, por
  // isso a cópia é feita elemento a elemento, não por atribuição direta
  SetLength(LNamedPools, Length(APools));
  for I := 0 to High(APools) do
    LNamedPools[I] := APools[I];

  THorse.Get(APath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LJson:  TJSONObject;
      LPools: TJSONObject;
      LPool:  TNamedPool;
    begin
      LJson := TJSONObject.Create;
      try
        // LPools entra em LJson antes de ser populado — se BuildSnapshotJson
        // lançar no meio do loop, LJson.Free (no finally) já cobre LPools e
        // tudo que já tiver sido adicionado a ele, sem try/finally aninhado
        LPools := TJSONObject.Create;
        LJson.AddPair('pools', LPools);

        for LPool in LNamedPools do
          LPools.AddPair(LPool.Name, BuildSnapshotJson(LPool.Factory));

        LJson.AddPair('timestamp', DateToISO8601(Now, False));

        Res.Status(200)
           .ContentType('application/json; charset=utf-8')
           .Send(LJson.ToJSON);
      finally
        LJson.Free;
      end;
    end);
end;

end.
