unit Horse.Middleware.Auth;

interface

uses
  Horse.Callback;

type
  /// Callback que valida o token extraído do header Authorization.
  /// Retorne True para autorizar, False para rejeitar com 401.
  TTokenValidator = reference to function(const AToken: string): Boolean;

  /// Middleware de autenticação Bearer.
  ///
  /// Fluxo:
  ///   1. Paths que começam com um dos AExcludedPrefixes passam direto (Next).
  ///   2. Ausência do header Authorization  → 401
  ///   3. Header sem prefixo "Bearer "      → 401
  ///   4. AValidator retorna False          → 401
  ///   5. AValidator retorna True           → Next
  ///
  /// Uso no DPR (após TErrorHandlerMiddleware, antes de RegisterRoutes):
  ///
  ///   THorse.Use(TAuthMiddleware.Bearer(
  ///     function(const AToken: string): Boolean
  ///     begin
  ///       Result := AToken = TAppConfig.Get('API_KEY', '');
  ///     end,
  ///     ['/health', '/swagger']));
  TAuthMiddleware = class
  public
    class function Bearer(
      AValidator: TTokenValidator;
      const AExcludedPrefixes: array of string): THorseCallback; overload;

    class function Bearer(
      AValidator: TTokenValidator): THorseCallback; overload;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Horse;

procedure SendUnauthorized(Res: THorseResponse; const AMessage: string);
var
  LJson: TJSONObject;
begin
  LJson := TJSONObject.Create;
  try
    LJson.AddPair('error', AMessage);
    Res.Status(401)
       .ContentType('application/json; charset=utf-8')
       .Send(LJson.ToJSON);
  finally
    LJson.Free;
  end;
end;

class function TAuthMiddleware.Bearer(
  AValidator: TTokenValidator;
  const AExcludedPrefixes: array of string): THorseCallback;
var
  LExcluded: TArray<string>;
  I: Integer;
begin
  SetLength(LExcluded, Length(AExcludedPrefixes));
  for I := 0 to High(AExcludedPrefixes) do
    LExcluded[I] := AExcludedPrefixes[I];

  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LPath:  string;
      LAuth:  string;
      LToken: string;
      LExcl:  string;
    begin
      LPath := Req.PathInfo;
      for LExcl in LExcluded do
        if LPath.StartsWith(LExcl, True) then
        begin
          Next();
          Exit;
        end;

      LAuth := Req.Headers['Authorization'];
      if LAuth.IsEmpty then
      begin
        SendUnauthorized(Res, 'Token de autorização ausente.');
        Exit;
      end;

      if not LAuth.StartsWith('Bearer ', True) then
      begin
        SendUnauthorized(Res, 'Formato inválido. Use: Authorization: Bearer <token>');
        Exit;
      end;

      LToken := Trim(LAuth.Substring(7));
      if LToken.IsEmpty or not AValidator(LToken) then
      begin
        SendUnauthorized(Res, 'Token inválido ou expirado.');
        Exit;
      end;

      Next();
    end;
end;

class function TAuthMiddleware.Bearer(
  AValidator: TTokenValidator): THorseCallback;
begin
  Result := Bearer(AValidator, []);
end;

end.
