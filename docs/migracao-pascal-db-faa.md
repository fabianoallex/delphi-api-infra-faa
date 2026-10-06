# Migração da camada `Db.*` para a pascal-db-faa

**Data da avaliação:** 2026-10-06 · infra `937ad1e` (v0.1.1 + pascal-common-faa v1.2.0) ·
pascal-db-faa **v0.10.1**

A [pascal-db-faa](https://github.com/fabianoallex/pascal-db-faa) foi extraída de `src/Db/*`
desta lib no commit `aa49f2b` (2026-08-25) e evoluiu sozinha desde então (dual-compiler, mais
adapters e bancos, várias correções). As duas camadas eram linhagens paralelas: correção feita
de um lado não chegava ao outro. Esta migração elimina `src/Db/` e passa a infra a consumir a
pascal-db-faa, do mesmo jeito que já consome a pascal-common-faa.

**Veredito:** migrar. A API que os repositórios usam é praticamente a mesma; o custo é
renomear units e trocar uma classe de configuração. Decidido renomear direto (sem units de
compatibilidade `Db.*` reexportando aliases), como breaking change da infra (v0.2.0).

---

## Comparação de API (assinaturas públicas, unit por unit)

### Igual ou superconjunto — nada muda no código de quem usa

- `IDBFactory`, `IQuery`, `IParams`, `IQueryResult`, `IScopeTransaction`, `ITransaction`,
  `IDBConnectionPool`: mesmas assinaturas. A pascal-db-faa só acrescenta (`IBatch`,
  `IPagingDialect`, `ISQLDialect.GetPingSQL`, `IDatabaseConfig.LockTimeoutMs` /
  `PoolKeepaliveSeconds` / `PoolValidateIdleSeconds`).
- `TDBMigrationEngine` / `TMigrationItem` (mesmos campos), `TDBRegistry`, `TConnectionPool`,
  `TPoolSnapshot`, `TPoolEvent`, `TMockDBFactory` (ganhou `AddFailure` / `Rewind`).
- `FFactory.SqlLoader['X'].ProcessTag(...).ReplaceLiteral(...)`, sintaxe `[TAG {] ... [} TAG]` e
  `${...}`. O nome do resource continua `SQL_<DIR>_<NOME>`: os `.rc` e o
  `tools/build_sql_res.bat` desta lib seguem valendo.
- As duas mudanças em `src/Db` desta lib depois de `aa49f2b` (fix dos marcadores de tag
  `48f7bca`; ida para a pascal-common-faa `72aec7a`) já existem na pascal-db-faa (v0.10.0 e
  v0.9.0). Nada se perde.

### Muda

| Onde | Antes | Depois |
|---|---|---|
| Units | `Db.Interfaces`, `Db.Connection.Pool`, `Db.Adapters.Registry`, `Db.Adapters.FireDAC`, `Db.Migrations`, `Db.SqlLoader`, `Db.SqlDialect`, `Db.Mock` | `PascalDb.Interfaces`, `PascalDb.Pool`, `PascalDb.Registry`, `PascalDb.Adapter.FireDAC`, `PascalDb.Migrations`, `PascalDb.SqlLoader`, `PascalDb.SqlDialect`, `PascalDb.Mock` |
| `Db.Constants` | unit vazia | removida |
| Config da factory | `LConfig: TFDConfig` (`Db.Adapters.FireDAC`) | `LConfig: IDatabaseConfig` + `TDatabaseConfig.Create` (`PascalDb.Adapter.Base`). Mesmos nomes (inclusive `PoolWaitMaxAttemps`), mas as properties (`ConnectionParams`, `SQLDialect`, `SQLDirectory`) só existem na **interface**: com a variável ainda do tipo da classe, `LConfig.ConnectionParams.Add(...)` não compila. Os `SetPoolXxx(...)` funcionam nos dois |
| `TSQLLoader` | `Load` / `ClearCache` eram `class` | métodos de instância; nenhum consumidor conhecido usa direto |
| Search path do consumidor | `infra\src\Db` | `modules\pascal-db-faa\src` + `modules\pascal-db-faa\adapters\firedac` |
| Namespaces por plataforma | `src/Db` usava nomes completos (`Winapi.Windows`) | A pascal-db-faa usa nomes sem namespace (`Windows`, `SysUtils`: regra dual-compiler dela). Todo `.dproj` que compila a pascal-db-faa precisa de `Winapi;System.Win;...` no `DCC_Namespace` **de cada plataforma**. A IDE costuma gravar isso só no grupo `Base_Win32`; sem ele no `Base_Win64`, o build 64 bits falha com `F2613 Unit 'Windows' not found` (aconteceu no teste de integração da infra; starter e api-test estão do mesmo jeito). Na IDE: Project Options > Building > Delphi Compiler > Unit scope names, alvo "Windows 64-bit platform" |

## Mudanças de comportamento em runtime

1. **Strings Unicode no FireDAC.** A pascal-db-faa grava `string` como `WideString` — resolve a
   pendência de [`firedac-parametros-string-ansi.md`](firedac-parametros-string-ansi.md)
   (`→` virando `?`).
2. **`ELockConflictException` (nova).** Lock wait expirado, conflito imediato (FireDAC/Zeos no
   Firebird não esperam), update conflict ou deadlock. Antes vinha a exceção do driver (→ 500).
   O `TErrorHandlerMiddleware` passa a responder **409**. `LockTimeoutMs` faz todos os adapters
   esperarem até o mesmo limite.
3. **`EDatabaseConnectException`** (subclasse de `EDatabaseUnavailableException`) quando o pool
   não consegue abrir conexão nova — cai no 503 já existente.
4. **Mensagens em inglês** nas exceções da lib. O `TErrorHandlerMiddleware` não repassa mais
   `AException.Message` no 503/409: usa texto próprio em português, para a resposta da API não
   mudar. O texto original continua no log (`AOnError`/`OriginalMessage`).
5. **Pool:** entrega a conexão ociosa mais recente (LIFO), então volta a encolher depois de um
   pico; depois de uma conexão morta, faz ping em todas as ociosas no próximo acquire; novas
   opções `PoolValidateIdleSeconds` (padrão 120, o valor que era fixo) e
   `PoolKeepaliveSeconds` (desligada).
6. **Outras correções herdadas:** "Data too large for variable" no PostgreSQL com string que
   cresce; contadores do snapshot do pool sem perda sob concorrência; `Sql` reatribuído com o
   mesmo texto mantém o prepare.
7. **Drivers:** o adapter FireDAC linka FB, PG, MySQL e SQLite sempre — `.exe` maior.

## Riscos

- pascal-db-faa ainda é 0.x: minor pode quebrar API. Consumidor fixa a tag; o mínimo é checado
  em compilação.
- O lado Delphi da pascal-db-faa é testado à mão, na IDE (CI cobre FPC/Linux).
- Dois `SafeWriteln` (`Common.SafeLog` e `PascalDb.SafeLog`), cada um com sua seção crítica.
  Mantidos separados por ora (a infra não força a pascal-db-faa em quem só usa `Common.*`);
  anotado em `.ci/findings-for-pascal-db-faa.md` como candidato à pascal-common-faa.
- Sem constante de versão na pascal-db-faa: a infra não consegue exigir o mínimo em compilação
  (idem, `.ci/findings-for-pascal-db-faa.md`).
- O consumidor passa a fornecer duas libs (common + db), mesmo modelo de submodule.

## Fora do escopo

- `Common.Pagination` / `Common.OrderBy` ficam. `PdbPagingClause` (o dialeto escreve
  `ROWS`/`LIMIT`/`OFFSET FETCH`) é melhoria possível depois.
- `Common.JsonMapper` fica; a ponte `PascalCommon.JsonMapper.Optionals` é de outra lib
  (pascal-jsonmapper-faa).

## Passos

1. **Infra** — submodule `external/pascal-db-faa` (tag fixa, só para os testes), remover
   `src/Db/`, ajustar `Common.HealthCheck`, `Common.PoolSnapshotEndpoint`,
   `Horse.Middleware.ErrorHandler` (+ 409 para `ELockConflictException`), remover os testes
   unitários `Db.*Tests` (cobertos na pascal-db-faa), manter o teste de integração de conexão
   como smoke test, atualizar CLAUDE.md/README/CHANGELOG. Release v0.2.0.
2. **delphi-api-starter**, depois **api-test** — submodule `modules/pascal-db-faa`, search
   path, renomear `uses`/`in`, `TFDConfig` → `TDatabaseConfig`, build na IDE, testes.
3. **retaweb-local** — mesmo roteiro (outra máquina).
