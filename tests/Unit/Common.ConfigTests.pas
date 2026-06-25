unit Common.ConfigTests;

interface

uses
  DUnitX.TestFramework,
  Common.Config;

type
  [TestFixture]
  TAppConfigTests = class
  private
    FSavedEnvPath: string;
    FTempEnv:      string;
    procedure WriteEnv(const AContent: string);
    procedure SetEnv(const AKey, AValue: string);
    procedure ClearEnv(const AKey: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- Get ---
    [Test]
    procedure Get_RetornaDefault_QuandoSemEnvEArquivo;
    [Test]
    procedure Get_LeArquivo_QuandoSemEnvVar;
    [Test]
    procedure Get_EnvVarTemPrioridade_SobreArquivo;
    [Test]
    procedure Get_RetornaVazio_QuandoSemDefaultNemFonte;
    [Test]
    procedure Get_IgnoraComentarios_ELinhasVazias;
    [Test]
    procedure Get_RemoveAspas_DuplosESimples;

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
  FSavedEnvPath := TAppConfig.EnvFilePath;
  FTempEnv      := TPath.Combine(TPath.GetTempPath, 'appconfig_test.env');
  TAppConfig.SetEnvFile(FTempEnv);
end;

procedure TAppConfigTests.TearDown;
begin
  TAppConfig.SetEnvFile(FSavedEnvPath);
  if TFile.Exists(FTempEnv) then
    TFile.Delete(FTempEnv);
  ClearEnv(KEY_A);
  ClearEnv(KEY_B);
end;

procedure TAppConfigTests.WriteEnv(const AContent: string);
begin
  TFile.WriteAllText(FTempEnv, AContent, TEncoding.UTF8);
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

procedure TAppConfigTests.Get_RetornaDefault_QuandoSemEnvEArquivo;
begin
  Assert.AreEqual('fallback', TAppConfig.Get(KEY_A, 'fallback'));
end;

procedure TAppConfigTests.Get_LeArquivo_QuandoSemEnvVar;
begin
  WriteEnv(KEY_A + '=valor_env_file');
  Assert.AreEqual('valor_env_file', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_EnvVarTemPrioridade_SobreArquivo;
begin
  WriteEnv(KEY_A + '=valor_arquivo');
  SetEnv(KEY_A, 'valor_env');
  Assert.AreEqual('valor_env', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_RetornaVazio_QuandoSemDefaultNemFonte;
begin
  Assert.AreEqual('', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_IgnoraComentarios_ELinhasVazias;
begin
  WriteEnv('# comentario' + sLineBreak + '' + sLineBreak + KEY_A + '=ok');
  Assert.AreEqual('ok', TAppConfig.Get(KEY_A));
end;

procedure TAppConfigTests.Get_RemoveAspas_DuplosESimples;
begin
  WriteEnv(KEY_A + '="valor com aspas"' + sLineBreak +
           KEY_B + '=''valor simples''');
  Assert.AreEqual('valor com aspas', TAppConfig.Get(KEY_A));
  Assert.AreEqual('valor simples',   TAppConfig.Get(KEY_B));
end;

{ GetInt }

procedure TAppConfigTests.GetInt_ParseaValorNumerico;
begin
  WriteEnv(KEY_A + '=9000');
  Assert.AreEqual(9000, TAppConfig.GetInt(KEY_A, 0));
end;

procedure TAppConfigTests.GetInt_RetornaDefault_QuandoNaoNumerico;
begin
  WriteEnv(KEY_A + '=abc');
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
