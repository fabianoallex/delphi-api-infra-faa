unit Horse.Middleware.Logger;

interface

uses
  Horse.Callback;

type
  TLogProc = reference to procedure(const ALine: string);

  /// Middleware de logging de requisições HTTP.
  ///
  /// Formato: [yyyy-mm-dd hh:nn:ss] METHOD /path STATUS Xms IP BYTES "QUERY" "USER-AGENT" REQUEST-ID
  ///
  /// BYTES é o Content-Length da resposta quando o provider expõe RawWebResponse
  /// (Indy, o caso comum desta lib) — "-" quando não disponível (ex.: providers
  /// CrossSocket/HttpSys). QUERY reconstrói a query string a partir de Req.Query
  /// (chave=valor&chave2=valor2, "-" se vazia). REQUEST-ID é gerado uma vez no
  /// início da requisição, sempre disponível também via Req.Headers['X-Request-Id']
  /// dentro do handler (e no header de resposta de mesmo nome) — use-o em
  /// chamadas de FileLog dentro do handler para cruzar essa linha de acesso com
  /// o que a aplicação logou processando essa requisição específica.
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
  System.Hash,
  System.Generics.Collections,
  Web.HTTPApp,
  Horse,
  Common.SafeLog;

const
  REQUEST_ID_HEADER = 'X-Request-Id';

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

function ExtractLogQuery(Req: THorseRequest): string;
var
  LPairs: TArray<TPair<string, string>>;
  LPair:  TPair<string, string>;
begin
  LPairs := Req.Query.ToArray;
  if Length(LPairs) = 0 then
    Exit('-');

  Result := '';
  for LPair in LPairs do
  begin
    if Result <> '' then
      Result := Result + '&';
    Result := Result + LPair.Key + '=' + LPair.Value;
  end;
end;

function ExtractLogUserAgent(Req: THorseRequest): string;
begin
  Result := Req.Headers['User-Agent'];
  if Result.IsEmpty then
    Result := '-';
end;

function ExtractLogBytes(Res: THorseResponse): string;
var
  LRawResponse: TWebResponse;
begin
  { RawWebResponse (TWebResponse) só existe nos providers baseados em Indy/fpWeb.
    Providers CrossSocket/HttpSys não o preenchem — nesse caso o tamanho fica
    indisponível e o campo sai como "-" em vez de um valor inventado.

    Resultado guardado numa variável local antes do teste — Assigned() aplicado
    direto numa chamada encadeada (Assigned(Res.RawWebResponse)) deu
    "E2036 Variable required" em pelo menos um compilador testado. }
  LRawResponse := Res.RawWebResponse;
  if LRawResponse <> nil then
    Result := IntToStr(LRawResponse.ContentLength)
  else
    Result := '-';
end;

function NewRequestId: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := Copy(THashMD5.GetHashString(GUIDToString(LGuid)), 1, 8);
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
      LSW:        TStopwatch;
      LLine:      string;
      LRequestId: string;
    begin
      LRequestId := NewRequestId;
      { Disponível pro handler via Req.Headers['X-Request-Id'] (correlação com
        FileLog feito dentro do handler) e pro cliente via header de resposta
        de mesmo nome. Setado antes do Next() para sobreviver mesmo se o
        handler lançar uma exceção capturada pelo TErrorHandlerMiddleware. }
      Req.Headers.Dictionary.AddOrSetValue(REQUEST_ID_HEADER, LRequestId);
      Res.AddHeader(REQUEST_ID_HEADER, LRequestId);

      LSW := TStopwatch.StartNew;
      try
        Next();
      finally
        LSW.Stop;
        LLine := Format('[%s] %s %s %d %dms %s %s "%s" "%s" %s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
           Req.Method,
           Req.PathInfo,
           Res.Status,
           LSW.ElapsedMilliseconds,
           ExtractLogIP(Req),
           ExtractLogBytes(Res),
           ExtractLogQuery(Req),
           ExtractLogUserAgent(Req),
           LRequestId]);

        if Assigned(LOnLog) then
          LOnLog(LLine)
        else
          SafeWriteln(LLine);
      end;
    end;
end;

end.
