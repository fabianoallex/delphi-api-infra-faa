unit Common.Config;

{
  Lê configuração de variáveis de ambiente com fallback para arquivo ini.
  Ordem de busca: env var → ini → default.

  Arquivo ini padrão: app.ini no diretório do executável, seção [Config].

  Uso:
    LPort := TAppConfig.GetInt('SERVER_PORT', 9000);
    LDb   := TAppConfig.Get('DB_PATH', 'C:\banco.fdb');

  Para substituir o arquivo ini (ex: em testes):
    TAppConfig.SetIniFile('C:\temp\test.ini');
}

interface

type
  TAppConfig = class
  private
    class var FIniPath: string;
    class var FSection: string;
    class function ReadEnv(const AKey: string): string;
    class function ReadIni(const AKey: string): string;
  public
    class constructor Create;
    class procedure SetIniFile(const APath: string; const ASection: string = 'Config');
    class function IniPath: string;
    class function Get(const AKey: string; const ADefault: string = ''): string;
    class function GetInt(const AKey: string; ADefault: Integer = 0): Integer;
    class function GetBool(const AKey: string; ADefault: Boolean = False): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.IniFiles,
  System.IOUtils;

class constructor TAppConfig.Create;
begin
  FSection := 'Config';
  FIniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'app.ini');
end;

class procedure TAppConfig.SetIniFile(const APath, ASection: string);
begin
  FIniPath := APath;
  FSection := ASection;
end;

class function TAppConfig.IniPath: string;
begin
  Result := FIniPath;
end;

class function TAppConfig.ReadEnv(const AKey: string): string;
begin
  Result := GetEnvironmentVariable(AKey);
end;

class function TAppConfig.ReadIni(const AKey: string): string;
var
  LIni: TIniFile;
begin
  Result := '';
  if not TFile.Exists(FIniPath) then Exit;
  LIni := TIniFile.Create(FIniPath);
  try
    Result := LIni.ReadString(FSection, AKey, '');
  finally
    LIni.Free;
  end;
end;

class function TAppConfig.Get(const AKey, ADefault: string): string;
begin
  Result := ReadEnv(AKey);
  if Result.IsEmpty then
    Result := ReadIni(AKey);
  if Result.IsEmpty then
    Result := ADefault;
end;

class function TAppConfig.GetInt(const AKey: string; ADefault: Integer): Integer;
begin
  if not TryStrToInt(Get(AKey), Result) then
    Result := ADefault;
end;

class function TAppConfig.GetBool(const AKey: string; ADefault: Boolean): Boolean;
var
  LVal: string;
begin
  LVal := Get(AKey).ToLower;
  if LVal.IsEmpty then
    Result := ADefault
  else
    Result := (LVal = 'true') or (LVal = '1') or (LVal = 'yes');
end;

end.
