unit MCP.Server;

{
  Expõe as rotas documentadas no TSwagDoc como tools MCP (Model Context Protocol).
  Transporte: HTTP, JSON-RPC 2.0 — POST <endpoint>.
  Execução de tools: HTTP call de volta ao próprio servidor Horse.

  Uso básico — endpoint único com todas as tools:
    TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp', 'http://localhost:9000');

  Uso com múltiplos endpoints filtrados por tag:
    var LTags := TStringList.Create;
    try
      LTags.Add('cidades');
      TMcpServer.Register(TRouteDoc.CurrentDoc, '/mcp/cidades',
        'http://localhost:9000', 'api', '1.0.0', nil, LTags);
    finally
      LTags.Free;
    end;
}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Swag.Doc,
  Swag.Doc.Path.Operation,
  Swag.Common.Types;

type
  TMcpServer = class
  private
    type
      TTool = class
        Name: string;
        Description: string;
        Method: string;
        Path: string;
        PathParams: TArray<string>;
        InputSchema: TJSONObject;
        destructor Destroy; override;
      end;

    // Owns all per-endpoint tool lists; each Horse closure holds a non-owning ref
    class var FAllToolLists: TObjectList<TObjectList<TTool>>;

    class function MethodStr(AOp: TSwagPathTypeOperation): string;
    class function ResolveRef(const ADefName: string; ADoc: TSwagDoc): TJSONObject;
    class function BuildSchema(AOp: TSwagPathOperation; ADoc: TSwagDoc): TJSONObject;
    class function BuildReturnHint(AOp: TSwagPathOperation; ADoc: TSwagDoc): string;
    class function BuildDescription(AOp: TSwagPathOperation; ADoc: TSwagDoc): string;

    class function Dispatch(const AJson: string;
      ATools: TObjectList<TTool>;
      const ABaseUrl, AServerName, AServerVersion: string): string;
    class function MakeResult(AId: TJSONValue; AResult: TJSONValue): TJSONObject;
    class function MakeError(AId: TJSONValue; ACode: Integer; const AMsg: string): TJSONObject;

    class function OnInitialize(AId: TJSONValue;
      const AServerName, AServerVersion: string): TJSONObject;
    class function OnToolsList(AId: TJSONValue;
      ATools: TObjectList<TTool>): TJSONObject;
    class function OnToolsCall(AId: TJSONValue; AParams: TJSONObject;
      ATools: TObjectList<TTool>; const ABaseUrl: string): TJSONObject;
    class function HttpCall(const AMethod, APath: string; AArgs: TJSONObject;
      const APathParams: TArray<string>; const ABaseUrl: string;
      out AStatusCode: Integer): string;
  public
    class constructor Create;
    class destructor Destroy;

    /// <summary>
    /// Lê ADoc, constrói a lista de tools e registra POST AEndpoint no Horse.
    /// Chamar antes de TRouteDoc.Serve — o doc é lido mas não é liberado aqui.
    /// AExcluded: lista de chaves "METHOD:PATH" a omitir (ver TRouteDoc.McpExcluded).
    /// ATags: se fornecido, inclui apenas operations que tenham pelo menos uma
    ///   das tags listadas. nil ou vazio = todas as operations.
    /// Pode ser chamado múltiplas vezes com endpoints diferentes para expor
    /// subconjuntos de tools por domínio (ex: '/mcp/cidades', '/mcp/produtos').
    /// </summary>
    class procedure Register(ADoc: TSwagDoc;
      const AEndpoint: string      = '/mcp';
      const ABaseUrl: string       = 'http://localhost:9000';
      const AServerName: string    = 'api';
      const AServerVersion: string = '1.0.0';
      AExcluded: TStrings          = nil;
      ATags: TStrings              = nil);
  end;

implementation

uses
  System.Net.HttpClient,
  Swag.Doc.Path,
  Swag.Doc.Path.Operation.RequestParameter,
  Swag.Doc.Path.Operation.Response,
  Swag.Doc.Definition,
  MCP.Utils,
  Horse;

{ TTool }

destructor TMcpServer.TTool.Destroy;
begin
  InputSchema.Free;
  inherited;
end;

{ TMcpServer — lifecycle }

class constructor TMcpServer.Create;
begin
  FAllToolLists := TObjectList<TObjectList<TTool>>.Create(True);
end;

class destructor TMcpServer.Destroy;
begin
  FAllToolLists.Free;
end;

{ TMcpServer — schema building }

