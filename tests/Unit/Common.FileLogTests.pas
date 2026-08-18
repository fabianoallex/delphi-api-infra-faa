unit Common.FileLogTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.RegularExpressions,
  Common.FileLog;

type
  { TFileLogStressThread
    Loga repetidamente em um IFileLogger para testar concorrência. }
  TFileLogStressThread = class(TThread)
  private
    FLogger: IFileLogger;
    FCategory: string;
    FThreadTag: Integer;
    FIterations: Integer;
    FErrorOccurred: Boolean;
    FErrorMessage: string;
  protected
    procedure Execute; override;
  public
    constructor Create(ALogger: IFileLogger; const ACategory: string;
      AThreadTag, AIterations: Integer);
    property ErrorOccurred: Boolean read FErrorOccurred;
    property ErrorMessage: string read FErrorMessage;
  end;

  [TestFixture]
  TFileLogTests = class
  private
    function NewTempDir: string;
    procedure CleanupDir(const ADir: string);
    function ExtractLineHash(const ALine: string): string;
  public
    [Test] procedure Test_FileLog_Log_Enfileira;
    [Test] procedure Test_FileLog_FlushNow_GravaArquivoEZeraFila;
    [Test] procedure Test_FileLog_CategoriasDiferentes_ArquivosSeparados;
    [Test] procedure Test_FileLog_Log_PrefixaComHashEData;
    [Test] procedure Test_FileLog_MultiplasCategorias_GravaEmTodosOsArquivos;
    [Test] procedure Test_FileLog_MultiplasCategorias_MesmoHashCorrelaciona;
    [Test] procedure Test_FileLog_ChamadasDiferentes_HashesDiferentes;
    [Test] procedure Test_FileLog_FilaCheia_DescartaMaisAntiga;
    [Test] procedure Test_FileLog_Rotacao_PorTamanho;
    [Test] procedure Test_FileLog_Destroy_DrenaFilaPendente;
    [Test] procedure Test_FileLog_Destroy_ComThreadAtiva_NaoTrava;
    [Test] procedure Test_FileLog_ThreadReal_FlushAutomatico;
    [Test] procedure Test_FileLog_Concorrencia;
    [Test] procedure Test_LogTruncate_ConteudoCurto_NaoAltera;
    [Test] procedure Test_LogTruncate_NoLimiteExato_NaoAltera;
    [Test] procedure Test_LogTruncate_ConteudoLongo_CortaEAnexaInfo;
    [Test] procedure Test_LogTruncate_MesmoConteudo_MesmoHash;
    [Test] procedure Test_LogTruncate_ConteudoDiferente_HashDiferente;
  end;

implementation

{ TFileLogStressThread }

constructor TFileLogStressThread.Create(ALogger: IFileLogger; const ACategory: string;
  AThreadTag, AIterations: Integer);
begin
  inherited Create(True); // suspenso — aguarda chamada explícita de Start
  FLogger     := ALogger;
  FCategory   := ACategory;
  FThreadTag  := AThreadTag;
  FIterations := AIterations;
  FreeOnTerminate := False;
  FErrorOccurred := False;
end;

procedure TFileLogStressThread.Execute;
var
  I: Integer;
begin
  try
    for I := 1 to FIterations do
      FLogger.Log(FCategory, Format('t%d-i%d', [FThreadTag, I]));
  except
    on E: Exception do
    begin
      FErrorOccurred := True;
      FErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TFileLogTests }

function TFileLogTests.NewTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'InfraFileLogTests_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(Random(1000000)));
end;

procedure TFileLogTests.CleanupDir(const ADir: string);
begin
  if TDirectory.Exists(ADir) then
    TDirectory.Delete(ADir, True);
end;

function TFileLogTests.ExtractLineHash(const ALine: string): string;
var
  LMatch: TMatch;
begin
  LMatch := TRegEx.Match(ALine, '^\[([0-9a-f]{8}) ');
  if LMatch.Success then
    Result := LMatch.Groups[1].Value
  else
    Result := '';
