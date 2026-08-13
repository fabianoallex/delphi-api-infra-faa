unit Horse.Middleware.ErrorHandler;

interface

uses
  System.SysUtils,
  Horse.Callback;

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
  /// Uso no DPR (antes de RegisterRoutes):
  ///   THorse.Use(TErrorHandlerMiddleware.New);
  TErrorHandlerMiddleware = class
  public
    class function New: THorseCallback;
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
