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
7. Registrar cada SQL em `sql/queries.rc` e recompilar: `brcc32.exe -fo sql\queries.res sql\queries.rc`
8. No `begin` do DPR: montar as dependências (Repository → Service) e chamar `RegisterRoutes`
9. Registrar o endpoint MCP antes de `TRouteDoc.Serve` (ver padrão de inicialização)

---

## Padrão de DTO

### Regras absolutas

- Atributos `[SwagProp]`, `[SwagMin]`, `[SwagMax]`, `[SwagEnum]`, `[SwagPattern]` **sempre na classe**, nunca na interface — o RTTI de métodos de interface não é gerado pelo compilador
- Toda classe DTO **deve** ter `class constructor` com `TJsonMapper.RegisterMapping<I, T>` — sem isso, `FromJson`/`ToJson` falha silenciosamente em runtime
- O DPR **deve** ter `{$STRONGLINKTYPES ON}` — sem isso, o `class constructor` não é executado

### Hierarquia de base

| Operação | Interface herda | Classe herda |
|---|---|---|
| Response | `IResponseDTOBase` | `TResponseDTOBase` |
| Insert | `IInsertDTOBase` | `TInsertDTOBase` |
| Update (PATCH) | `IUpdateDTOBase` | `TUpdateDTOBase` |
| Find (paginado) | `IFindPaginationDTOBase` | `TFindPaginationDTOBase` |

`IFindPaginationDTOBase` já fornece `Page`, `Limit`, `OrderBy`, `Search` — não redeclare.

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

### Campos opcionais — Update (PATCH)

Todos os campos de um UpdateDTO são `IOptString`/`IOptInteger`. No getter, use `TOptionals.Safe`:

```pascal
function TPedidoUpdateDTO.GetStatus: IOptString;
begin
  Result := TOptionals.Safe(FStatus);
end;
```

No Service, cheque `Assigned` antes de validar o valor:

```pascal
if Assigned(ADto.Status) and (Trim(ADto.Status.Value) = '') then
  raise Exception.Create('Status não pode ser vazio.');
```

No Repository, cheque `ADto.Status.HasValue` antes de usar o valor.
No SQL de UPDATE, use `ProcessTag` para incluir/excluir campos condicionalmente.

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
```

- `${LIMIT}` / `${OFFSET}` / `${ORDER_BY}` — substituídos por `ReplaceLiteral`
- `[TAG { ... } TAG]` — bloco ativado/desativado por `ProcessTag('TAG', bool)`
- Parâmetros nomeados `:STATUS` — passados via `LQuery.Params.Strings['STATUS']`
- **INSERT com RETURNING**: chamar `LQuery.Open` (não `ExecSql`) — o FireDAC trata como SELECT

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
  LParams      := TPageParams.From(ADto.Page, ADto.Limit);
  LHasSearch   := Assigned(ADto) and Assigned(ADto.Search) and
                  ADto.Search.HasValue and (Trim(ADto.Search.Value) <> '');
  LOrderByExpr := '';
  if Assigned(ADto) and Assigned(ADto.OrderBy) and ADto.OrderBy.HasValue then
    LOrderByExpr := ADto.OrderBy.Value;

  LFindSql := FFactory.SqlLoader['PEDIDO.FIND']
    .ReplaceLiteral('LIMIT',    IntToStr(LParams.Limit))
    .ReplaceLiteral('OFFSET',   IntToStr(LParams.Offset))
    .ReplaceLiteral('ORDER_BY', OrderBySpec.Build(LOrderByExpr))
    .ProcessTag('SEARCH', LHasSearch);

  LCountSql := FFactory.SqlLoader['PEDIDO.FIND_COUNT']
    .ProcessTag('SEARCH', LHasSearch);

  // Executar COUNT e DATA em queries separadas (ver Cidade.Repository para referência completa)
end;
```

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
  .Register(handler);

TRouteDoc.Patch('/pedidos/:id')
  .Summary('Atualizar pedido (parcial)')
  .Tag('pedidos')
  .PathParam('id', 'ID do pedido', qptInteger)
  .Body<IPedidoUpdateDTO>('Campos a atualizar')
  .NoContent('204', 'Atualizado com sucesso')
  .NoContent('404', 'Pedido não encontrado')
  .Register(handler);
```

Para `BuildItemsJson`, ver implementação em `Cidade.Controller` — padrão idêntico.
`EOrderByException` não precisa ser capturada no handler — o `TErrorHandlerMiddleware` converte automaticamente para 400.

---

## Padrão de inicialização no DPR

```pascal
{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}   // obrigatório para RTTI dos DTOs

// Montar dependências
LService := TPedidoService.Create(TPedidoRepository.Create(LFactory));

// Health check — fora do Swagger e do MCP (registrar antes dos middlewares)
THealthCheck.Register(LFactory);

