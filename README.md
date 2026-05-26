# delphi-api-infra-faa

Biblioteca de infraestrutura para APIs Delphi. Fornece tipos opcionais/anuláveis, serialização JSON, pool de conexões, carregamento de SQL, documentação Swagger e exposição de tools MCP.

O acesso a banco de dados é agnóstico: a camada de abstração (`Db.Interfaces`) desacopla a lógica da aplicação de qualquer componente ou banco. Inclui um adaptador FireDAC pronto para uso (Firebird, PostgreSQL e outros bancos suportados pelo FireDAC), e a arquitetura permite registrar adaptadores para qualquer outro componente (Zeos, UniDAC, dbExpress, etc.) implementando as interfaces de `Db.Interfaces`.

## Conteúdo

```
src/
  Common/
    Common.Optionals.pas      — IOptXxx, INullXxx, IOptNullXxx (9 tipos base)
    Common.JsonMapper.pas     — TJsonMapper: FromJson<I> / ToJson<I> (saída camelCase)
    Common.DTO.Base.pas       — IDTOBase e hierarquia de interfaces/classes base para DTOs
    Common.Helpers.pas        — Helpers de Variant e TParams para Optionals
    Common.ClockCache.pas     — Cache flyweight thread-safe dos Optional values
    Common.SystemContext.pas  — TClock e TSleep injetáveis (testabilidade)
    Common.OrderBy.pas        — TOrderBySpec: ordenação segura com whitelist, tiebreaker e DocHint
    Common.Pagination.pas     — TPageMeta, TPageParams: paginação padronizada com WrapJson
    Common.Config.pas         — TAppConfig: leitura de env vars com fallback para app.ini
    Common.HealthCheck.pas    — THealthCheck: registra GET /health com verificação de banco
  Db/
    Db.Interfaces.pas         — IDBConnection, IDBConnectionPool, ITransaction, IQuery, IMigrationDialect
    Db.Connection.Pool.pas    — TConnectionPool thread-safe com timeout e inatividade
    Db.SqlLoader.pas          — TSQLResult (ProcessTag, ApplyFilter, ReplaceLiteral)
    Db.SqlDialect.pas         — TFirebirdDialect, TPostgreSQLDialect (ISQLDialect + IMigrationDialect)
    Db.Migrations.pas         — TMigrationItem, TDBMigrationEngine
    Db.Adapters.FireDAC.pas   — Adapter FireDAC (agnóstico ao driver)
    Db.Adapters.Registry.pas  — TDBRegistry: registro de factories por nome
    Db.Constants.pas          — Constantes de configuração do pool
  Swagger/
    Swagger.Attributes.pas    — [SwagProp], [SwagMin], [SwagMax], [SwagEnum], [SwagPattern]: atributos de schema
    Swagger.Builder.pas       — TRouteDoc / TRouteDocBuilder: builder fluente de rotas + doc
    Swagger.Server.pas        — TSwaggerServer: serve JSON spec e Swagger UI via Horse
  MCP/
    MCP.Server.pas            — TMcpServer: expõe rotas do TSwagDoc como tools MCP (HTTP JSON-RPC 2.0)
    MCP.Utils.pas             — McpDeriveName, McpMatchesTags (utilitários sem dependência Horse)
  Middleware/
    Horse.Middleware.ErrorHandler.pas — TErrorHandlerMiddleware + hierarquia EHttpException
tests/
  Unit/         — testes unitários (DUnitX) — Infra.UnitTests.dpr
  Integration/  — testes com banco Firebird real — Infra.IntegrationTests.dpr
```

---

## Usando como submodule

### Adicionar ao seu projeto

Na raiz do repositório do seu projeto:

```bash
git submodule add https://github.com/fabianoallex/delphi-api-infra-faa infra
```

Isso cria a pasta `infra/` com todo o código da biblioteca e registra o submodule no `.gitmodules`.

### Clonar um projeto que já usa este submodule

```bash
git clone --recurse-submodules <url-do-seu-projeto>
```

### Atualizar o submodule para a versão mais recente

```bash
git submodule update --remote infra
git add infra
git commit -m "chore: atualiza infra"
```

---

## Configurando o projeto Delphi

### 1. Search path no DPROJ

