# Compatibilidade com Lazarus / Free Pascal — avaliação

> **Documento de consulta pontual.** Não é carregado em sessão nenhuma por padrão — leia
> apenas quando o assunto for porte/compatibilidade FPC. O CLAUDE.md tem só um ponteiro
> para cá, de propósito.

**Data da avaliação:** 2026-08-21
**Base analisada:** 35 units em `src/` (~12.000 linhas), commit `a31924d`
**Veredito:** portável na arquitetura, bloqueado no que dá o diferencial à lib.
Não portar sem um consumidor FPC concreto em mãos.

---

## Por que este documento existe

A avaliação foi feita uma vez, em profundidade. Sem registro, qualquer reavaliação futura
recomeça do zero e chega às mesmas conclusões gastando o mesmo esforço. O objetivo aqui é
duplo:

1. **Registrar o veredito e o raciocínio** — para não re-derivar.
2. **Listar os gatilhos de reavaliação** (seção final) — o que precisa mudar no FPC, ou no
   projeto, para o veredito virar. Os compiladores vêm convergindo; a decisão de hoje tem
   prazo de validade, e o jeito de saber que ele venceu é checar aquela lista, não refazer a
   análise inteira.

---

## Veredito em uma frase

~55% do código sai quase de graça. Os 45% restantes dependem de três coisas sem equivalente
direto no FPC — e duas delas são exatamente o `TJsonMapper` e o Swagger automático, que são o
diferencial da biblioteca.

---

## Os bloqueios

### 1. RTTI estendida — o bloqueio estrutural

É o único bloqueio que não é "reescrever código", e sim "a convenção central não tem como ser
reproduzida".

| Onde | O que faz | Por que trava no FPC |
|---|---|---|
| `Common.JsonMapper.pas:481` | `LRttiType.GetProperties` sobre classes com propriedades **públicas** | FPC só gera RTTI para membros `published` |
| `Swagger.Builder.pas:371` | `TRttiMethod.GetAttributes` lendo `[SwagProp]`/`[SwagMin]`/... em **métodos** `GetXxx` | atributo customizado em método não existe no FPC (suporte limitado a tipos e propriedades published) |

Consequência: o modelo "declaro `[SwagProp]` no getter e o schema Swagger sai sozinho" precisaria
virar registro declarativo em código — algo na linha de
`TSchema.For<IPedidoDTO>.Prop('status', ...)`. Isso muda a convenção descrita no CLAUDE.md
inteiro (seções "Padrão de DTO" e "Swagger"), não só a implementação.

O mesmo vale, em menor grau, para o `FromJson<I>`: a resolução por GUID via `RegisterMapping`
sobrevive, mas a população das properties depende de `TRttiProperty.SetValue`, que no FPC exigiria
DTOs com seção `published` — mudança de convenção que atinge todo projeto consumidor, não só a
lib.

### 2. FireDAC — inexistente no FPC

`Db.Adapters.FireDAC.pas` (1.370 linhas) + `Common.Helpers.pas` (496 linhas, class helpers para
`TFDParams`) são reescrita completa sobre SQLdb ou Zeos.

**Aqui a arquitetura já ajuda, e este é o bloqueio menos preocupante:** `Db.Interfaces` é
agnóstico e `Db.Adapters.Registry` existe exatamente para permitir adapter externo. É trabalho
de adapter novo, previsto pelo desenho — não refatoração de núcleo.

### 3. Closures (`reference to`)

6 tipos `reference to` (pool, migrations, auth, logger, rate limit) + ~16 closures inline.

O FPC tem function references e anonymous functions desde 2022, atrás dos modeswitches
`FUNCTIONREFERENCES` e `ANONYMOUSFUNCTIONS` — **mas não no 3.2.2 estável**, que é o que o Lazarus
estável embarca. Some-se a isso que o Horse sob FPC usa callback `of object`: middlewares que
hoje devolvem closure capturando configuração (`TCorsMiddleware.New('https://app.exemplo.com')`)
teriam que virar objetos com estado.

### 4. SwagDoc (submodule de terceiro)

19 das 30 units de `modules/swag-doc/Source` usam `System.JSON`/`System.Rtti`. Sem porte FPC
conhecido. Teria que ser portado (fora do nosso controle) ou abandonado em favor de geração
própria do documento OpenAPI.