// Logger (opcional) — deve ser o PRIMEIRO: envolve todos os outros middlewares
// para capturar o status correto mesmo em respostas de erro
// THorse.Use(TLoggerMiddleware.New);                         // console
// THorse.Use(TLoggerMiddleware.New(procedure(const S: string) begin ... end));

// Middleware de erros — deve vir APÓS o Logger; captura exceções de todos os handlers seguintes
THorse.Use(TErrorHandlerMiddleware.New);

// Rate limiting (opcional) — deve vir APÓS o ErrorHandler; antes de RegisterRoutes
// THorse.Use(TRateLimitMiddleware.New(60, 60));   // 60 req/min por IP

// CORS (opcional) — deve vir APÓS o ErrorHandler; antes de RegisterRoutes
// THorse.Use(TCorsMiddleware.New);                          // dev: libera *
// THorse.Use(TCorsMiddleware.New('https://app.example.com')); // produção

// Autenticação Bearer (opcional) — deve vir APÓS o ErrorHandler
// THorse.Use(TAuthMiddleware.Bearer(
//   function(const AToken: string): Boolean
//   begin
//     Result := AToken = TAppConfig.Get('API_KEY', '');
//   end,
//   ['/health', '/swagger']));

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

## Anti-padrões a evitar

- Colocar lógica de negócio no Repository — validações vão no Service
- Omitir `class constructor` no DTO — o mapping não é registrado; falha silenciosa em runtime
- Omitir `{$STRONGLINKTYPES ON}` — o `class constructor` não é executado
- Colocar `[SwagProp]` na interface em vez da classe — o RTTI não existe na interface
- `ExecSql` em INSERT com RETURNING — use `Open`
- SQL inline no código — todo SQL vai em arquivo `.sql` + `queries.rc`
- Esquecer de recompilar `queries.res` após adicionar SQL novo
- `IOptional.Value` sem checar `HasValue` antes
- Chamar `LResult.Next` antes de checar `LResult.IsEmpty` — o padrão correto é `while not LResult.Eof`
- Registrar `TMcpServer` após `TRouteDoc.Serve` — o doc já foi liberado
- Lançar `Exception` genérica para erros de domínio — use as classes tipadas: `EValidationException` (400), `ENotFoundException` (404), `EConflictException` (409); o middleware converte automaticamente para o status correto

---

## Teste de conformação de DTOs (projeto consumidor)

Todo projeto concreto deve ter um fixture DUnitX que garanta que cada DTO tem seu mapeamento
registrado no `TJsonMapper`. Sem isso, `FromJson`/`ToJson` falha silenciosamente em runtime.

```pascal
// tests/Unit/DTOConformanceTests.pas
[TestFixture]
TDTOConformanceTests = class
public
  [Test]
  procedure AllDTOs_HaveJsonMapping;
end;

procedure TDTOConformanceTests.AllDTOs_HaveJsonMapping;
var
  LCtx:   TRttiContext;
  LType:  TRttiType;
  LImpl:  TClass;
begin
  LCtx := TRttiContext.Create;
  try
    for LType in LCtx.GetTypes do
    begin
      if not (LType is TRttiInstanceType) then Continue;
      if not LType.AsInstance.MetaclassType.InheritsFrom(TDTOBase) then Continue;
      if LType.AsInstance.MetaclassType = TDTOBase then Continue; // pula base abstrata

      LImpl := TJsonMapper.FindImplClass(LType.Handle);
      Assert.IsNotNull(LImpl,
        LType.Name + ' herda de TDTOBase mas não tem RegisterMapping registrado');
    end;
  finally
    LCtx.Free;
  end;
end;
```

**Pré-requisitos:** `{$STRONGLINKTYPES ON}` no DPR do projeto e todas as units de DTO na seção `uses`
— sem isso os `class constructor` não são executados e o teste sempre passa em falso positivo.

---

## Referências rápidas

- DTO completo de referência: `src/Domain/Cidade/Cidade.DTOs.pas`
- Controller de referência: `src/Domain/Cidade/Cidade.Controller.pas`
- Repository de referência (paginação): `src/Domain/Cidade/Cidade.Repository.pas`
- Template de projeto novo: https://github.com/fabianoallex/delphi-api-starter (domínio Exemplo completo, submodules pré-configurados)
- DPR de referência: `Api.Test.dpr` (na raiz do projeto consumidor)
- SQL de referência: `sql/CIDADE.FIND.sql`, `sql/CIDADE.FIND_COUNT.sql`
- Middleware de logging: `src/Middleware/Horse.Middleware.Logger.pas`
- Middleware de erros: `src/Middleware/Horse.Middleware.ErrorHandler.pas`
- Middleware de autenticação: `src/Middleware/Horse.Middleware.Auth.pas`
- Middleware CORS: `src/Middleware/Horse.Middleware.Cors.pas`
- Middleware rate limiting: `src/Middleware/Horse.Middleware.RateLimit.pas`
- Health check: `src/Common/Common.HealthCheck.pas`
