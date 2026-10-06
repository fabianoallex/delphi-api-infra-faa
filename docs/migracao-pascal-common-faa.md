# Migrando um projeto consumidor para a v0.1.0 (pascal-common-faa)

Guia para os projetos que usam esta lib como submodule em `infra/` (delphi-api-starter, api-test,
retaweb-local...) ao avançar o ponteiro para a v0.1.0 ou mais nova. Contexto: fase F9 do plano da
pascal-common-faa (`docs/plan.md`, seção "Beyond the first four libraries").

## O que mudou e por quê

`Common.Optionals`, `Common.SystemContext` e `Common.ClockCache` foram **removidas** desta lib. Os
mesmos tipos, com os mesmos nomes e os mesmos GUIDs, vêm agora da
[pascal-common-faa](https://github.com/fabianoallex/pascal-common-faa):

| Antes (infra) | Depois (pascal-common-faa) |
|---|---|
| `Common.Optionals` | `PascalCommon.Optionals` |
| `Common.SystemContext` | `PascalCommon.SystemContext` (agora com `TTicker`) |
| `Common.ClockCache` | `PascalCommon.ClockCache` |
| `TOptNullXxx.SafeNullable/SafeOptional/SafeOptNull` (deprecated) | `TOptionals.Safe` |

Os nomes dos tipos não mudam: `IOptString`, `TOptNullInteger`, `TOptionals`, `TClock`, `TSleep`,
`TClockCache`... Código de domínio só troca a unit no `uses`.

O motivo: as duas cópias declaravam as mesmas interfaces com os mesmos GUIDs. Uma aplicação que
usasse esta lib e o pascal-db-faa (ou amqp, pipes, redis) teria dois `IOptString` diferentes com
um GUID só.

**A infra não traz a pascal-common-faa para a aplicação.** O `infra/external/pascal-common-faa`
é só para os testes da infra. A aplicação fornece a **única** cópia.

## Passos

Da raiz do projeto consumidor (nunca de dentro de `infra/`):

1. **Avançar a infra** para a v0.1.0:

   ```bash
   git -C infra fetch --tags
   git -C infra checkout v0.1.0
   git add infra
   git submodule update --init --recursive infra
   ```

   O `git add infra` vem **antes** do `submodule update`: o update leva o submodule ao commit
   gravado no índice do projeto pai, e sem o `add` esse ainda é o ponteiro antigo (o checkout
   seria desfeito sem aviso). O `--recursive` continua necessário (SwagDoc é submodule aninhado da infra) e, com ele, vem
   também `infra/external/pascal-common-faa`. Ela fica em disco, mas **não entra no search path**.

2. **Adicionar a pascal-common-faa como submodule da aplicação**, na mesma pasta dos outros
   módulos (`modules/`, onde já está o Horse):

   ```bash
   git submodule add https://github.com/fabianoallex/pascal-common-faa modules/pascal-common-faa
   git -C modules/pascal-common-faa checkout v1.2.0
   ```

   Sem `--recursive` aqui: a pascal-common-faa tem um submodule próprio
   (`external/pascal-jsonmapper-faa`) que só os testes dela usam.

3. **Search path** de **todo** `.dproj` que compila a infra (API, serviço, testes): acrescentar
   `modules\pascal-common-faa\src` (relativo ao `.dproj`; num projeto de teste em
   `tests\Unit\`, `..\..\modules\pascal-common-faa\src`). Nunca `infra\external\...`.

4. **`.dpr`/`.dproj`**: trocar as três linhas

   ```pascal
   Common.Optionals       in 'infra\src\Common\Common.Optionals.pas',
   Common.SystemContext   in 'infra\src\Common\Common.SystemContext.pas',
   Common.ClockCache      in 'infra\src\Common\Common.ClockCache.pas',
   ```

   por

   ```pascal
   PascalCommon.Optionals     in 'modules\pascal-common-faa\src\PascalCommon.Optionals.pas',
   PascalCommon.SystemContext in 'modules\pascal-common-faa\src\PascalCommon.SystemContext.pas',
   PascalCommon.ClockCache    in 'modules\pascal-common-faa\src\PascalCommon.ClockCache.pas',
   ```

   e as `<DCCReference>` correspondentes no `.dproj` (ou deixe a IDE regerar a partir do `.dpr`).
   `PascalCommon.Threading` e `PascalCommon.Version` são achados pelo search path.

5. **Renomear no código do projeto** (DTOs, Repositories, testes), com `perl -pi` e não `sed -i`
   (no Git Bash do Windows, `sed -i` troca CRLF por LF até nos arquivos sem ocorrência):

   ```bash
   perl -pi -e 's/\bCommon\.(Optionals|SystemContext|ClockCache)\b/PascalCommon.$1/g' <arquivos>
   ```

   Se algum código chamar `TOptNullXxx.SafeNullable/SafeOptional/SafeOptNull`, troque por
   `TOptionals.Safe(...)`.

6. **Compilar** (IDE) todos os projetos, Win32 e Win64. Se a cópia da pascal-common-faa for
   antiga demais, a build para com
   `F1054 delphi-api-infra-faa precisa da pascal-common-faa 1.0.0 ou mais nova`.

7. **Documentação do projeto**: README/CLAUDE.md que listem as units `Common.Optionals` etc. ou
   o comando de clone.

## Comportamento que muda

- **Pool de conexões**: a ociosidade (teste de vida aos 120 s e varredura de
  `PoolIdleTimeoutSeconds`) é medida com `TTicker` (monotônico). Antes era `TClock.Now`: uma
  mudança da hora do sistema fazia toda conexão ociosa parecer mais velha.
- **Rate limit** (`TRateLimitMiddleware`): a janela é medida com `TTicker`. Antes, um recuo da hora
  do sistema mantinha clientes bloqueados por até 1 h além da janela. `X-RateLimit-Reset` e
  `Retry-After` continuam em hora de parede, iguais a antes.
- **`TClock`/`TSleep`/`TTicker`**: o padrão é criado no `initialization` da unit (antes, no
  primeiro uso, o que tinha corrida entre threads). `Reset` volta ao padrão do sistema, e
  `SetClock(nil)` também.
- **Testes que injetam relógio**: quem fingia o tempo do pool com `TClock.SetClock` agora precisa
  de `TTicker.SetTicker` (ver `tests/Unit/Db.PoolTests.pas`, `TFakeTicker`).

## Por projeto

| Projeto | Onde | Situação |
|---|---|---|
| delphi-api-starter | mesma máquina | **migrado** em 2026-10-05 (`553f9b5`, merge `c91edf3`): infra v0.1.0, `modules/pascal-common-faa` v1.1.1, Win64 habilitado; o pedido abaixo fica como referência |
| api-test | mesma máquina | **migrado** em 2026-10-05 (`d5718b6`, só local: o repo não tem remote). Além deste guia precisou do Horse 3.3.2 (o ErrorHandler atual usa `THorse.OnError`), `TErrorHandlerMiddleware.New` → `.Register` e `app.ini` → `.env` |
| retaweb-local | outra máquina (`R:\Fabiano\supermercado\retaweb-local`) | **ainda não migrado**. Seguir os passos acima nos 3 `.dproj` (API + testes unitários + integração, os mesmos que já têm o pre-build do `build_sql_res.bat`). Se ele também usar pascal-db-faa ou amqp algum dia, esta migração é o que evita o conflito de GUIDs |

## Pedido para a sessão no delphi-api-starter

> Vamos avançar o submódulo `infra/` do delphi-api-starter para a delphi-api-infra-faa v0.1.0,
> que trocou `Common.Optionals`/`Common.SystemContext`/`Common.ClockCache` pela
> pascal-common-faa (fase F9 do plano em `../pascal-common-faa/docs/plan.md`). Leia antes
> `infra/docs/migracao-pascal-common-faa.md` (passos, comportamento que muda) e o
> `infra/CHANGELOG.md`.
>
> O que fazer:
> - `infra` na tag v0.1.0: `git -C infra checkout v0.1.0`, depois `git add infra` e só então
>   `git submodule update --init --recursive infra` (sem o `add`, o update desfaz o checkout; o
>   guia na tag v0.1.0 tem esse passo errado, a versão certa está na main);
> - submódulo `modules/pascal-common-faa` na tag v1.1.1, sem recursive — é a única cópia da
>   aplicação; nunca pôr `infra\external\...` no search path;
> - `Api.Starter` e `Api.Starter.Svc`: search path (`modules\pascal-common-faa\src`), `uses` do
>   `.dpr` e `<DCCReference>` do `.dproj`;
> - `src/Domain/Exemplo` (DTOs, Repository): `Common.Optionals` → `PascalCommon.Optionals`, com
>   `perl -pi` e `\b` (não `sed -i`);
> - README, CLAUDE.md e AGENTS.md: a dependência nova, o comando de clone e a regra de uma cópia
>   só por aplicação (quem clonar o template precisa saber que a pascal-common-faa é dele).
>
> Critério de pronto: os dois programas compilam no Delphi Win32 e Win64 (eu faço o build no IDE),
> o `Api.Starter.exe` sobe, `GET /health` e o CRUD do `Exemplo` respondem (incluindo um PATCH com
> campo omitido, `null` e valor, que exercita as optionals pelo mapper), e o serviço instala e
> para. Não altere a infra nem a pascal-common-faa: o que for para elas vai em
> `.ci/f9-findings.md` (versionado).