### 5. `System.JSON` → `fpjson`

API e modelo de ownership diferentes. Atinge `Common.JsonMapper`, `Swagger.Builder`,
`MCP.Server`, `Common.HealthCheck` e 3 middlewares.

### O que **não** é problema

- **Horse tem suporte oficial a Lazarus/FPC** (provider `fphttpserver` no lugar do Indy).
- `Generics.Collections`, `SyncObjs`, `class constructor`, class/record helpers e interfaces
  genéricas existem no FPC.
- `System.Hash` / `System.NetEncoding` / `System.Diagnostics` / `System.RegularExpressions` /
  `System.IOUtils` têm substitutos diretos (`fpsha256` + `hmac`, `base64`, relógio próprio,
  `RegExpr`, `SysUtils`/`FileUtil`).

---

## Tiers de esforço

| Tier | Units | Linhas | Esforço |
|---|---|---|---|
| **1 — sai quase de graça** | Optionals, OrderBy, SystemContext, DTO.Base, Db.Interfaces, Db.Mock, Db.SqlDialect, Db.Adapters.Registry, Messaging.\*, MCP.Utils, Pagination, ClockCache, RateLimitState, SafeLog, Db.Constants | ~4.300 | baixo |
| **2 — ajuste mecânico** | Config e FileLog (`System.IOUtils`), SqlLoader (`Winapi.Windows`/`FindResource` — só Windows), Migrations e Connection.Pool (closures) | ~2.400 | médio |
| **3 — reescrita** | Db.Adapters.FireDAC, Common.Helpers, MCP.Server, middlewares Horse, HealthCheck | ~3.500 | alto |
| **4 — redesenho conceitual** | JsonMapper, Swagger.Builder, Swagger.Attributes, Swagger.Server | ~1.800 | alto, **e muda a convenção de DTO** |

---

## Se a necessidade aparecer: repo único ou projeto paralelo?

As duas necessidades possíveis têm respostas **opostas**. A pergunta a fazer primeiro é qual
delas é a real.

### Cenário A — reusar só o core portável (tiers 1 e 2)

Consumidor FPC que quer `Optionals`, `Db.Interfaces`, `SqlLoader`, `Pool`, `Migrations`, `Mock`,
`Messaging` — sem Horse, sem Swagger, sem FireDAC.

**Repo único.** Projeto paralelo aqui é a pior opção: seriam ~6.000 linhas semanticamente
idênticas em dois lugares, e elas divergem — não é hipótese, é o destino padrão de fork sem dono
único.

Forma recomendada: um `.lpk` ao lado dos `.dproj` existentes, **sem mexer na estrutura de
pastas**, com IFDEFs nos poucos pontos onde a superfície hostil está concentrada
(`System.IOUtils` em 2 units, `FindResource` em 1, closures em 2). É pouco IFDEF porque a
fronteira é estreita.

Motivo de não quebrar o repo em dois: `delphi-api-starter` e `retaweb-local` consomem esta lib
como submodule único em `infra/`. Separar o core em outro repo multiplica search path e ponteiro
de submodule em cada consumidor, para benefício zero do lado Delphi.

### Cenário B — stack completo em FPC (Horse + Swagger + adapter de banco)

**Projeto paralelo.** Não pelo volume, mas porque sem RTTI estendida o modelo de DTO tem que ser
redesenhado (bloqueio 1). Isso não é um porte — é outra biblioteca resolvendo o mesmo problema
com outra convenção. Manter no mesmo repo significaria o CLAUDE.md documentando duas convenções
de DTO que se contradizem, e toda feature nova sendo desenhada duas vezes.

Se esse repo paralelo nascer, ele **depende** do core (cenário A), nunca o forka. Assim existe
uma dependência, não uma duplicata.

### A linha de corte real

Não é "Delphi vs FPC" — é **"esta unit depende de RTTI estendida, FireDAC ou Horse?"**. Essa
fronteira já existe hoje no repo: `src/Common` e a parte abstrata de `src/Db` de um lado;
`src/Swagger`, `src/Middleware` e `Db.Adapters.FireDAC` do outro. O trabalho, nos dois cenários,
é tornar essa fronteira latente explícita — não escolher entre um repo e dois.

### O custo contínuo, que não deve ser escondido

