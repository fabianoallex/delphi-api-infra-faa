# TODO — Melhorias da base de infraestrutura

Melhorias identificadas nas avaliações do projeto, ordenadas por prioridade e impacto.

---

## Alta prioridade

### 16. Domínio Auth — geração de JWT

**Quando:** Qualquer API que use o `TJwtMiddleware` precisa de um endpoint de login para gerar o token.  
**Solução:** Domínio `Auth` no template (`Auth.DTOs`, `Auth.Service`, `Auth.Controller`) com `POST /auth/login` recebendo credenciais e retornando `access_token` + `expires_in`. `TJwtHelper` já valida; falta a contraparte de geração com `THashSHA2`.

---

### 17. Refresh token

**Quando:** Ao usar JWT com tempo de expiração curto em apps que precisam de sessão longa.  
**Solução:** `POST /auth/refresh` — token de curta duração (ex: 15 min) + refresh de longa duração (ex: 7 dias) armazenado no banco. Middleware distingue os dois tipos pelo claim `type`.

---

### 18. Estrutura de testes DUnitX no template

**Quando:** Todo projeto consumidor deveria ter testes desde o início.  
**Solução:** Projeto `tests/` no template com: fixture de conformidade de DTOs (já documentado no CLAUDE.md mas não existe no template), exemplo de teste de Service com `TMockDBFactory`, e DPR de test runner configurado com `{$STRONGLINKTYPES ON}`.

---

### 19. Dockerfile + docker-compose

**Quando:** Ao fazer deploy em servidor Linux ou ambiente containerizado.  
**Solução:** `Dockerfile` compilando via Wine+Delphi ou usando binário pré-compilado; `docker-compose.yml` com serviço da API + Firebird ou PostgreSQL. Reduz barreira de adoção para quem quer subir rapidamente.

---

## Média prioridade

### 20. Audit fields automáticos

**Quando:** Em qualquer domínio que precise de rastreabilidade (quase todos).  
**Solução:** `CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP`, `UPDATED_AT TIMESTAMP`, `CREATED_BY VARCHAR(100)` preenchidos pela infra via hook no Repository base, sem precisar declarar em cada domínio.

---

### 21. Soft delete

**Quando:** Ao precisar preservar histórico de registros excluídos.  
**Solução:** Campo `DELETED_AT TIMESTAMP NULL` na tabela. Repository base filtra `WHERE DELETED_AT IS NULL` automaticamente. `DELETE` físico substituído por `UPDATE ... SET DELETED_AT = CURRENT_TIMESTAMP`.

---

### 22. Validação declarativa nos DTOs

**Quando:** Em vez de `if/raise` manual no Service para cada campo.  
**Solução:** Atributos `[Required]`, `[MinLength(N)]`, `[MaxLength(N)]`, `[Range(Min, Max)]` nos DTOs. Uma classe `TDTOValidator.Validate<T>(ADto)` lida via RTTI antes de chegar no Service, lançando `EValidationException` com lista de erros.

---

### 23. Graceful shutdown

**Quando:** Em deploy com Docker ou process manager (systemd, NSSM).  
**Solução:** Capturar `SIGTERM` / `Ctrl+C` via `SetConsoleCtrlHandler`, aguardar requests em andamento concluírem e fechar o pool de conexões antes de encerrar.

---

### 24. Variáveis de ambiente via arquivo `.env`

**Quando:** Em ambientes Docker onde `.env` é o padrão de configuração.  
**Solução:** `TAppConfig` já lê env vars e `app.ini`. Adicionar suporte a arquivo `.env` (formato `CHAVE=VALOR`) como terceira fonte, com precedência: env var > `.env` > `app.ini` > default.

---

## Baixa prioridade

### 25. Cache em memória com TTL

**Quando:** Em endpoints de leitura pesada com dados que mudam pouco (tabelas de domínio, configurações).  
**Solução:** `TCacheManager` com dicionário thread-safe `TDictionary<string, TCacheEntry>` onde cada entrada tem valor + timestamp de expiração. Helper `CacheOrFetch(AKey, ATTL, ALoader)` para uso nos Services.

---

### 26. Upload de arquivo

**Quando:** Em endpoints que recebem imagens, documentos ou planilhas.  
**Solução:** Parser de `multipart/form-data` integrado ao Horse. Helper `TFileUpload` com validação de tipo MIME, tamanho máximo e salvamento em disco ou BLOB no banco.

---

### 27. Export CSV

**Quando:** Em sistemas corporativos onde relatórios em planilha são requisito comum.  
**Solução:** Helper `TCSVExporter.FromList<T>` que serializa via RTTI os mesmos DTOs do endpoint. Controller detecta `Accept: text/csv` ou `?format=csv` e serve o mesmo resultado do Find como arquivo `.csv`.

---

### 28. Versionamento de API

**Quando:** Ao precisar manter compatibilidade com clientes antigos enquanto evolui a API.  
**Solução:** Prefixo `/v1/`, `/v2/` no registro de rotas. `TRouteDoc.Init` recebe versão e agrupa no Swagger por versão. Middleware opcional que rejeita versões descontinuadas com 410 Gone.

---

### 29. Webhook outbound

**Quando:** Ao precisar notificar sistemas externos sobre eventos do domínio.  
**Solução:** `TWebhookDispatcher` que faz `POST` HTTP para URLs cadastradas quando eventos ocorrem (ex: registro criado/atualizado). Tabela `WEBHOOK_SUBSCRIPTIONS` com URL, evento e secret para HMAC de assinatura do payload.

---

### 30. Background jobs

**Quando:** Para tarefas assíncronas como envio de e-mail, geração de relatório ou processamento em lote.  
**Solução:** Fila em memória com worker thread (`TThread`) consumindo jobs. Interface `IJobHandler` com método `Execute`. Persistência opcional dos jobs em tabela para retentativa em caso de falha.

---

### 31. WebSocket

**Quando:** Para push em tempo real (notificações, dashboards ao vivo, chat).  
**Solução:** Integração com o suporte WebSocket do Horse/Indy. Helper para broadcast por sala/canal. Autenticação via token no handshake inicial.

---

### 14. CORS middleware

**Quando:** Ao expor a API para clientes browser (SPAs, dashboards).  
**Solução:** Middleware Horse que emita os headers `Access-Control-Allow-*` configuráveis por origem.

---

### 15. Rate limiting

**Quando:** Ao expor endpoints publicamente ou via MCP para agentes externos.  
**Solução:** Middleware com janela deslizante por IP ou por API key. Retorna 429 ao exceder o limite.

### 14. CORS middleware

**Quando:** Ao expor a API para clientes browser (SPAs, dashboards).  
**Solução:** Middleware Horse que emita os headers `Access-Control-Allow-*` configuráveis por origem.

---

### 15. Rate limiting

**Quando:** Ao expor endpoints publicamente ou via MCP para agentes externos.  
**Solução:** Middleware com janela deslizante por IP ou por API key. Retorna 429 ao exceder o limite.

---

## Concluído

- [x] Item 15 — `Horse.Middleware.RateLimit.pas`: sliding window por IP (X-Forwarded-For + RemoteAddr) ou chave customizável via `TRateLimitKeyExtractor`; retorna 429 + `Retry-After`; headers `X-RateLimit-Limit/Remaining/Reset` em todas as respostas; estado thread-safe em memória (IRateLimitState com TCriticalSection); auto-free via ARC na closure
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
