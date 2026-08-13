unit Common.Config;

{
  Lê configuração de variáveis de ambiente com fallback para arquivo .env.
  Ordem de busca: env var → .env → default.

  Arquivo padrão: .env no diretório do executável.
  Formato: KEY=VALUE (uma por linha; linhas em branco e comentários com # são ignorados).
  Valores podem ser opcionalmente delimitados por aspas simples ou duplas.

  Uso:
    LPort := TAppConfig.GetInt('SERVER_PORT', 9000);
    LDb   := TAppConfig.Get('DB_PATH', 'C:\banco.fdb');

  Para substituir o arquivo (ex: em testes):
    TAppConfig.SetEnvFile('C:\temp\test.env');
}

interface

type
  TAppConfig = class
  private
    class var FEnvPath: string;
    class function ReadEnv(const AKey: string): string;
    class function ReadFile(const AKey: string): string;
  public
    class constructor Create;
    class procedure SetEnvFile(const APath: string);
    class function EnvFilePath: string;
    class function Get(const AKey: string; const ADefault: string = ''): string;
    class function GetInt(const AKey: string; ADefault: Integer = 0): Integer;
    class function GetBool(const AKey: string; ADefault: Boolean = False): Boolean;

    { Compatibilidade retroativa com SetIniFile/IniPath }
    class procedure SetIniFile(const APath: string; const ASection: string = '');
    class function IniPath: string;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes;

class constructor TAppConfig.Create;
begin
  FEnvPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '.env');
end;

class procedure TAppConfig.SetEnvFile(const APath: string);
begin
  FEnvPath := APath;
end;

class function TAppConfig.EnvFilePath: string;
begin
  Result := FEnvPath;
end;

class procedure TAppConfig.SetIniFile(const APath: string; const ASection: string);
begin
  FEnvPath := APath;
end;

class function TAppConfig.IniPath: string;
begin
  Result := FEnvPath;
end;

class function TAppConfig.ReadEnv(const AKey: string): string;
begin
  Result := GetEnvironmentVariable(AKey);
end;

class function TAppConfig.ReadFile(const AKey: string): string;
var
  LLines: TStringList;
  LLine, LK, LV: string;
  LSep: Integer;
begin
  Result := '';
  if not TFile.Exists(FEnvPath) then Exit;
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(FEnvPath, TEncoding.UTF8);
    for LLine in LLines do
    begin
      LK := Trim(LLine);
      if LK.IsEmpty or LK.StartsWith('#') then Continue;
      LSep := LK.IndexOf('=');
      if LSep <= 0 then Continue;
      if not SameText(LK.Substring(0, LSep).Trim, AKey) then Continue;
      LV := LK.Substring(LSep + 1);
      if (LV.Length >= 2) and
         ((LV.StartsWith('"') and LV.EndsWith('"')) or
          (LV.StartsWith('''') and LV.EndsWith(''''))) then
        LV := LV.Substring(1, LV.Length - 2);
      Result := LV;
      Exit;
    end;
  finally
    LLines.Free;
  end;
end;

class function TAppConfig.Get(const AKey, ADefault: string): string;
begin
  Result := ReadEnv(AKey);
  if Result.IsEmpty then
    Result := ReadFile(AKey);
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