Dual-compile cobra pedágio permanente: toda mudança no core precisa ser validada em dois IDEs.
Como o build por linha de comando não é confiável nesta máquina (`dcc32`/`msbuild` fingem sucesso
sem compilar), a validação é manual dos dois lados. Isso é argumento para manter a superfície
compartilhada pequena e estável — o que o tier 1 já é — e para só pagar esse pedágio com um
consumidor FPC real, nunca preventivamente.

---

## Gatilhos de reavaliação

Reabrir esta avaliação quando **qualquer** item abaixo mudar. Cada um está escrito como algo
verificável — a checagem é rodar o teste, não reler a análise.

### No Free Pascal / Lazarus

| # | Gatilho | Como verificar | Impacto se verdadeiro |
|---|---|---|---|
| G1 | **RTTI estendida para membros públicos** — FPC passa a gerar RTTI de propriedades/métodos fora de `published` | compilar uma classe com property pública e checar se `TRttiType.GetProperties` a devolve | **Derruba o bloqueio principal.** `TJsonMapper` volta a ser porte, não redesenho |
| G2 | **Atributos customizados em métodos** — `TRttiMethod.GetAttributes` funcional | anotar um método com atributo próprio e lê-lo via unit `Rtti` | Swagger automático (`[SwagProp]` no getter) volta a ser viável |
| G3 | **Anonymous functions em release estável** — modeswitches `ANONYMOUSFUNCTIONS`/`FUNCTIONREFERENCES` fora do compilador de desenvolvimento | versão do FPC embarcada no Lazarus estável | Tier 2 cai para trivial; middlewares mantêm a API de closure |
| G4 | **`TRttiProperty.SetValue` com `tkInterface`** no FPC | setar uma property de tipo interface via RTTI | Necessário para o `FromJson` popular campos `IOptXxx` |
| G5 | Aparece **porte FPC do SwagDoc**, ou decidimos gerar o OpenAPI sem ele | — | Remove o bloqueio 4 |

G1 e G2 juntos são o divisor de águas: com os dois, o veredito muda de "não portar" para
"cenário A vira porte completo barato". Sem G1, nada mais importa muito.

### No projeto

| # | Gatilho | Impacto |
|---|---|---|
| P1 | Aparece **consumidor FPC concreto** (não hipotético) | Sai do "não portar"; decidir cenário A vs B pela lista de units que ele precisa |
| P2 | Necessidade de rodar a API em **Linux/ARM sem Delphi** | Empurra para cenário B |
| P3 | Adapter de banco não-FireDAC (Zeos/SQLdb) passa a existir por outro motivo | Bloqueio 2 deixa de ser custo do porte |

---

## Como refazer a medição

Para uma reavaliação comparável com esta, a varredura que gerou os tiers:

```bash
for f in $(find src -name '*.pas' | grep -v __history | sort); do
  flags=""
  grep -q "System.JSON\|TJSONObject"        "$f" && flags="$flags JSON"
  grep -q "System.Rtti\|TRtti"              "$f" && flags="$flags RTTI"
  grep -q "TCustomAttribute\|GetAttributes" "$f" && flags="$flags ATTR"
  grep -q "reference to"                    "$f" && flags="$flags ANON"
  grep -q "FireDAC\|Data.DB"                "$f" && flags="$flags FIREDAC"
  grep -q "Horse"                           "$f" && flags="$flags HORSE"
  grep -q "Winapi"                          "$f" && flags="$flags WINAPI"
  grep -q "System.IOUtils"                  "$f" && flags="$flags IOUTILS"
  grep -q "class helper\|record helper"     "$f" && flags="$flags HELPER"
  printf "%-46s %s\n" "$f" "${flags:- --}"
done
```

Atenção a um falso positivo conhecido do filtro `HORSE`: `Common.SafeLog`, `Common.Pagination` e
`Common.RateLimitState` só citam Horse em comentário — não têm dependência real e pertencem ao
tier 1.

---

## Referências

- [Horse (HashLoad)](https://github.com/HashLoad/horse) — suporte a Delphi e Lazarus; provider
  `fphttpserver` no FPC
- [FPC — Function References and Anonymous Functions (anúncio, mai/2022)](https://lists.freepascal.org/fpc-announce/2022-May/000619.html)
- [FPC New Features Trunk](https://wiki.freepascal.org/FPC_New_Features_Trunk) — acompanhar G1/G2/G3
