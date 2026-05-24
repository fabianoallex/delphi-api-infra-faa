program Infra.IntegrationTests;

{$APPTYPE GUI}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  Vcl.Forms,
  Winapi.Windows,
  // FireDAC: registra driver Firebird e infra de fábricas (sem estas units os drivers não são encontrados)
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,      // registra TFDGUIxWaitCursor para apps VCL/GUI
  FireDAC.Phys.FB,         // registra o driver Firebird (obrigatório)
  FireDAC.DApt,            // registra TFDQuery factory (obrigatório para queries)
  DUnitX.Loggers.GUI.VCL,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  TestConfig in 'TestConfig.pas',
  Db.ConnectionTests in 'Db.ConnectionTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger : ITestLogger;
  ShouldRunGUI: Boolean;
  I: Integer;
  LVendorDir: string;
begin
  // FireDAC (32-bit) precisa encontrar fbclient.dll antes de qualquer conexão.
  // No Windows 64-bit o Firebird instala a DLL 32-bit em WOW64\, fora do PATH
  // do sistema. SetDllDirectory adiciona o diretório ao search path do processo.
  LVendorDir := ExtractFilePath(TTestConfig.DetectFirebirdVendorLib);
  if (LVendorDir <> '') and DirectoryExists(LVendorDir) then
    SetDllDirectory(PChar(LVendorDir));

  ReportMemoryLeaksOnShutdown := True;

  ShouldRunGUI := False;
  for I := 1 to ParamCount do
  begin
    if SameText(ParamStr(I), 'gui') then
    begin
      ShouldRunGUI := True;
      Break;
    end;
  end;

  try
    if ShouldRunGUI then
    begin
      // --- MODO GUI ---
      Application.Initialize;
      Application.MainFormOnTaskBar := True;
      Run; // Procedure global da unit DUnitX.Loggers.GUI.VCL
    end
    else
    begin
      // --- MODO CONSOLE (PADRÃO) ---
      if not AttachConsole(ATTACH_PARENT_PROCESS) then
        AllocConsole;

      AssignFile(Output, 'CONOUT$');
      Rewrite(Output);

      TDUnitX.CheckCommandLine;

      if TDUnitX.Options.Include = '' then
        TDUnitX.Options.Include := '.';

      runner := TDUnitX.CreateRunner;
      runner.UseRTTI := True;
      runner.FailsOnNoAsserts := False;

      if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
      begin
        logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
        runner.AddLogger(logger);
      end;

      nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
      runner.AddLogger(nunitLogger);

      results := runner.Execute;

      if not results.AllPassed then
        System.ExitCode := EXIT_ERRORS;

      if (TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause) or (ParamCount = 0) then
      begin
        System.Writeln('Done.. press <Enter> key to quit.');
        System.Readln;
      end;

      FreeConsole;
    end;

  except
    on E: Exception do
    begin
      if IsConsole then
        System.Writeln(E.ClassName, ': ', E.Message)
      else
        MessageBox(0, PChar(E.Message), 'Application Error', MB_OK or MB_ICONERROR);
    end;
  end;
end.
