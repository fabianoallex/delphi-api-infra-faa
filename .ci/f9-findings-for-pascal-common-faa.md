# F9 — achados para a pascal-common-faa

Migração da delphi-api-infra-faa para a pascal-common-faa v1.1.1 (fase F9 do plano). A
pascal-common-faa não foi alterada a partir daqui. O que segue é para uma sessão naquele
repositório.

## 1. Texto que fica obsoleto com a F9

Três lugares descrevem `Common.SystemContext`/`Common.ClockCache` da delphi-api-infra-faa como
existentes. Desde a v0.1.0 da infra essas units não existem mais (a infra usa as da
pascal-common-faa):

- `docs/plan.md`, decisão 7 ("Known cost: delphi-api-infra-faa's `Common.SystemContext` and
  `Common.ClockCache` declare the same names...");
- `docs/migrating.md`, último item de "Behavior to know about" ("Name clash with
  delphi-api-infra-faa");
- cabeçalho de `src/PascalCommon.SystemContext.pas` (último parágrafo).

Sugestão: marcar a F9 como feita na tabela de fases e trocar o aviso de conflito de nomes por uma
nota histórica (ou removê-lo). O cabeçalho de `bridges/jsonmapper/PascalCommon.JsonMapper.Optionals.pas`
("Two of these rules differ from delphi-api-infra-faa's Common.JsonMapper") **continua
verdadeiro**: o `Common.JsonMapper` da infra não foi trocado (ver 3).

## 2. `migrating.md` não cobre uma lib cujos consumidores clonam recursivamente

O passo 1 diz que o submódulo `external/` é só para testes e CI. Isso funciona quando o consumidor
não clona a lib recursivamente. A delphi-api-infra-faa é consumida como submódulo `infra/` e tem
outro submódulo aninhado que é **necessário em runtime** (`modules/swag-doc`, o SwagDoc). Por
isso os consumidores precisam de `git submodule update --init --recursive`, e esse comando também
baixa `infra/external/pascal-common-faa` (e o `external/pascal-jsonmapper-faa` de dentro dela)
para a árvore da aplicação.

Medido na atualização do api-test (2026-10-05): `git submodule update --init --recursive infra`
baixou `infra/external/pascal-common-faa` e `infra/external/pascal-common-faa/external/pascal-jsonmapper-faa`
(este último com "Failed to clone ... Retry scheduled" na primeira tentativa) para dentro da
árvore da aplicação, que já tinha a sua `modules/pascal-common-faa`.

Não quebra nada sozinho: a cópia fica em disco e é ignorada enquanto o search path da aplicação
apontar para a cópia dela. Mas é uma segunda cópia a um `;` de distância no search path, e o
diamante volta assim que alguém aponta para ela "porque já estava lá". Nesta migração a regra foi
escrita no README e no CLAUDE.md da infra e no guia `docs/migracao-pascal-common-faa.md`.

Sugestão para o `migrating.md` (passo 1 ou "For library authors" do README): se a lib tem um
submódulo que os consumidores precisam inicializar, o `--recursive` deles traz o `external/`
junto. Documente que a cópia de `external/` nunca vai no search path da aplicação. Alternativa
não medida: `update = none` no `.gitmodules` da lib para `external/pascal-common-faa`, que
exigiria `--checkout` explícito nos testes e no CI da própria lib.

## 3. Assunto futuro: dois mappers com regras diferentes para as optionals

A infra continua com o `Common.JsonMapper` próprio. Ele reconhece as optionals por
`TypeInfo(IOptString)` etc., resolvidos agora contra `PascalCommon.Optionals`, e passou na suíte
Unit sem mudança (testes `Common.JsonMapperTests`, `Common.JsonResolverTests` e
`Common.JsonSerializerTests`). As duas regras que a `PascalCommon.JsonMapper.Optionals` documenta
como diferentes continuam diferentes: `null` num `IOptXxx` (a infra guarda `Null`, a ponte
rejeita) e `INullXxx` nil (a infra omite o membro, a ponte escreve `null`). Se a infra um dia
trocar de mapper para o pascal-jsonmapper-faa com a ponte, essas duas regras mudam para os
clientes HTTP das APIs, e isso é uma mudança de contrato da API, não só interna.

## 4. Confirmado na prática: a checagem de versão no Delphi

A checagem `{$IF PASCALCOMMON_VERSION < 10000}` depois do `uses` compila no Delphi 12 (Win32 e
Win64) em `Common.DTO.Base` e `Db.Interfaces`. O caminho de falha (subir o mínimo acima da cópia
presente) não foi medido aqui. Ele já tinha sido medido no piloto do pascal-db-faa (F6).
