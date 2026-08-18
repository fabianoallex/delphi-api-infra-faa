unit Common.FileLog;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TLogItem = record
    Category: string;
    Line: string;
  end;

  IFileLogger = interface
    ['{759D3123-E813-48A6-9F81-712D5690D261}']
    procedure Log(const ACategory, AText: string); overload;
    procedure Log(const ACategories: array of string; const AText: string); overload;
    procedure Log(const ACategory, AFormatStr: string; const AArgs: array of const); overload;
    procedure Log(const ACategories: array of string; const AFormatStr: string;
      const AArgs: array of const); overload;
    procedure FlushNow;
    function PendingCount: Integer;
  end;

  { TFileLogger — implementação concreta. AAutoFlush=False (só em testes) não
    cria a thread de background: o chamador drena a fila manualmente via
    FlushNow, de forma síncrona e determinística, sem depender de tempo real. }
  TFileLogger = class(TInterfacedObject, IFileLogger)
  private
    FLogDir:          string;
    FCapacity:         Integer;
    FFlushIntervalMs:  Integer;
    FMaxFileSize:      Int64;
    FQueue:            TQueue<TLogItem>;
    FLock:             TCriticalSection;
    FThread:           TThread;
    FWake:             TEvent;
    function NewEventId: string;
    procedure Enqueue(const ACategory, ALine: string);
    procedure FlushQueue;
    function CategoryFilePath(const ACategory: string): string;
    function CurrentFileSize(const APath: string): Int64;
    procedure RotateIfNeeded(const APath: string);
    procedure StopFlushThread;
  public
    constructor Create(const ALogDir: string; ACapacity, AFlushIntervalMs: Integer;
      AMaxFileSizeBytes: Int64; AAutoFlush: Boolean = True);
    destructor Destroy; override;
    procedure Log(const ACategory, AText: string); overload;
    procedure Log(const ACategories: array of string; const AText: string); overload;
    procedure Log(const ACategory, AFormatStr: string; const AArgs: array of const); overload;
    procedure Log(const ACategories: array of string; const AFormatStr: string;
      const AArgs: array of const); overload;
    procedure FlushNow;
    function PendingCount: Integer;
  end;

  { TLogTruncate — corta conteúdo grande antes de logar (ex: corpo de mensagem
    de fila), sem perder rastreabilidade: anexa o tamanho total e um hash curto
    do conteúdo completo, pra permitir correlacionar duas linhas truncadas sem
    guardar o conteúdo inteiro em lugar nenhum. }
  TLogTruncate = class
  public
    class function Apply(const AContent: string; AMaxLen: Integer = 250): string;
  end;

/// Log assíncrono em arquivo, separado por categoria e por tamanho.
///
/// FileLog só enfileira a linha (nunca bloqueia a thread chamadora esperando
/// I/O de disco) — uma thread dedicada drena a fila e grava em lote, no
/// intervalo configurado. A fila tem tamanho limitado; se lotar, descarta a
/// linha mais antiga (o log nunca pode travar nem derrubar quem está logando).
///
/// Cada categoria grava no seu próprio arquivo (<LOG_DIR>\<categoria>.log).
/// Quando o arquivo atual atinge o tamanho máximo, é renomeado para
/// <categoria>_yyyymmddhhnnss.log e um arquivo novo é iniciado — assim logs
/// antigos ficam isolados em arquivos por época, fáceis de arquivar/apagar.
///
/// Toda linha é prefixada com [<hash> <data hora>]. O hash é gerado uma vez
/// por chamada e é o mesmo em todas as categorias daquela chamada — permite
/// reconhecer, ao inspecionar dois arquivos diferentes, que duas linhas se
/// referem ao mesmo evento de log.
///
/// Uma mesma mensagem pode ir para mais de uma categoria passando um array:
///   FileLog(['exception', 'inicializacao'], 'Falha ao conectar no banco: %s', [E.Message]);
/// grava a mesma linha (mesmo hash) em exception.log e inicializacao.log —
/// uma exceção durante o startup aparece em ambos, correlacionável pelo hash.
///
/// Uso:
///   FileLog('pipe', 'Consulta NFE: loja=%s chave=%s', [LLoja, LChave]);
///   FileLog('amqp', 'Mensagem processada');
///   FileLog('rabbitmq', 'Mensagem recebida: ' + TLogTruncate.Apply(ADelivery.BodyAsText));
///
/// Configuração (.env / TAppConfig):
///   LOG_DIR                 diretório dos arquivos de log (padrão: logs)
///   LOG_QUEUE_CAPACITY      tamanho máximo da fila em memória (padrão: 10000)
///   LOG_FLUSH_INTERVAL_MS   intervalo de gravação em disco (padrão: 200)
///   LOG_MAX_FILE_SIZE_MB    tamanho máximo por arquivo antes de rotacionar (padrão: 2)
procedure FileLog(const ACategory, AText: string); overload;
procedure FileLog(const ACategories: array of string; const AText: string); overload;
procedure FileLog(const ACategory, AFormatStr: string; const AArgs: array of const); overload;
procedure FileLog(const ACategories: array of string; const AFormatStr: string;
  const AArgs: array of const); overload;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Hash,
  Common.Config,
  Common.SafeLog;

