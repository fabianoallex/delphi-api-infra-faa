# Achados para a pascal-db-faa

Anotados durante a migração da delphi-api-infra-faa para a pascal-db-faa v0.10.1
(2026-10-06, ver `docs/migracao-pascal-db-faa.md`) e no teste por HTTP do starter e do api-test
logo depois. Não editar a pascal-db-faa a partir daqui: cada item é trabalhado numa sessão
**na própria pascal-db-faa** (dual-compiler, três adapters, suíte de contrato, CI FPC/Linux).
O que depende disso do lado da infra está em "Depois, na infra" no fim de cada item.

Prioridade sugerida: 4 e 5 (corrigem respostas erradas da API hoje), depois 1, 2 e 3.

## 1. Sem constante de versão

A pascal-common-faa expõe `PASCALCOMMON_VERSION` (`PascalCommon.Version`), e quem depende dela
para a build com mensagem clara quando a cópia fornecida é antiga demais
(`{$IF PASCALCOMMON_VERSION < ...}{$MESSAGE FATAL ...}`). A pascal-db-faa não tem equivalente:
a infra não consegue exigir "0.10.1 ou mais nova" em compilação. Hoje o mínimo real é implícito
(o `TErrorHandlerMiddleware` usa `ELockConflictException`, que existe desde a 0.4.0); uma cópia
antiga demais falha com "Undeclared identifier", sem dizer qual versão falta.

Sugestão: `PascalDb.Version` com `PASCALDB_VERSION` (mesmo formato `MMmmpp` da common), incluída
por `PascalDb.Interfaces`.

**Depois, na infra:** `{$IF PASCALDB_VERSION < ...}{$MESSAGE FATAL ...}` em
`Horse.Middleware.ErrorHandler` (a unit da infra que mais depende de classes recentes).

## 2. `TDatabaseConfig` sem properties na classe

As properties (`ConnectionParams`, `SQLDialect`, `PoolIniConnections`...) só existem em
`IDatabaseConfig`. O `TFDConfig` da infra tinha `ConnectionParams`/`SQLDialect`/`SQLDirectory`
como properties da classe, e os consumidores declaravam `LConfig: TFDConfig`. Com
`TDatabaseConfig` isso não compila (`LConfig.ConnectionParams.Add(...)`,
`LConfig.SQLDialect := ...` no starter e no api-test). Trocar o tipo da variável é o certo de
qualquer forma (é `TInterfacedObject`), mas a mensagem de erro não leva a essa conclusão. Vale
uma linha no header de `PascalDb.Adapter.Base` / `docs/getting-started.md` dizendo
explicitamente "declare `IDatabaseConfig`, a classe não tem properties".

## 3. Dois `SafeWriteln`

`PascalDb.SafeLog` e o `Common.SafeLog` da infra são cópias, cada uma com sua seção crítica: num
processo que usa as duas, um `SafeWriteln` de cada lado pode intercalar. Candidato a ir para a
pascal-common-faa (o próprio `docs/plan.md` dela cita `PascalDb.SafeLog` como candidato "se
aparecer um segundo usuário": este é o segundo).

**Depois, na infra:** `Common.SafeLog` vira fachada (ou some) para a unit da common.

## 4. Violação de constraint (chave duplicada, FK) sobe como exceção crua do driver

Observado no api-test: `POST /cidades` com `COD_IBGE` já existente responde **500** com
`[FireDAC][Phys][FB]violation of PRIMARY or UNIQUE KEY constraint "PK_CIDADE"...` — mensagem do
driver vazando para o cliente, e uma classe diferente por adapter. O mesmo vale para FK
(`DELETE` de registro referenciado). Para a camada HTTP isso é 409, mas sem uma classe estável
não dá para mapear sem conhecer cada driver.

Sugestão, no mesmo molde de `ELockConflictException` (v0.4.0):

- Classe nova em `PascalDb.Interfaces`, ex. `EConstraintViolationException` com
  `Kind: (cvUnique, cvForeignKey)` (talvez `cvNotNull`/`cvCheck` depois) +
  `ConstraintName` quando o driver informar + `OriginalClassName`/`OriginalMessage`. Mensagem
  genérica em inglês, segura para o cliente.
- `IsConstraintViolationError(E, out AKind)` virtual em `TTransactionBase` /
  `TDataSetQueryBase`, chamada nos mesmos três pontos de `IsLockConflictError`
  (`Open`, `ExecSql`, `ExecBatch` em `PascalDb.Adapter.DataSet`; `ExecSql` em
  `PascalDb.Adapter.Base`). Ordem: lock antes de constraint.
- Códigos por banco (conferir contra a suíte de contrato, como foi feito com os de lock):

  | Banco | Unique / PK | FK |
  |---|---|---|
  | Firebird | `isc_unique_key_violation` 335544665, `isc_no_dup` 335544349 | `isc_foreign_key` 335544466 |
  | PostgreSQL (SQLSTATE) | `23505` | `23503` |
  | MySQL/MariaDB | 1062 (`ER_DUP_ENTRY`) | 1451, 1452 |
  | SQLite | `SQLITE_CONSTRAINT` (19); estendidos 2067 / 1555 | 787 (estendido) |
  | SQL Server | 2627, 2601 | 547 (também CHECK — separar pela mensagem ou deixar fora) |

  FireDAC já classifica: `EFDDBEngineException.Kind` = `ekUKViolated` / `ekFKViolated` — o
  adapter FireDAC talvez nem precise dos códigos. SQLite só devolve o código estendido com
  `sqlite3_extended_result_codes` ligado; sem ele, 19 não distingue unique de FK.
- Contrato: `Insert_DuplicateKey_RaisesConstraintViolation`,
  `Delete_Referenced_RaisesConstraintViolation` (Kind certo, transação continua utilizável após
  rollback).

**Depois, na infra:** `TErrorHandlerMiddleware` mapeia a classe para **409** com mensagem fixa
em português (como já faz com `ELockConflictException`), detalhe só no `AOnError`. Starter e
api-test param de devolver 500 em chave duplicada sem mudar nada no domínio.

## 5. `ExecSql` não informa linhas afetadas

`IQuery.ExecSql` é `procedure`. Um `UPDATE`/`DELETE` por id que não acha linha não tem como
avisar, e o Repository acaba respondendo 204 para id inexistente (visto no starter e no
api-test). Os drivers sabem: `TFDQuery.RowsAffected`, `TSQLQuery.RowsAffected`,
`TZQuery.RowsAffected`.

Sugestão: `function ExecSql: Integer` (linhas afetadas; `-1` quando o driver não souber) ou
`property RowsAffected` em `IQuery` depois do `ExecSql`. Trocar `procedure` por `function` é
compatível na chamada (`LQuery.ExecSql;` continua compilando), mas quebra quem implementa
`IQuery` (adapters de terceiros, `TMockQuery`) — anotar no CHANGELOG. O mock precisa de um jeito
de programar o valor devolvido. O wrapper do pool repassa.

**Enquanto isso, na infra/starter:** `UPDATE ... RETURNING ID` / `DELETE ... RETURNING ID` com
`Open`, e "não achou" = `IsEmpty` **ou** `ID` nulo — Firebird < 5 devolve uma linha de `NULL`s
quando nada casa (singleton em DSQL; medido no 2.5), Firebird 5/PostgreSQL devolvem nenhuma.
MySQL não tem `RETURNING`. Esse desvio por banco é mais um argumento para o `RowsAffected`. Quando `RowsAffected`
existir, o starter pode voltar ao `ExecSql` simples — o padrão fica documentado no CLAUDE.md da
infra.
