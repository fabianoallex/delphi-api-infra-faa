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

  --- CAMPO IsDDL ---
  Cada TMigrationItem declara se o script é DDL ou DML via o campo IsDDL.
  O padrão (False) indica DML — script e registro de versão na mesma transação,
  garantindo atomicidade completa.

  IsDDL = False (DML): script + INSERT de versão → uma transação atômica.
    Use para: INSERTs de seed, UPDATEs de dados, DELETEs de limpeza.

  IsDDL = True  (DDL): script em T1 (commit) → INSERT de versão em T2 separada.
    Use para: CREATE TABLE, ALTER TABLE, CREATE INDEX, DROP, etc.
    Motivo: em Firebird, DDL faz auto-commit da transação ativa. Em PostgreSQL,
    DDL é transacional — mas o comportamento de duas transações é seguro para
    ambos os bancos, tornando IsDDL=True portável.

  ATENÇÃO: esquecer IsDDL=True em um script DDL provoca erro "Table unknown"
  no INSERT de versão (o mesmo erro que motivou este flag).
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
    IsDDL: Boolean;
  end;

  { TDBMigrationEngine }

  TDBMigrationEngine = class
  private
    FFactory: IDBFactory;
    function ResolveMigrationDialect: IMigrationDialect;
    function GetCurrentVersion(AMigDialect: IMigrationDialect): Integer;
    procedure ApplyScript(const AMigration: TMigrationItem; ATransaction: ITransaction);
    procedure InsertVersionRecord(AVersion: Integer; AMigDialect: IMigrationDialect;
      ATransaction: ITransaction = nil);
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
  if Assigned(ATransaction) then
  begin
    // DML: INSERT na mesma transação do script para garantir atomicidade.
    // Usa CreateQuery diretamente para não interferir com o IScopeTransaction do chamador.
    LQuery := FFactory.CreateQuery(ATransaction.GetConnection, ATransaction);
    LQuery.Sql := AMigDialect.GetMigrationInsertVersionSQL;
    LQuery.Params.Integers['VERSION'] := AVersion;
    LQuery.ExecSql;
  end
  else
  begin
    // DDL: Firebird auto-commita DDL; precisamos de transação nova
    // para enxergar a tabela criada pelo script anterior.
    LScope := FFactory.GetPool.AcquireQuery(LQuery);
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

    if LMigration.IsDDL then
    begin
      // T1: executa o DDL e commita (Firebird auto-commita; PostgreSQL commita aqui)
      LScope := FFactory.GetPool.AcquireQuery(LQuery);
      LScope.StartTransaction;
      try
        ApplyScript(LMigration, LScope.GetOriginalTransaction);
        LScope.Commit;
      except
        LScope.Rollback;
        raise;
      end;

      // T2: registra versão — transação nova enxerga a tabela criada acima
      InsertVersionRecord(LMigration.Version, LMigDialect, nil);
    end
    else
    begin
      // DML: script + versão em uma única transação (atômica)
      LScope := FFactory.GetPool.AcquireQuery(LQuery);
      LScope.StartTransaction;
      try
        ApplyScript(LMigration, LScope.GetOriginalTransaction);
        InsertVersionRecord(LMigration.Version, LMigDialect,
          LScope.GetOriginalTransaction);
        LScope.Commit;
      except
        LScope.Rollback;
        raise;
      end;
    end;
  end;
end;

end.
