# delphi-api-infra-faa — Guia para Agentes de IA

Biblioteca de infraestrutura Delphi para APIs REST com Horse. Projetos consumidores incluem
esta lib como submodule em `infra/`. Este guia descreve convenções, padrões e armadilhas
comuns para que agentes de IA produzam código correto desde a primeira tentativa.

---

## Checklist: criar um novo domínio

Ao criar um domínio `Pedido` (ou qualquer outro), siga esta sequência:

1. `src/Domain/Pedido/Pedido.DTOs.pas` — interfaces + classes DTO (ver padrão abaixo)
2. `src/Domain/Pedido/Pedido.Repository.pas` — `IPedidoRepository` + `TPedidoRepository`
3. `src/Domain/Pedido/Pedido.Service.pas` — `IPedidoService` + `TPedidoService`
4. `src/Domain/Pedido/Pedido.Controller.pas` — `TPedidoController.RegisterRoutes`
5. Adicionar as 4 units ao DPR na seção `uses` (com caminhos relativos)
6. Criar os arquivos SQL: `PEDIDO.FIND.sql`, `PEDIDO.FIND_COUNT.sql`, `PEDIDO.FIND_BY_ID.sql`, `PEDIDO.INSERT.sql`, `PEDIDO.UPDATE.sql`, `PEDIDO.DELETE.sql`
7. Registrar cada SQL em `sql/queries.rc` — recompilação do `.res` é automática via pre-build event (ver "Build automático dos `.res`" logo abaixo), não rode `brcc32.exe` manualmente
8. No `begin` do DPR: montar as dependências (Repository → Service) e chamar `RegisterRoutes`
9. Registrar o endpoint MCP antes de `TRouteDoc.Serve` (ver padrão de inicialização)

---

## Padrão de DTO

### Regras absolutas

- Atributos `[SwagProp]`, `[SwagMin]`, `[SwagMax]`, `[SwagEnum]`, `[SwagPattern]` **sempre na classe**, nunca na interface — o RTTI de métodos de interface não é gerado pelo compilador
- Toda classe DTO **deve** ter `class constructor` com `TJsonMapper.RegisterMapping<I, T>` — sem isso, `FromJson`/`ToJson` falha silenciosamente em runtime
- O DPR **deve** ter `{$STRONGLINKTYPES ON}` — sem isso, o `class constructor` não é executado
- Handler que recebe corpo (POST/PATCH/PUT) **sempre** monta o DTO com `TJsonMapper.FromJson<I>(Req.Body)` — nunca campo a campo a partir de `TJSONObject`. Ver "Desserialização do corpo — sempre via `TJsonMapper.FromJson<I>`" logo abaixo para o porquê do mapper conseguir devolver um objeto concreto através de uma interface
- Getter de campo `IOptXxx`/`INullXxx`/`IOptNullXxx` **sempre** devolve `TOptionals.Safe(FField)`, nunca o field cru — essa é a única blindagem contra `nil` desses campos. Por isso Service/Repository nunca checam `Assigned` num campo individual, só `.HasValue`; `Assigned` só se justifica no `ADto` inteiro. Ver "Campos opcionais" logo abaixo e o teste `AllOptionalGetters_NeverReturnNil` em "Teste de conformação de DTOs" — é assim que essa garantia é checada automaticamente, não só por revisão manual
- `INullXxx` **nunca** aparece em DTO de Insert/Update/Find — é exclusivo de Response DTO (leitura de linha de banco). Campo de JSON/query string é `IOptXxx` ou `IOptNullXxx`, nunca `INullXxx` puro. Ver "`IOptXxx` vs `INullXxx` vs `IOptNullXxx`" logo abaixo para o porquê

### Hierarquia de base

| Operação | Interface herda | Classe herda |
|---|---|---|
| Response | `IResponseDTOBase` | `TResponseDTOBase` |
| Insert | `IInsertDTOBase` | `TInsertDTOBase` |
| Update (PATCH) | `IUpdateDTOBase` | `TUpdateDTOBase` |
| Find (paginado) | `IFindPaginationDTOBase` | `TFindPaginationDTOBase` |

`IFindPaginationDTOBase` já fornece `Page`, `Limit`, `OrderBy`, `Search` — não redeclare.

### `IOptXxx` vs `INullXxx` vs `IOptNullXxx` — qual usar

Os três respondem perguntas diferentes, e a escolha errada não dá erro de compilação — só se
manifesta em runtime, de um jeito que só aparece lendo `Common.JsonMapper`/`Db.Interfaces` linha
a linha. Decida **antes** de escrever a interface, com base nesta tabela, não por "parece
opcional":

| Tipo | Responde | Não sabe responder |
|---|---|---|
| `IOptXxx` | "Foi enviado/definido?" (`HasValue`) | Se o valor, quando existe, pode ser nulo |
| `INullXxx` | "É nulo ou tem valor?" (`IsNull`) | Se o campo foi enviado ou está ausente |
| `IOptNullXxx` | As duas coisas — `HasValue` **e** `IsNull` | — (é o único tri-state completo) |

Guia por tipo de DTO — a origem do valor decide o tipo, não o nome do campo:

- **Find (filtros de query string) → sempre `IOptXxx`.** `ParseQueryStr`/`ParseQueryInt` só
  sabem dizer "a chave veio na URL ou não" — não existe "null" numa query string nesse parser.
  `INullXxx`/`IOptNullXxx` não se aplicam: não tem o que ser "sempre presente" (é filtro, opcional
  por natureza) nem como expressar um "null" explícito na URL.
- **Response (linha lida do banco) → coluna `NOT NULL` = tipo puro; coluna nullable =
  `INullXxx`.** Uma linha que voltou do `SELECT` sempre tem a coluna "presente" — não existe
  "ausência de coluna" numa linha, só a possibilidade dela ser `NULL`. Por isso `IQueryResult`
  expõe `NullableStrings`/`NullableIntegers`/etc. como `INullXxx`, nunca `IOptXxx`: `HasValue`
  não teria o que responder aí.
- **Insert → coluna obrigatória = tipo puro; coluna opcional = `IOptXxx` no caso normal.** É o
  padrão do exemplo `PEDIDO.INSERT` com tag, acima: se o cliente não manda o campo, a coluna nem
  entra no `INSERT`, e o banco aplica `DEFAULT`/`NULL` normalmente. `IOptNullXxx` só entra se
  precisar diferenciar "não mandei" (deixa o `DEFAULT` do banco agir) de "mandei `null`
  explicitamente" (força `NULL` mesmo havendo `DEFAULT` não-nulo) — caso raro.
- **Update (PATCH) → é onde `IOptNullXxx` de fato serve pra algo.** Coluna nullable + precisa
  diferenciar as três intenções do cliente: chave ausente no JSON = não mexe no campo;
  `"campo": null` = limpa pra `NULL` no banco; `"campo": "valor"` = seta o valor. Se a coluna
  nunca pode ser `NULL`, mas é opcional de atualizar, `IOptXxx` já basta (ausência = não mexe;
  "não pode ser vazio" é validação de Service, não do tipo).

**Pegadinha que só aparece lendo `TJsonMapper.DeserializeObject`/`TryResolveOptional`:** para
`INullXxx`, "chave ausente no JSON" e `"campo": null` **colapsam pro mesmo estado**
(`IsNull = True`) — o tipo não tem `HasValue`, então nada no mapper guarda se a chave chegou a
existir. `TryResolveOptional` só roda quando `FindJsonValue` acha a chave; se a chave não existe,
o field interno nunca é populado e o getter cai no mesmo `TOptionals.Safe` que devolve `Null`
para o valor explícito `null` — o resultado é indistinguível dos dois lados.

