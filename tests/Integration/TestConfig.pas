unit TestConfig;

interface

uses
  System.SysUtils,
  System.IniFiles,
  System.Classes;

(*
  Lê parâmetros de conexão de um arquivo INI externo não versionado.

  Crie o arquivo "integration_test.ini" na mesma pasta deste executável
  com o seguinte conteúdo (ajuste os valores ao seu ambiente):

    [Database]
    DriverID=FB
    Database=C:\caminho\para\rweb_test.fdb
    User_Name=SYSDBA
    Password=masterkey
    CharacterSet=UTF8

    [Options]
    SQLDialect=Firebird
*)

type
  TTestConfig = class
  private
    class var FConfigPath: string;
    class var FConfigured: Boolean;
    class var FChecked: Boolean;
    class function IniPath: string;
  public
    class function IsConfigured: Boolean;
    class function GetConnectionParams: TStrings;
    class function GetSQLDialect: string;
    class function DetectFirebirdVendorLib: string;
  end;

implementation

{ TTestConfig }

class function TTestConfig.IniPath: string;
const
  FileName = 'integration_test.ini';
var
  LDir: string;
  I: Integer;
begin
  // Sobe até 4 níveis a partir do exe (cobre Win32\Debug\ → Integration\)
  LDir := ExtractFilePath(ParamStr(0));
  for I := 0 to 4 do
  begin
    Result := LDir + FileName;
    if FileExists(Result) then
      Exit;
    LDir := ExtractFilePath(ExcludeTrailingPathDelimiter(LDir));
  end;
  Result := ExtractFilePath(ParamStr(0)) + FileName;
end;

class function TTestConfig.IsConfigured: Boolean;
begin
  if not FChecked then
  begin
    FChecked := True;
    FConfigured := FileExists(IniPath);
  end;
  Result := FConfigured;
end;

class function TTestConfig.GetConnectionParams: TStrings;
var
  LIni: TIniFile;
  LKeys: TStringList;
  I: Integer;
  LKey, LValue: string;
begin
  Result := TStringList.Create;
  if not IsConfigured then
    Exit;

  LIni := TIniFile.Create(IniPath);
  try
    LKeys := TStringList.Create;
    try
      LIni.ReadSectionValues('Database', LKeys);
      for I := 0 to LKeys.Count - 1 do
        Result.Add(LKeys[I]);
    finally
      LKeys.Free;
    end;
  finally
    LIni.Free;
  end;
end;

class function TTestConfig.DetectFirebirdVendorLib: string;
const
  // Win32 (32-bit) exige a fbclient.dll 32-bit; no Firebird 2.5 de 64-bit
  // ela fica na subpasta WOW64. Em instalações 32-bit fica em bin\.
  Candidates: array[0..3] of string = (
    'C:\Program Files\Firebird\Firebird_2_5\WOW64\fbclient.dll',
    'C:\Program Files\Firebird\Firebird_2_5\bin\fbclient.dll',
    'C:\Program Files (x86)\Firebird\Firebird_2_5\bin\fbclient.dll',
    ''
  );
var
  LPath: string;
begin
  for LPath in Candidates do
  begin
    if (LPath = '') or FileExists(LPath) then
    begin
      Result := LPath;
      Exit;
    end;
  end;
  Result := '';
end;

class function TTestConfig.GetSQLDialect: string;
var
  LIni: TIniFile;
begin
  Result := 'PostgreSQL';
  if not IsConfigured then
    Exit;

  LIni := TIniFile.Create(IniPath);
  try
    Result := LIni.ReadString('Options', 'SQLDialect', 'PostgreSQL');
  finally
    LIni.Free;
  end;
end;

end.