Adicione ao `DCC_UnitSearchPath` do seu `.dproj`:

```
infra\src\Common;infra\src\Db;infra\src\Swagger;infra\src\MCP;infra\src\Middleware;infra\modules\swag-doc\Source
```

### 2. Referências explícitas no DPR

```pascal
uses
  Common.Optionals     in 'infra\src\Common\Common.Optionals.pas',
  Common.JsonMapper    in 'infra\src\Common\Common.JsonMapper.pas',
  Common.Helpers       in 'infra\src\Common\Common.Helpers.pas',
  Common.ClockCache    in 'infra\src\Common\Common.ClockCache.pas',
  Common.SystemContext in 'infra\src\Common\Common.SystemContext.pas',
  Db.Interfaces        in 'infra\src\Db\Db.Interfaces.pas',
  Db.Connection.Pool   in 'infra\src\Db\Db.Connection.Pool.pas',
  Db.SqlLoader         in 'infra\src\Db\Db.SqlLoader.pas',
  Db.SqlDialect        in 'infra\src\Db\Db.SqlDialect.pas',
  Db.Adapters.Registry in 'infra\src\Db\Db.Adapters.Registry.pas',
  Db.Adapters.FireDAC  in 'infra\src\Db\Db.Adapters.FireDAC.pas',
  Db.Constants         in 'infra\src\Db\Db.Constants.pas',
  // Swagger (opcional — incluir apenas se o projeto usa TRouteDoc)
  Swagger.Attributes   in 'infra\src\Swagger\Swagger.Attributes.pas',
  Swagger.Builder      in 'infra\src\Swagger\Swagger.Builder.pas',
  Swagger.Server       in 'infra\src\Swagger\Swagger.Server.pas',
  // MCP (opcional — incluir apenas se o projeto expõe tools MCP)
  MCP.Server           in 'infra\src\MCP\MCP.Server.pas',
  // Middleware (opcional — incluir conforme necessário)
  Horse.Middleware.ErrorHandler in 'infra\src\Middleware\Horse.Middleware.ErrorHandler.pas';
```

### 3. Units FireDAC obrigatórias

O FireDAC usa `initialization` de cada unit para registrar suas factories internas. A ausência de qualquer uma dessas units causa erros de "Object factory missing" em runtime — não em compilação.

```pascal
uses
  Winapi.Windows,          // necessário para SetDllDirectory
  FireDAC.Stan.Def,        // definições e factories base
  FireDAC.Stan.Pool,       // suporte a pool de conexões
  FireDAC.Stan.Async,      // operações assíncronas
  FireDAC.Stan.ExprFuncs,  // funções de expressão
  FireDAC.UI.Intf,         // interface abstrata de wait cursor
  FireDAC.ConsoleUI.Wait,  // wait cursor para {$APPTYPE CONSOLE}
                           // Para {$APPTYPE GUI}: usar FireDAC.VCLUI.Wait
  FireDAC.Phys,            // camada física base
  FireDAC.Phys.FB,         // driver Firebird (ou FireDAC.Phys.PG para PostgreSQL)
  FireDAC.DApt;            // factory do TFDQuery (obrigatório para Open/ExecSQL)
```

### 4. fbclient.dll no Windows 64-bit

Em instalações 64-bit do Windows, a `fbclient.dll` 32-bit fica em `WOW64\`, fora do PATH do sistema. O parâmetro `VendorLib` no `ConnectionParams` **não funciona** para o driver FB — o FireDAC carrega a DLL antes de ler os parâmetros de conexão. A solução é chamar `SetDllDirectory` no início do `begin` do DPR, antes de qualquer operação FireDAC:

```pascal
begin
  SetDllDirectory('C:\Program Files\Firebird\Firebird_2_5\WOW64');
  // ... restante da inicialização