**Consequência direta: `INullXxx` nunca aparece em DTO de Insert/Update/Find (nada que venha de
JSON ou query string) — é exclusivo de Response DTO, lendo linha de banco via
`IQueryResult.NullableXxx`.** Se aparecer num DTO que passa por `TJsonMapper.FromJson<I>`, é
sinal de que o tipo errado foi escolhido — o campo quase certamente devia ser `IOptXxx` (só
precisa saber se veio) ou `IOptNullXxx` (precisa saber se veio *e* se veio nulo).

### Exemplo completo (Response)

```pascal
IPedidoResponseDTO = interface(IResponseDTOBase)
  ['{GUID-AQUI}']
  function GetId: Integer;
  function GetStatus: string;
  property Id: Integer read GetId;
  property Status: string read GetStatus;
end;

TPedidoResponseDTO = class(TResponseDTOBase, IPedidoResponseDTO)
private
  FId: Integer;
  FStatus: string;
public
  class constructor Create;
  [SwagProp('ID do pedido', '1')]
  function GetId: Integer;
  [SwagProp('Status do pedido', 'pendente')]
  [SwagEnum('pendente,aprovado,cancelado')]
  function GetStatus: string;
end;

class constructor TPedidoResponseDTO.Create;
begin
  TJsonMapper.RegisterMapping<IPedidoResponseDTO, TPedidoResponseDTO>;
end;
```

### Campos opcionais — a blindagem contra `nil` nasce no getter do DTO

Todos os campos de um UpdateDTO (e todo campo `IOptXxx`/`INullXxx`/`IOptNullXxx` em qualquer
DTO) são retornados pelo getter via `TOptionals.Safe` — **nunca** o field interno cru:

```pascal
function TPedidoUpdateDTO.GetStatus: IOptString;
begin
  Result := TOptionals.Safe(FStatus);
end;
```

`FStatus` continua `nil` internamente até algo popular a property (`FromJson`, `SetStatus`
manual, etc.) — mas `TOptionals.Safe` nunca deixa isso vazar: se `FStatus` for `nil`, devolve um
objeto "vazio" (`HasValue = False`), nunca a referência nula. **Essa é a única blindagem contra
`nil` que existe nesses campos, e ela acontece uma vez só, na declaração do DTO** — não deve ser
reproduzida em cada método que consome o DTO depois.

**Consequência direta e obrigatória:** Service e Repository nunca checam `Assigned` num campo
opcional individual (`Assigned(ADto.Status)`) — só `.HasValue`. Ver um `Assigned` desses no meio
de um Service/Repository é sinal de bug no getter do DTO (esqueceu o `TOptionals.Safe`), nunca
uma checagem defensiva legítima do lado de quem consome:

```pascal
// Service — direto, sem Assigned no campo
if ADto.Status.HasValue and (Trim(ADto.Status.Value) = '') then
  raise EValidationException.Create('Status não pode ser vazio.');

// Repository — direto, sem Assigned no campo; ProcessTag decide o SQL, HasValue decide o valor
LQuery.Sql := FFactory.SqlLoader['PEDIDO.UPDATE']
  .ProcessTag('STATUS', ADto.Status.HasValue)
  .SQL;
LQuery.Params.OptStrings['STATUS'] := ADto.Status;
```

Os helpers `Params.OptXxx`/`Params.OptNullXxx` (`Db.Adapters.FireDAC`) já fazem
`if not AValue.HasValue then Exit` por dentro — por isso `ADto.Status` pode ser passado direto
para `Params.OptStrings['STATUS']`, sem checagem prévia nenhuma. Esses helpers **dependem** da
garantia de não-nil do getter: se o getter não usasse `TOptionals.Safe` e devolvesse `nil`, a
chamada a `AValue.HasValue` ali dentro quebraria com Access Violation.

`Assigned` continua fazendo sentido, mas só no **parâmetro do DTO inteiro** (`ADto`), nunca nos
seus campos — é o único ponto em que uma referência pode de fato chegar nula (chamada direta com
`nil`, sem passar por `FromJson`/`TDto.Create`):

```pascal
if not Assigned(ADto) then
  raise Exception.Create('[ADto: IPedidoUpdateDTO] não pode ser nil');
```

Essa garantia não depende de revisão manual a cada DTO novo: o fixture
`AllOptionalGetters_NeverReturnNil` (seção "Teste de conformação de DTOs", mais abaixo)
instancia cada DTO vazio e invoca todo getter opcional, falhando se algum devolver `nil`. Ao
criar ou alterar um DTO, rodar esse teste é a forma de confirmar a blindagem — não precisa
inspecionar `TOptionals.Safe` campo a campo de cabeça.

---

## Desserialização do corpo — sempre via `TJsonMapper.FromJson<I>`

**Regra absoluta:** em qualquer handler que recebe corpo (POST, PATCH, PUT), o DTO é construído
com uma única linha:

```pascal
LDto := TJsonMapper.FromJson<IPedidoInsertDTO>(Req.Body);
```

Nunca mapeie campo a campo a partir de `TJSONObject` (`LJson.GetValue<string>('campo')` →
`LDto.Campo := ...`). Se você (agente) está prestes a escrever esse tipo de código porque o
pedido do usuário não citou explicitamente "usar o mapper", pare: **o caminho certo é sempre
`FromJson<I>`**, mesmo sem essa instrução explícita. Mapeamento manual só é aceitável se
`FromJson<I>` estiver de fato indisponível para o caso (não é — ver exceções no fim desta seção).

### Por que o mapper consegue devolver um objeto concreto através de uma interface

`FromJson<I>` nunca sabe, em tempo de compilação, qual classe implementa `I` — ele descobre em
runtime através de um registro que cada DTO monta sozinho:

1. Toda interface de DTO tem um GUID (`['{...}']`) — é a chave de busca.
2. O `class constructor Create` da classe concreta chama
   `TJsonMapper.RegisterMapping<IMeuDTO, TMeuDTO>`, que grava `GUID(IMeuDTO) → TMeuDTO` num
   dicionário estático interno da lib.
3. `TJsonMapper.FromJson<IMeuDTO>(AJson)` lê o GUID de `IMeuDTO` via RTTI, busca a classe
   registrada para esse GUID, instancia `TMeuDTO.Create` e preenche cada `property` da classe
   via RTTI, casando o nome da property com a chave do JSON (case-insensitive). Tipos
   `IOptXxx`/`INullXxx`/`IOptNullXxx` são reconhecidos à parte e recebem `HasValue`/`IsNull`
   corretamente conforme a chave existir ou não no JSON, ou vier como `null`.
4. O objeto populado é convertido de volta para `IMeuDTO` (`GetInterface`) e devolvido — quem
   chamou o handler nunca referencia `TMeuDTO` diretamente, só a interface.

`ToJson<I>` faz o caminho inverso: percorre os métodos `GetXxx` da classe concreta via RTTI e
monta o `TJSONObject` de saída.

Duas pré-condições sustentam esse mecanismo. Faltando qualquer uma, `FromJson` lança
`EJsonMapperException` ("Nenhuma classe registrada para esta interface"), e o único jeito de
"corrigir" isso mapeando campo a campo é reintroduzir manualmente tudo que o mapper já faz:

| Pré-condição | Por quê |
|---|---|
| `class constructor Create` chamando `RegisterMapping<I, C>` em **toda** classe DTO | é o único lugar onde a lib aprende qual classe implementa qual interface — sem ele o dicionário fica vazio para aquele GUID |
| `{$STRONGLINKTYPES ON}` no `.dpr` | sem essa diretiva o compilador pode não vincular o RTTI da classe se ela não for referenciada diretamente em código, e o `class constructor` nunca chega a executar |

### Exemplo didático (interface + classe + handler)

