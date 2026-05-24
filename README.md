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
    Db.Interfaces.pas         — IDBConnection, IDBConnectionPool, ITransaction, IQuery
    Db.Connection.Pool.pas    — TConnectionPool thread-safe com timeout e inatividade
    Db.SqlLoader.pas          — TSQLResult (ProcessTag, ApplyFilter, ReplaceLiteral)
    Db.SqlDialect.pas         — Enum de dialetos SQL
    Db.Adapters.FireDAC.pas   — Adapter FireDAC/Firebird
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
  Common.Optionals    in 'infra\src\Common\Common.Optionals.pas',
  Common.JsonMapper   in 'infra\src\Common\Common.JsonMapper.pas',
  Common.Helpers      in 'infra\src\Common\Common.Helpers.pas',
  Common.ClockCache   in 'infra\src\Common\Common.ClockCache.pas',
  Common.SystemContext in 'infra\src\Common\Common.SystemContext.pas',
  Db.Interfaces       in 'infra\src\Db\Db.Interfaces.pas',
  Db.Connection.Pool  in 'infra\src\Db\Db.Connection.Pool.pas',
  Db.SqlLoader        in 'infra\src\Db\Db.SqlLoader.pas',
  Db.SqlDialect       in 'infra\src\Db\Db.SqlDialect.pas',
  Db.Adapters.Registry in 'infra\src\Db\Db.Adapters.Registry.pas',
  Db.Adapters.FireDAC  in 'infra\src\Db\Db.Adapters.FireDAC.pas',
  Db.Constants         in 'infra\src\Db\Db.Constants.pas';
```

### 3. Recursos SQL (TSQLLoader)

O `Db.SqlLoader` não embute recursos — cada projeto fornece os seus. Adicione ao DPR:

```pascal
{$R 'src\Db\sql\queries.res'}
```

E compile o arquivo de recursos com:

```bash
brcc32.exe -fo src\Db\sql\queries.res src\Db\sql\queries.rc
```

---

## Licença

MIT — consulte o arquivo [LICENSE](LICENSE).
