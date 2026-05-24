unit Db.SqlDialect;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Db.Interfaces;

type
  TSQLDialectClass = class of TInterfacedObject;

  { TSQLDialectFactory }

  TSQLDialectFactory = class
  private
    class var FDialects: TDictionary<string, TSQLDialectClass>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure RegisterDialect(const AName: string; ADialectClass: TSQLDialectClass);
    class function GetDialect(const AName: string): ISQLDialect;
  end;

  { TPostgreSQLDialect }

  TPostgreSQLDialect = class(TInterfacedObject, ISQLDialect)
  public
    function GetReleaseSavepointSQL(const AName: string): string;
    function GetRollbackToSavepointSQL(const AName: string): string;
    function GetSavepointSQL(const AName: string): string;
    function SupportsRelease: Boolean;
  end;

  { TFirebirdDialect }

  TFirebirdDialect = class(TInterfacedObject, ISQLDialect)
  public
    function GetReleaseSavepointSQL(const AName: string): string;
    function GetRollbackToSavepointSQL(const AName: string): string;
    function GetSavepointSQL(const AName: string): string;
    function SupportsRelease: Boolean;
  end;

implementation

{ TSQLDialectFactory }

class constructor TSQLDialectFactory.Create;
begin
  FDialects := TDictionary<string, TSQLDialectClass>.Create;
end;

class destructor TSQLDialectFactory.Destroy;
begin
  FDialects.Free;
end;

class procedure TSQLDialectFactory.RegisterDialect(const AName: string;
  ADialectClass: TSQLDialectClass);
begin
  FDialects.Add(AName, ADialectClass);
end;

class function TSQLDialectFactory.GetDialect(const AName: string): ISQLDialect;
var
  LDialectClass: TSQLDialectClass;
begin
  if not FDialects.TryGetValue(AName, LDialectClass) then
    raise Exception.CreateFmt('Dialeto SQL "%s" não encontrado ou não registrado.', [AName]);

  Result := LDialectClass.Create as ISQLDialect;
end;

{ TPostgreSQLDialect }

function TPostgreSQLDialect.GetReleaseSavepointSQL(const AName: string): string;
begin
  Result := Format('RELEASE SAVEPOINT %s;', [AName]);
end;

function TPostgreSQLDialect.GetRollbackToSavepointSQL(const AName: string): string;
begin
  Result := Format('ROLLBACK TO SAVEPOINT %s;', [AName]);
end;

function TPostgreSQLDialect.GetSavepointSQL(const AName: string): string;
begin
  Result := Format('SAVEPOINT %s;', [AName]);
end;

function TPostgreSQLDialect.SupportsRelease: Boolean;
begin
  Result := True;
end;

{ TFirebirdDialect }

function TFirebirdDialect.GetReleaseSavepointSQL(const AName: string): string;
begin
  Result := Format('RELEASE SAVEPOINT %s;', [AName]);
end;

function TFirebirdDialect.GetRollbackToSavepointSQL(const AName: string): string;
begin
  Result := Format('ROLLBACK TO SAVEPOINT %s;', [AName]);
end;

function TFirebirdDialect.GetSavepointSQL(const AName: string): string;
begin
  Result := Format('SAVEPOINT %s;', [AName]);
end;

function TFirebirdDialect.SupportsRelease: Boolean;
begin
  Result := True;
end;

initialization
  TSQLDialectFactory.RegisterDialect('PostgreSQL', TPostgreSQLDialect);
  TSQLDialectFactory.RegisterDialect('Firebird', TFirebirdDialect);

end.
