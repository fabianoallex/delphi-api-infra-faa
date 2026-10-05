# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem
[SemVer](https://semver.org/lang/pt-BR/). Antes da 0.1.0 a lib não tinha versões: os consumidores
apontavam o submódulo para um commit.

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
