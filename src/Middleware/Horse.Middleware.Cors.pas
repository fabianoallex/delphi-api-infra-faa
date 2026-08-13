unit Horse.Middleware.Cors;

interface

uses
  Horse.Callback;

type
  /// Opções do middleware CORS.
  /// Use TCorsOptions.Default como ponto de partida e ajuste os campos necessários.
  TCorsOptions = record
    /// Origem(ns) permitidas. '*' libera qualquer origem (incompatível com AllowCredentials=True).
    /// Para origem única, informe o valor exato (ex: 'https://app.example.com').
    AllowOrigin: string;
    /// Métodos HTTP aceitos. Padrão: GET,POST,PUT,PATCH,DELETE,OPTIONS.
    AllowMethods: string;
    /// Headers de requisição aceitos. Padrão: Content-Type,Authorization.
    AllowHeaders: string;
    /// Permite envio de cookies/credenciais. Requer AllowOrigin com origem exata (não '*').
    AllowCredentials: Boolean;
    /// Tempo em segundos que o browser pode cachear a resposta preflight. Padrão: 86400.
    MaxAge: Integer;
    /// Headers de resposta extras expostos ao JavaScript (além dos safe-listed). Padrão: ''.
    ExposeHeaders: string;
    class function Default: TCorsOptions; static;
  end;

  /// Middleware CORS para Horse.
  ///
  /// Comportamento:
  ///   - Requisições OPTIONS (preflight): responde 204 com headers CORS e NÃO chama Next.
  ///   - Demais requisições: adiciona headers CORS e chama Next normalmente.
  ///   - AllowOrigin='*': envia '*' incondicionalmente.
  ///   - AllowOrigin com valor específico: envia o header apenas se o Origin da requisição
  ///     bater exatamente; adiciona 'Vary: Origin' para evitar cache incorreto.
  ///   - Origin ausente ou não correspondente: nenhum header CORS é emitido.
  ///
  /// Uso no DPR (antes de RegisterRoutes, após TErrorHandlerMiddleware):
  ///
  ///   // Desenvolvimento — libera qualquer origem
  ///   THorse.Use(TCorsMiddleware.New);
  ///
  ///   // Produção — origem única
  ///   THorse.Use(TCorsMiddleware.New('https://app.example.com'));
  ///
  ///   // Configuração completa
  ///   var LCors: TCorsOptions;
  ///   LCors := TCorsOptions.Default;
  ///   LCors.AllowOrigin      := 'https://app.example.com';
  ///   LCors.AllowCredentials := True;
  ///   LCors.ExposeHeaders    := 'X-Total-Count';
  ///   THorse.Use(TCorsMiddleware.New(LCors));
  TCorsMiddleware = class
  public
    /// Defaults: AllowOrigin=*, AllowCredentials=False.
    class function New: THorseCallback; overload;
    /// Mesmos defaults, com AllowOrigin configurável.
    class function New(const AAllowOrigin: string): THorseCallback; overload;
    /// Controle total via TCorsOptions.
    class function New(const AOptions: TCorsOptions): THorseCallback; overload;
  end;

implementation

uses
  System.SysUtils,
  Horse;

const
  DEFAULT_METHODS = 'GET,POST,PUT,PATCH,DELETE,OPTIONS';
  DEFAULT_HEADERS = 'Content-Type,Authorization';
  DEFAULT_MAX_AGE = 86400;

{ TCorsOptions }

class function TCorsOptions.Default: TCorsOptions;
begin
  Result.AllowOrigin      := '*';
  Result.AllowMethods     := DEFAULT_METHODS;
  Result.AllowHeaders     := DEFAULT_HEADERS;
  Result.AllowCredentials := False;
  Result.MaxAge           := DEFAULT_MAX_AGE;
  Result.ExposeHeaders    := '';
end;

{ TCorsMiddleware }

class function TCorsMiddleware.New: THorseCallback;
begin
  Result := New(TCorsOptions.Default);
end;

class function TCorsMiddleware.New(const AAllowOrigin: string): THorseCallback;
var
  LOptions: TCorsOptions;
begin
  LOptions             := TCorsOptions.Default;
  LOptions.AllowOrigin := AAllowOrigin;
  Result := New(LOptions);
end;

class function TCorsMiddleware.New(const AOptions: TCorsOptions): THorseCallback;
var
  LOptions: TCorsOptions;
begin
  LOptions := AOptions;
  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LRequestOrigin: string;
      LAllowOrigin:   string;
    begin
      LRequestOrigin := Req.Headers['Origin'];

      if LOptions.AllowOrigin = '*' then
        LAllowOrigin := '*'
      else if SameText(LRequestOrigin, LOptions.AllowOrigin) then
        LAllowOrigin := LRequestOrigin
      else
        LAllowOrigin := '';

      if LAllowOrigin <> '' then
      begin
        Res.AddHeader('Access-Control-Allow-Origin',  LAllowOrigin);
        Res.AddHeader('Access-Control-Allow-Methods', LOptions.AllowMethods);
        Res.AddHeader('Access-Control-Allow-Headers', LOptions.AllowHeaders);

        if LOptions.AllowOrigin <> '*' then
          Res.AddHeader('Vary', 'Origin');

        if LOptions.AllowCredentials then
          Res.AddHeader('Access-Control-Allow-Credentials', 'true');

        if LOptions.MaxAge > 0 then
          Res.AddHeader('Access-Control-Max-Age', IntToStr(LOptions.MaxAge));

        if LOptions.ExposeHeaders <> '' then
          Res.AddHeader('Access-Control-Expose-Headers', LOptions.ExposeHeaders);
      end;

      // Preflight — responde diretamente sem chamar Next
      if SameText(Req.Method, 'OPTIONS') then
      begin
        Res.Status(204).Send('');
        Exit;
      end;

      Next();
    end;
end;

end.
