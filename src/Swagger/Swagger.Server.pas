unit Swagger.Server;

interface

uses
  Swag.Doc;

type
  TSwaggerServer = class
  public
    /// <summary>
    /// Registers two Horse routes:
    ///   GET ABasePath/doc.json  → serves the Swagger JSON
    ///   GET ABasePath           → serves the Swagger UI (CDN)
    /// The doc is serialized once at registration time; ADoc can be freed afterwards.
    /// </summary>
    class procedure Register(ADoc: TSwagDoc; const ABasePath: string = '/swagger');
  end;

implementation

uses
  System.SysUtils,
  Horse,
  Horse.Commons;

{ TSwaggerServer }

class procedure TSwaggerServer.Register(ADoc: TSwagDoc; const ABasePath: string);
var
  LDocUrl : string;
  LJsonStr: string;
  LHtml   : string;
begin
  ADoc.GenerateSwaggerJson;
  LJsonStr := ADoc.SwaggerJson.ToJSON;
  LDocUrl  := ABasePath + '/doc.json';

  LHtml :=
    '<!DOCTYPE html><html><head>' +
    '<title>Swagger UI</title><meta charset="utf-8"/>' +
    '<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">' +
    '</head><body><div id="swagger-ui"></div>' +
    '<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>' +
    '<script>window.onload=function(){SwaggerUIBundle({url:"' + LDocUrl + '",' +
    'dom_id:"#swagger-ui",' +
    'presets:[SwaggerUIBundle.presets.apis,SwaggerUIBundle.SwaggerUIStandalonePreset],' +
    'layout:"BaseLayout"})}</script></body></html>';

  THorse.Get(LDocUrl,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      Res.ContentType('application/json').Send(LJsonStr);
    end);

  THorse.Get(ABasePath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      Res.ContentType('text/html').Send(LHtml);
    end);
end;

end.
