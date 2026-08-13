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

  // Executar COUNT e DATA em queries separadas (ver Exemplo.Repository no delphi-api-starter para referência completa)
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

Para `BuildItemsJson`, ver implementação em `Exemplo.Controller` no delphi-api-starter — padrão idêntico.
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

// Autenticação Bearer com API key (opcional) — deve vir APÓS o ErrorHandler
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
    fb.bat          — brcc32 fb.rc -fo fb.res
    MIG.0001.sql    — DDL Firebird  (terminador ^)
    PEDIDO.FIND.sql
    ...
  pg/
    pg.rc           — SQL_PG_MIG_0001, SQL_PG_PEDIDO_FIND ...
    pg.bat          — brcc32 pg.rc -fo pg.res
    MIG.0001.sql    — DDL PostgreSQL (terminador ;)
    PEDIDO.FIND.sql
    ...
```

O prefixo (`FB` / `PG`) é o `SQLDirectory` do `TFDConfig` e vira o segmento do meio no nome do resource: `SQL_<DIRECTORY>_<NOME>`. Ambos os `.res` ficam embutidos no executável via `{$R}`; em runtime, apenas os resources do dialeto ativo são acessados.

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