```pascal
IClienteInsertDTO = interface(IInsertDTOBase)
  ['{7B1F2C10-2E4A-4F2B-9A11-1F0F6D0B9A21}']
  function GetNome: string;
  function GetEmail: string;
  function GetTelefone: IOptString;          // campo opcional no corpo
  property Nome: string read GetNome;
  property Email: string read GetEmail;
  property Telefone: IOptString read GetTelefone;
end;

TClienteInsertDTO = class(TInsertDTOBase, IClienteInsertDTO)
private
  FNome: string;
  FEmail: string;
  FTelefone: IOptString;
public
  class constructor Create;    // registra IClienteInsertDTO -> TClienteInsertDTO
  [SwagProp('Nome do cliente', 'Maria Silva')]
  function GetNome: string;
  [SwagProp('E-mail do cliente', 'maria@exemplo.com', 'email')]
  function GetEmail: string;
  [SwagProp('Telefone (opcional)', '11999998888')]
  function GetTelefone: IOptString;
end;

class constructor TClienteInsertDTO.Create;
begin
  TJsonMapper.RegisterMapping<IClienteInsertDTO, TClienteInsertDTO>;
end;

// Controller — nenhum mapeamento manual de campo
procedure HandleInsertCliente(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  LDto: IClienteInsertDTO;
  LResult: IClienteResponseDTO;
begin
  { TJsonMapper busca a classe registrada para IClienteInsertDTO (ver
    TClienteInsertDTO.Create) e preenche cada property a partir do JSON do
    corpo da requisição. Sem essa classe registrada, EJsonMapperException
    é disparada aqui — nunca falha silenciosa. }
  LDto := TJsonMapper.FromJson<IClienteInsertDTO>(Req.Body);

  LResult := AService.Insert(LDto);
  Res.Status(201).ContentType('application/json; charset=utf-8')
     .Send(TJsonMapper.ToJson<IClienteResponseDTO>(LResult));
end;
```

### Quando NÃO é `FromJson<I>`

DTOs de **Find** (paginação/filtros via query string) continuam montados campo a campo com
`ParseQueryInt`/`ParseQueryStr` a partir de `Req.Query[...]` — não têm corpo JSON, então não há
o que o mapper resolva. `FromJson<I>` é especificamente para o corpo de POST/PATCH/PUT (ver
"Padrão de Controller" abaixo para o handler de `Find` completo).

---

## Padrão de SQL (Firebird)

```sql
-- PEDIDO.FIND.sql
SELECT FIRST ${LIMIT} SKIP ${OFFSET}
  ID, STATUS
FROM PEDIDO
WHERE (1=1)
[SEARCH {]
  AND (UPPER(STATUS) LIKE UPPER('%' || :SEARCH || '%'))
[} SEARCH]
ORDER BY ${ORDER_BY}

-- PEDIDO.FIND_COUNT.sql
SELECT COUNT(*) AS TOTAL FROM PEDIDO
WHERE (1=1)
[SEARCH {]
  AND (UPPER(STATUS) LIKE UPPER('%' || :SEARCH || '%'))
[} SEARCH]

-- PEDIDO.INSERT.sql (RETURNING — tratado como SELECT)
INSERT INTO PEDIDO (STATUS) VALUES (:STATUS) RETURNING ID, STATUS

-- PEDIDO.INSERT.sql (com colunas opcionais — mesma tag repetida na lista de
-- colunas e na de valores; um único ProcessTag('TAG', bool) ativa as duas ocorrências)
INSERT INTO PEDIDO (
  STATUS
  [OBSERVACAO {]      , OBSERVACAO      [} OBSERVACAO]
  [DATA_ENTREGA {]     , DATA_ENTREGA     [} DATA_ENTREGA]
) VALUES (
  :STATUS
  [OBSERVACAO {]      , :OBSERVACAO      [} OBSERVACAO]
  [DATA_ENTREGA {]     , :DATA_ENTREGA    [} DATA_ENTREGA]
)
RETURNING ID, STATUS, OBSERVACAO, DATA_ENTREGA
```

- `${LIMIT}` / `${OFFSET}` / `${ORDER_BY}` — substituídos por `ReplaceLiteral`
- `[TAG { ... } TAG]` — bloco ativado/desativado por `ProcessTag('TAG', bool)`. A mesma tag pode
  (e deve) se repetir em vários pontos do SQL — lista de colunas e lista de valores de um
  INSERT, por exemplo — e um único `ProcessTag('TAG', ADto.Campo.HasValue)` ativa/desativa todas
  as ocorrências ao mesmo tempo. É assim que se evita `if`/concatenação manual de string para
  montar SQL condicional em Delphi: a decisão fica inteira na chamada a `ProcessTag`, no
  Repository, nunca espalhada pelo SQL ou reconstruída campo a campo
- Parâmetros nomeados `:STATUS` — passados via `LQuery.Params.Strings['STATUS']`; para campos
  opcionais, `LQuery.Params.OptStrings['OBSERVACAO'] := ADto.Observacao` (ou `OptNullXxx` para
  `IOptNullXxx`) — o parâmetro já resolve `HasValue`/`IsNull` por dentro, sem checagem prévia
- **INSERT com RETURNING**: chamar `LQuery.Open` (não `ExecSql`) — o FireDAC trata como SELECT

### Contrato DTO ↔ SQL: opcionalidade tem que bater dos dois lados

Cada campo de filtro/coluna tem uma única decisão de "é obrigatório ou é opcional?" — e essa
decisão precisa aparecer **idêntica** em três lugares: o tipo do campo no DTO, a presença (ou
não) de `[TAG {} TAG]` no SQL, e a chamada (ou não) de `ProcessTag` no Repository. Escrever
qualquer um desses três sem checar os outros dois é a causa mais comum de bug nesse fluxo — o
código compila, os testes de tipo passam, e a query quebra ou filtra errado só em runtime.

| No DTO | No SQL | No Repository |
|---|---|---|
| Campo **obrigatório** (`string`, `Integer`, `TDateTime`, ...) | Aparece **sem** `[TAG {} TAG]` — sempre no `WHERE`/`VALUES` | Bind direto: `Params.Strings['COL'] := ADto.Campo` |
| Campo **opcional** (`IOptXxx`/`INullXxx`/`IOptNullXxx`) | Envolvido em `[TAG {} TAG]` | `ProcessTag('TAG', ADto.Campo.HasValue)` **e** `Params.OptXxx['COL'] := ADto.Campo` |

Duas quebras de contrato acontecem na prática, e as duas são silenciosas até alguém chamar a
rota com (ou sem) aquele filtro:

1. **Campo `Opt` no DTO, mas o SQL trata a coluna como obrigatória** (sem tag). Se o chamador não
   informar o filtro, o parâmetro nunca é vinculado (o helper `Params.OptXxx` só atribui quando
   `HasValue`) e o FireDAC estoura em runtime por parâmetro sem valor — ou, pior, se o código ler
   `.Value` direto sem checar `HasValue`, filtra por string vazia/zero e devolve resultado errado
   sem erro nenhum. Sinal de que o campo deveria ser obrigatório no DTO (ou a coluna precisa
   ganhar a tag no SQL).
2. **Tag no SQL sem campo correspondente no DTO** (ou DTO com campo que não aparece em nenhuma
   tag/coluna do SQL). Nos dois casos sobra código morto: um filtro que o SQL sabe fazer mas a
   API nunca consegue acionar, ou um campo que o cliente pode preencher e que nunca influencia a
   consulta.

**Checklist antes de considerar um Find (ou Insert/Update com colunas opcionais) pronto** — rode
isso comparando DTO, SQL e Repository lado a lado, campo por campo:

- Todo campo obrigatório do DTO aparece sem tag no SQL, e é vinculado direto no Repository.
- Todo campo opcional (`IOptXxx`/`INullXxx`/`IOptNullXxx`) do DTO tem uma tag correspondente no
  SQL **e** um `ProcessTag` correspondente no Repository — nenhum dos dois pode faltar.
- Toda tag do SQL tem um `ProcessTag` que a aciona no Repository, e esse `ProcessTag` lê
  `.HasValue` de um campo que existe de fato no DTO — nenhuma tag "órfã".
- Nenhum campo do DTO fica sem uso em lugar nenhum do SQL/Repository — nenhum campo "morto".