class function TMcpServer.MethodStr(AOp: TSwagPathTypeOperation): string;
begin
  case AOp of
    ohvGet:    Result := 'GET';
    ohvPost:   Result := 'POST';
    ohvPut:    Result := 'PUT';
    ohvPatch:  Result := 'PATCH';
    ohvDelete: Result := 'DELETE';
  else
    Result := '';
  end;
end;

class function TMcpServer.ResolveRef(const ADefName: string; ADoc: TSwagDoc): TJSONObject;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to ADoc.Definitions.Count - 1 do
    if SameText(ADoc.Definitions[I].Name, ADefName) then
      Exit(ADoc.Definitions[I].JsonSchema);
end;

class function TMcpServer.BuildSchema(AOp: TSwagPathOperation; ADoc: TSwagDoc): TJSONObject;
var
  LProps: TJSONObject;
  LRequired: TJSONArray;
  LParam: TSwagRequestParameter;
  LTypeName: string;
  LBodyDef: TJSONObject;
  LDefProps: TJSONObject;
  LDefRequired: TJSONArray;
  LPair: TJSONPair;
  LReqItem: TJSONValue;
  LPropObj: TJSONObject;
  LPropClone: TJSONObject;
  LExamplePair: TJSONPair;
  LDescPair: TJSONPair;
  LMergedDesc: string;
begin
  LProps    := TJSONObject.Create;
  LRequired := TJSONArray.Create;

  for LParam in AOp.Parameters do
  begin
    if LParam.InLocation = rpiPath then
    begin
      case LParam.TypeParameter of
        stpNumber:  LTypeName := 'number';
        stpBoolean: LTypeName := 'boolean';
        stpInteger: LTypeName := 'integer';
      else          LTypeName := 'string';
      end;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', LTypeName);
      if not LParam.Description.IsEmpty then
        LPropObj.AddPair('description', LParam.Description);
      LProps.AddPair(LParam.Name, LPropObj);
      LRequired.Add(LParam.Name);
    end
    else if LParam.InLocation = rpiQuery then
    begin
      case LParam.TypeParameter of
        stpNumber:  LTypeName := 'number';
        stpBoolean: LTypeName := 'boolean';
        stpInteger: LTypeName := 'integer';
      else          LTypeName := 'string';
      end;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', LTypeName);
      if not LParam.Description.IsEmpty then
        LPropObj.AddPair('description', LParam.Description);
      LProps.AddPair(LParam.Name, LPropObj);
      // query params are optional — not added to required
    end
    else if (LParam.InLocation = rpiBody) and not LParam.Schema.Name.IsEmpty then
    begin
      LBodyDef := ResolveRef(LParam.Schema.Name, ADoc);
      if Assigned(LBodyDef) then
      begin
        LDefProps    := LBodyDef.GetValue('properties') as TJSONObject;
        LDefRequired := LBodyDef.GetValue('required')   as TJSONArray;
        if Assigned(LDefProps) then
          for LPair in LDefProps do
          begin
            LPropClone   := LPair.JsonValue.Clone as TJSONObject;
            LExamplePair := LPropClone.RemovePair('example');
            if Assigned(LExamplePair) then
            try
              LDescPair := LPropClone.RemovePair('description');
              if Assigned(LDescPair) then
              try
                LMergedDesc := LDescPair.JsonValue.Value + '. Ex: ' + LExamplePair.JsonValue.Value;
              finally
                LDescPair.Free;
              end
              else
                LMergedDesc := 'Ex: ' + LExamplePair.JsonValue.Value;
              LPropClone.AddPair('description', LMergedDesc);
            finally
              LExamplePair.Free;
            end;
            LProps.AddPair(LPair.JsonString.Value, LPropClone);
          end;
        if Assigned(LDefRequired) then
          for LReqItem in LDefRequired do
            LRequired.AddElement(LReqItem.Clone as TJSONValue);
      end;
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', LProps);
  if LRequired.Count > 0 then
    Result.AddPair('required', LRequired)
  else
    LRequired.Free;
  Result.AddPair('additionalProperties', TJSONBool.Create(False));
end;

{ TMcpServer — description building }

class function TMcpServer.BuildReturnHint(AOp: TSwagPathOperation; ADoc: TSwagDoc): string;
var
  LResponse: TSwagResponse;
  LDefName: string;
  LDef, LProps, LPropObj: TJSONObject;
  LJsonSchema, LItemsObj, LInnerItems: TJSONObject;
  LPair: TJSONPair;
  LRefVal, LTypeVal, LDescVal: TJSONValue;
  LTypeStr, LDescStr, LFieldStr: string;
  LFields: TArray<string>;
