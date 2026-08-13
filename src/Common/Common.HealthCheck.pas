unit Common.HealthCheck;

interface

uses
  Db.Interfaces;

type
  /// Registra GET /health no Horse (fora do Swagger e do MCP).
  /// Cria uma conexão temporária, testa com IDBFactory.TestConnection e a
  /// descarta — não consome conexões do pool.
  ///
  /// Uso no DPR (após criar LFactory, antes de TRouteDoc.Init):
  ///   THealthCheck.Register(LFactory);
  ///
  /// Respostas:
  ///   200  {"status":"ok"}
  ///   503  {"status":"degraded","detail":"<mensagem>"}
  THealthCheck = class
  public
    class procedure Register(AFactory: IDBFactory;
      const APath: string = '/health');
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Horse;

class procedure THealthCheck.Register(AFactory: IDBFactory;
  const APath: string);
begin
  THorse.Get(APath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LConn:   IDBConnection;
      LJson:   TJSONObject;
      LOk:     Boolean;
      LDetail: string;
    begin
      LOk     := False;
      LDetail := '';
      try
        LConn := AFactory.CreateConnection;
        LConn.Connect;
        try
          LOk := AFactory.TestConnection(LConn);
          if not LOk then
            LDetail := 'banco não respondeu ao teste de conectividade';
        finally
          LConn.Disconnect;
        end;
      except
        on E: Exception do
        begin
          LOk     := False;
          LDetail := E.Message;
        end;
      end;

      LJson := TJSONObject.Create;
      try
        if LOk then
        begin
          LJson.AddPair('status', 'ok');
          Res.Status(200)
             .ContentType('application/json; charset=utf-8')
             .Send(LJson.ToJSON);
        end
        else
        begin
          LJson.AddPair('status', 'degraded');
          if LDetail <> '' then
            LJson.AddPair('detail', LDetail);
          Res.Status(503)
             .ContentType('application/json; charset=utf-8')
             .Send(LJson.ToJSON);
        end;
      finally
        LJson.Free;
      end;
    end);
end;

end.