end.
```

### 5. Recursos SQL (TSQLLoader)

O `Db.SqlLoader` não embute recursos — cada projeto fornece os seus. Adicione ao DPR:

```pascal
{$R 'src\Db\sql\queries.res'}
```

E compile o arquivo de recursos com:

```bash
brcc32.exe -fo src\Db\sql\queries.res src\Db\sql\queries.rc
```

### 6. Submodule swag-doc

O módulo Swagger depende de [SwagDoc](https://github.com/marcelojaloto/SwagDoc) como nested submodule dentro de `infra/`. Ao clonar o projeto que usa esta infra, inicialize todos os submodules recursivamente:

```bash
git submodule update --init --recursive
```

---

## DTO Base

O módulo `Common.DTO.Base` define a hierarquia de interfaces e classes base para todos os DTOs da aplicação. Fornece tipagem semântica, suporte a paginação e uma convenção de auto-registro no `TJsonMapper`.

### Hierarquia

```
IDTOBase
├── IResponseDTOBase
│   └── IResponsePaginationDTOBase   — resposta paginada (Page, Limit, Total: Integer)
├── IInsertDTOBase
├── IUpdateDTOBase
├── IDeleteDTOBase
└── IFindPaginationDTOBase           — consulta paginada (Page, Limit: IOptInteger;
                                        OrderBy, Search: IOptString)
```

As interfaces de marcador (`IResponseDTOBase`, `IInsertDTOBase`, etc.) não adicionam métodos — definem a intenção semântica do DTO e habilitam testes de conformação por RTTI.

### Convenção de uso

```pascal
// Interface herda o marcador semântico correto
IProdutoResponseDTO = interface(IResponseDTOBase)
  ['{...}']
  function GetId: Integer;
  function GetNome: string;
  property Id: Integer read GetId;
  property Nome: string read GetNome;
end;

// Classe herda a classe base correspondente e registra o mapeamento
TProdutoResponseDTO = class(TResponseDTOBase, IProdutoResponseDTO)
public
  class constructor Create;  // auto-registro no TJsonMapper
  [SwagProp('ID do produto', '1')]
  function GetId: Integer;
  [SwagProp('Nome do produto', 'Arroz')]
  function GetNome: string;
end;

class constructor TProdutoResponseDTO.Create;
begin
  TJsonMapper.RegisterMapping<IProdutoResponseDTO, TProdutoResponseDTO>;
end;
```

### DTO com paginação

```pascal
// Find — parâmetros de consulta (todos opcionais)
IProdutoFindDTO = interface(IFindPaginationDTOBase)
  ['{...}']
  function GetNome: IOptString;
  property Nome: IOptString read GetNome;
end;

TProdutoFindDTO = class(TFindPaginationDTOBase, IProdutoFindDTO)
public
  class constructor Create;
  function GetNome: IOptString;
end;

// Response paginado — metadados + itens específicos do domínio
IProdutoListResponseDTO = interface(IResponsePaginationDTOBase)
  ['{...}']
  // Page, Limit, Total já estão na interface base
  // Adicionar aqui os itens: ex. GetItems: TArray<IProdutoResponseDTO>
end;
```

---

## Configuração (TAppConfig)

O módulo `Common.Config` resolve configuração em três níveis, em ordem de prioridade:

1. **Variável de ambiente** — ideal para containers e CI/CD
2. **Arquivo `app.ini`** — para desenvolvimento local (nunca commitar credenciais)
3. **Valor default** embutido no código — fallback seguro

O arquivo ini é buscado automaticamente no diretório do executável com o nome `app.ini`, seção `[Config]`. O caminho pode ser substituído via `TAppConfig.SetIniFile` (útil em testes).

### Uso

```pascal
uses Common.Config;

// No DPR, antes de qualquer inicialização:
SetDllDirectory(TAppConfig.Get('FB_CLIENT_DIR',
  'C:\Program Files\Firebird\Firebird_2_5\WOW64'));

LConfig.ConnectionParams.Add('Database=' +
  TAppConfig.Get('DB_PATH', 'C:\meu-banco.fdb'));
LConfig.ConnectionParams.Add('User_Name=' +
  TAppConfig.Get('DB_USER', 'SYSDBA'));
LConfig.ConnectionParams.Add('Password=' +
  TAppConfig.Get('DB_PASSWORD', 'masterkey'));

