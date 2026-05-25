# delphi-api-infra-faa

Biblioteca de infraestrutura para APIs Delphi. Fornece tipos opcionais/anuláveis, serialização JSON, pool de conexões, carregamento de SQL, documentação Swagger e exposição de tools MCP.

O acesso a banco de dados é agnóstico: a camada de abstração (`Db.Interfaces`) desacopla a lógica da aplicação de qualquer componente ou banco. Inclui um adaptador FireDAC pronto para uso (Firebird, PostgreSQL e outros bancos suportados pelo FireDAC), e a arquitetura permite registrar adaptadores para qualquer outro componente (Zeos, UniDAC, dbExpress, etc.) implementando as interfaces de `Db.Interfaces`.

## Conteúdo

```
src/
  Common/
    Common.Optionals.pas      — IOptXxx, INullXxx, IOptNullXxx (9 tipos base)
    Common.JsonMapper.pas     — TJsonMapper: FromJson<I> / ToJson<I>
    Common.Helpers.pas        — Helpers de Variant e TParams para Optionals
    Common.ClockCache.pas     — Cache flyweight thread-safe dos Optional values
    Common.SystemContext.pas  — TClock e TSleep injetáveis (testabilidade)
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
    Swagger.Attributes.pas    — [SwagProp]: atributo de documentação por campo
    Swagger.Builder.pas       — TRouteDoc / TRouteDocBuilder: builder fluente de rotas + doc
    Swagger.Server.pas        — TSwaggerServer: serve JSON spec e Swagger UI via Horse
  MCP/
    MCP.Server.pas            — TMcpServer: expõe rotas do TSwagDoc como tools MCP (HTTP JSON-RPC 2.0)
tests/
  Unit/         — 23 testes unitários (DUnitX) — Infra.UnitTests.dpr
  Integration/  — 4 testes com banco Firebird real — Infra.IntegrationTests.dpr
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
infra\src\Common;infra\src\Db;infra\src\Swagger;infra\src\MCP;infra\modules\swag-doc\Source
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
  MCP.Server           in 'infra\src\MCP\MCP.Server.pas';
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
| `.Tag(tag)` | Agrupa a rota na UI por tag |
| `.PathParam(name, desc)` | Parâmetro de path (`:id` → `{id}`) |
| `.Body<I>(desc)` | Corpo da requisição — gera schema a partir do DTO |
| `.Response<I>(code, desc)` | Resposta com schema de objeto |
| `.ResponseArray<I>(code, desc)` | Resposta com schema de array |
| `.NoContent(code, desc)` | Resposta sem corpo (204, 404, etc.) |
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

### Atributo `[SwagProp]`

Adicione `[SwagProp]` nos métodos `Get*` da **classe de implementação** para enriquecer o schema com descrição, exemplo e formato:

```pascal
// Produto.DTOs.pas

IProdutoResponseDTO = interface(IInterface)
  ['{...}']
  function GetId: Integer;
  function GetNome: string;
  property Id: Integer read GetId;
  property Nome: string read GetNome;
end;

TProdutoResponseDTO = class(TInterfacedObject, IProdutoResponseDTO)
public
  [SwagProp('ID do produto', '1')]
  function GetId: Integer;
  [SwagProp('Nome do produto', 'Arroz')]
  function GetNome: string;
  // ...
end;
```

> **Importante:** `[SwagProp]` deve estar na **classe** (`TProdutoResponseDTO`), não na interface (`IProdutoResponseDTO`). O schema é gerado via RTTI da classe concreta — o RTTI de métodos de interface não é gerado pelo compilador por padrão.

Construtor do atributo:

```pascal
[SwagProp('descrição')]
[SwagProp('descrição', 'exemplo')]
[SwagProp('descrição', 'exemplo', 'formato')]  // formato: 'email', 'uri', 'date', etc.
```

O campo `exemplo` é emitido com o tipo JSON correto: `'1'` vira `1` (number), `'true'` vira `true` (boolean), strings ficam como string.

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

- **Nome** derivado do método HTTP + último segmento do path (sempre no singular)
- **description** mapeada do `.Summary()` da rota
- **inputSchema** gerado dos parâmetros de path e do body (via `TSwagDoc`)
- Exemplos do `[SwagProp]` são incorporados no `description` da propriedade (`"desc. Ex: valor"`)

### Exemplo de resposta do tools/list

```json
{
  "name": "create_produto",
  "description": "Criar produto",
  "inputSchema": {
    "type": "object",
    "properties": {
      "Nome": { "type": "string", "description": "Nome do produto. Ex: Arroz" }
    },
    "required": ["Nome"]
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