{ TLogTruncate }

class function TLogTruncate.Apply(const AContent: string; AMaxLen: Integer): string;
begin
  if Length(AContent) <= AMaxLen then
    Exit(AContent);

  Result := Copy(AContent, 1, AMaxLen) + Format(' [cortado; tamanho_total=%d; hash=%s]',
    [Length(AContent), Copy(THashMD5.GetHashString(AContent), 1, 8)]);
end;

{ TFileLogger }

constructor TFileLogger.Create(const ALogDir: string; ACapacity, AFlushIntervalMs: Integer;
  AMaxFileSizeBytes: Int64; AAutoFlush: Boolean);
begin
  inherited Create;
  FLogDir          := ALogDir;
  FCapacity        := ACapacity;
  FFlushIntervalMs := AFlushIntervalMs;
  FMaxFileSize     := AMaxFileSizeBytes;
  FQueue           := TQueue<TLogItem>.Create;
  FLock            := TCriticalSection.Create;

  if not AAutoFlush then
    Exit;

  // Evento manual-reset: SetEvent na finalização acorda a thread na hora,
  // sem esperar o intervalo cheio — mesmo padrão do idle-sweep do pool
  // (Db.Connection.Pool.TConnectionPool.StartIdleSweep).
  FWake := TEvent.Create(nil, True, False, '');
  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while FWake.WaitFor(FFlushIntervalMs) = wrTimeout do
        FlushQueue;
      FlushQueue; // drena o que restou antes de encerrar
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TFileLogger.Destroy;
begin
  StopFlushThread;
  FlushQueue; // garante que nada fique pendente, mesmo sem thread (AAutoFlush=False)
  FQueue.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TFileLogger.StopFlushThread;
begin
  if not Assigned(FThread) then
    Exit;
  FWake.SetEvent;
  FThread.WaitFor;
  FreeAndNil(FThread);
  FreeAndNil(FWake);
end;

procedure TFileLogger.Enqueue(const ACategory, ALine: string);
var
  LItem: TLogItem;
begin
  LItem.Category := ACategory;
  LItem.Line     := ALine;
  FLock.Enter;
  try
    if FQueue.Count >= FCapacity then
      FQueue.Dequeue; // descarta a mais antiga — a fila nunca pode travar quem loga
    FQueue.Enqueue(LItem);
  finally
    FLock.Leave;
  end;
end;

function TFileLogger.PendingCount: Integer;
begin
  FLock.Enter;
  try
    Result := FQueue.Count;
  finally
    FLock.Leave;
  end;
end;

function TFileLogger.CategoryFilePath(const ACategory: string): string;
begin
  Result := TPath.Combine(FLogDir, ACategory + '.log');
end;

function TFileLogger.CurrentFileSize(const APath: string): Int64;
var
  LStream: TFileStream;
begin
  Result := 0;
  if not TFile.Exists(APath) then
    Exit;
  LStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := LStream.Size;
  finally
    LStream.Free;
  end;
end;

procedure TFileLogger.RotateIfNeeded(const APath: string);
var
  LArchive: string;