begin
  Result := '';

  if not (AOp.Responses.TryGetValue('200', LResponse) or
          AOp.Responses.TryGetValue('201', LResponse)) then
    Exit;

  LDefName := '';

  if not LResponse.Schema.Name.IsEmpty then
    // Simple object: Schema.Name = definition name
    LDefName := LResponse.Schema.Name
  else if Assigned(LResponse.Schema.JsonSchema) then
  begin
    LJsonSchema := LResponse.Schema.JsonSchema;
    LTypeVal    := LJsonSchema.GetValue('type');
    if not Assigned(LTypeVal) then Exit;

    if LTypeVal.Value = 'array' then
    begin
      // {"type":"array","items":{"$ref":"#/definitions/X"}}
      LItemsObj := LJsonSchema.GetValue('items') as TJSONObject;
      if Assigned(LItemsObj) then
      begin
        LRefVal := LItemsObj.GetValue('$ref');
        if Assigned(LRefVal) then
          LDefName := LRefVal.Value.Replace('#/definitions/', '');
      end;
    end
    else if LTypeVal.Value = 'object' then
    begin
      // Paged: properties → items → items → $ref
      LProps := LJsonSchema.GetValue('properties') as TJSONObject;
      if Assigned(LProps) then
      begin
        LItemsObj := LProps.GetValue('items') as TJSONObject;
        if Assigned(LItemsObj) then
        begin
          LInnerItems := LItemsObj.GetValue('items') as TJSONObject;
          if Assigned(LInnerItems) then
          begin
            LRefVal := LInnerItems.GetValue('$ref');
            if Assigned(LRefVal) then
              LDefName := LRefVal.Value.Replace('#/definitions/', '');
          end;
        end;
      end;
    end;
  end;

  if LDefName.IsEmpty then Exit;

  LDef := ResolveRef(LDefName, ADoc);
  if not Assigned(LDef) then Exit;

  LProps := LDef.GetValue('properties') as TJSONObject;
  if not Assigned(LProps) or (LProps.Count = 0) then Exit;

  LFields := [];
  for LPair in LProps do
  begin
    if not (LPair.JsonValue is TJSONObject) then Continue;
    LPropObj := TJSONObject(LPair.JsonValue);

    LTypeVal := LPropObj.GetValue('type');
    LDescVal := LPropObj.GetValue('description');

    LTypeStr := '';
    LDescStr := '';
    if Assigned(LTypeVal) then LTypeStr := LTypeVal.Value;
    if Assigned(LDescVal) then LDescStr := LDescVal.Value;

    if not LDescStr.IsEmpty then
      LFieldStr := LPair.JsonString.Value + ' (' + LTypeStr + ', ' + LDescStr + ')'
    else
      LFieldStr := LPair.JsonString.Value + ' (' + LTypeStr + ')';

    LFields := LFields + [LFieldStr];
  end;

  if Length(LFields) > 0 then
    Result := 'Returns: ' + string.Join(', ', LFields) + '.';
end;

class function TMcpServer.BuildDescription(AOp: TSwagPathOperation; ADoc: TSwagDoc): string;
var
  LReturnHint: string;
begin
  Result := AOp.Summary;

  if not AOp.Description.IsEmpty then
    Result := Result + '. ' + AOp.Description;

  LReturnHint := BuildReturnHint(AOp, ADoc);
  if not LReturnHint.IsEmpty then
    Result := Result + ' ' + LReturnHint;
end;

{ TMcpServer — JSON-RPC helpers }

