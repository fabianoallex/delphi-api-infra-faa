# TODO — Melhorias MCP

Melhorias identificadas na avaliação da estrutura de tools MCP, ordenadas por prioridade e impacto para agentes de IA.

---

## Alta prioridade

### ~~1. Descriptions ricas com retorno e dependências~~ ✓

### 2. Campo `isError` no envelope de resposta do tools/call

**Arquivo:** `MCP.Server.pas` — `OnToolsCall` / `HttpCall`  
**Problema:** Respostas de erro HTTP (404, 500, etc.) chegam ao agente como texto no campo `content`, sem sinalização de falha. O agente pode tratar um erro como dado válido.  
**Solução:** Inspecionar o HTTP status code e emitir `"isError": true` quando >= 400.

```json
{ "content": [{ "type": "text", "text": "Produto não encontrado" }], "isError": true }
```

---

## Média prioridade

### 3. Constraints nos campos do schema

**Arquivo:** `Swagger.Attributes.pas` e/ou `MCP.Server.pas` — `BuildSchema`  
**Problema:** Agentes não conhecem limites dos campos. Isso gera chamadas inválidas que só falham no servidor.  
**Solução:** Expor `minLength`, `maxLength`, `minimum`, `maximum` no schema das tools.

```json
"Nome": { "type": "string", "minLength": 1, "maxLength": 100 },
"id":   { "type": "integer", "minimum": 1 }
```

---

### 4. `additionalProperties: false` no inputSchema

**Arquivo:** `MCP.Server.pas` — `BuildSchema`  
**Problema:** Sem esta declaração, agentes podem enviar campos extras acreditando que serão aceitos.  
**Solução:** Adicionar `"additionalProperties": false` em todo `inputSchema` gerado.

---

### 5. Paginação nos endpoints de listagem

**Arquivo:** `Swagger.Builder.pas` e controllers dos projetos consumidores  
**Problema:** `list_*` sem parâmetros retorna todos os registros. Com volume alto, o contexto do agente satura ou o servidor sobrecarrega.  
**Solução:** Adicionar parâmetros opcionais de paginação às rotas de listagem.

```json
"page":  { "type": "integer", "minimum": 1, "default": 1 },
"limit": { "type": "integer", "minimum": 1, "maximum": 100, "default": 20 }
```

---

## Baixa prioridade (escala futura)

### 6. Namespacing por domínio

**Quando:** A partir de ~15 tools ou múltiplos domínios (produto, pedido, cliente, etc.)  
**Solução:** Prefixar o nome da tool com o domínio para evitar colisões e facilitar a leitura pelo agente.

```
produto_list    produto_create    produto_get
pedido_list     pedido_create     pedido_get
```

---

### 7. Estratégia de versionamento de tools

**Quando:** Antes de ter consumidores externos em produção.  
**Regra:** Campos novos sempre opcionais (non-breaking). Para mudanças breaking, manter versão antiga por período de deprecação antes de remover.

---

### 8. Teste de conformação de DTOs

**Arquivo:** `tests/Unit/` — novo fixture DUnitX  
**Objetivo:** Garantir que todo DTO que herda de `IDTOBase` tem seu mapeamento registrado no `TJsonMapper`, evitando falhas silenciosas em runtime.  
**Abordagem:** Via RTTI, descobrir todas as classes descendentes de `TDTOBase` e, para cada uma, verificar que `TJsonMapper.FindImplClass(TypeInfo(I))` retorna non-nil. Como o `class constructor` dispara ao referenciar a classe, basta incluir os units dos DTOs no projeto de testes.

---

## Concluído

- [x] Item 1 — Descriptions ricas: `BuildDescription` combina Summary + `.Descr()` + "Returns: field (type, desc)..." auto-gerado do schema de resposta

- [x] `Common.DTO.Base.pas` — hierarquia de interfaces/classes base para DTOs
- [x] Nomes de tools singularizados (`create_produto`, `list_produto`)
- [x] Campo `example` incorporado no `description` da propriedade
- [x] `AddElement` para compatibilidade com versões anteriores do Delphi
- [x] Item 2 — `isError: true` no envelope `tools/call` quando HTTP status >= 400
- [x] Item 3 — Constraints `[SwagMin]`/`[SwagMax]` no schema: strings → `minLength`/`maxLength`, números → `minimum`/`maximum`
- [x] Item 4 — `additionalProperties: false` em todo `inputSchema` gerado pelo MCP
- [x] Item 5 — Paginação em `GET /produtos`: `page`, `limit`, `search`, `orderBy` (mesmo padrão de `/cidades`)
- [x] Item 6 — Isolamento por domínio via múltiplos endpoints filtrados por tag (`/mcp/produtos`, `/mcp/cidades`) — abordagem preferida ao prefixo no nome da tool