end;

procedure TFileLogTests.Test_FileLog_Log_Enfileira;
var
  LDir: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    Assert.AreEqual(0, LLogger.PendingCount, 'Fila deve começar vazia');

    LLogger.Log('app', 'mensagem 1');
    LLogger.Log('app', 'mensagem 2');

    Assert.AreEqual(2, LLogger.PendingCount, 'Fila deve ter 2 itens após 2 Log');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_FlushNow_GravaArquivoEZeraFila;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log('app', 'mensagem de teste');
    LLogger.FlushNow;

    Assert.AreEqual(0, LLogger.PendingCount, 'FlushNow deve esvaziar a fila');

    LPath := TPath.Combine(LDir, 'app.log');
    Assert.IsTrue(TFile.Exists(LPath), 'Arquivo app.log deveria existir após FlushNow');

    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Assert.IsTrue(LContent.Contains('mensagem de teste'),
      'Conteúdo do arquivo deveria conter a mensagem logada');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_CategoriasDiferentes_ArquivosSeparados;
var
  LDir, LPipePath, LAmqpPath, LPipeContent, LAmqpContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log('pipe', 'evento do pipe');
    LLogger.Log('amqp', 'evento do amqp');
    LLogger.FlushNow;

    LPipePath := TPath.Combine(LDir, 'pipe.log');
    LAmqpPath := TPath.Combine(LDir, 'amqp.log');

    Assert.IsTrue(TFile.Exists(LPipePath), 'pipe.log deveria existir');
    Assert.IsTrue(TFile.Exists(LAmqpPath), 'amqp.log deveria existir');

    LPipeContent := TFile.ReadAllText(LPipePath, TEncoding.UTF8);
    LAmqpContent := TFile.ReadAllText(LAmqpPath, TEncoding.UTF8);

    Assert.IsTrue(LPipeContent.Contains('evento do pipe'), 'pipe.log deveria conter seu evento');
    Assert.IsFalse(LPipeContent.Contains('evento do amqp'), 'pipe.log não deveria conter evento de amqp');

    Assert.IsTrue(LAmqpContent.Contains('evento do amqp'), 'amqp.log deveria conter seu evento');
    Assert.IsFalse(LAmqpContent.Contains('evento do pipe'), 'amqp.log não deveria conter evento de pipe');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_Log_PrefixaComHashEData;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log('app', 'mensagem com prefixo');
    LLogger.FlushNow;

    LPath := TPath.Combine(LDir, 'app.log');
    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);

    Assert.IsTrue(
      TRegEx.IsMatch(LContent, '^\[[0-9a-f]{8} \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] mensagem com prefixo'),
      'Linha deveria começar com [hash data hora] antes da mensagem');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_MultiplasCategorias_GravaEmTodosOsArquivos;
var
  LDir, LExceptionPath, LInitPath, LExceptionContent, LInitContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log(['exception', 'inicializacao'], 'falha ao conectar no banco');
    LLogger.FlushNow;

    LExceptionPath := TPath.Combine(LDir, 'exception.log');
    LInitPath      := TPath.Combine(LDir, 'inicializacao.log');

    Assert.IsTrue(TFile.Exists(LExceptionPath), 'exception.log deveria existir');
    Assert.IsTrue(TFile.Exists(LInitPath), 'inicializacao.log deveria existir');

    LExceptionContent := TFile.ReadAllText(LExceptionPath, TEncoding.UTF8);
    LInitContent      := TFile.ReadAllText(LInitPath, TEncoding.UTF8);

    Assert.IsTrue(LExceptionContent.Contains('falha ao conectar no banco'),
      'exception.log deveria conter a mensagem');
    Assert.IsTrue(LInitContent.Contains('falha ao conectar no banco'),
      'inicializacao.log deveria conter a mesma mensagem');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_MultiplasCategorias_MesmoHashCorrelaciona;