class function TMcpServer.MakeResult(AId: TJSONValue; AResult: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if Assigned(AId) then
    Result.AddPair('id', AId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);
  Result.AddPair('result', AResult);
end;

class function TMcpServer.MakeError(AId: TJSONValue; ACode: Integer; const AMsg: string): TJSONObject;
var
  LErr: TJSONObject;
begin
  LErr := TJSONObject.Create;
  LErr.AddPair('code',    TJSONNumber.Create(ACode));
  LErr.AddPair('message', AMsg);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if Assigned(AId) then
    Result.AddPair('id', AId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);
  Result.AddPair('error', LErr);
end;

{ TMcpServer — MCP method handlers }

class function TMcpServer.OnInitialize(AId: TJSONValue;
  const AServerName, AServerVersion: string): TJSONObject;
var
  LResult, LCaps, LInfo: TJSONObject;
begin
  LCaps := TJSONObject.Create;
  LCaps.AddPair('tools', TJSONObject.Create);

  LInfo := TJSONObject.Create;
  LInfo.AddPair('name',    AServerName);
  LInfo.AddPair('version', AServerVersion);

  LResult := TJSONObject.Create;
  LResult.AddPair('protocolVersion', '2024-11-05');
  LResult.AddPair('capabilities',    LCaps);
  LResult.AddPair('serverInfo',      LInfo);

  Result := MakeResult(AId, LResult);
end;

class function TMcpServer.OnToolsList(AId: TJSONValue;
  ATools: TObjectList<TTool>): TJSONObject;
var
  LList: TJSONArray;
  LTool: TTool;
  LObj: TJSONObject;
  LResult: TJSONObject;
begin
  LList := TJSONArray.Create;
  for LTool in ATools do
  begin
    LObj := TJSONObject.Create;
    LObj.AddPair('name',        LTool.Name);
    LObj.AddPair('description', LTool.Description);
    LObj.AddPair('inputSchema', LTool.InputSchema.Clone as TJSONValue);
    LList.AddElement(LObj);
  end;
  LResult := TJSONObject.Create;
  LResult.AddPair('tools', LList);
  Result := MakeResult(AId, LResult);
end;

class function TMcpServer.OnToolsCall(AId: TJSONValue; AParams: TJSONObject;
  ATools: TObjectList<TTool>; const ABaseUrl: string): TJSONObject;
var
  LNameVal: TJSONValue;
  LName: string;
  LArgsVal: TJSONValue;
  LArgs: TJSONObject;
  LTool, LFound: TTool;
  LOutput: string;
  LStatusCode: Integer;
  LItem: TJSONObject;
  LContent: TJSONArray;
  LResult: TJSONObject;
begin
  if not Assigned(AParams) then
    Exit(MakeError(AId, -32602, 'tools/call: params ausente'));

  LNameVal := AParams.GetValue('name');
  if Assigned(LNameVal) then LName := LNameVal.Value else LName := '';
  if LName.IsEmpty then
    Exit(MakeError(AId, -32602, 'tools/call: "name" ausente'));

  LArgsVal := AParams.GetValue('arguments');
  if LArgsVal is TJSONObject then LArgs := TJSONObject(LArgsVal) else LArgs := nil;

  LFound := nil;
  for LTool in ATools do
    if SameText(LTool.Name, LName) then
    begin
      LFound := LTool;
      Break;
    end;

  if not Assigned(LFound) then
    Exit(MakeError(AId, -32602, 'Tool desconhecida: ' + LName));

  try
    LOutput := HttpCall(LFound.Method, LFound.Path, LArgs, LFound.PathParams, ABaseUrl, LStatusCode);
  except
    on E: Exception do
      Exit(MakeError(AId, -32603, 'Falha na execução: ' + E.Message));
  end;

  LItem := TJSONObject.Create;
  LItem.AddPair('type', 'text');
  LItem.AddPair('text', LOutput);

  LContent := TJSONArray.Create;
  LContent.AddElement(LItem);

  LResult := TJSONObject.Create;
  LResult.AddPair('content', LContent);
  if LStatusCode >= 400 then
    LResult.AddPair('isError', TJSONBool.Create(True));

  Result := MakeResult(AId, LResult);
end;

{ TMcpServer — HTTP execution }

class function TMcpServer.HttpCall(const AMethod, APath: string;
  AArgs: TJSONObject; const APathParams: TArray<string>;
  const ABaseUrl: string; out AStatusCode: Integer): string;
var
  LUrl: string;
  LBody: TJSONObject;
  LPair: TJSONPair;
  LIsPathParam: Boolean;
  LParamName: string;
  LHttp: THTTPClient;
  LStream: TStringStream;
  LResponse: IHTTPResponse;
begin
  LUrl := ABaseUrl + APath;
  if Assigned(AArgs) then
    for LParamName in APathParams do
      LUrl := LUrl.Replace('{' + LParamName + '}',
        AArgs.GetValue(LParamName).Value);

  LBody := TJSONObject.Create;
  try
    if Assigned(AArgs) then
      for LPair in AArgs do
      begin
        LIsPathParam := False;
        for LParamName in APathParams do
          if SameText(LPair.JsonString.Value, LParamName) then
          begin
            LIsPathParam := True;
            Break;
          end;
        if not LIsPathParam then
          LBody.AddPair(LPair.JsonString.Value, LPair.JsonValue.Clone as TJSONValue);
      end;

    LHttp := THTTPClient.Create;
    try
      LHttp.ContentType := 'application/json';
      LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
      try
        if      SameText(AMethod, 'GET')    then LResponse := LHttp.Get(LUrl)
        else if SameText(AMethod, 'POST')   then LResponse := LHttp.Post(LUrl, LStream)
        else if SameText(AMethod, 'PUT')    then LResponse := LHttp.Put(LUrl, LStream)
        else if SameText(AMethod, 'PATCH')  then LResponse := LHttp.Patch(LUrl, LStream)
        else if SameText(AMethod, 'DELETE') then LResponse := LHttp.Delete(LUrl)
        else                                     LResponse := LHttp.Get(LUrl);
        AStatusCode := LResponse.StatusCode;
        Result      := LResponse.ContentAsString(TEncoding.UTF8);
      finally
        LStream.Free;
      end;
    finally
      LHttp.Free;
    end;
  finally
    LBody.Free;
  end;
end;

{ TMcpServer — JSON-RPC dispatcher }

class function TMcpServer.Dispatch(const AJson: string;
  ATools: TObjectList<TTool>;
  const ABaseUrl, AServerName, AServerVersion: string): string;
var
  LReq: TJSONObject;
  LId: TJSONValue;
  LMethod: string;
  LParamsVal: TJSONValue;
  LParams: TJSONObject;
  LResp: TJSONObject;
begin
  Result := '';
  LReq := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if not Assigned(LReq) then
    Exit('{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}');
  try
    LId        := LReq.GetValue('id');
    LMethod    := LReq.GetValue('method').Value;
    LParamsVal := LReq.GetValue('params');
    if LParamsVal is TJSONObject then LParams := TJSONObject(LParamsVal) else LParams := nil;

    LResp := nil;
    if      LMethod = 'initialize'                then LResp := OnInitialize(LId, AServerName, AServerVersion)
    else if LMethod = 'notifications/initialized' then {fire-and-forget — sem resposta}
    else if LMethod = 'tools/list'                then LResp := OnToolsList(LId, ATools)
    else if LMethod = 'tools/call'                then LResp := OnToolsCall(LId, LParams, ATools, ABaseUrl)
    else if Assigned(LId) then
      LResp := MakeError(LId, -32601, 'Method not found: ' + LMethod);

    if Assigned(LResp) then
    try
      Result := LResp.ToJSON;
    finally
      LResp.Free;
    end;
  finally
    LReq.Free;
  end;
end;

{ TMcpServer — public }

class procedure TMcpServer.Register(ADoc: TSwagDoc;
  const AEndpoint, ABaseUrl, AServerName, AServerVersion: string;
  AExcluded: TStrings; ATags: TStrings);
var
  LPath: TSwagPath;
  LOp: TSwagPathOperation;
  LTool: TTool;
  LMethod: string;
  LParam: TSwagRequestParameter;
  LTools: TObjectList<TTool>;
  LCapturedBaseUrl: string;
  LCapturedServerName: string;
  LCapturedServerVersion: string;
begin
  LTools := TObjectList<TTool>.Create(True);
  FAllToolLists.Add(LTools);

  LCapturedBaseUrl       := ABaseUrl;
  LCapturedServerName    := AServerName;
  LCapturedServerVersion := AServerVersion;

  for LPath in ADoc.Paths do
    for LOp in LPath.Operations do
    begin
      LMethod := MethodStr(LOp.Operation);
      if LMethod.IsEmpty then Continue;

      if Assigned(AExcluded) and
         (AExcluded.IndexOf(LMethod + ':' + LPath.Uri) >= 0) then
        Continue;

      if not McpMatchesTags(LOp.Tags.ToArray, ATags) then
        Continue;

      LTool             := TTool.Create;
      if not LOp.OperationId.IsEmpty then
        LTool.Name := LOp.OperationId
      else
        LTool.Name := McpDeriveName(LMethod, LPath.Uri);
      LTool.Description := BuildDescription(LOp, ADoc);
      LTool.Method      := LMethod;
      LTool.Path        := LPath.Uri;
      LTool.InputSchema := BuildSchema(LOp, ADoc);
      LTool.PathParams  := [];

      for LParam in LOp.Parameters do
        if LParam.InLocation = rpiPath then
        begin
          SetLength(LTool.PathParams, Length(LTool.PathParams) + 1);
          LTool.PathParams[High(LTool.PathParams)] := LParam.Name;
        end;

      LTools.Add(LTool);
    end;

  THorse.Post(AEndpoint,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LBody: string;
    begin
      LBody := Dispatch(Req.Body, LTools,
        LCapturedBaseUrl, LCapturedServerName, LCapturedServerVersion);
      if LBody <> '' then
        Res.ContentType('application/json; charset=utf-8').Send(LBody)
      else
        Res.Status(202).Send('');
    end);
end;

end.
