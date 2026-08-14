unit Horse.Middleware.Logger;

interface

uses
  Horse.Callback;

type
  TLogProc = reference to procedure(const ALine: string);

  /// Middleware de logging de requisições HTTP.
  ///
  /// Formato: [yyyy-mm-dd hh:nn:ss] METHOD /path STATUS Xms IP
  ///
  /// Deve ser registrado ANTES de TErrorHandlerMiddleware para capturar o
  /// status correto de respostas de erro (4xx/5xx).
  ///
  /// Uso no DPR (deve ser o PRIMEIRO middleware):
  ///
  ///   // Console (padrão)
  ///   THorse.Use(TLoggerMiddleware.New);
  ///
  ///   // Callback customizado (arquivo, syslog, ElasticSearch, etc.)
  ///   THorse.Use(TLoggerMiddleware.New(
  ///     procedure(const ALine: string)
  ///     begin
  ///       TMyLogger.Info(ALine);
  ///     end));
  TLoggerMiddleware = class
  public
    class function New: THorseCallback; overload;
    class function New(AOnLog: TLogProc): THorseCallback; overload;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Horse,
  Common.SafeLog;

function ExtractLogIP(Req: THorseRequest): string;
var
  LForwarded: string;
  LComma:     Integer;
begin
  LForwarded := Req.Headers['X-Forwarded-For'];
  if not LForwarded.IsEmpty then
  begin
    LComma := Pos(',', LForwarded);
    if LComma > 0 then
      Result := Trim(Copy(LForwarded, 1, LComma - 1))
    else
      Result := Trim(LForwarded);
  end
  else
    Result := Req.RemoteAddr;

  if Result.IsEmpty then
    Result := '-';
end;

{ TLoggerMiddleware }

class function TLoggerMiddleware.New: THorseCallback;
begin
  Result := New(nil);
end;

class function TLoggerMiddleware.New(AOnLog: TLogProc): THorseCallback;
var
  LOnLog: TLogProc;
begin
  LOnLog := AOnLog;
  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LSW:   TStopwatch;
      LLine: string;
    begin
      LSW := TStopwatch.StartNew;
      try
        Next();
      finally
        LSW.Stop;
        LLine := Format('[%s] %s %s %d %dms %s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
           Req.Method,
           Req.PathInfo,
           Res.Status,
           LSW.ElapsedMilliseconds,
           ExtractLogIP(Req)]);

        if Assigned(LOnLog) then
          LOnLog(LLine)
        else
          SafeWriteln(LLine);
      end;
    end;
end;

end.