var
  LDir, LExceptionPath, LInitPath, LExceptionContent, LInitContent, LHash1, LHash2: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log(['exception', 'inicializacao'], 'evento correlacionado');
    LLogger.FlushNow;

    LExceptionPath := TPath.Combine(LDir, 'exception.log');
    LInitPath      := TPath.Combine(LDir, 'inicializacao.log');

    LExceptionContent := TFile.ReadAllText(LExceptionPath, TEncoding.UTF8);
    LInitContent      := TFile.ReadAllText(LInitPath, TEncoding.UTF8);

    LHash1 := ExtractLineHash(LExceptionContent);
    LHash2 := ExtractLineHash(LInitContent);

    Assert.AreNotEqual('', LHash1, 'Deveria extrair um hash de exception.log');
    Assert.AreEqual(LHash1, LHash2,
      'Mesma chamada de Log em categorias diferentes deve gerar o mesmo hash, ' +
      'para correlacionar os eventos entre arquivos');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_ChamadasDiferentes_HashesDiferentes;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
  LLines: TArray<string>;
  LHash1, LHash2: string;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log('app', 'primeira chamada');
    LLogger.Log('app', 'segunda chamada');
    LLogger.FlushNow;

    LPath    := TPath.Combine(LDir, 'app.log');
    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LLines   := LContent.Split([#13#10], TStringSplitOptions.ExcludeEmpty);

    Assert.AreEqual(2, Length(LLines), 'Deveriam existir 2 linhas');

    LHash1 := ExtractLineHash(LLines[0]);
    LHash2 := ExtractLineHash(LLines[1]);

    Assert.AreNotEqual('', LHash1);
    Assert.AreNotEqual('', LHash2);
    Assert.AreNotEqual(LHash1, LHash2,
      'Chamadas diferentes de Log deveriam gerar hashes diferentes');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_FilaCheia_DescartaMaisAntiga;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 3, 999999999, 2 * 1024 * 1024, False);

    LLogger.Log('app', 'msg1');
    LLogger.Log('app', 'msg2');
    LLogger.Log('app', 'msg3');
    LLogger.Log('app', 'msg4');
    LLogger.Log('app', 'msg5');

    Assert.AreEqual(3, LLogger.PendingCount, 'Capacidade de 3 deve ser respeitada');

    LLogger.FlushNow;
    LPath := TPath.Combine(LDir, 'app.log');
    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);

    Assert.IsFalse(LContent.Contains('msg1'), 'msg1 (mais antiga) deveria ter sido descartada');
    Assert.IsFalse(LContent.Contains('msg2'), 'msg2 deveria ter sido descartada');
    Assert.IsTrue(LContent.Contains('msg3'), 'msg3 deveria ter sido mantida');
    Assert.IsTrue(LContent.Contains('msg4'), 'msg4 deveria ter sido mantida');
    Assert.IsTrue(LContent.Contains('msg5'), 'msg5 (mais recente) deveria ter sido mantida');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_Rotacao_PorTamanho;