THorse.Listen(TAppConfig.GetInt('SERVER_PORT', 9000));
```

### Métodos

| Método | Retorno | Descrição |
|---|---|---|
| `Get(key, default)` | `string` | Lê env var → ini → default |
| `GetInt(key, default)` | `Integer` | Mesmo fluxo; default se não parseável |
| `GetBool(key, default)` | `Boolean` | Aceita `true`, `1`, `yes` (case-insensitive) |
| `SetIniFile(path, section)` | — | Substitui o arquivo ini (padrão: `app.ini` ao lado do exe) |

### Exemplo de `app.ini`

```ini
[Config]
FB_CLIENT_DIR=C:\Program Files\Firebird\Firebird_2_5\WOW64
DB_PATH=C:\meu-banco\banco.fdb
DB_USER=SYSDBA
DB_PASSWORD=masterkey
SERVER_PORT=9000
BASE_URL=http://localhost:9000
```

> Adicione `app.ini` ao `.gitignore` para não commitar credenciais. Versione apenas um `app.ini.example` com valores de placeholder.

---

## Swagger

O módulo Swagger integra documentação OpenAPI 2.0 (Swagger) diretamente no registro de rotas do Horse. Uma única cadeia fluente define a rota, os parâmetros, o schema de entrada/saída e a documentação — sem nenhum arquivo de configuração separado.

### Fluxo de uso

```pascal
// 1. Inicializar o doc (antes de registrar as rotas)
TRouteDoc.Init('Minha API', '1.0.0', 'localhost:9000');

// 2. Registrar rotas — documenta e registra no Horse ao mesmo tempo
TRouteDoc.Get('/produtos')
  .Summary('Listar produtos')
  .Tag('produtos')
  .ResponseArray<IProdutoResponseDTO>('200', 'Lista de produtos')
  .Register(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      // handler
    end);

TRouteDoc.Post('/produtos')
  .Summary('Criar produto')
  .Tag('produtos')
  .Body<IProdutoInsertDTO>('Dados do produto')
  .Response<IProdutoResponseDTO>('201', 'Produto criado')
  .Register(handler);

TRouteDoc.Patch('/produtos/:id')
  .Summary('Atualizar produto')
  .Tag('produtos')
  .PathParam('id', 'ID do produto')
  .Body<IProdutoUpdateDTO>('Campos a atualizar')
  .NoContent('204', 'Atualizado')
  .NoContent('404', 'Não encontrado')
  .Register(handler);

TRouteDoc.Delete('/produtos/:id')
  .Summary('Excluir produto')
  .Tag('produtos')
  .PathParam('id', 'ID do produto')
  .NoContent('204', 'Excluído')
  .Register(handler);

// 3. Publicar Swagger UI + JSON (serializa e libera o doc interno)
TRouteDoc.Serve('/swagger');