A decisão de "esse filtro é obrigatório ou opcional" nasce da regra de negócio do endpoint, não
do tipo que parecia mais natural escrever no DTO — ao criar a interface do DTO, primeiro decida
isso olhando a query que vai alimentá-la, nunca o contrário.

### Build automático dos `.res` — nunca rode `brcc32` na mão

Cada `.sql` só existe na API compilada depois de passar por `brcc32.exe` (`.rc` → `.res`), e o
`{$R}` no DPR embute esse `.res`. Enquanto isso for um passo manual, existe uma janela onde
alguém edita/adiciona um `.sql`, esquece de recompilar o `.res`, e o `.exe` gerado compila sem
erro nenhum — só que rodando a versão **anterior** do SQL. É especialmente fácil isso acontecer
ao trocar de máquina (clone novo, ou pull numa máquina que não tinha o hábito de recompilar): o
`.res` commitado no repositório é o que fica valendo até alguém rodar `brcc32` de novo.

**Solução: pre-build event no `.dproj`, não lembrete manual.** Copie
[`tools/build_sql_res.bat`](tools/build_sql_res.bat) (desta lib) para o projeto consumidor e
registre como Pre-Build Event:

```
Project Options > Building > Build Events > Pre-build event:
  call tools\build_sql_res.bat
```

O script varre toda a árvore `sql/` (funciona tanto pro caso simples — `sql/queries.rc` — quanto
pro multi-banco — `sql/fb/fb.rc` + `sql/pg/pg.rc`, ou qualquer outra estrutura de subpastas) e
recompila **todo** `.rc` encontrado, sempre, em toda build — não tenta detectar "mudou ou não":
`brcc32` é rápido o bastante pra isso não valer a complexidade, e eliminar a lógica de
staleness elimina também uma categoria inteira de bug (a lógica de detecção errada). Se algum
`.rc` falhar ao compilar, o script sai com código de erro != 0, o que aborta a compilação — o
`.exe` nunca chega a ser gerado com um `.res` que falhou.

O script resolve `sql/` a partir da própria localização do `.bat` (`%~dp0..\sql`), nunca do
working directory de quem chama — por isso o mesmo arquivo funciona chamado de qualquer `.dproj`
do repositório, só ajustando o caminho relativo até ele. **Registre o Pre-Build Event em todo
`.dproj` que embute esses `{$R}`, não só no da API principal** — os projetos de teste
(unitário/integração) tipicamente também referenciam os mesmos resources (via `Db.SqlLoader`
para testes que batem no banco de verdade), e ficam expostos ao mesmo risco de `.res`
desatualizado se ficarem de fora:

```
tests\Unit\MeuProjeto.UnitTests.dproj:
  call ..\..\tools\build_sql_res.bat

tests\Integration\MeuProjeto.IntegrationTests.dproj:
  call ..\..\tools\build_sql_res.bat
```

**Limite conhecido:** Pre-Build Event só dispara quando a compilação passa pelo `.dproj` (IDE ou
`msbuild` no `.dproj`). Rodar `dcc32 projeto.dpr` direto ignora o `.dproj` inteiro, Build Events
inclusive — nesse caminho o `.res` que estiver em disco é usado sem aviso. Se o projeto tiver
motivo para builds fora do `.dproj`, considere reforçar com uma checagem em runtime (ex.: hash do
conteúdo `.sql` embutido como resource extra, comparado contra o hash recalculado dos `.sql` em
disco num teste de conformação) — mas para o fluxo normal (IDE ou CI via `.dproj`), o pre-build
event já fecha o problema.

---

## Padrão de Repository

```pascal
class function TPedidoRepository.OrderBySpec: TOrderBySpec;
begin
  Result := TOrderBySpec.New
    .Allow('id',     'ID')
    .Allow('status', 'STATUS')
    .Default('id');
end;

function TPedidoRepository.Find(ADto: IPedidoFindDTO): TPedidoPageResult;
var
  LParams: TPageParams;
  LHasSearch: Boolean;
  LFindSql, LCountSql: TSQLResult;
  LOrderByExpr: string;
begin
  if not Assigned(ADto) then                     // único Assigned legítimo: o DTO inteiro
    raise Exception.Create('[ADto: IPedidoFindDTO] não pode ser nil');

  LParams      := TPageParams.From(ADto.Page, ADto.Limit);
  LHasSearch   := ADto.Search.HasValue and (Trim(ADto.Search.Value) <> '');  // sem Assigned no campo
  LOrderByExpr := '';
  if ADto.OrderBy.HasValue then
    LOrderByExpr := ADto.OrderBy.Value;

  LFindSql := FFactory.SqlLoader['PEDIDO.FIND']
    .ReplaceLiteral('LIMIT',    IntToStr(LParams.Limit))
    .ReplaceLiteral('OFFSET',   IntToStr(LParams.Offset))
    .ReplaceLiteral('ORDER_BY', OrderBySpec.Build(LOrderByExpr))
    .ProcessTag('SEARCH', LHasSearch);

  LCountSql := FFactory.SqlLoader['PEDIDO.FIND_COUNT']
    .ProcessTag('SEARCH', LHasSearch);

  // Executar COUNT e DATA em queries separadas (ver Exemplo.Repository no delphi-api-starter para referência completa)
end;

function TPedidoRepository.Insert(ADto: IPedidoInsertDTO): IPedidoResponseDTO;
var
  LScope: IScopeTransaction;
  LQuery: IQuery;
  LResult: IQueryResult;
begin
  if not Assigned(ADto) then                     // único Assigned legítimo: o DTO inteiro
    raise Exception.Create('[ADto: IPedidoInsertDTO] não pode ser nil');

  Result := nil;
  LScope := FFactory.GetPool.AcquireQuery(LQuery);
  LScope.StartTransaction;
  try
    LQuery.Sql := FFactory.SqlLoader['PEDIDO.INSERT']
      .ProcessTag('OBSERVACAO',   ADto.Observacao.HasValue)     // sem Assigned no campo
      .ProcessTag('DATA_ENTREGA', ADto.DataEntrega.HasValue)
      .SQL;

    LQuery.Params.Strings['STATUS']               := ADto.Status;
    LQuery.Params.OptStrings['OBSERVACAO']         := ADto.Observacao;
    LQuery.Params.OptNullDateTimes['DATA_ENTREGA'] := ADto.DataEntrega;

    LResult := LQuery.Open;   // INSERT com RETURNING — Open, não ExecSql
    if not LResult.IsEmpty then
      Result := BuildResponseDTO(LResult);
    LScope.Commit;
  except
    LScope.Rollback;
    raise;
  end;
end;
```

Note o padrão: **um único `Assigned`, no topo, para o `ADto` como um todo.** Daí em diante, todo
campo opcional é `.HasValue` puro — `ProcessTag` decide o SQL, `Params.OptXxx`/`OptNullXxx`
decide o valor, nenhum dos dois precisa que o Repository proteja contra `nil` de novo.

---

## Padrão de Controller

