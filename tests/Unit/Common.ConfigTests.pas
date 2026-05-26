unit Common.ConfigTests;

interface

uses
  DUnitX.TestFramework,
  Common.Config;

type
  [TestFixture]
  TAppConfigTests = class
  private
    FSavedIniPath: string;
    FTempIni:      string;
    procedure WriteIni(const AContent: string);
    procedure SetEnv(const AKey, AValue: string);
    procedure ClearEnv(const AKey: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- Get ---
    [Test]
    procedure Get_RetornaDefault_QuandoSemEnvEIni;
    [Test]
    procedure Get_LeLni_QuandoSemEnvVar;
    [Test]
    procedure Get_EnvVarTemPrioridade_SobreIni;
    [Test]
    procedure Get_RetornaVazio_QuandoSemDefaultNemFonte;

    // --- GetInt ---
    [Test]
    procedure GetInt_ParseaValorNumerico;
    [Test]
    procedure GetInt_RetornaDefault_QuandoNaoNumerico;
    [Test]
    procedure GetInt_RetornaDefault_QuandoAusente;

    // --- GetBool ---
    [Test]
    procedure GetBool_Reconhece_True;
    [Test]
    procedure GetBool_Reconhece_Um;
    [Test]
    procedure GetBool_Reconhece_Yes;
    [Test]
    procedure GetBool_Reconhece_False;
    [Test]
    procedure GetBool_RetornaDefault_QuandoAusente;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows;

const
  KEY_A = 'APPCONFIG_TEST_KEY_A_XYZ';
  KEY_B = 'APPCONFIG_TEST_KEY_B_XYZ';

procedure TAppConfigTests.Setup;
begin
  FSavedIniPath := TAppConfig.IniPath;
  FTempIni      := TPath.Combine(TPath.GetTempPath, 'appconfig_test.ini');
  TAppConfig.SetIniFile(FTempIni);
end;

procedure TAppConfigTests.TearDown;
begin
  TAppConfig.SetIniFile(FSavedIniPath);
  if TFile.Exists(FTempIni) then
    TFile.Delete(FTempIni);
  ClearEnv(KEY_A);
  ClearEnv(KEY_B);
end;

procedure TAppConfigTests.WriteIni(const AContent: string);
begin
  TFile.WriteAllText(FTempIni, AContent);
end;

procedure TAppConfigTests.SetEnv(const AKey, AValue: string);
begin
  Winapi.Windows.SetEnvironmentVariable(PChar(AKey), PChar(AValue));
end;

procedure TAppConfigTests.ClearEnv(const AKey: string);
begin
  Winapi.Windows.SetEnvironmentVariable(PChar(AKey), nil);
end;

{ Get }

procedure TAppConfigTests.Get_RetornaDefault_QuandoSemEnvEIni;
begin
  Assert.AreEqual('fallback', TAppConfig.Get(KEY_A, 'fallback'));
end;

procedure TAppConfigTests.Get_LeLni_QuandoSemEnvVar;
begin
  WriteIni('[Config]' + sLineBreak + KEY_A + '=valor_ini');
  Assert.AreEqual('valor_ini', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_EnvVarTemPrioridade_SobreIni;
begin
  WriteIni('[Config]' + sLineBreak + KEY_A + '=valor_ini');
  SetEnv(KEY_A, 'valor_env');
  Assert.AreEqual('valor_env', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_RetornaVazio_QuandoSemDefaultNemFonte;
begin
  Assert.AreEqual('', TAppConfig.Get(KEY_A));
end;

{ GetInt }

procedure TAppConfigTests.GetInt_ParseaValorNumerico;
begin
  WriteIni('[Config]' + sLineBreak + KEY_A + '=9000');
  Assert.AreEqual(9000, TAppConfig.GetInt(KEY_A, 0));
end;

procedure TAppConfigTests.GetInt_RetornaDefault_QuandoNaoNumerico;
begin
  WriteIni('[Config]' + sLineBreak + KEY_A + '=abc');
  Assert.AreEqual(42, TAppConfig.GetInt(KEY_A, 42));
end;

procedure TAppConfigTests.GetInt_RetornaDefault_QuandoAusente;
begin
  Assert.AreEqual(8080, TAppConfig.GetInt(KEY_A, 8080));
end;

{ GetBool }

procedure TAppConfigTests.GetBool_Reconhece_True;
begin
  SetEnv(KEY_A, 'true');
  Assert.IsTrue(TAppConfig.GetBool(KEY_A, False));
end;

procedure TAppConfigTests.GetBool_Reconhece_Um;
begin
  SetEnv(KEY_A, '1');
  Assert.IsTrue(TAppConfig.GetBool(KEY_A, False));
end;

procedure TAppConfigTests.GetBool_Reconhece_Yes;
begin
  SetEnv(KEY_A, 'yes');
  Assert.IsTrue(TAppConfig.GetBool(KEY_A, False));
end;

procedure TAppConfigTests.GetBool_Reconhece_False;
begin
  SetEnv(KEY_A, 'false');
  Assert.IsFalse(TAppConfig.GetBool(KEY_A, True));
end;

procedure TAppConfigTests.GetBool_RetornaDefault_QuandoAusente;
begin
  Assert.IsTrue(TAppConfig.GetBool(KEY_A, True));
  Assert.IsFalse(TAppConfig.GetBool(KEY_B, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAppConfigTests);

end.