// 4. Iniciar o servidor
THorse.Listen(9000);
// → http://localhost:9000/swagger      (Swagger UI)
// → http://localhost:9000/swagger/doc.json  (OpenAPI JSON)
```

### Métodos do builder

| Método | Descrição |
|---|---|
| `.Summary(text)` | Título curto da operação |
| `.Descr(text)` | Descrição longa |
| `.Tag(tag)` | Agrupa a rota na UI por tag (pode ser chamado N vezes) |
| `.PathParam(name, desc, type)` | Parâmetro de path (`:id` → `{id}`); `type`: `qptString` (padrão) ou `qptInteger` |
| `.QueryParam(name, desc, type)` | Parâmetro de query string; `type`: `qptString` (padrão) ou `qptInteger` |
| `.Body<I>(desc)` | Corpo da requisição — gera schema a partir do DTO |
| `.Response<I>(code, desc)` | Resposta com schema de objeto |
| `.ResponseArray<I>(code, desc)` | Resposta com schema de array |
| `.ResponsePaged<I>(code, desc)` | Resposta com envelope de paginação (`page`, `limit`, `total`, `items`) |
| `.NoContent(code, desc)` | Resposta sem corpo (204, 404, etc.) |
| `.ToolName(name)` | Nome explícito da tool MCP gerada — sobrescreve a derivação automática (útil para plurais irregulares) |
| `.NoMcp` | Exclui a rota das tools MCP; continua registrada no Horse e documentada no Swagger |
| `.Register(handler)` | Finaliza: registra no Horse e no doc; libera o builder |

### Schemas automáticos via RTTI

O schema de cada DTO é gerado automaticamente a partir dos métodos `Get*` da **classe de implementação** (não da interface). O tipo de retorno de cada getter determina o tipo JSON:

| Tipo Delphi | Tipo JSON | Format |
|---|---|---|
| `string` | `string` | — |
| `Integer` | `integer` | `int32` |
| `Int64` | `integer` | `int64` |
| `Double` | `number` | `double` |
| `Single` | `number` | `float` |
| `Currency` | `number` | — |
| `Boolean` | `boolean` | — |
| `TDateTime` | `string` | `date-time` |
| `TGUID` | `string` | `uuid` |
| `IOptXxx` | tipo base | campo marcado como opcional |
| `INullXxx` | tipo base | `nullable: true` |
| `IOptNullXxx` | tipo base | opcional + `nullable: true` |

Os nomes de propriedade são emitidos em **camelCase** automaticamente: o getter `GetCodIbge` gera a chave `codIbge` no JSON e no schema Swagger. Nenhuma configuração extra é necessária.

### Atributos de schema

Aplique nos métodos `Get*` da **classe de implementação** para enriquecer o schema com metadados e restrições. Todos são opcionais e combináveis no mesmo método.

> **Importante:** os atributos devem estar na **classe** (`TProdutoInsertDTO`), não na interface. O schema é gerado via RTTI da classe concreta — o RTTI de métodos de interface não é gerado pelo compilador por padrão.

#### `[SwagProp]` — descrição, exemplo e formato

```pascal
[SwagProp('descrição')]
[SwagProp('descrição', 'exemplo')]
[SwagProp('descrição', 'exemplo', 'formato')]  // formato: 'email', 'uri', 'date', etc.
```

O campo `exemplo` é emitido com o tipo JSON correto: `'1'` vira `1` (number), `'true'` vira `true` (boolean), strings ficam como string. No MCP, o exemplo é incorporado na `description` da propriedade (`"desc. Ex: valor"`).

#### `[SwagMin]` / `[SwagMax]` — restrições numéricas e de comprimento

O atributo escolhe automaticamente a chave correta com base no tipo do campo:

| Tipo do campo | `[SwagMin(N)]` | `[SwagMax(N)]` |
|---|---|---|
| `string` | `"minLength": N` | `"maxLength": N` |
| `integer`, `number` | `"minimum": N` | `"maximum": N` |

#### `[SwagEnum]` — lista de valores válidos

```pascal
[SwagEnum('ativo,inativo,suspenso')]  →  "enum": ["ativo", "inativo", "suspenso"]
```

Valores separados por vírgula; espaços em volta da vírgula são ignorados.

#### `[SwagPattern]` — validação por regex

```pascal
[SwagPattern('^[A-Z]{2}$')]  →  "pattern": "^[A-Z]{2}$"
```

#### Exemplo completo

```pascal
TProdutoInsertDTO = class(TInsertDTOBase, IProdutoInsertDTO)
public
  [SwagProp('Nome do produto', 'Arroz')]
  [SwagMin(1)]
  [SwagMax(100)]
  function GetNome: string;

  [SwagProp('Status', 'ativo')]
  [SwagEnum('ativo,inativo,suspenso')]
  function GetStatus: string;

  [SwagProp('Código UF', 'SP')]
  [SwagPattern('^[A-Z]{2}$')]
  function GetUf: string;

  [SwagProp('Preço', '9.90')]
  [SwagMin(0)]
  function GetPreco: Double;

  [SwagProp('Quantidade', '10')]
  [SwagMin(0)]
  [SwagMax(9999)]
  function GetQuantidade: Integer;
end;
```

Schema gerado:

```json
{
  "nome":       { "type": "string",  "description": "Nome do produto", "minLength": 1, "maxLength": 100 },
  "status":     { "type": "string",  "description": "Status",          "enum": ["ativo", "inativo", "suspenso"] },
  "uf":         { "type": "string",  "description": "Código UF",       "pattern": "^[A-Z]{2}$" },
  "preco":      { "type": "number",  "description": "Preço",           "minimum": 0 },
  "quantidade": { "type": "integer", "description": "Quantidade",      "minimum": 0, "maximum": 9999 }
}
```

No `inputSchema` MCP, o campo `additionalProperties: false` é adicionado automaticamente a todo schema gerado.

---

## Health check

O módulo `Common.HealthCheck` registra um endpoint `GET /health` diretamente no Horse, **fora do Swagger e do MCP**. Isso evita que o endpoint apareça na documentação da API ou vire uma tool MCP.

A verificação cria uma conexão temporária via `IDBFactory.CreateConnection`, chama `TestConnection`, e a descarta — sem consumir conexões do pool.

### Registro

Chame após criar a factory e antes de `TRouteDoc.Init`:

```pascal
uses
  Common.HealthCheck in 'infra\src\Common\Common.HealthCheck.pas';