```pascal
TRouteDoc.Get('/pedidos')
  .Summary('Listar pedidos (paginado)')
  .Tag('pedidos')
  .QueryParam('page',    'Página (padrão: 1)',                      qptInteger)
  .QueryParam('limit',   'Itens por página (padrão: 20, máx: 100)', qptInteger)
  .QueryParam('search',  'Filtro por status (parcial, opcional)')
  .QueryParam('orderBy', TPedidoRepository.OrderBySpec.DocHint)
  .ResponsePaged<IPedidoResponseDTO>('200', 'Lista paginada de pedidos')
  .Register(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var LDto: IPedidoFindDTO; LResult: TPedidoPageResult;
    begin
      LDto         := TPedidoFindDTO.Create;
      LDto.Page    := ParseQueryInt(Req.Query['page']);
      LDto.Limit   := ParseQueryInt(Req.Query['limit']);
      LDto.Search  := ParseQueryStr(Req.Query['search']);
      LDto.OrderBy := ParseQueryStr(Req.Query['orderBy']);
      LResult := AService.Find(LDto);
      Res.ContentType('application/json; charset=utf-8')
         .Send(LResult.Meta.WrapJson(BuildItemsJson(LResult.Items)));
    end);

TRouteDoc.Post('/pedidos')
  .Summary('Criar pedido')
  .Tag('pedidos')
  .Body<IPedidoInsertDTO>('Dados do novo pedido')
  .Response<IPedidoResponseDTO>('201', 'Pedido criado')
  .Register(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var LDto: IPedidoInsertDTO; LResult: IPedidoResponseDTO;
    begin
      // corpo da requisição — sempre via FromJson<I>, nunca campo a campo
      // (ver "Desserialização do corpo — sempre via TJsonMapper.FromJson<I>")
      LDto := TJsonMapper.FromJson<IPedidoInsertDTO>(Req.Body);
      LResult := AService.Insert(LDto);
      Res.Status(201).ContentType('application/json; charset=utf-8')
         .Send(TJsonMapper.ToJson<IPedidoResponseDTO>(LResult));
    end);

TRouteDoc.Patch('/pedidos/:id')
  .Summary('Atualizar pedido (parcial)')
  .Tag('pedidos')
  .PathParam('id', 'ID do pedido', qptInteger)
  .Body<IPedidoUpdateDTO>('Campos a atualizar')
  .NoContent('204', 'Atualizado com sucesso')
  .NoContent('404', 'Pedido não encontrado')
  .Register(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var LDto: IPedidoUpdateDTO;
    begin
      LDto := TJsonMapper.FromJson<IPedidoUpdateDTO>(Req.Body);
      AService.Update(StrToInt(Req.Params['id']), LDto);
      Res.Status(204);
    end);
```

Para `BuildItemsJson`, ver implementação em `Exemplo.Controller` no delphi-api-starter — padrão idêntico.
`EOrderByException` não precisa ser capturada no handler — o `TErrorHandlerMiddleware` (via `THorse.OnError`) converte automaticamente para 400.

---

## Padrão de inicialização no DPR

```pascal
{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}   // obrigatório para RTTI dos DTOs

// Montar dependências
LService := TPedidoService.Create(TPedidoRepository.Create(LFactory));

// Health check — fora do Swagger e do MCP (registrar antes dos middlewares)
THealthCheck.Register(LFactory);

// Logger (opcional) — deve ser o PRIMEIRO middleware em THorse.Use, para medir
// a duração total da requisição (inclui o que os middlewares seguintes fazem)
// THorse.Use(TLoggerMiddleware.New);                         // console
// THorse.Use(TLoggerMiddleware.New(procedure(const S: string) begin ... end));

// Middleware de erros — usa THorse.OnError (hook nativo do core), não é um
// middleware em THorse.Use: não entra na cadeia de Next(), sem posição
// relativa aos outros a respeitar. Registre em qualquer ponto antes de Listen.
TErrorHandlerMiddleware.Register;
// Com log em arquivo do que quebrou de verdade (erros 500; validação/404/409 não contam):
// TErrorHandlerMiddleware.Register(
//   procedure(const ALine: string)
//   begin
//     FileLog(['exception', 'http'], ALine);
//   end);

// Rate limiting (opcional) — antes de RegisterRoutes
// THorse.Use(TRateLimitMiddleware.New(60, 60));   // 60 req/min por IP

// CORS (opcional) — antes de RegisterRoutes
// THorse.Use(TCorsMiddleware.New);                          // dev: libera *
// THorse.Use(TCorsMiddleware.New('https://app.example.com')); // produção

// Autenticação Bearer com API key (opcional)
// THorse.Use(TAuthMiddleware.Bearer(
//   function(const AToken: string): Boolean
//   begin
//     Result := AToken = TAppConfig.Get('API_KEY', '');
//   end,
//   ['/health', '/swagger']));

// Autenticação JWT HS256 (opcional) — alternativa ao Bearer simples
// THorse.Use(TJwtMiddleware.New(
//   TAppConfig.Get('JWT_SECRET', ''),
//   ['/health', '/swagger', '/auth/login']));
//
// Para ler claims em um handler:
//   var LClaims := TJwtHelper.GetClaimsFromRequest(Req, TAppConfig.Get('JWT_SECRET', ''));
//   try
//     if Assigned(LClaims) then
//       LUserId := LClaims.GetValue<string>('sub');
//   finally
//     LClaims.Free;
//   end;

// Swagger (deve vir antes de RegisterRoutes)
TRouteDoc.Init('Minha API', '1.0.0', 'localhost:9000');

// Registrar rotas
TPedidoController.RegisterRoutes(LService);

// MCP (antes de TRouteDoc.Serve)
TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp', 'http://localhost:9000', 'Minha API', '1.0.0');

// Endpoint por domínio (opcional)
LTags := TStringList.Create;
try
  LTags.Add('pedidos');
  TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp/pedidos',
    'http://localhost:9000', 'Minha API', '1.0.0', nil, LTags);
finally
  LTags.Free;
end;

TRouteDoc.Serve('/swagger');   // serializa e libera o doc
THorse.Listen(9000);
```

---

## MCP — nomes de tools

Derivação automática: método HTTP + último segmento do path, singular (strip do `s`):
- `GET /pedidos` → `list_pedido`
- `POST /pedidos` → `create_pedido`
- `GET /pedidos/:id` → `get_pedido`

Para plurais irregulares (`operacoes`, `perfis`, `animais`), use `.ToolName()`:

```pascal
TRouteDoc.Get('/operacoes').ToolName('list_operacao')...
```

---

## Suporte a múltiplos bancos por configuração

O mesmo executável pode ser implantado com Firebird ou PostgreSQL — o banco ativo é determinado por uma chave de configuração (ex: `DB_DIALECT` no `.env`). Nenhum código de domínio muda; apenas o DPR lê o dialeto e monta a factory correta.

### Estrutura de SQL

Organize os arquivos em subpastas por banco. Os nomes de arquivo são idênticos; apenas o conteúdo difere:

```
sql/
  fb/
    fb.rc           — SQL_FB_MIG_0001, SQL_FB_PEDIDO_FIND ...
    fb.res          — gerado, ver "Build automático dos .res" abaixo
    MIG.0001.sql    — DDL Firebird  (terminador ^)
    PEDIDO.FIND.sql
    ...
  pg/
    pg.rc           — SQL_PG_MIG_0001, SQL_PG_PEDIDO_FIND ...
    pg.res          — gerado, ver "Build automático dos .res" abaixo
    MIG.0001.sql    — DDL PostgreSQL (terminador ;)
    PEDIDO.FIND.sql
    ...
```

O prefixo (`FB` / `PG`) é o `SQLDirectory` do `TFDConfig` e vira o segmento do meio no nome do resource: `SQL_<DIRECTORY>_<NOME>`. Ambos os `.res` ficam embutidos no executável via `{$R}`; em runtime, apenas os resources do dialeto ativo são acessados. Não crie `.bat` por pasta (`fb.bat`, `pg.bat`) — o script único descrito abaixo varre `sql/` inteira e recompila todos os `.rc` que encontrar, dialeto único ou múltiplos bancos, sem distinção.

### DPR — factory única, seleção em runtime

