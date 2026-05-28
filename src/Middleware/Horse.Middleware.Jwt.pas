unit Horse.Middleware.Jwt;

interface

uses
  Horse.Callback,
  Horse.Request,
  System.JSON;

type
  /// Middleware JWT com validação HS256.
  ///
  /// Valida assinatura HMAC-SHA256 e claim exp (expiração).
  /// Paths com prefixos excluídos passam sem validação.
  ///
  /// Uso no DPR (após TErrorHandlerMiddleware, antes de RegisterRoutes):
  ///
  ///   THorse.Use(TJwtMiddleware.New(
  ///     TAppConfig.Get('JWT_SECRET', ''),
  ///     ['/health', '/swagger', '/auth/login']));
  TJwtMiddleware = class
  public
    class function New(const ASecret: string;
      const AExcludedPrefixes: array of string): THorseCallback; overload;
    class function New(const ASecret: string): THorseCallback; overload;
  end;

  /// Utilitário JWT — validação de token e extração de claims.
  ///
  /// Uso em handlers para ler claims do token já validado pelo middleware:
  ///
  ///   var LClaims: TJSONObject;
  ///   LClaims := TJwtHelper.GetClaimsFromRequest(Req, ASecret);
  ///   try
  ///     if Assigned(LClaims) then
  ///       LUserId := LClaims.GetValue<string>('sub');
  ///   finally
  ///     LClaims.Free;
  ///   end;
  TJwtHelper = class
  public
    /// Valida assinatura e exp. Retorna os claims ou nil se inválido/expirado.
    /// O chamador deve libertar o TJSONObject retornado.
    class function GetClaims(const AToken, ASecret: string): TJSONObject; static;

    /// Retorna True se o token tem assinatura válida e não está expirado.
    class function Validate(const AToken, ASecret: string): Boolean; static;

    /// Extrai e valida o token do header Authorization da requisição.
    /// Retorna nil se ausente, inválido ou expirado. Chamador deve libertar.
    class function GetClaimsFromRequest(AReq: THorseRequest;
      const ASecret: string): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.NetEncoding,
  System.Hash,
  Horse,
  Horse.Middleware.Auth;

function Base64UrlDecode(const AInput: string): TBytes;
var
  LPadded: string;
begin
  LPadded := StringReplace(AInput, '-', '+', [rfReplaceAll]);
  LPadded := StringReplace(LPadded, '_', '/', [rfReplaceAll]);
  case Length(LPadded) mod 4 of
    2: LPadded := LPadded + '==';
    3: LPadded := LPadded + '=';
  end;
  Result := TNetEncoding.Base64.DecodeStringToBytes(LPadded);
end;

function Base64UrlEncode(const ABytes: TBytes): string;
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(ABytes);
  Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '=', '',  [rfReplaceAll]);
end;

function ComputeHmacSha256(const AData, AKey: string): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(
    TEncoding.UTF8.GetBytes(AData),
    TEncoding.UTF8.GetBytes(AKey));
end;

{ TJwtHelper }

class function TJwtHelper.GetClaims(const AToken, ASecret: string): TJSONObject;
var
  LParts:      TArray<string>;
  LExpected:   string;
  LPayload:    TJSONObject;
  LExpValue:   TJSONValue;
  LExpUnix:    Int64;
begin
  Result := nil;

  LParts := AToken.Split(['.']);
  if Length(LParts) <> 3 then
    Exit;

  // Valida assinatura
  LExpected := Base64UrlEncode(ComputeHmacSha256(LParts[0] + '.' + LParts[1], ASecret));
  if LExpected <> LParts[2] then
    Exit;

  // Decodifica payload
  try
    LPayload := TJSONObject.ParseJSONValue(
      TEncoding.UTF8.GetString(Base64UrlDecode(LParts[1]))) as TJSONObject;
  except
    Exit;
  end;

  if not Assigned(LPayload) then
    Exit;

  // Verifica expiração
  LExpValue := LPayload.GetValue('exp');
  if Assigned(LExpValue) then
  begin
    LExpUnix := StrToInt64Def(LExpValue.Value, 0);
    if (LExpUnix > 0) and (DateTimeToUnix(Now, False) > LExpUnix) then
    begin
      LPayload.Free;
      Exit;
    end;
  end;

  Result := LPayload;
end;

class function TJwtHelper.Validate(const AToken, ASecret: string): Boolean;
var
  LClaims: TJSONObject;
begin
  LClaims := GetClaims(AToken, ASecret);
  Result  := Assigned(LClaims);
  if Result then
    LClaims.Free;
end;

class function TJwtHelper.GetClaimsFromRequest(AReq: THorseRequest;
  const ASecret: string): TJSONObject;
var
  LAuth: string;
begin
  LAuth := AReq.Headers['Authorization'];
  if not LAuth.StartsWith('Bearer ', True) then
    Exit(nil);
  Result := GetClaims(Trim(LAuth.Substring(7)), ASecret);
end;

{ TJwtMiddleware }

class function TJwtMiddleware.New(const ASecret: string;
  const AExcludedPrefixes: array of string): THorseCallback;
var
  LSecret: string;
begin
  LSecret := ASecret;
  Result := TAuthMiddleware.Bearer(
    function(const AToken: string): Boolean
    begin
      Result := TJwtHelper.Validate(AToken, LSecret);
    end,
    AExcludedPrefixes);
end;

class function TJwtMiddleware.New(const ASecret: string): THorseCallback;
begin
  Result := New(ASecret, []);
end;

end.
