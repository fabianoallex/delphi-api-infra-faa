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

  /// Middleware que captura exceções não tratadas e devolve JSON padronizado.
  ///
  /// Mapeamento:
  ///   EHttpException     → E.StatusCode
  ///   EOrderByException  → 400
  ///   Exception          → 500
  ///
  /// AOnError é opcional e só é chamado para o branch 500 (Exception genérica)
  /// — EHttpException/EOrderByException são fluxo de negócio esperado (400/404/409),
  /// não erro a ser monitorado. Mesmo padrão de TLoggerMiddleware.New: o
  /// middleware não decide o destino do log, só entrega a linha pronta.
  ///
  /// Uso no DPR (antes de RegisterRoutes):
  ///   THorse.Use(TErrorHandlerMiddleware.New);
  ///
  ///   // Com log em arquivo (ver Common.FileLog) — categoria 'exception' vira
  ///   // um índice enxuto de tudo que quebrou; correlacione com uma segunda
  ///   // categoria (ex.: 'http') se quiser mais contexto no mesmo arquivo:
  ///   THorse.Use(TErrorHandlerMiddleware.New(
  ///     procedure(const ALine: string)
  ///     begin
  ///       FileLog(['exception', 'http'], ALine);
  ///     end));
  TErrorHandlerMiddleware = class
  public
    class function New: THorseCallback; overload;
    class function New(AOnError: TLogProc): THorseCallback; overload;
  end;

implementation

uses
  System.JSON,
  Horse,
  Common.OrderBy;

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

class function TErrorHandlerMiddleware.New: THorseCallback;
begin
  Result := New(nil);
end;

class function TErrorHandlerMiddleware.New(AOnError: TLogProc): THorseCallback;
begin
  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LStatus: Integer;
      LMessage: string;
      LJson: TJSONObject;
    begin
      LStatus := 0;
      try
        Next();
      except
        on E: EHttpException do
        begin
          LStatus  := E.StatusCode;
          LMessage := E.Message;
        end;
        on E: EOrderByException do
        begin
          LStatus  := 400;
          LMessage := E.Message;
        end;
        on E: Exception do
        begin
          LStatus  := 500;
          LMessage := E.Message;
          if Assigned(AOnError) then
            AOnError(Format('%s %s -> %d: %s: %s',
              [Req.Method, Req.PathInfo, LStatus, E.ClassName, LMessage]));
        end;
      end;

      if LStatus = 0 then Exit;

      LJson := TJSONObject.Create;
      try
        LJson.AddPair('error', LMessage);
        Res.Status(LStatus).ContentType('application/json; charset=utf-8').Send(LJson.ToJSON);
      finally
        LJson.Free;
      end;
    end;
end;

end.
