unit Horse.Middleware.ErrorHandler;

interface

uses
  System.SysUtils,
  Horse.Callback,
  Horse.Middleware.Logger;

type
  /// Exceção HTTP genérica — carrega o status code HTTP a ser retornado.
  /// Use as subclasses para os casos mais comuns.
  EHttpException = class(Exception)
  private
    FStatusCode: Integer;
  public
    constructor Create(AStatusCode: Integer; const AMessage: string);
    property StatusCode: Integer read FStatusCode;
  end;

  /// 400 — campo inválido, parâmetro ausente, regra de negócio violada.
  EValidationException = class(EHttpException)
  public
    constructor Create(const AMessage: string);
  end;

  /// 404 — recurso não encontrado pelo identificador fornecido.
  ENotFoundException = class(EHttpException)
  public
    constructor Create(const AMessage: string = 'Recurso não encontrado.');
  end;

  /// 409 — conflito de unicidade ou estado incompatível.
  EConflictException = class(EHttpException)
  public
    constructor Create(const AMessage: string);
  end;

  /// Registra o tratamento global de exceções não capturadas, devolvendo JSON
  /// padronizado. Usa THorse.OnError (hook nativo do core, chamado pelo
  /// próprio router em qualquer exceção não tratada durante o dispatch) —
  /// não é mais um middleware em THorse.Use, então não entra na cadeia de
  /// Next() e não tem posição relativa a outros middlewares para respeitar
  /// (basta chamar Register antes de THorse.Listen).
  ///
  /// Requer uma versão do Horse com THorse.OnError/THorseOnError no core
  /// (Horse.Core.pas) — não existe nas versões anteriores ao PR
  /// "feat: implement native global error handler (OnError)".
  ///
  /// Mapeamento:
  ///   EHttpException              → E.StatusCode
  ///   EOrderByException           → 400
  ///   EDatabaseUnavailableException → 503 (Db.Interfaces — conexão perdida/AV
  ///                                  classificada por BuildDatabaseException;
  ///                                  diferente de EHttpException/EOrderByException,
  ///                                  ESTE branch chama AOnError — é infra quebrando,
  ///                                  não fluxo de negócio esperado)
  ///   Exception                   → 500
  ///
  /// AOnError é opcional e só é chamado para o branch 500 (Exception genérica)
  /// — EHttpException/EOrderByException são fluxo de negócio esperado (400/404/409),
  /// não erro a ser monitorado.
  ///
  /// Uso no DPR (em qualquer ponto antes de THorse.Listen):
  ///   TErrorHandlerMiddleware.Register;
  ///
  ///   // Com log em arquivo (ver Common.FileLog) — categoria 'exception' vira
  ///   // um índice enxuto de tudo que quebrou; correlacione com uma segunda
  ///   // categoria (ex.: 'http') se quiser mais contexto no mesmo arquivo:
  ///   TErrorHandlerMiddleware.Register(
  ///     procedure(const ALine: string)
  ///     begin
  ///       FileLog(['exception', 'http'], ALine);
  ///     end);
  TErrorHandlerMiddleware = class
  public
    class procedure Register; overload;
    class procedure Register(AOnError: TLogProc); overload;
  end;

implementation

uses
  System.JSON,
  Horse,
  Common.OrderBy,
  Db.Interfaces;

{ EHttpException }

constructor EHttpException.Create(AStatusCode: Integer; const AMessage: string);
begin
  inherited Create(AMessage);
  FStatusCode := AStatusCode;
end;

{ EValidationException }

constructor EValidationException.Create(const AMessage: string);
begin
  inherited Create(400, AMessage);
end;

{ ENotFoundException }

constructor ENotFoundException.Create(const AMessage: string);
begin
  inherited Create(404, AMessage);
end;

{ EConflictException }

constructor EConflictException.Create(const AMessage: string);
begin
  inherited Create(409, AMessage);
end;

{ TErrorHandlerMiddleware }

var
  // THorseOnError é `procedure(...)` puro (nem `reference to`, nem `of object`)
  // — não aceita closure, então não dá para capturar AOnError localmente
  // dentro de Register. Guardamos aqui; reflete o próprio design do Horse
  // (THorseCore.FOnError também é um único slot global, não por middleware).
  GOnError: TLogProc;

// TJSONObject.ToJSON escapa todo caractere > 127 como \uXXXX por padrão,
// sem flag pra desligar nesta versão do Delphi — sem isso, qualquer mensagem
// de erro com acento (ex. "indisponível", "não encontrado") chega
// ao cliente ilegível assim, em vez de "indisponível"/"não encontrado".
// Tecnicamente é JSON válido (qualquer parser decodifica de volta certo).
// Reverte só esse escaping extra — não re-implementa aspas/barras/controle,
// que o TJSONObject já escapa corretamente antes desta função rodar.
// Limitação aceita: não trata pares substitutos (caracteres fora do BMP,
// \uD800-\uDFFF) — irrelevante para mensagem de erro em português.
function UnescapeNonAsciiJSON(const AJson: string): string;
var
  I, LCode: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AJson) do
  begin
    if (AJson[I] = '\') and (I + 5 <= Length(AJson)) and (AJson[I + 1] = 'u') then
    begin
      LCode := StrToIntDef('$' + Copy(AJson, I + 2, 4), -1);
      if LCode > 127 then
      begin
        Result := Result + Chr(LCode);
        Inc(I, 6);
        Continue;
      end;
    end;
    Result := Result + AJson[I];
    Inc(I);
  end;
end;

procedure HandleHorseError(const ARequest: THorseRequest; const AResponse: THorseResponse;
  const AException: Exception);
var
  LStatus: Integer;
  LMessage: string;
  LJson: TJSONObject;
begin
  if AException is EHttpException then
  begin
    LStatus  := EHttpException(AException).StatusCode;
    LMessage := AException.Message;
  end
  else if AException is EOrderByException then
  begin
    LStatus  := 400;
    LMessage := AException.Message;
  end
  else if AException is EDatabaseUnavailableException then
  begin
    LStatus  := 503;
    LMessage := AException.Message; // genérica de propósito — ver EDatabaseUnavailableException
    // Diferente de EHttpException/EOrderByException (fluxo de negócio
    // esperado, não loga): isto É infra quebrando — vale monitorar. O
    // detalhe original (classe + mensagem da exceção nativa, endereço de AV
    // incluso) vai só pro log, nunca pro cliente.
    if Assigned(GOnError) then
      GOnError(Format('%s %s -> %d: %s (%s: %s)',
        [ARequest.Method, ARequest.PathInfo, LStatus, LMessage,
         EDatabaseUnavailableException(AException).OriginalClassName,
         EDatabaseUnavailableException(AException).OriginalMessage]));
  end
  else
  begin
    LStatus  := 500;
    LMessage := AException.Message;
    if Assigned(GOnError) then
      GOnError(Format('%s %s -> %d: %s: %s',
        [ARequest.Method, ARequest.PathInfo, LStatus, AException.ClassName, LMessage]));
  end;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('error', LMessage);
    AResponse.Status(LStatus).ContentType('application/json; charset=utf-8')
       .Send(UnescapeNonAsciiJSON(LJson.ToJSON));
  finally
    LJson.Free;
  end;
end;

class procedure TErrorHandlerMiddleware.Register;
begin
  Register(nil);
end;

class procedure TErrorHandlerMiddleware.Register(AOnError: TLogProc);
begin
  GOnError := AOnError;
  THorse.OnError(HandleHorseError);
end;

end.