begin
  if CurrentFileSize(APath) < FMaxFileSize then
    Exit;
  LArchive := ChangeFileExt(APath, '') + '_' + FormatDateTime('yyyymmddhhnnss', Now) +
    ExtractFileExt(APath);
  TFile.Move(APath, LArchive);
end;

procedure TFileLogger.FlushQueue;
var
  LItem:  TLogItem;
  LByCat: TObjectDictionary<string, TStringList>;
  LList:  TStringList;
  LPair:  TPair<string, TStringList>;
  LPath:  string;
begin
  LByCat := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    FLock.Enter;
    try
      while FQueue.Count > 0 do
      begin
        LItem := FQueue.Dequeue;
        if not LByCat.TryGetValue(LItem.Category, LList) then
        begin
          LList := TStringList.Create;
          LByCat.Add(LItem.Category, LList);
        end;
        LList.Add(LItem.Line);
      end;
    finally
      FLock.Leave;
    end;

    if LByCat.Count = 0 then
      Exit;

    if not TDirectory.Exists(FLogDir) then
      TDirectory.CreateDirectory(FLogDir);

    for LPair in LByCat do
    begin
      LPath := CategoryFilePath(LPair.Key);
      try
        RotateIfNeeded(LPath);
        TFile.AppendAllText(LPath, LPair.Value.Text, TEncoding.UTF8);
      except
        on E: Exception do
          // arquivo de log não pode derrubar a aplicação; melhor esforço no console
          SafeWriteln('[Common.FileLog] falha ao gravar log em arquivo (' + LPair.Key + '): ' + E.Message);
      end;
    end;
  finally
    LByCat.Free;
  end;
end;

procedure TFileLogger.FlushNow;
begin
  FlushQueue;
end;

function TFileLogger.NewEventId: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := Copy(THashMD5.GetHashString(GUIDToString(LGuid)), 1, 8);
end;

procedure TFileLogger.Log(const ACategory, AText: string);
begin
  Log([ACategory], AText);
end;

procedure TFileLogger.Log(const ACategories: array of string; const AText: string);
var
  LLine: string;
  LCategory: string;
begin
  // Mesmo hash em todas as categorias desta chamada — correlaciona a mesma
  // linha gravada em mais de um arquivo (ex.: exception.log + inicializacao.log).
  LLine := Format('[%s %s] %s',
    [NewEventId, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), AText]);
  for LCategory in ACategories do
    Enqueue(LCategory, LLine);
end;

procedure TFileLogger.Log(const ACategory, AFormatStr: string; const AArgs: array of const);
begin
  Log([ACategory], Format(AFormatStr, AArgs));
end;

procedure TFileLogger.Log(const ACategories: array of string; const AFormatStr: string;
  const AArgs: array of const);
begin
  Log(ACategories, Format(AFormatStr, AArgs));
end;

{ FileLog — instância global usada pelo resto da aplicação }

var
  GDefaultLogger: IFileLogger;

procedure FileLog(const ACategory, AText: string);
begin
  GDefaultLogger.Log(ACategory, AText);
end;

procedure FileLog(const ACategories: array of string; const AText: string);
begin
  GDefaultLogger.Log(ACategories, AText);
end;

procedure FileLog(const ACategory, AFormatStr: string; const AArgs: array of const);
begin
  GDefaultLogger.Log(ACategory, AFormatStr, AArgs);
end;

procedure FileLog(const ACategories: array of string; const AFormatStr: string;
  const AArgs: array of const);
begin
  GDefaultLogger.Log(ACategories, AFormatStr, AArgs);
end;

initialization
  GDefaultLogger := TFileLogger.Create(
    TAppConfig.Get('LOG_DIR', 'logs'),
    TAppConfig.GetInt('LOG_QUEUE_CAPACITY', 10000),
    TAppConfig.GetInt('LOG_FLUSH_INTERVAL_MS', 200),
    Int64(TAppConfig.GetInt('LOG_MAX_FILE_SIZE_MB', 2)) * 1024 * 1024);

finalization
  GDefaultLogger := nil; // refcount -> 0 aciona TFileLogger.Destroy (para thread, drena a fila)

end.