```pascal
{$R 'sql\fb\fb.res'}
{$R 'sql\pg\pg.res'}

// Inclua os dois drivers para que o FireDAC os registre
uses FireDAC.Phys.FB, FireDAC.Phys.PG, ...

const
  MIGRATIONS_FB: array[0..0] of TMigrationItem = (
    (Version: 1; ScriptName: 'MIG.0001'; ParamReplaceProc: nil; Terminator: '^'; IsDDL: True)
  );
  MIGRATIONS_PG: array[0..0] of TMigrationItem = (
    (Version: 1; ScriptName: 'MIG.0001'; ParamReplaceProc: nil; Terminator: ';'; IsDDL: True)
  );

LDialect := TAppConfig.Get('DB_DIALECT', 'Firebird');
LConfig  := TFDConfig.Create;

if SameText(LDialect, 'PostgreSQL') then
begin
  LConfig.ConnectionParams.Add('DriverID=PG');
  LConfig.ConnectionParams.Add('Server='   + TAppConfig.Get('DB_HOST', 'localhost'));
  LConfig.ConnectionParams.Add('Port='     + TAppConfig.Get('DB_PORT', '5432'));
  LConfig.ConnectionParams.Add('Database=' + TAppConfig.Get('DB_NAME', ''));
  LConfig.ConnectionParams.Add('User_Name='+ TAppConfig.Get('DB_USER', 'postgres'));
  LConfig.ConnectionParams.Add('Password=' + TAppConfig.Get('DB_PASSWORD', ''));
  LConfig.SQLDialect   := 'PostgreSQL';
  LConfig.SQLDirectory := 'PG';
end
else
begin
  SetDllDirectory(PWideChar(TAppConfig.Get('FB_CLIENT_DIR', '')));
  LConfig.ConnectionParams.Add('DriverID=FB');
  LConfig.ConnectionParams.Add('Database=' + TAppConfig.Get('DB_PATH', ''));
  LConfig.ConnectionParams.Add('User_Name='+ TAppConfig.Get('DB_USER', 'SYSDBA'));
  LConfig.ConnectionParams.Add('Password=' + TAppConfig.Get('DB_PASSWORD', 'masterkey'));
  LConfig.ConnectionParams.Add('CharacterSet=UTF8');
  LConfig.SQLDialect   := 'Firebird';
  LConfig.SQLDirectory := 'FB';
end;

LFactory := TFDFactory.Create(LConfig, nil);

// Migration do dialeto ativo
LEngine := TDBMigrationEngine.Create(LFactory);
if SameText(LDialect, 'PostgreSQL') then
  LEngine.Execute(MIGRATIONS_PG)
else
  LEngine.Execute(MIGRATIONS_FB);
LEngine.Free;

// Domínio — nenhuma alteração
LService := TPedidoService.Create(TPedidoRepository.Create(LFactory));
```

### Diferenças SQL por banco

| Recurso | Firebird | PostgreSQL |
|---|---|---|
| Paginação | `SELECT FIRST ${LIMIT} SKIP ${OFFSET} ...` | `SELECT ... LIMIT ${LIMIT} OFFSET ${OFFSET}` |
| Auto-incremento | `CREATE GENERATOR` + trigger | `GENERATED BY DEFAULT AS IDENTITY` |
| Terminador migration | `^` | `;` |
| Driver FireDAC | `FireDAC.Phys.FB` | `FireDAC.Phys.PG` |
| `INSERT RETURNING` | suportado | suportado |

---

## Pool de conexões

Tamanho do pool e fechamento por inatividade são configurados em `TFDConfig`, antes de `TFDFactory.Create` (mesmo bloco de montagem da factory, acima):

```pascal
LConfig.PoolIniConnections      := TAppConfig.GetInt('POOL_INI_CONNECTIONS', 3);
LConfig.PoolMaxConnections      := TAppConfig.GetInt('POOL_MAX_CONNECTIONS', 20);
LConfig.PoolIdleTimeoutSeconds  := TAppConfig.GetInt('POOL_IDLE_TIMEOUT_SECONDS', 0);   // 0 = desligado (padrão)
LConfig.PoolIdleCheckIntervalMs := TAppConfig.GetInt('POOL_IDLE_CHECK_INTERVAL_MS', 30000);

LFactory := TFDFactory.Create(LConfig, nil);
```

`PoolIniConnections`/`PoolMaxConnections` **não têm default** em `TFDConfig` — sem configurar, ficam `0` e o pool não abre conexão nenhuma. `PoolIdleTimeoutSeconds` fecha conexões ociosas no pool além do limite configurado, nunca abaixo de `PoolIniConnections`; fica desligado (comportamento idêntico a antes da opção existir) até ser configurado explicitamente. Campos completos e efeitos colaterais no README, seção "Pool de conexões".

---

## Logging

`Common.SafeLog.SafeWriteln` — `Writeln` thread-safe pro console (`TCriticalSection` global). Use em qualquer ponto que pode rodar fora da main thread (handler HTTP, `OnRequest` de pipe-server, thread de pool) — `Writeln` direto corrompe o buffer do CRT sob concorrência.

`Common.FileLog.FileLog(ACategory, AText)` — log assíncrono em arquivo, por categoria, pra código fora do ciclo de requisição do Horse (startup, jobs, handlers de pipe/mensageria). Só enfileira (nunca bloqueia esperando disco); thread dedicada drena e grava em lote. Rotaciona por tamanho: arquivo cheio vira `<categoria>_yyyymmddhhnnss.log`, um novo começa vazio. Toda linha é prefixada com `[<hash> <data hora>]`.

```pascal
FileLog('pipe', 'Consulta NFE: loja=%s chave=%s', [LLoja, LChave]);
```

Config (`.env`): `LOG_DIR` (padrão `logs`), `LOG_QUEUE_CAPACITY` (padrão `10000`), `LOG_FLUSH_INTERVAL_MS` (padrão `200`), `LOG_MAX_FILE_SIZE_MB` (padrão `2`). Detalhes no README, seção "Logging".

### Padrão: `exception.log` como índice, correlacionado por hash

`FileLog` aceita um array de categorias — a mesma linha (mesmo hash) vai pra mais de um arquivo:

```pascal
FileLog(['exception', 'pipe'], 'Falha ao processar NFe: %s', [E.Message]);
```

O hash é gerado uma vez por chamada e repete em todas as categorias daquela chamada — grepar o hash em `exception.log` acha a mesma linha, com o mesmo hash, no arquivo de contexto completo (`pipe.log`, `migrations.log`, etc.). Use isso pra manter `exception.log` como um índice curto e monitorável (poucas linhas, sinal de "algo quebrou"), sem duplicar todo o contexto operacional nele.

Dois pontos onde aplicar por padrão em todo projeto novo:

1. **Erros HTTP não tratados** — `TErrorHandlerMiddleware.Register` aceita um `AOnError: TLogProc` opcional, chamado só para o branch 500 (erro de verdade; validação/404/409 são fluxo esperado, não vão pro log):
   ```pascal
   TErrorHandlerMiddleware.Register(
     procedure(const ALine: string)
     begin
       FileLog(['exception', 'http'], ALine);
     end);
   ```
2. **Etapas críticas do startup** (conexão com banco, migrations, conexão com fila, etc.) — envolva cada etapa num `try/except` que loga em `['exception', '<categoria-do-app>']` antes de re-lançar, pra uma falha na inicialização aparecer tanto no índice quanto no log completo de startup:
   ```pascal
   try
     LConsumer.Start;
   except
     on E: Exception do
     begin
       FileLog(['exception', 'minha-api'], 'Falha ao iniciar consumer RabbitMQ: %s', [E.Message]);
       raise;
     end;
   end;
   ```

---

## Anti-padrões a evitar

