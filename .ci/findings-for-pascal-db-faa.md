# Achados para a pascal-db-faa

Anotados durante a migração da delphi-api-infra-faa para a pascal-db-faa v0.10.1
(2026-10-06, ver `docs/migracao-pascal-db-faa.md`). Não editar a pascal-db-faa a partir daqui:
levar cada item para lá.

## 1. Sem constante de versão

A pascal-common-faa expõe `PASCALCOMMON_VERSION` (`PascalCommon.Version`), e quem depende dela
para a build com mensagem clara quando a cópia fornecida é antiga demais
(`{$IF PASCALCOMMON_VERSION < ...}{$MESSAGE FATAL ...}`). A pascal-db-faa não tem equivalente:
a infra não consegue exigir "0.10.1 ou mais nova" em compilação. Hoje o mínimo real é implícito
(o `TErrorHandlerMiddleware` usa `ELockConflictException`, que existe desde a 0.4.0); uma cópia
antiga demais falha com "Undeclared identifier", sem dizer qual versão falta.

Sugestão: `PascalDb.Version` com `PASCALDB_VERSION` (mesmo formato `MMmmpp` da common), incluída
por `PascalDb.Interfaces`.

## 2. `TDatabaseConfig` sem properties na classe

As properties (`ConnectionParams`, `SQLDialect`, `PoolIniConnections`...) só existem em
`IDatabaseConfig`. O `TFDConfig` da infra tinha `ConnectionParams`/`SQLDialect`/`SQLDirectory`
como properties da classe, e os consumidores declaravam `LConfig: TFDConfig`. Com
`TDatabaseConfig` isso não compila (`LConfig.ConnectionParams.Add(...)`,
`LConfig.SQLDialect := ...` no starter e no api-test). Trocar o tipo da variável é o certo de
qualquer forma (é `TInterfacedObject`), mas a mensagem de erro não leva a essa conclusão. Vale uma linha no header de `PascalDb.Adapter.Base` / `docs/getting-started.md`
dizendo explicitamente "declare `IDatabaseConfig`, a classe não tem properties".

## 3. Dois `SafeWriteln`

`PascalDb.SafeLog` e o `Common.SafeLog` da infra são cópias, cada uma com sua seção crítica: num
processo que usa as duas, um `SafeWriteln` de cada lado pode intercalar. Candidato a ir para a
pascal-common-faa (o próprio `docs/plan.md` dela cita `PascalDb.SafeLog` como candidato "se
aparecer um segundo usuário": este é o segundo).
