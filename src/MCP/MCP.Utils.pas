unit MCP.Utils;

{$CODEPAGE UTF8}

interface

uses
  System.Classes,
  System.SysUtils;

/// <summary>
/// Deriva o nome da tool MCP a partir do método HTTP e do path.
/// Exemplos:
///   GET  /produtos        → list_produto
///   GET  /produtos/{id}   → get_produto
///   POST /produtos        → create_produto
///   PATCH /produtos/{id}  → update_produto
///   DELETE /produtos/{id} → delete_produto
/// </summary>
function McpDeriveName(const AMethod, APath: string): string;

/// <summary>
/// Retorna True se AOpTags intersecta AFilterTags.
/// Se AFilterTags for nil ou vazio, sempre retorna True (sem filtro).
/// </summary>
function McpMatchesTags(const AOpTags: TArray<string>; const AFilterTags: TStrings): Boolean;

implementation

function McpDeriveName(const AMethod, APath: string): string;
var
  LParts: TArray<string>;
  LResource, S: string;
  LHasId: Boolean;
begin
  LHasId    := APath.Contains('{');
  LParts    := APath.TrimLeft(['/']).Split(['/']);
  LResource := '';
  for S in LParts do
    if not S.StartsWith('{') then
      LResource := S.Replace('-', '_');
  if LResource.EndsWith('s') then
    LResource := LResource.Substring(0, LResource.Length - 1);
  if      SameText(AMethod, 'GET')    and not LHasId then Result := 'list_'   + LResource
  else if SameText(AMethod, 'GET')                   then Result := 'get_'    + LResource
  else if SameText(AMethod, 'POST')                  then Result := 'create_' + LResource
  else if SameText(AMethod, 'PATCH') or
          SameText(AMethod, 'PUT')                   then Result := 'update_' + LResource
  else if SameText(AMethod, 'DELETE')                then Result := 'delete_' + LResource
  else                                                    Result := LowerCase(AMethod) + '_' + LResource;
end;

function McpMatchesTags(const AOpTags: TArray<string>; const AFilterTags: TStrings): Boolean;
var
  LTag: string;
begin
  if (AFilterTags = nil) or (AFilterTags.Count = 0) then
    Exit(True);
  for LTag in AOpTags do
    if AFilterTags.IndexOf(LTag) >= 0 then
      Exit(True);
  Result := False;
end;

end.
