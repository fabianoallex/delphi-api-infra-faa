# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem
[SemVer](https://semver.org/lang/pt-BR/). Antes da 0.1.0 a lib não tinha versões: os consumidores
apontavam o submódulo para um commit.

## [0.2.1] — 2026-10-06

### Corrigido

- Mensagens acentuadas do `TErrorHandlerMiddleware` saíam corrompidas na resposta HTTP
  (`Banco de dados indisponÃ­vel...`, e o padrão `Recurso nÃ£o encontrado.` de
  `ENotFoundException`): `Horse.Middleware.ErrorHandler.pas` estava em UTF-8 **sem BOM**, e o
  Delphi lê fonte sem BOM como ANSI. Arquivo regravado com BOM (também
  `Common.PoolSnapshotEndpoint.pas` e `Infra.UnitTests.dpr`, que só tinham acento em
  comentário). Regra nova no CLAUDE.md ("Anti-padrões").
- `TErrorHandlerMiddleware`: `EEncodingError` → **400** com mensagem fixa ("envie o corpo em
  UTF-8"), sem `AOnError`. É o que o provider do Horse levanta ao ler `Req.Body` com bytes que
  não são UTF-8 válido; antes virava 500 com "No mapping for the Unicode character exists in the
  target multi-byte code page".

### Documentação

- CLAUDE.md, "Registro inexistente → 404, sempre pelo Service": `ENotFoundException` lançada no
  Service (nunca `Res.Status(404).Send` no handler) e `UPDATE`/`DELETE ... RETURNING` para
  detectar id inexistente, incluindo o desvio do Firebird < 5 (linha de `NULL`s quando nada
  casa).
- `.ci/findings-for-pascal-db-faa.md`: itens 4 (violação de constraint como exceção própria,
  para virar 409) e 5 (linhas afetadas no `ExecSql`), com o levantamento por banco/adapter.

## [0.2.0] — 2026-10-06

### Mudado

- **Quebra de compatibilidade:** a camada de banco passa a vir da
  [pascal-db-faa](https://github.com/fabianoallex/pascal-db-faa) (v0.10.1). `src/Db/` foi
  removido; a aplicação fornece a pascal-db-faa (submodule `modules/pascal-db-faa`, com `src` e
  `adaptersiredac` no search path), como já fornece a pascal-common-faa. Renomes: `Db.Interfaces`
  → `PascalDb.Interfaces`, `Db.Connection.Pool` → `PascalDb.Pool`, `Db.Adapters.Registry` →
  `PascalDb.Registry`, `Db.Adapters.FireDAC` → `PascalDb.Adapter.FireDAC`, `Db.SqlLoader` /
  `Db.SqlDialect` / `Db.Migrations` / `Db.Mock` → `PascalDb.*` com o mesmo sufixo; `Db.Constants`
  (vazia) some. `TFDConfig` → `TDatabaseConfig` (`PascalDb.Adapter.Base`), numa variável
  `IDatabaseConfig`. Os tipos (`IDBFactory`, `IQuery`, `IParams`, `TSQLLoader`,
  `TDBMigrationEngine`, `TMockDBFactory`...) mantêm nome e assinatura. Roteiro e mudanças de
  comportamento herdadas (strings Unicode no FireDAC, pool LIFO, `ELockConflictException`,
  `EDatabaseConnectException`, mensagens em inglês): `docs/migracao-pascal-db-faa.md`.
- `TErrorHandlerMiddleware`: `ELockConflictException` → **409**, com `AOnError`. No 503 e no 409
  o corpo traz mensagem fixa em português em vez de `E.Message` (as exceções da pascal-db-faa são
  em inglês); a linha de `AOnError` do 503 traz a classe da exceção no lugar da mensagem genérica.
- Testes e versão recomendada aos consumidores (README, guia de migração) passam à
  pascal-common-faa v1.2.0. Mínimo exigido continua 1.0.0.
- Testes: os unitários `Db.PoolTests`, `Db.SqlLoaderTests` e `Db.MockTests` saem (a pascal-db-faa
  tem os seus); o de integração `Db.ConnectionTests` fica, agora sobre a pascal-db-faa.

## [0.1.1] — 2026-10-05

### Corrigido

- **Tags de SQL** (`Db.SqlLoader`): o marcador de fechamento passa a aceitar espaços opcionais em
  volta do nome (`[}TAG]`, `[}  TAG ]`), como a abertura já aceitava, e a abertura também aceita
  espaços depois do `[`. Antes, o fechamento só era reconhecido escrito como `[} TAG]`. Fora disso,
  `ProcessTag` deixava as marcações no SQL (o FireDAC então falhava com
  `-307 Escape function name must be not empty`, sem apontar a causa), ou pareava a abertura com o
  fechamento de outro bloco e apagava o SQL entre eles, ou entrava em laço infinito quando esse
  fechamento vinha antes da abertura. A limpeza feita ao ler `.SQL` segue a mesma regra (deixava
  `[TAG{]` para trás). Portado de pascal-db-faa 0.10.0 (`16d1649`). Achado no api-test
  (`PRODUTO.UPDATE.sql`, `[}NOME]`).

### Mudado

- `ProcessTag` lança `ESQLLoaderException` para bloco malformado da tag: fechamento sem abertura
  antes, abertura sem fechamento depois, ou bloco aninhado em outro da mesma tag. Antes deixava
  marcações no SQL, removia o texto errado ou travava.

### Documentação

- CLAUDE.md: o Pre-build event do `build_sql_res.bat` tem que ser configurado pela IDE (Build
  Events). Um `<Target Name="BeforeBuild">` escrito à mão no `.dproj` é ignorado pelo build da IDE
  e deixa o `.res` velho sem erro nenhum (achado no starter e no api-test).

## [0.1.0] — 2026-10-05

Primeira versão com tag. Migra os tipos opcionais, o relógio e o cache para a
[pascal-common-faa](https://github.com/fabianoallex/pascal-common-faa) (fase F9 do plano dela).
Guia para os consumidores: [`docs/migracao-pascal-common-faa.md`](docs/migracao-pascal-common-faa.md).

### Mudanças incompatíveis

- **Removidas** `Common.Optionals`, `Common.SystemContext` e `Common.ClockCache`. Use
  `PascalCommon.Optionals`, `PascalCommon.SystemContext` e `PascalCommon.ClockCache`. Os nomes dos
  tipos não mudam (`IOptString`, `TOptNullXxx`, `TOptionals`, `TClock`, `TSleep`, `TClockCache`...).
  Os GUIDs também não: eram os mesmos nas duas libs, e é por isso que uma aplicação com esta lib e
  o pascal-db-faa teria dois `IOptString` com um GUID só.
- **A aplicação fornece a pascal-common-faa** (1.0.0 ou mais nova): submódulo próprio e o `src`
  dele no search path. O `external/pascal-common-faa` desta lib é só para os testes daqui. Uma cópia
  antiga demais para a build com `F1054` (checagem em `Common.DTO.Base` e `Db.Interfaces`).
- Removidos `TOptNullXxx.SafeNullable`/`SafeOptional`/`SafeOptNull` (eram deprecated). Use
  `TOptionals.Safe`.
- `TConnectionItem.LastRelease` (`Db.Connection.Pool`) passou de `TDateTime` para `UInt64`
  (leitura de `TTicker.NowMs`).
- Testes que fingiam o tempo do pool com `TClock.SetClock` precisam de `TTicker.SetTicker`.

### Corrigido

- **Pool de conexões:** a ociosidade (teste de vida aos 120 s e varredura de
  `PoolIdleTimeoutSeconds`) passa a ser medida com `TTicker` (monotônico) em vez de
  `TClock.Now`. Antes, uma mudança da hora do sistema (horário de verão, NTP, operador) fazia toda
  conexão ociosa parecer mais velha: todas iam juntas para o teste de vida e para a varredura. É o
  mesmo bug corrigido no pascal-db-faa (`89464d1`). Teste:
  `Test_Pool_MudancaDoRelogio_NaoEnvelheceConexoes`.
- **Rate limit** (`TRateLimitState`): a janela passa a ser medida com `TTicker`. Antes, um recuo
  da hora do sistema deixava as entradas "no futuro" e mantinha o cliente bloqueado por até 1 h
  além da janela; um avanço encerrava o bloqueio antes da hora. `ResetUnix` (`X-RateLimit-Reset`,
  `Retry-After`) continua em hora de parede: agora + o que falta da janela. O relógio passa a ser
  lido dentro do lock, então as entradas de uma chave ficam em ordem mesmo sob concorrência.
  Testes: `WallClockMovesBack_DoesNotExtendBlock` e `WallClockMovesForward_DoesNotEndBlockEarly`.
- `TClock`/`TSleep` (agora os da pascal-common-faa) criam o padrão no `initialization`. Antes era
  no primeiro uso, e duas threads fazendo esse primeiro uso juntas corriam sobre o campo
  compartilhado (corrigido no pascal-db-faa `5c853c6`).
- Os testes compilam em Win64. `Length()` e `TList<T>.Count` são `NativeInt` lá, e o
  `Assert.AreEqual` com um literal não inferia o tipo (E2532).

### Testes

- Saem `OptionalsTests` e `ClockCacheTests`: são os mesmos testes que a pascal-common-faa roda
  (`PascalCommon.OptionalsTests`, `PascalCommon.ClockCacheTests`), traduzidos lá.
- Win64 habilitado nos dois projetos de teste. Na integração, a `fbclient.dll` é escolhida
  conforme a plataforma: `bin\` em Win64, `WOW64\` em Win32. O `integration_test.ini` não fixa
  mais `VendorLib`.

### Assunto futuro

- O `Common.JsonMapper` continua com regras próprias para as optionals. Duas delas diferem, de
  propósito, da ponte `PascalCommon.JsonMapper.Optionals` (pascal-jsonmapper-faa): `null` num
  `IOptXxx` e `INullXxx` nil na escrita. Trocar de mapper mudaria o contrato JSON das APIs. Ver
  `.ci/f9-findings-for-pascal-common-faa.md`.