begin
  LFactory := TFDFactory.Create(LConfig, nil);
  THealthCheck.Register(LFactory);          // ← GET /health
  THorse.Use(TErrorHandlerMiddleware.New);
  TRouteDoc.Init(...);
  // ...
end.
```

### Respostas

| Situação | Status | Corpo |
|---|---|---|
| Banco acessível | 200 | `{"status":"ok"}` |
| Falha de conexão / timeout | 503 | `{"status":"degraded","detail":"<mensagem>"}` |

```bash
curl http://localhost:9000/health
# {"status":"ok"}
```

O path padrão é `/health`. Para usar outro:

```pascal
THealthCheck.Register(LFactory, '/status');
```

---

## Middleware de tratamento de erros

O módulo `Horse.Middleware.ErrorHandler` centraliza o tratamento de exceções não capturadas. Sem ele, cada controller precisa de um `try/except` próprio, e exceções inesperadas chegam ao cliente como `500` sem corpo JSON.

### Registro

Chame `THorse.Use` **antes** de registrar as rotas:

```pascal
uses
  Horse.Middleware.ErrorHandler in 'infra\src\Middleware\Horse.Middleware.ErrorHandler.pas';

begin
  THorse.Use(TErrorHandlerMiddleware.New);   // ← antes de qualquer RegisterRoutes
  TRouteDoc.Init('Minha API', '1.0.0', 'localhost:9000');
  TProdutoController.RegisterRoutes(LService);
  // ...
  TRouteDoc.Serve('/swagger');
  THorse.Listen(9000);
end.
```

### Hierarquia de exceções

Lance a classe correta no Service ou Repository — o middleware converte automaticamente para o status HTTP correspondente:

| Classe | Status | Quando usar |
|---|---|---|
| `EValidationException` | 400 | Campo inválido, regra de negócio violada |
| `ENotFoundException` | 404 | Registro não encontrado pelo ID informado |
| `EConflictException` | 409 | Violação de unicidade, estado incompatível |
| `EOrderByException` | 400 | Ordenação por campo não permitido (gerada internamente pelo `TOrderBySpec`) |
| `EHttpException` | custom | Qualquer outro status — `EHttpException.Create(status, msg)` |
| `Exception` | 500 | Qualquer exceção não mapeada |

```pascal
// No Service:
function TProdutoService.FindById(AId: Integer): IProdutoResponseDTO;
begin
  Result := FRepository.FindById(AId);
  if not Assigned(Result) then
    raise ENotFoundException.Create('Produto não encontrado.');
end;

procedure TProdutoService.Insert(ADto: IProdutoInsertDTO);
begin
  if Trim(ADto.Nome.Value) = '' then
    raise EValidationException.Create('Nome é obrigatório.');
  // ...
end;
```

### Formato da resposta de erro

Todos os erros retornam `Content-Type: application/json` com o envelope:

```json
{ "error": "mensagem descritiva" }
```

A mensagem é obtida de `E.Message` da exceção capturada — use mensagens orientadas ao usuário final nas classes `EValidationException`, `ENotFoundException` e `EConflictException`.

---

## MCP (Model Context Protocol)

O módulo MCP expõe as rotas documentadas no `TSwagDoc` como **tools MCP** sobre HTTP JSON-RPC 2.0. Com uma única chamada, o servidor passa a ser operável por agentes de IA compatíveis com o protocolo MCP.

### Fluxo de uso

```pascal
// Após registrar as rotas com TRouteDoc e antes de TRouteDoc.Serve:
TMcpServer.Register(
  TRouteDoc.CurrentDoc,    // doc com as rotas documentadas
  '/mcp',                  // endpoint MCP (POST)
  'http://localhost:9000', // base URL para o agente chamar de volta
  'Minha API',             // serverInfo.name
  '1.0.0'                  // serverInfo.version
);

