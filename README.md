# delphi-api-infra-faa

Biblioteca de infraestrutura para APIs Delphi com Firebird. Fornece tipos opcionais/anuláveis, serialização JSON, pool de conexões e carregamento de SQL.

## Conteúdo

```
src/
  Common/
    Common.Optionals.pas      — IOptXxx, INullXxx, IOptNullXxx (9 tipos base)
    Common.JsonMapper.pas     — TJsonMapper: FromJson<I> / ToJson<I>
    Common.Helpers.pas        — Helpers de Variant e TParams para Optionals
    Common.ClockCache.pas     — Cache flyweight thread-safe dos Optional values
    Common.SystemContext.pas  — TClock e TSleep injetáveis (testabilidade)
  Db/
    Db.Interfaces.pas         — IDBConnection, IDBConnectionPool, ITransaction, IQuery, IMigrationDialect
    Db.Connection.Pool.pas    — TConnectionPool thread-safe com timeout e inatividade
    Db.SqlLoader.pas          — TSQLResult (ProcessTag, ApplyFilter, ReplaceLiteral)
    Db.SqlDialect.pas         — TFirebirdDialect, TPostgreSQLDialect (ISQLDialect + IMigrationDialect)
    Db.Migrations.pas         — TMigrationItem, TDBMigrationEngine
    Db.Adapters.FireDAC.pas   — Adapter FireDAC (agnóstico ao driver)
    Db.Adapters.Registry.pas  — TDBRegistry: registro de factories por nome
    Db.Constants.pas          — Constantes de configuração do pool
tests/
  Unit/         — 23 testes unitários (DUnitX) — Infra.UnitTests.dpr
  Integration/  — 4 testes com banco Firebird real — Infra.IntegrationTests.dpr
```

---

## Usando como submodule

### Adicionar ao seu projeto

Na raiz do repositório do seu projeto:

```bash
git submodule add https://github.com/fabianoallex/delphi-api-infra-faa infra
```

Isso cria a pasta `infra/` com todo o código da biblioteca e registra o submodule no `.gitmodules`.

### Clonar um projeto que já usa este submodule

```bash
git clone --recurse-submodules <url-do-seu-projeto>
```

### Atualizar o submodule para a versão mais recente

```bash
git submodule update --remote infra
git add infra
git commit -m "chore: atualiza infra"
```

---

## Configurando o projeto Delphi

### 1. Search path no DPROJ

Adicione ao `DCC_UnitSearchPath` do seu `.dproj`:

```
infra\src\Common;infra\src\Db
```

### 2. Referências explícitas no DPR

```pascal
uses
  Common.Optionals     in 'infra\src\Common\Common.Optionals.pas',
  Common.JsonMapper    in 'infra\src\Common\Common.JsonMapper.pas',
  Common.Helpers       in 'infra\src\Common\Common.Helpers.pas',
  Common.ClockCache    in 'infra\src\Common\Common.ClockCache.pas',
  Common.SystemContext in 'infra\src\Common\Common.SystemContext.pas',
  Db.Interfaces        in 'infra\src\Db\Db.Interfaces.pas',
  Db.Connection.Pool   in 'infra\src\Db\Db.Connection.Pool.pas',
  Db.SqlLoader         in 'infra\src\Db\Db.SqlLoader.pas',
  Db.SqlDialect        in 'infra\src\Db\Db.SqlDialect.pas',
  Db.Adapters.Registry in 'infra\src\Db\Db.Adapters.Registry.pas',
  Db.Adapters.FireDAC  in 'infra\src\Db\Db.Adapters.FireDAC.pas',
  Db.Constants         in 'infra\src\Db\Db.Constants.pas';
```

### 3. Units FireDAC obrigatórias

O FireDAC usa `initialization` de cada unit para registrar suas factories internas. A ausência de qualquer uma dessas units causa erros de "Object factory missing" em runtime — não em compilação.

```pascal
uses
  Winapi.Windows,          // necessário para SetDllDirectory
  FireDAC.Stan.Def,        // definições e factories base
  FireDAC.Stan.Pool,       // suporte a pool de conexões
  FireDAC.Stan.Async,      // operações assíncronas
  FireDAC.Stan.ExprFuncs,  // funções de expressão
  FireDAC.UI.Intf,         // interface abstrata de wait cursor
  FireDAC.ConsoleUI.Wait,  // wait cursor para {$APPTYPE CONSOLE}
                           // Para {$APPTYPE GUI}: usar FireDAC.VCLUI.Wait
  FireDAC.Phys,            // camada física base
  FireDAC.Phys.FB,         // driver Firebird (ou FireDAC.Phys.PG para PostgreSQL)
  FireDAC.DApt;            // factory do TFDQuery (obrigatório para Open/ExecSQL)
```

### 4. fbclient.dll no Windows 64-bit

Em instalações 64-bit do Windows, a `fbclient.dll` 32-bit fica em `WOW64\`, fora do PATH do sistema. O parâmetro `VendorLib` no `ConnectionParams` **não funciona** para o driver FB — o FireDAC carrega a DLL antes de ler os parâmetros de conexão. A solução é chamar `SetDllDirectory` no início do `begin` do DPR, antes de qualquer operação FireDAC:

```pascal
begin
  SetDllDirectory('C:\Program Files\Firebird\Firebird_2_5\WOW64');
  // ... restante da inicialização