- Colocar lógica de negócio no Repository — validações vão no Service
- Omitir `class constructor` no DTO — o mapping não é registrado; falha silenciosa em runtime
- Omitir `{$STRONGLINKTYPES ON}` — o `class constructor` não é executado
- Colocar `[SwagProp]` na interface em vez da classe — o RTTI não existe na interface
- Mapear o corpo da requisição campo a campo (`LJson.GetValue<string>('campo')` → `LDto.Campo := ...`) em vez de `TJsonMapper.FromJson<I>(Req.Body)` — repete lógica que o mapper já faz, ignora o tratamento de `IOptXxx`/`INullXxx` e some silenciosamente na próxima vez que um campo for adicionado ao DTO sem atualizar o mapeamento manual
- Declarar um campo de Find/Insert/Update como `IOptXxx`/`INullXxx` sem checar se o SQL trata essa coluna como opcional (`[TAG {} TAG]`) — ou o oposto, deixar uma tag no SQL sem campo `Opt` correspondente no DTO. Ver "Contrato DTO ↔ SQL" em "Padrão de SQL" — a opcionalidade é uma única decisão que precisa bater no DTO, no SQL e no `ProcessTag` do Repository ao mesmo tempo, nunca decidida isoladamente em um dos três
- Usar `INullXxx` (sem `Opt`) num campo de DTO que vem de JSON ou query string (Insert/Update/Find) — o tipo não distingue "chave ausente" de `"campo": null` (as duas colapsam pro mesmo `IsNull = True`, ver "`IOptXxx` vs `INullXxx` vs `IOptNullXxx`"). `INullXxx` é só para Response DTO lendo linha de banco
- `ExecSql` em INSERT com RETURNING — use `Open`
- SQL inline no código — todo SQL vai em arquivo `.sql` + `queries.rc`
- Depender de lembrar de rodar `brcc32` manualmente após adicionar/editar SQL — configure o pre-build event (ver "Build automático dos `.res`" em "Padrão de SQL") em vez de confiar em disciplina humana
- `Writeln` direto em código que pode rodar fora da main thread (handler HTTP, `OnRequest` de pipe-server, thread de pool) — usar `SafeWriteln` (`Common.SafeLog`)
- `IOptional.Value` sem checar `HasValue` antes
- Checar `Assigned` num campo `IOptXxx`/`INullXxx`/`IOptNullXxx` individual do DTO antes de `.HasValue` — o getter já garante não-nil via `TOptionals.Safe` (ver "Campos opcionais"); `Assigned` só se justifica no `ADto` inteiro, nunca nos seus campos
- Chamar `LResult.Next` antes de checar `LResult.IsEmpty` — o padrão correto é `while not LResult.Eof`
- Registrar `TMcpServer` após `TRouteDoc.Serve` — o doc já foi liberado
- Lançar `Exception` genérica para erros de domínio — use as classes tipadas: `EValidationException` (400), `ENotFoundException` (404), `EConflictException` (409); o middleware converte automaticamente para o status correto

---

## Teste de conformação de DTOs (projeto consumidor)

Todo projeto concreto deve ter um fixture DUnitX com dois testes: um garante que cada DTO tem
mapeamento registrado no `TJsonMapper` (sem isso, `FromJson`/`ToJson` falha silenciosamente em
runtime); o outro garante que nenhum getter opcional devolve `nil` (sem isso, a regra de
"Campos opcionais" — `.HasValue` direto, sem `Assigned` no campo — vira uma aposta, não uma
garantia).

```pascal
// tests/Unit/DTOConformanceTests.pas
uses
  DUnitX.TestFramework, System.Rtti, System.TypInfo,
  Common.DTO.Base, Common.JsonMapper;

type
  [TestFixture]
  TDTOConformanceTests = class
  public
    [Test]
    procedure AllDTOs_HaveJsonMapping;
    [Test]
    procedure AllDTOs_OptionalGettersNeverReturnNil;
  end;

implementation

procedure TDTOConformanceTests.AllDTOs_HaveJsonMapping;
var
  LCtx:   TRttiContext;
  LType:  TRttiType;
  LClass: TClass;
  LIntf:  TRttiInterfaceType;
  LImpl:  TClass;
  LWarm:  TObject;
  LFound: Boolean;
begin
  LCtx := TRttiContext.Create;
  try
    for LType in LCtx.GetTypes do
    begin
      if not (LType is TRttiInstanceType) then Continue;
      LClass := LType.AsInstance.MetaclassType;
      if not LClass.InheritsFrom(TDTOBase) then Continue;
      // pula as classes-base abstratas da própria infra (TDTOBase, TResponseDTOBase,
      // TInsertDTOBase, ...) — nenhuma delas tem RegisterMapping, só as classes
      // concretas de domínio
      if LClass.UnitName = 'Common.DTO.Base' then Continue;

      // TRttiContext.GetTypes é RTTI pura — não conta como "uso" da classe pro
      // compilador, então o class constructor (onde o RegisterMapping acontece)
      // pode ainda não ter rodado se nada mais no processo instanciou essa classe
      // antes (depende da ordem de execução dos outros fixtures de teste). Cria e
      // descarta uma instância aqui pra garantir a execução antes do check.
      LWarm := LClass.Create;
      LWarm.Free;

      // FindImplClass espera o PTypeInfo de uma INTERFACE (é de lá que ele lê o
      // GUID) — o PTypeInfo da classe não tem GUID de verdade nesse offset (TTypeData
      // é um record variante; leria lixo de outro campo). Por isso não dá pra checar
      // a classe direto: precisa achar qual interface implementada por ela foi
      // registrada via RegisterMapping.
      LFound := False;
      for LIntf in TRttiInstanceType(LType).GetImplementedInterfaces do
      begin
        LImpl := TJsonMapper.FindImplClass(LIntf.Handle);
        if LImpl = LClass then
        begin
          LFound := True;
          Break;
        end;
      end;

      Assert.IsTrue(LFound,
        LType.Name + ' herda de TDTOBase mas não tem RegisterMapping registrado');
    end;
  finally
    LCtx.Free;
  end;
end;

procedure TDTOConformanceTests.AllDTOs_OptionalGettersNeverReturnNil;
var
  LCtx:      TRttiContext;
  LType:     TRttiType;
  LClass:    TClass;
  LInstType: TRttiInstanceType;
  LObj:      TObject;
  LMethod:   TRttiMethod;
  LRetType:  TRttiType;
  LValue:    TValue;
begin
  LCtx := TRttiContext.Create;
  try
    for LType in LCtx.GetTypes do
    begin
      if not (LType is TRttiInstanceType) then Continue;
      LClass := LType.AsInstance.MetaclassType;
      if not LClass.InheritsFrom(TDTOBase) then Continue;
      if LClass.UnitName = 'Common.DTO.Base' then Continue;

      LInstType := TRttiInstanceType(LType);

      // instância "vazia" — nenhum field foi populado, é exatamente o cenário em
      // que TOptionals.Safe precisa entrar em ação nos getters opcionais
      LObj := LClass.Create;
      try
        for LMethod in LInstType.GetMethods do
        begin
          if LMethod.MethodKind <> mkFunction then Continue;    // TMethodKind — System.TypInfo
          if Length(LMethod.GetParameters) <> 0 then Continue;
          if not LMethod.Name.StartsWith('Get', True) then Continue;

          LRetType := LMethod.ReturnType;
          if (LRetType = nil) or (LRetType.TypeKind <> tkInterface) then Continue;
          // convenção da lib (Common.Optionals): todo tipo opcional/anulável começa
          // com IOpt ou INull. Outros getters de interface (DTOs aninhados etc.)
          // não fazem parte desse contrato de "nunca nil".
          if not (LRetType.Name.StartsWith('IOpt') or LRetType.Name.StartsWith('INull')) then
            Continue;

          LValue := LMethod.Invoke(LObj, []);
          Assert.IsFalse(LValue.IsEmpty,
            LType.Name + '.' + LMethod.Name +
            ' retornou nil — getter precisa usar TOptionals.Safe (ver "Campos opcionais")');
        end;
      finally
        LObj.Free;
      end;
    end;
  finally
    LCtx.Free;
  end;
end;
```

Se `AllDTOs_OptionalGettersNeverReturnNil` falhar, o problema está sempre no getter do DTO
apontado (faltou `TOptionals.Safe`) — nunca em quem consome o DTO depois.

### Pré-requisitos — no projeto de TESTE, não (só) no da API

`{$STRONGLINKTYPES ON}` e "toda unit de DTO referenciada" precisam valer para o **binário do
projeto de teste** especificamente — é um `.dpr`/`.dproj` separado do da API, com sua própria
linkagem:

- `{$STRONGLINKTYPES ON}` tem que estar no `.dpr` do **projeto de teste**. Tê-lo só no `.dpr` da
  API não ajuda em nada aqui — são executáveis diferentes, cada um decide sozinho quais
  `class constructor` rodam.