TRouteDoc.Serve('/swagger');
THorse.Listen(9000);
// → POST http://localhost:9000/mcp  (endpoint MCP JSON-RPC 2.0)
```

### Métodos JSON-RPC suportados

| Método | Descrição |
|---|---|
| `initialize` | Handshake — retorna `protocolVersion`, `capabilities` e `serverInfo` |
| `notifications/initialized` | Notificação do cliente — sem resposta (fire-and-forget) |
| `tools/list` | Retorna a lista de tools geradas a partir das rotas documentadas |
| `tools/call` | Executa uma tool: faz HTTP call de volta ao servidor e retorna o resultado |

### Geração automática de tools

Cada rota documentada vira uma tool MCP:

| Rota | Tool gerada |
|---|---|
| `GET /produtos` | `list_produto` |
| `POST /produtos` | `create_produto` |
| `GET /produtos/{id}` | `get_produto` |
| `PATCH /produtos/{id}` | `update_produto` |
| `DELETE /produtos/{id}` | `delete_produto` |

- **Nome** derivado do método HTTP + último segmento do path, no singular (strip do `s` final por palavra)
- **description** mapeada do `.Summary()` da rota
- **inputSchema** gerado dos parâmetros de path e do body (via `TSwagDoc`)
- Exemplos do `[SwagProp]` são incorporados no `description` da propriedade (`"desc. Ex: valor"`)
- Propriedades do schema em **camelCase** (segue a serialização JSON)

#### Override de nome com `.ToolName()`

A derivação automática falha para plurais irregulares ou compostos (`operações`, `perfis`, `animais`). Use `.ToolName()` para definir o nome explicitamente:

```pascal
TRouteDoc.Get('/operacoes')
  .Summary('Listar operações')
  .Tag('operacoes')
  .ToolName('list_operacao')   // ← sobrescreve a derivação automática
  .ResponseArray<IOperacaoDTO>('200', 'OK')
  .Register(handler);
```

O nome informado é gravado no campo `operationId` do Swagger (campo padrão OpenAPI), aparecendo também na UI do Swagger.

### Múltiplos endpoints por domínio

`TMcpServer.Register` pode ser chamado várias vezes para expor subconjuntos de tools filtrados por tag:

```pascal
// Endpoint geral — todas as tools (debug / agente generalista)
TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp', 'http://localhost:9000', 'API', '1.0.0');

// Endpoints por domínio — filtrados pela tag registrada com .Tag()
var LTags := TStringList.Create;
try
  LTags.Add('produtos');
  TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp/produtos',
    'http://localhost:9000', 'API', '1.0.0', nil, LTags);

  LTags.Clear;
  LTags.Add('cidades');
  TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp/cidades',
    'http://localhost:9000', 'API', '1.0.0', nil, LTags);
finally
  LTags.Free;
end;

TRouteDoc.Serve('/swagger');
THorse.Listen(9000);
// → POST /mcp          todas as tools
// → POST /mcp/produtos tools com tag "produtos"
// → POST /mcp/cidades  tools com tag "cidades"
```

Cada endpoint mantém sua própria lista de tools isolada. O parâmetro `AExcluded` (penúltimo) aceita a lista de `TRouteDoc.McpExcluded` para omitir rotas marcadas com `.NoMcp`.

### Exemplo de resposta do tools/list

```json
{
  "name": "create_produto",
  "description": "Criar produto",
  "inputSchema": {
    "type": "object",
    "properties": {
      "nome": { "type": "string", "description": "Nome do produto. Ex: Arroz" }
    },
    "required": ["nome"]
  }
}
```

---

## Migrations

O `Db.Migrations` fornece um engine de migrations baseado em **append-only immutable log**: scripts nunca são alterados após publicados em produção. Suporta Firebird e PostgreSQL via `IMigrationDialect` (implementado em ambos os dialetos da infra).

### Funcionamento

- A primeira migration do projeto deve criar a tabela `SCHEMA_MIGRATIONS`
- O engine verifica automaticamente a versão atual e aplica apenas as pendentes
- Cada migration roda em sua própria transação — falhas não desfazem as anteriores
- DDL no Firebird faz auto-commit (comportamento nativo do banco)

### Estrutura mínima da tabela de controle

```sql
-- Firebird (colocar no script MIG.0001):
CREATE TABLE SCHEMA_MIGRATIONS (
  VERSION    INTEGER   NOT NULL,
  APPLIED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT PK_SCHEMA_MIGRATIONS PRIMARY KEY (VERSION)
);