end.
```

### 5. Recursos SQL (TSQLLoader)

O `Db.SqlLoader` não embute recursos — cada projeto fornece os seus. Adicione ao DPR:

```pascal
{$R 'src\Db\sql\queries.res'}
```

E compile o arquivo de recursos com:

```bash
brcc32.exe -fo src\Db\sql\queries.res src\Db\sql\queries.rc
```

---

## Migrations

O `Db.Migrations` fornece um engine de migrations baseado em **append-only immutable log**: scripts nunca são alterados após publicados em produção. Suporta Firebird e PostgreSQL via `IMigrationDialect` (implementado em ambos os dialetos da infra).

### Funcionamento

- A primeira migration do projeto deve criar a tabela `SCHEMA_MIGRATIONS`
- O engine verifica automaticamente a versão atual e aplica apenas as pendentes
- Cada migration roda em sua própria transação — falhas não desfazem as anteriores
- DDL no Firebird faz auto-commit (comportamento nativo do banco)

### Estrutura mínima da tabela de controle

```sql
-- Firebird (colocar no script MIG.0001):
CREATE TABLE SCHEMA_MIGRATIONS (
  VERSION    INTEGER   NOT NULL,
  APPLIED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT PK_SCHEMA_MIGRATIONS PRIMARY KEY (VERSION)
);

-- PostgreSQL (colocar no script MIG.0001):
CREATE TABLE IF NOT EXISTS schema_migrations (
  version    INTEGER   NOT NULL,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT pk_schema_migrations PRIMARY KEY (version)
);
```

### Uso no projeto

```pascal
uses
  Db.Migrations in 'infra\src\Db\Db.Migrations.pas';

const
  MIGRATIONS: array[0..2] of TMigrationItem = (
    (Version: 1; ScriptName: 'MIG.0001'; ParamReplaceProc: nil; Terminator: ';'; IsDDL: True),
    (Version: 2; ScriptName: 'MIG.0002'; ParamReplaceProc: nil; Terminator: ';'; IsDDL: True),
    (Version: 3; ScriptName: 'MIG.0003'; ParamReplaceProc: @MIG_0003Params; Terminator: '&'; IsDDL: False)
  );

// Na inicialização da aplicação, antes de iniciar o servidor:
var LEngine := TDBMigrationEngine.Create(TDBRegistry.GetFactory('meu_banco'));
LEngine.Execute(MIGRATIONS);
LEngine.Free;
```

O campo `IsDDL` indica se o script contém instruções DDL (`CREATE TABLE`, `ALTER TABLE`, etc.). Scripts DDL são executados em transação separada do registro de versão — necessário porque em Firebird o DDL auto-commita a transação ativa. Scripts DML (`IsDDL: False`) executam script e registro de versão em uma única transação atômica.

O campo `Terminator` define o separador de statements dentro do script (`;` para SQL padrão, `&` ou outro caractere quando o script contém blocos que já usam `;` internamente, como stored procedures no Firebird).

O `ParamReplaceProc` é um callback opcional para substituir placeholders no script antes da execução — útil para seeds com senhas hasheadas ou valores de ambiente:

```pascal
procedure MIG_0003Params(AScript: TStrings);
begin
  AScript.Text := StringReplace(AScript.Text, ':ADMIN_EMAIL',
    QuotedStr(GetEnvOrDefault('ADMIN_EMAIL', 'admin@exemplo.com')), [rfReplaceAll]);
end;
```

---

## Suporte a bancos de dados

O adaptador FireDAC (`Db.Adapters.FireDAC`) é agnóstico ao driver — o banco é definido pelo `DriverID` nos parâmetros de conexão. Os dialetos SQL (`Db.SqlDialect`) para savepoints já estão registrados para Firebird e PostgreSQL.

### Firebird

No DPR do projeto, inclua o driver FireDAC:

```pascal
uses
  FireDAC.Phys.FB;
```

Arquivo de configuração (`.ini` ou equivalente):

```ini
[Database]
DriverID=FB
Database=C:\caminho\para\banco.fdb
User_Name=SYSDBA
Password=masterkey
CharacterSet=UTF8
VendorLib=C:\Program Files\Firebird\Firebird_2_5\WOW64\fbclient.dll

[Options]
SQLDialect=Firebird
```

### PostgreSQL

No DPR do projeto, inclua o driver FireDAC:

```pascal
uses
  FireDAC.Phys.PG;
```

Arquivo de configuração:

```ini
[Database]
DriverID=PG
Database=meu_banco
Server=localhost
Port=5432
User_Name=postgres
Password=senha
CharacterSet=UTF8

[Options]
SQLDialect=PostgreSQL
```

> Os dois bancos podem coexistir no mesmo binário — basta registrar duas factories no `TDBRegistry` com nomes distintos e incluir ambos os units de driver no DPR.

### Outros componentes de acesso a dados

A arquitetura é extensível: qualquer componente (Zeos, UniDAC, dbExpress, etc.) pode ser suportado implementando as interfaces `IDBConnection`, `IDBConnectionPool`, `ITransaction` e `IQuery` definidas em `Db.Interfaces.pas` e registrando a factory no `TDBRegistry`.

---

## Licença

MIT — consulte o arquivo [LICENSE](LICENSE).
