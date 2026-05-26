# TODO — Melhorias da base de infraestrutura

Melhorias identificadas nas avaliações do projeto, ordenadas por prioridade e impacto.

---

## Média prioridade

---

## Baixa prioridade

### 14. CORS middleware

**Quando:** Ao expor a API para clientes browser (SPAs, dashboards).  
**Solução:** Middleware Horse que emita os headers `Access-Control-Allow-*` configuráveis por origem.

---

### 15. Rate limiting

**Quando:** Ao expor endpoints publicamente ou via MCP para agentes externos.  
**Solução:** Middleware com janela deslizante por IP ou por API key. Retorna 429 ao exceder o limite.

---

### 16. Campos de auditoria (created_at / updated_at)

**Quando:** Domínios que precisam de rastreabilidade de alterações.  
**Solução:** Mixin ou base class para Repository que gerencie automaticamente `CREATED_AT` e `UPDATED_AT` via trigger ou no INSERT/UPDATE.

---

### 7. Estratégia de versionamento de tools MCP

**Quando:** Antes de ter consumidores externos em produção.  
**Regra:** Campos novos sempre opcionais (non-breaking). Para mudanças breaking, manter versão antiga por período de deprecação antes de remover.

---

## Concluído

- [x] Item 14 — `Horse.Middleware.Cors.pas`: `TCorsMiddleware.New` (3 overloads); `TCorsOptions.Default`; AllowOrigin=`*` emite incondicionalmente; origem específica echoa com `Vary: Origin`; preflight `OPTIONS` responde 204 sem chamar Next; suporte a `AllowCredentials`, `MaxAge`, `ExposeHeaders`
- [x] Item 12 — `Db.Mock.pas`: `TMockDBFactory` implementando `IDBFactory`; `TMockQueryResult` (Empty/SingleRow/MultiRows); `TMockParams` com 56 setters/getters Opt/Null/OptNull; `TMockSQLLoader` retorna chave como SQL (bypass de .res); `TMockExecution` captura snapshot de params; `Db.MockTests.pas` com 4 fixtures DUnitX; `Db.SqlLoader.GetSql` promovido a `protected virtual`
- [x] Item 13 — `Horse.Middleware.Auth.pas`: `TAuthMiddleware.Bearer(AValidator, AExcludedPrefixes)` valida `Authorization: Bearer`; paths com prefixo excluído passam sem autenticação; retorna 401 com JSON para token ausente, formato inválido ou validator retornando False
- [x] Item 11 — `Common.HealthCheck.pas`: `THealthCheck.Register(AFactory)` registra `GET /health` fora do Swagger e MCP; testa com `IDBFactory.CreateConnection` + `TestConnection`; retorna `{"status":"ok"}` 200 ou `{"status":"degraded","detail":"..."}` 503
- [x] Item 10 — `Horse.Middleware.ErrorHandler.pas`: middleware `TErrorHandlerMiddleware.New` captura exceções não tratadas; hierarquia `EHttpException` → `EValidationException` (400), `ENotFoundException` (404), `EConflictException` (409); `EOrderByException` mapeada para 400; qualquer outra `Exception` → 500; resposta `{"error":"..."}` com JSON-safe escaping via `TJSONObject`
- [x] Item 9 — `Common.Config.pas`: `TAppConfig` com leitura de env vars + fallback para `app.ini`; `Api.Test.dpr` atualizado para usar `TAppConfig` em todas as configurações hardcoded

- [x] Item 1 — Descriptions ricas: `BuildDescription` combina Summary + `.Descr()` + "Returns: field (type, desc)..." auto-gerado do schema de resposta
- [x] Item 2 — `isError: true` no envelope `tools/call` quando HTTP status >= 400
- [x] Item 3 — Constraints `[SwagMin]`/`[SwagMax]` no schema: strings → `minLength`/`maxLength`, números → `minimum`/`maximum`
- [x] Item 4 — `additionalProperties: false` em todo `inputSchema` gerado pelo MCP
- [x] Item 5 — Paginação em `GET /produtos`: `page`, `limit`, `search`, `orderBy` (mesmo padrão de `/cidades`)
- [x] Item 6 — Isolamento por domínio via múltiplos endpoints filtrados por tag (`/mcp/produtos`, `/mcp/cidades`) — abordagem preferida ao prefixo no nome da tool
- [x] `Common.DTO.Base.pas` — hierarquia de interfaces/classes base para DTOs
- [x] Nomes de tools singularizados (`create_produto`, `list_produto`)
- [x] Campo `example` incorporado no `description` da propriedade
- [x] `AddElement` para compatibilidade com versões anteriores do Delphi
- [x] `CLAUDE.md` — guia de convenções para agentes de IA (checklist de domínio, padrões, anti-padrões)