- Toda unit de DTO precisa estar **explicitamente alcançável a partir da `uses` do projeto de
  teste** (direto, ou indiretamente via outra unit que o projeto de teste já referencia). O
  projeto de teste só enxerga o que foi de fato compilado nele — uma unit de DTO usada apenas
  pelo app principal, e nunca referenciada em nenhuma unit do projeto de teste, simplesmente não
  entra no binário de teste, e RTTI (`TRttiContext.GetTypes`) não vê o que não foi linkado.

O efeito de esquecer isso é silencioso: sem erro de compilação, sem exceção — os dois testes
passam "verdes" porque nunca chegaram a ver aquele DTO. É falso positivo puro (teste reporta
sucesso sem ter checado nada da classe esquecida), não uma falha visível que chama atenção
sozinha. Prática recomendada: mantenha uma unit central no projeto de teste (ex.:
`tests/Unit/AllDTOs.pas`, sem nenhum `[TestFixture]`, só existindo pra puxar todo `*.DTOs.pas`
do domínio na `uses`) e inclua-a no `.dpr` de teste — assim adicionar um domínio novo é só um
`uses` a mais, sem depender de lembrar disso a cada DTO.

---

## Mensageria (IMessageConsumer / IMessagePublisher)

O módulo `src/Messaging/Messaging.Interfaces.pas` define o contrato de mensageria agnóstico de protocolo e broker. Adapters concretos (AMQP, STOMP, etc.) implementam `IMessageConsumer` e `IMessagePublisher`. O projeto de negócio implementa apenas `IMessageHandler`.

### Interfaces

| Interface | Responsabilidade |
|---|---|
| `IMessagePayload` | Mensagem recebida — `Body`, `RoutingKey`, `Header(key)` |
| `IMessageHandler` | O que fazer com a mensagem — implementado pelo projeto |
| `IMessageConsumer` | Gerencia consumo de uma queue — `Subscribe`, `Start`, `Stop`, `IsRunning` |
| `IMessagePublisher` | Publica mensagens — `Publish(exchange, routingKey, body)` |
| `IMessagingFactory` | Cria `IMessageConsumer`/`IMessagePublisher` — implementada pelo adapter concreto |

`TMessagingConfig` carrega os parâmetros de conexão (Host, Port, User, Password, VHost) normalmente via `TAppConfig`.

`TMessagingRegistry` (`Messaging.Adapters.Registry.pas`) resolve o `IMessagingFactory` por nome — mesmo padrão de `Db.Adapters.Registry.TDBRegistry`. O projeto de negócio nunca referencia o pacote concreto do adapter, só a string do nome que ele registrou.

### Padrão de uso (consumidor)

```pascal
// No projeto — única classe que o negócio precisa implementar
TNotaFiscalHandler = class(TInterfacedObject, IMessageHandler)
public
  procedure Handle(const APayload: IMessagePayload);
end;

procedure TNotaFiscalHandler.Handle(const APayload: IMessagePayload);
var
  LJson: TJSONObject;
begin
  LJson := TJSONObject.ParseJSONValue(APayload.Body) as TJSONObject;
  try
    // processar LJson.GetValue<string>('chave') ...
  finally
    LJson.Free;
  end;
end;

// No DPR — montar config e iniciar consumer
LConfig          := TMessagingConfig.Create;
LConfig.Host     := TAppConfig.Get('RABBITMQ_HOST', 'localhost');
LConfig.Port     := TAppConfig.GetInt('RABBITMQ_PORT', 5672);
LConfig.User     := TAppConfig.Get('RABBITMQ_USER', 'guest');
LConfig.Password := TAppConfig.Get('RABBITMQ_PASSWORD', 'guest');
LConfig.VHost    := TAppConfig.Get('RABBITMQ_VHOST', '/');

// 'rabbitmq' é o nome que o adapter concreto usa para se registrar
LFactory  := TMessagingRegistry.GetFactory(TAppConfig.Get('MESSAGING_ADAPTER', 'rabbitmq'));
LConsumer := LFactory.CreateConsumer(LConfig);
LConsumer.Subscribe(TAppConfig.Get('RABBITMQ_QUEUE', ''), TNotaFiscalHandler.Create(LService));
LConsumer.Start;
// ...
LConsumer.Stop;
```

### Convenção de chaves no .env

```env
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
RABBITMQ_QUEUE=nome_da_queue
```

### Adapters disponíveis

O contrato (`Messaging.Interfaces.pas`) e o registro (`Messaging.Adapters.Registry.pas`) ficam nesta biblioteca. O adapter concreto fica **fora** dela, em pacote próprio — depende diretamente do componente AMQP escolhido, então não deve contaminar esta biblioteca open source com a licença/dependência de terceiros:

```
delphi-api-infra-faa/ (este repo — sem dependência de AMQP)
  src/Messaging/
    Messaging.Interfaces.pas          — interfaces (disponível)
    Messaging.Adapters.Registry.pas   — TMessagingRegistry (disponível)

delphi-amqp-faa/ (https://github.com/fabianoallex/delphi-amqp-faa — MIT)
  src/Messaging.Adapters.DelphiAmqpFaa.pas
                                      — implementa IMessagingFactory/IMessageConsumer/
                                        IMessagePublisher sobre AMQP.Connection;
                                        registra-se como 'rabbitmq' na própria
                                        unit initialization
```

Uso: search path do projeto precisa de `src/Messaging` desta biblioteca +
`src` de `delphi-amqp-faa`; incluir `Messaging.Adapters.DelphiAmqpFaa` no
`uses` já registra a factory (`TMessagingRegistry.GetFactory('rabbitmq')`).

### Anti-padrões a evitar

- Implementar lógica de negócio no adapter — o adapter só faz connect/subscribe/ack; a lógica fica no `IMessageHandler`
- Instanciar o adapter diretamente no handler — o handler recebe o service por injeção de dependência
- Referenciar o pacote do adapter concreto (ex.: unit do AMQP) fora da própria unit do adapter — o resto do código só conhece `TMessagingRegistry` + as interfaces
- Usar `TMessagingConfig` com valores hardcoded — sempre ler do `TAppConfig`

---

## Referências rápidas

As referências de domínio apontam para o template [delphi-api-starter](https://github.com/fabianoallex/delphi-api-starter), que contém o domínio `Exemplo` completo e funcional:

- DTO completo de referência: `src/Domain/Exemplo/Exemplo.DTOs.pas`
- Controller de referência: `src/Domain/Exemplo/Exemplo.Controller.pas`
- Repository de referência (paginação): `src/Domain/Exemplo/Exemplo.Repository.pas`
- DPR de referência: `Api.Starter.dpr`
- SQL de referência: `sql/EXEMPLO.FIND.sql`, `sql/EXEMPLO.FIND_COUNT.sql`
- Middleware de logging: `src/Middleware/Horse.Middleware.Logger.pas`
- Middleware de erros: `src/Middleware/Horse.Middleware.ErrorHandler.pas`
- Middleware de autenticação Bearer: `src/Middleware/Horse.Middleware.Auth.pas`
- Middleware JWT (HS256): `src/Middleware/Horse.Middleware.Jwt.pas`
- Middleware CORS: `src/Middleware/Horse.Middleware.Cors.pas`
- Middleware rate limiting: `src/Middleware/Horse.Middleware.RateLimit.pas`
- Health check: `src/Common/Common.HealthCheck.pas`

### Documentos de consulta pontual (não leia por padrão)

- `docs/lazarus-compat.md` — avaliação de compatibilidade com Lazarus/FPC: bloqueios, tiers de
  esforço, repo único vs projeto paralelo, e gatilhos de reavaliação. **Só abra se a tarefa for
  especificamente sobre porte/compatibilidade FPC** — a análise já está fechada (veredito:
  não portar sem consumidor FPC concreto), não precisa ser re-derivada.