-- PostgreSQL (colocar no script MIG.0001):
CREATE TABLE IF NOT EXISTS schema_migrations (
  version    INTEGER   NOT NULL,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT pk_schema_migrations PRIMARY KEY (version)
);
```

### Uso no projeto

```pascal
uses
  Db.Migrations in 'infra\src\Db\Db.Migrations.pas';

const
  MIGRATIONS: array[0..2] of TMigrationItem = (
    (Version: 1; ScriptName: 'MIG.0001'; ParamReplaceProc: nil; Terminator: ';'; IsDDL: True),
    (Version: 2; ScriptName: 'MIG.0002'; ParamReplaceProc: nil; Terminator: ';'; IsDDL: True),
    (Version: 3; ScriptName: 'MIG.0003'; ParamReplaceProc: @MIG_0003Params; Terminator: '&'; IsDDL: False)
  );

// Na inicialização da aplicação, antes de iniciar o servidor:
var LEngine := TDBMigrationEngine.Create(TDBRegistry.GetFactory('meu_banco'));
LEngine.Execute(MIGRATIONS);
LEngine.Free;
```

O campo `IsDDL` indica se o script contém instruções DDL (`CREATE TABLE`, `ALTER TABLE`, etc.). Scripts DDL são executados em transação separada do registro de versão — necessário porque em Firebird o DDL auto-commita a transação ativa. Scripts DML (`IsDDL: False`) executam script e registro de versão em uma única transação atômica.

O campo `Terminator` define o separador de statements dentro do script (`;` para SQL padrão, `&` ou outro caractere quando o script contém blocos que já usam `;` internamente, como stored procedures no Firebird).

O `ParamReplaceProc` é um callback opcional para substituir placeholders no script antes da execução — útil para seeds com senhas hasheadas ou valores de ambiente:

```pascal
procedure MIG_0003Params(AScript: TStrings);
begin
  AScript.Text := StringReplace(AScript.Text, ':ADMIN_EMAIL',
    QuotedStr(GetEnvOrDefault('ADMIN_EMAIL', 'admin@exemplo.com')), [rfReplaceAll]);
end;
```

---

## Suporte a bancos de dados

O adaptador FireDAC (`Db.Adapters.FireDAC`) é agnóstico ao driver — o banco é definido pelo `DriverID` nos parâmetros de conexão. Os dialetos SQL (`Db.SqlDialect`) para savepoints já estão registrados para Firebird e PostgreSQL.

### Firebird

No DPR do projeto, inclua o driver FireDAC:

```pascal
uses
  FireDAC.Phys.FB;
```

Arquivo de configuração (`.ini` ou equivalente):

```ini
[Database]
DriverID=FB
Database=C:\caminho\para\banco.fdb
User_Name=SYSDBA
Password=masterkey
CharacterSet=UTF8
VendorLib=C:\Program Files\Firebird\Firebird_2_5\WOW64\fbclient.dll

[Options]
SQLDialect=Firebird
```

### PostgreSQL

No DPR do projeto, inclua o driver FireDAC:

```pascal
uses
  FireDAC.Phys.PG;
```

Arquivo de configuração:

```ini
[Database]
DriverID=PG
Database=meu_banco
Server=localhost
Port=5432
User_Name=postgres
Password=senha
CharacterSet=UTF8

[Options]
SQLDialect=PostgreSQL
```

> Os dois bancos podem coexistir no mesmo binário — basta registrar duas factories no `TDBRegistry` com nomes distintos e incluir ambos os units de driver no DPR.

### Outros componentes de acesso a dados

A arquitetura é extensível: qualquer componente (Zeos, UniDAC, dbExpress, etc.) pode ser suportado implementando as interfaces `IDBConnection`, `IDBConnectionPool`, `ITransaction` e `IQuery` definidas em `Db.Interfaces.pas` e registrando a factory no `TDBRegistry`.

---

## Licença

MIT — consulte o arquivo [LICENSE](LICENSE).