var
  LDir, LPath, LContent: string;
  LFiles: TArray<string>;
  LArchiveContent: string;
  LFound: Boolean;
  I: Integer;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    // Limite bem pequeno: qualquer primeira mensagem já ultrapassa — a checagem
    // roda ANTES de gravar o lote, então o primeiro flush nunca rotaciona
    // (arquivo ainda não existe); só o segundo flush encontra o arquivo já
    // maior que o limite e rotaciona antes de escrever o novo lote.
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 10, False);

    LLogger.Log('rot', 'primeira mensagem');
    LLogger.FlushNow;

    LLogger.Log('rot', 'segunda mensagem');
    LLogger.FlushNow;

    LPath := TPath.Combine(LDir, 'rot.log');
    Assert.IsTrue(TFile.Exists(LPath), 'rot.log deveria existir após o segundo flush');

    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Assert.IsTrue(LContent.Contains('segunda mensagem'),
      'rot.log (arquivo atual) deveria conter só a segunda mensagem');
    Assert.IsFalse(LContent.Contains('primeira mensagem'),
      'rot.log (arquivo atual) não deveria mais conter a primeira mensagem');

    LFiles := TDirectory.GetFiles(LDir, 'rot_*.log');
    Assert.IsTrue(Length(LFiles) = 1,
      Format('Deveria existir exatamente 1 arquivo arquivado (rot_*.log), encontrados %d',
        [Length(LFiles)]));

    LFound := False;
    for I := 0 to High(LFiles) do
    begin
      LArchiveContent := TFile.ReadAllText(LFiles[I], TEncoding.UTF8);
      if LArchiveContent.Contains('primeira mensagem') then
        LFound := True;
    end;
    Assert.IsTrue(LFound, 'Arquivo arquivado deveria conter a primeira mensagem');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_Destroy_DrenaFilaPendente;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, False);
    LLogger.Log('app', 'mensagem antes do destroy');
    LLogger := nil; // aciona Destroy -> deve drenar a fila mesmo sem FlushNow explícito

    LPath := TPath.Combine(LDir, 'app.log');
    Assert.IsTrue(TFile.Exists(LPath), 'Destroy deveria ter drenado a fila pendente para o arquivo');

    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Assert.IsTrue(LContent.Contains('mensagem antes do destroy'),
      'Conteúdo drenado no Destroy deveria estar no arquivo');
  finally
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_Destroy_ComThreadAtiva_NaoTrava;
var
  LDir: string;
  LStopwatch: TStopwatch;
  LLogger: IFileLogger;
begin
  LDir := NewTempDir;
  try
    // AAutoFlush=True com intervalo gigante: a thread real existe, mas nunca
    // dispararia sozinha a tempo do teste — prova que o Destroy não espera
    // o intervalo, acorda a thread na hora via SetEvent.
    LLogger := TFileLogger.Create(LDir, 100, 999999999, 2 * 1024 * 1024, True);
    LLogger.Log('app', 'mensagem');

    LStopwatch := TStopwatch.StartNew;
    LLogger := nil;
    LStopwatch.Stop;

    Assert.IsTrue(LStopwatch.ElapsedMilliseconds < 2000,
      Format('Destroy com thread ativa deveria ser quase instantâneo (SetEvent), levou %dms',
        [LStopwatch.ElapsedMilliseconds]));
  finally
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_ThreadReal_FlushAutomatico;
var
  LDir, LPath: string;
  LLogger: IFileLogger;
  LStopwatch: TStopwatch;
  LFound: Boolean;
begin
  LDir := NewTempDir;
  try
    // Sem FlushNow aqui de propósito: quer a thread de background REAL
    // rodando (intervalo curto) e provando que ela grava sozinha.
    LLogger := TFileLogger.Create(LDir, 100, 20, 2 * 1024 * 1024, True);
    LLogger.Log('app', 'mensagem via thread real');

    LPath := TPath.Combine(LDir, 'app.log');
    LFound := False;
    LStopwatch := TStopwatch.StartNew;
    while LStopwatch.ElapsedMilliseconds < 2000 do
    begin
      if TFile.Exists(LPath) and
         TFile.ReadAllText(LPath, TEncoding.UTF8).Contains('mensagem via thread real') then
      begin
        LFound := True;
        Break;
      end;
      Sleep(10);
    end;

    Assert.IsTrue(LFound, 'A thread de background deveria ter gravado o arquivo sozinha em até 2s');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

procedure TFileLogTests.Test_FileLog_Concorrencia;
const
  NUM_THREADS = 10;
  ITERACOES   = 100;
var
  LDir, LPath, LContent: string;
  LLogger: IFileLogger;
  LThreads: array[1..NUM_THREADS] of TFileLogStressThread;
  I: Integer;
  LLineCount: Integer;
