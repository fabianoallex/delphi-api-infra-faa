unit Db.Migrations;

{*******************************************************************************
  ESTRATÉGIA DE EVOLUÇÃO DO SCHEMA (MIGRATIONS)

  Padrão: append-only immutable log. Scripts nunca são alterados após publicados.

  --- RESPONSABILIDADE DA PRIMEIRA MIGRATION ---
  O engine NÃO cria a tabela SCHEMA_MIGRATIONS automaticamente. O script MIG.0001
  do projeto deve criar a tabela com a seguinte estrutura mínima:

    -- Firebird:
    CREATE TABLE SCHEMA_MIGRATIONS (
      VERSION   INTEGER   NOT NULL,
      APPLIED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
      CONSTRAINT PK_SCHEMA_MIGRATIONS PRIMARY KEY (VERSION)
    );

    -- PostgreSQL:
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    INTEGER   NOT NULL,
      applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
      CONSTRAINT pk_schema_migrations PRIMARY KEY (version)
    );

  --- BASELINE (SQUASHING) ---
  Consolide scripts antigos em um Baseline quando o volume tornar o deploy lento
  ou ao atingir uma versão major. Garanta que nenhum banco em produção esteja
  abaixo da versão do Baseline antes de remover os scripts anteriores.

  --- ADICIONANDO SCRIPTS ---
  Sempre adicione ao final de MIGRATIONS_LIST para garantir ordem cronológica.

  --- COMPORTAMENTO POR MIGRATION ---
  Cada migration roda em sua própria transação. Se falhar, as anteriores já estão
  commitadas e o processo reinicia a partir da versão pendente.

  Nota Firebird: DDL (CREATE TABLE, ALTER TABLE, etc.) dentro de uma transaction
  faz auto-commit no Firebird. Isso é comportamento nativo do banco — não é um
  bug do engine.
*******************************************************************************}

interface

uses
  System.Classes,
  System.SysUtils,
  Db.Interfaces;

type
  TParamReplaceProc = procedure(AScript: TStrings);

  TMigrationItem = record
    Version: Integer;
    ScriptName: string;
    ParamReplaceProc: TParamReplaceProc;
    Terminator: string;
  end;

  { TDBMigrationEngine }

  TDBMigrationEngine = class
  private
    FFactory: IDBFactory;
    function ResolveMigrationDialect: IMigrationDialect;
    function GetCurrentVersion(AMigDialect: IMigrationDialect): Integer;
    procedure ApplyScript(const AMigration: TMigrationItem; ATransaction: ITransaction);
    procedure InsertVersionRecord(AVersion: Integer; AMigDialect: IMigrationDialect;
      ATransaction: ITransaction);
  public
    constructor Create(AFactory: IDBFactory);
    procedure Execute(const AMigrations: array of TMigrationItem);
  end;

implementation

{ TDBMigrationEngine }

constructor TDBMigrationEngine.Create(AFactory: IDBFactory);
begin
  FFactory := AFactory;
end;

function TDBMigrationEngine.ResolveMigrationDialect: IMigrationDialect;
var
  LConn: IDBConnection;
begin
  LConn := FFactory.GetPool.AcquireConnection;
  try
    if not Supports(LConn.GetSQLDialect, IMigrationDialect, Result) then
      raise Exception.Create(
        'O dialeto configurado não implementa IMigrationDialect. ' +
        'Verifique se TFirebirdDialect ou TPostgreSQLDialect está em uso.');
  finally
    LConn := nil; // devolve ao pool
  end;
end;

function TDBMigrationEngine.GetCurrentVersion(AMigDialect: IMigrationDialect): Integer;
var
  LScope: IScopeTransaction;
  LQuery: IQuery;
  LResult: IQueryResult;
  LTableExists: Boolean;
begin
  // Verifica existência da tabela de controle
  LScope := FFactory.GetPool.AcquireQuery(LQuery);
  LScope.StartTransaction;
  try
    LQuery.Sql := AMigDialect.GetMigrationTableExistsSQL;
    LResult := LQuery.Open;
    LTableExists := LResult.Booleans['EXISTS'];
    LScope.Commit;
  except
    LScope.Rollback;
    raise;
  end;

  if not LTableExists then
  begin
    Result := 0;
    Exit;
  end;

  // Lê a versão atual
  LScope := FFactory.GetPool.AcquireQuery(LQuery);
  LScope.StartTransaction;
  try
    LQuery.Sql := AMigDialect.GetMigrationLastVersionSQL;
    LResult := LQuery.Open;
    Result := LResult.Integers['VERSION'];
    LScope.Commit;
  except
    LScope.Rollback;
    raise;
  end;
end;

procedure TDBMigrationEngine.ApplyScript(const AMigration: TMigrationItem;
  ATransaction: ITransaction);
var
  LScript: TStrings;
  LSqlScript: ISqlScript;
begin
  LScript := TStringList.Create;
  try
    LScript.Text := FFactory.SqlLoader[AMigration.ScriptName].SQL;

    if Assigned(AMigration.ParamReplaceProc) then
      AMigration.ParamReplaceProc(LScript);

    if Trim(LScript.Text) = '' then
      raise Exception.CreateFmt('Script vazio: %s', [AMigration.ScriptName]);

    LSqlScript := FFactory.CreateSqlScript(ATransaction.GetConnection, ATransaction);
    LSqlScript.Script := LScript;
    LSqlScript.ExecuteScript(AMigration.Terminator);
  finally
    LScript.Free;
  end;
end;

procedure TDBMigrationEngine.InsertVersionRecord(AVersion: Integer;
  AMigDialect: IMigrationDialect; ATransaction: ITransaction);
var
  LScope: IScopeTransaction;
  LQuery: IQuery;
begin
  LScope := FFactory.GetPool.AcquireQuery(LQuery, ATransaction);
  LScope.StartTransaction;
  try
    LQuery.Sql := AMigDialect.GetMigrationInsertVersionSQL;
    LQuery.Params.Integers['VERSION'] := AVersion;
    LQuery.ExecSql;
    LScope.Commit;
  except
    LScope.Rollback;
    raise;
  end;
end;

procedure TDBMigrationEngine.Execute(const AMigrations: array of TMigrationItem);
var
  LMigDialect: IMigrationDialect;
  LCurrentVersion: Integer;
  LMigration: TMigrationItem;
  LScope: IScopeTransaction;
  LQuery: IQuery;
begin
  LMigDialect := ResolveMigrationDialect;
  LCurrentVersion := GetCurrentVersion(LMigDialect);

  for LMigration in AMigrations do
  begin
    if LMigration.Version <= LCurrentVersion then
      Continue;

    LScope := FFactory.GetPool.AcquireQuery(LQuery);
    LScope.StartTransaction;
    try
      ApplyScript(LMigration, LScope.GetOriginalTransaction);
      InsertVersionRecord(LMigration.Version, LMigDialect, LScope.GetOriginalTransaction);
      LScope.Commit;
    except
      LScope.Rollback;
      raise;
    end;
  end;
end;

end.
