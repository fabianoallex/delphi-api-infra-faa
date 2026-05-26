program Infra.UnitTests;

{$APPTYPE GUI}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  Vcl.Forms,
  Winapi.Windows,
  DUnitX.Loggers.GUI.VCL,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  Common.JsonMapper in '..\..\src\Common\Common.JsonMapper.pas',
  Common.Helpers in '..\..\src\Common\Common.Helpers.pas',
  Common.DTO.Base in '..\..\src\Common\Common.DTO.Base.pas',
  Common.OrderBy in '..\..\src\Common\Common.OrderBy.pas',
  Common.Pagination in '..\..\src\Common\Common.Pagination.pas',
  Common.Config in '..\..\src\Common\Common.Config.pas',
  MCP.Utils in '..\..\src\MCP\MCP.Utils.pas',
  Swagger.Attributes in '..\..\src\Swagger\Swagger.Attributes.pas',
  Common.HelpersTests in 'Common.HelpersTests.pas',
  Common.JsonMapperTests in 'Common.JsonMapperTests.pas',
  Common.JsonResolverTests in 'Common.JsonResolverTests.pas',
  Common.JsonSerializerTests in 'Common.JsonSerializerTests.pas',
  ClockCacheTests in 'ClockCacheTests.pas',
  OptionalsTests in 'OptionalsTests.pas',
  Db.Mock in '..\..\src\Db\Db.Mock.pas',
  Db.PoolTests in 'Db.PoolTests.pas',
  Db.SqlLoaderTests in 'Db.SqlLoaderTests.pas',
  Db.MockTests in 'Db.MockTests.pas',
  Swagger.SchemaTests in 'Swagger.SchemaTests.pas',
  Common.OrderByTests in 'Common.OrderByTests.pas',
  Common.PaginationTests in 'Common.PaginationTests.pas',
  MCP.UtilsTests in 'MCP.UtilsTests.pas',
  Common.ConfigTests in 'Common.ConfigTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger : ITestLogger;
  ShouldRunGUI: Boolean;
  I: Integer;
begin
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
      begin
        TDUnitX.Options.Include := '.';
      end;

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