begin
  LDir := NewTempDir;
  try
    LLogger := TFileLogger.Create(LDir, NUM_THREADS * ITERACOES + 10, 999999999, 2 * 1024 * 1024, False);

    for I := 1 to NUM_THREADS do
      LThreads[I] := TFileLogStressThread.Create(LLogger, 'app', I, ITERACOES);

    for I := 1 to NUM_THREADS do
      LThreads[I].Start;

    for I := 1 to NUM_THREADS do
    begin
      LThreads[I].WaitFor;
      Assert.IsFalse(LThreads[I].ErrorOccurred,
        Format('Thread %d reportou erro: %s', [I, LThreads[I].ErrorMessage]));
      LThreads[I].Free;
    end;

    Assert.AreEqual(NUM_THREADS * ITERACOES, LLogger.PendingCount,
      'Capacidade suficiente: nenhuma linha deveria ter sido descartada');

    LLogger.FlushNow;
    LPath := TPath.Combine(LDir, 'app.log');
    LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LLineCount := Length(LContent.Split([#13, #10], TStringSplitOptions.ExcludeEmpty));

    Assert.AreEqual(NUM_THREADS * ITERACOES, LLineCount,
      'Todas as linhas logadas concorrentemente deveriam estar no arquivo, sem corrupção');
  finally
    LLogger := nil;
    CleanupDir(LDir);
  end;
end;

{ TFileLogTests — TLogTruncate }

procedure TFileLogTests.Test_LogTruncate_ConteudoCurto_NaoAltera;
var
  LContent: string;
begin
  LContent := 'mensagem pequena';
  Assert.AreEqual(LContent, TLogTruncate.Apply(LContent, 250),
    'Conteudo menor que o limite deve voltar inalterado');
end;

procedure TFileLogTests.Test_LogTruncate_NoLimiteExato_NaoAltera;
var
  LContent: string;
begin
  LContent := StringOfChar('x', 250);
  Assert.AreEqual(LContent, TLogTruncate.Apply(LContent, 250),
    'Conteudo com tamanho exatamente igual ao limite nao deve ser cortado');
end;

procedure TFileLogTests.Test_LogTruncate_ConteudoLongo_CortaEAnexaInfo;
var
  LContent, LResult: string;
begin
  LContent := StringOfChar('a', 4832);
  LResult := TLogTruncate.Apply(LContent, 250);

  Assert.IsTrue(LResult.StartsWith(StringOfChar('a', 250)),
    'Resultado deve comecar com os primeiros 250 caracteres do conteudo original');
  Assert.IsTrue(LResult.Contains('tamanho_total=4832'),
    'Resultado deve informar o tamanho total do conteudo original');
  Assert.IsTrue(LResult.Contains('hash='),
    'Resultado deve conter um hash do conteudo original');
  Assert.IsTrue(Length(LResult) < Length(LContent),
    'Resultado cortado deve ser menor que o conteudo original');
end;

procedure TFileLogTests.Test_LogTruncate_MesmoConteudo_MesmoHash;
var
  LContent, LResult1, LResult2: string;
begin
  LContent := StringOfChar('b', 1000);
  LResult1 := TLogTruncate.Apply(LContent, 250);
  LResult2 := TLogTruncate.Apply(LContent, 250);

  Assert.AreEqual(LResult1, LResult2,
    'Mesmo conteudo deve produzir sempre o mesmo resultado (hash deterministico)');
end;

procedure TFileLogTests.Test_LogTruncate_ConteudoDiferente_HashDiferente;
var
  LContent1, LContent2, LResult1, LResult2: string;
begin
  // Mesmo prefixo visivel (250 chars) e mesmo tamanho total (254) nos dois —
  // qualquer diferenca no resultado só pode vir do hash, provando que ele
  // reflete o conteudo completo, nao só a parte truncada.
  LContent1 := StringOfChar('c', 250) + 'AAAA';
  LContent2 := StringOfChar('c', 250) + 'BBBB';
  LResult1 := TLogTruncate.Apply(LContent1, 250);
  LResult2 := TLogTruncate.Apply(LContent2, 250);

  Assert.AreNotEqual(LResult1, LResult2,
    'Conteudos diferentes com mesmo prefixo e tamanho devem produzir hashes diferentes');
end;

initialization
  TDUnitX.RegisterTestFixture(TFileLogTests);

end.
