unit Swagger.Builder;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  Swag.Common.Types,
  Swag.Doc,
  Swag.Doc.Path,
  Swag.Doc.Path.Operation,
  Swag.Doc.Path.Operation.RequestParameter,
  Swag.Doc.Path.Operation.Response,
  Swag.Doc.Definition,
  Horse.Callback,
  Swagger.Attributes,
  Swagger.Server;

type
  TQueryParamType = (qptString, qptInteger);

  TRouteDocBuilder = class;

  /// <summary>
  /// Ponto central de configuração e registro de rotas.
  ///
  /// Fluxo:
  ///   TRouteDoc.Init(title, version, host)
  ///   TRouteDoc.Get('/path').Summary('...').Response<IDto>('200','...').Register(handler)
  ///   TRouteDoc.Post('/path').Body<IDto>.Response<IDto>('201','...').Register(handler)
  ///   TRouteDoc.Serve('/swagger')   // serializa o doc e registra as rotas Swagger UI
  /// </summary>
  TRouteDoc = class
  private
    class var FDoc: TSwagDoc;
    class var FMcpExcluded: TStringList;
    class procedure FindOrCreatePath(const AUri: string; out APath: TSwagPath);
  public
    class destructor Destroy;

    class procedure Init(const ATitle, AVersion, AHost: string;
      const ABasePath: string = '/';
      ASchemes: TSwagTransferProtocolSchemes = [tpsHttp]);
    class procedure Serve(const ABasePath: string = '/swagger');

    /// <summary>
    /// Retorna o doc em construção sem liberá-lo. Usar antes de Serve para
    /// registrar integrações que precisam ler o doc (ex: TMcpServer.Register).
    /// </summary>
    class function CurrentDoc: TSwagDoc;

    /// <summary>
    /// Lista de chaves "METHOD:PATH" de rotas marcadas com .NoMcp().
    /// Passar para TMcpServer.Register como AExcluded para omiti-las das tools.
    /// </summary>
    class function McpExcluded: TStringList;

    class function Get(const AUri: string): TRouteDocBuilder;
    class function Post(const AUri: string): TRouteDocBuilder;
    class function Put(const AUri: string): TRouteDocBuilder;
    class function Patch(const AUri: string): TRouteDocBuilder;
    class function Delete(const AUri: string): TRouteDocBuilder;
  end;

  /// <summary>
  /// Builder fluente que registra simultaneamente a rota no Horse e a
  /// entrada correspondente no Swagger. Terminar sempre com Register(handler).
  ///
  /// O schema de cada DTO é gerado automaticamente via RTTI:
  ///   - Tipo do campo  → tipo JSON (string, integer, number, boolean)
  ///   - IOptXxx        → campo opcional (omitido do array "required")
  ///   - INullXxx       → campo anulável (nullable: true)
  ///   - IOptNullXxx    → ambos
  ///   - [SwagProp]     → description + example no schema
  /// </summary>
  TRouteDocBuilder = class
  private
    type
      TResponseEntry = record
        Code: string;
        Desc: string;
        SchemaRef: string;
        IsArray: Boolean;
        IsPaged: Boolean;
      end;
      TQueryParamEntry = record
        Name:      string;
        Desc:      string;
        ParamType: TQueryParamType;
      end;

  private
    FUri: string;
    FOperation: TSwagPathTypeOperation;
    FSummary: string;
    FDescription: string;
    FTags: TList<string>;
    FPathParams:  TList<TQueryParamEntry>;
    FQueryParams: TList<TQueryParamEntry>;
    FBodySchemaRef: string;
    FBodyDesc: string;
    FResponses: TList<TResponseEntry>;
    FNoMcp: Boolean;
    FToolName: string;

    class function NormalizeUri(const AUri: string): string; static;
    class function SchemaNameFromTypeInfo(ATypeInfo: PTypeInfo): string; static;
    class function GenerateSchema(ATypeInfo: PTypeInfo): TJSONObject; static;
    class function BuildPagedSchema(const AItemSchemaRef: string): TJSONObject; static;
    class procedure EnsureDefinition(ATypeInfo: PTypeInfo); static;

  public
    constructor Create(const AUri: string; AOp: TSwagPathTypeOperation);
    destructor Destroy; override;

    function Summary(const AText: string): TRouteDocBuilder;
    function Descr(const AText: string): TRouteDocBuilder;
    function Tag(const ATag: string): TRouteDocBuilder;
    function PathParam(const AName: string;
      const ADesc: string = '';
      AType: TQueryParamType = qptString): TRouteDocBuilder;
    function QueryParam(const AName: string;
      const ADesc: string = '';
      AType: TQueryParamType = qptString): TRouteDocBuilder;

    function Body<I: IInterface>(
      const ADesc: string = ''): TRouteDocBuilder;
    function Response<I: IInterface>(
      const ACode: string;
      const ADesc: string = ''): TRouteDocBuilder;
    function ResponseArray<I: IInterface>(
      const ACode: string;
      const ADesc: string = ''): TRouteDocBuilder;
    function ResponsePaged<I: IInterface>(
      const ACode: string;
      const ADesc: string = ''): TRouteDocBuilder;
    function NoContent(
      const ACode: string = '204';
      const ADesc: string = 'No Content'): TRouteDocBuilder;

    /// <summary>
    /// Define o nome explícito da tool MCP gerada para esta rota, sobrescrevendo
    /// o nome derivado automaticamente de método+path.
    /// Usar quando o plural irregular ou composto produziria um nome errado.
    /// Exemplos: .ToolName('list_operacao'), .ToolName('get_perfil')
    /// </summary>
    function ToolName(const AName: string): TRouteDocBuilder;

    /// <summary>
    /// Exclui esta rota da geração de tools MCP. A rota continua registrada
    /// no Horse e documentada no Swagger — apenas não vira tool MCP.
    /// </summary>
    function NoMcp: TRouteDocBuilder;

    /// <summary>
    /// Finaliza o builder: adiciona a operação ao Swagger doc e registra a
    /// rota no Horse. O builder é liberado automaticamente após este método.
    /// </summary>
    procedure Register(const AHandler: THorseCallback);
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Horse,
  Common.JsonMapper;

// ---------------------------------------------------------------------------
// Schema generation helpers (standalone, implementation-only)
// ---------------------------------------------------------------------------

function LowerFirst(const S: string): string;
begin
  if S.IsEmpty then Exit('');
  Result := LowerCase(Copy(S, 1, 1)) + Copy(S, 2, MaxInt);
end;

function ParseOptionalName(const AName: string;
  out ABase: string; out AIsOpt, AIsNull: Boolean): Boolean;
begin
  if AName.StartsWith('IOptNull') then
  begin
    AIsOpt := True;  AIsNull := True;
    ABase  := AName.Substring(8);
    Exit(True);
  end;
  if AName.StartsWith('INull') then
  begin
    AIsOpt := False; AIsNull := True;
    ABase  := AName.Substring(5);
    Exit(True);
  end;
  if AName.StartsWith('IOpt') then
  begin
    AIsOpt := True;  AIsNull := False;
    ABase  := AName.Substring(4);
    Exit(True);
  end;
  Result := False;
end;

procedure BaseTypeToSwagger(const ABase: string;
  out AJsonType, AFormat: string);
begin
  AFormat := '';
  if      ABase = 'String'   then AJsonType := 'string'
  else if ABase = 'Integer'  then begin AJsonType := 'integer'; AFormat := 'int32';     end
  else if ABase = 'Int64'    then begin AJsonType := 'integer'; AFormat := 'int64';     end
  else if ABase = 'Double'   then begin AJsonType := 'number';  AFormat := 'double';    end
  else if ABase = 'Single'   then begin AJsonType := 'number';  AFormat := 'float';     end
  else if ABase = 'Currency' then       AJsonType := 'number'
  else if ABase = 'Boolean'  then       AJsonType := 'boolean'
  else if ABase = 'DateTime' then begin AJsonType := 'string';  AFormat := 'date-time'; end
  else if ABase = 'Guid'     then begin AJsonType := 'string';  AFormat := 'uuid';      end
  else                                  AJsonType := 'string';
end;

procedure RttiTypeToSwagger(ARttiType: TRttiType;
  out AJsonType, AFormat: string);
begin
  AFormat := '';
  case ARttiType.TypeKind of
    tkUString, tkString, tkWString: AJsonType := 'string';
    tkInteger: begin AJsonType := 'integer'; AFormat := 'int32'; end;
    tkInt64:   begin AJsonType := 'integer'; AFormat := 'int64'; end;
    tkFloat:
    begin
      if      ARttiType.Name = 'TDateTime' then begin AJsonType := 'string';  AFormat := 'date-time'; end
      else if ARttiType.Name = 'Currency'  then       AJsonType := 'number'
      else if ARttiType.Name = 'Single'    then begin AJsonType := 'number';  AFormat := 'float';     end
      else                                      begin AJsonType := 'number';  AFormat := 'double';    end;
    end;
    tkEnumeration:
      if ARttiType.Name = 'Boolean' then AJsonType := 'boolean'
      else                               AJsonType := 'string';
  else
    AJsonType := 'string';
  end;
end;

function BuildPropertyJson(ARttiType: TRttiType;
  out AIsRequired: Boolean; out ANullable: Boolean;
  AAttr: SwagProp; AMin: SwagMin; AMax: SwagMax;
  AEnum: SwagEnum; APattern: SwagPattern): TJSONObject;
var
  LBase, LJsonType, LFormat: string;
  LIsOpt, LIsNull: Boolean;
  LExampleJson: TJSONValue;
begin
  AIsRequired := True;
  ANullable   := False;
  LFormat     := '';

  if (ARttiType.TypeKind = tkInterface) and
     ParseOptionalName(ARttiType.Name, LBase, LIsOpt, LIsNull) then
  begin
    AIsRequired := not LIsOpt;
    ANullable   := LIsNull;
    BaseTypeToSwagger(LBase, LJsonType, LFormat);
  end
  else
    RttiTypeToSwagger(ARttiType, LJsonType, LFormat);

  // Attribute format overrides the inferred one (e.g. 'email', 'uri')
  if Assigned(AAttr) and not AAttr.Format.IsEmpty then
    LFormat := AAttr.Format;

  Result := TJSONObject.Create;
  Result.AddPair('type', LJsonType);
  if LFormat <> '' then
    Result.AddPair('format', LFormat);

  if Assigned(AAttr) then
  begin
    if not AAttr.Description.IsEmpty then
      Result.AddPair('description', AAttr.Description);
    if not AAttr.Example.IsEmpty then
    begin
      // Try to emit the example as its natural JSON type (number, bool, etc.)
      LExampleJson := TJSONObject.ParseJSONValue(AAttr.Example);
      if Assigned(LExampleJson) then
        Result.AddPair('example', LExampleJson)
      else
        Result.AddPair('example', AAttr.Example);
    end;
  end;

  if Assigned(AMin) then
  begin
    if LJsonType = 'string' then Result.AddPair('minLength', TJSONNumber.Create(AMin.Value))
                            else Result.AddPair('minimum',   TJSONNumber.Create(AMin.Value));
  end;
  if Assigned(AMax) then
  begin
    if LJsonType = 'string' then Result.AddPair('maxLength', TJSONNumber.Create(AMax.Value))
                            else Result.AddPair('maximum',   TJSONNumber.Create(AMax.Value));
  end;

  if Assigned(AEnum) then
  begin
    var LEnumArr := TJSONArray.Create;
    for var LItem in AEnum.Values.Split([',']) do
      LEnumArr.Add(Trim(LItem));
    Result.AddPair('enum', LEnumArr);
  end;

  if Assigned(APattern) then
    Result.AddPair('pattern', APattern.Value);
end;

// ---------------------------------------------------------------------------
// TRouteDocBuilder — private class methods
// ---------------------------------------------------------------------------

class function TRouteDocBuilder.NormalizeUri(const AUri: string): string;
begin
  // Convert Horse-style :param to Swagger-style {param}
  Result := TRegEx.Replace(AUri, ':(\w+)', '{$1}');
end;

class function TRouteDocBuilder.SchemaNameFromTypeInfo(ATypeInfo: PTypeInfo): string;
begin
  Result := string(ATypeInfo.Name);
  if Result.StartsWith('I') then
    Result := Result.Substring(1);
  if Result.EndsWith('DTO') then
    Result := Result.Substring(0, Result.Length - 3);
end;

class function TRouteDocBuilder.GenerateSchema(ATypeInfo: PTypeInfo): TJSONObject;
var
  LCtx: TRttiContext;
  LImplClass: TClass;
  LRttiType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LFieldName: string;
  LPropJson: TJSONObject;
  LProps: TJSONObject;
  LRequired: TJSONArray;
  LIsRequired, LNullable: Boolean;
  LAttr: TCustomAttribute;
  LSwagProp: SwagProp;
begin
  LProps    := TJSONObject.Create;
  LRequired := TJSONArray.Create;

  LImplClass := TJsonMapper.FindImplClass(ATypeInfo);
  if Assigned(LImplClass) then
  begin
    LCtx := TRttiContext.Create;
    try
      LRttiType := LCtx.GetType(LImplClass) as TRttiInstanceType;
      for LMethod in LRttiType.GetDeclaredMethods do
      begin
        if LMethod.MethodKind <> mkFunction then Continue;
        if Length(LMethod.GetParameters) > 0          then Continue;
        if LMethod.ReturnType = nil                   then Continue;
        if not LMethod.Name.StartsWith('Get', True)   then Continue;

        LFieldName := LowerFirst(LMethod.Name.Substring(3));
        if LFieldName.IsEmpty then Continue;

        LSwagProp := nil;
        var LSwagMin:     SwagMin     := nil;
        var LSwagMax:     SwagMax     := nil;
        var LSwagEnum:    SwagEnum    := nil;
        var LSwagPattern: SwagPattern := nil;
        for LAttr in LMethod.GetAttributes do
        begin
          if      LAttr is SwagProp    then LSwagProp    := SwagProp(LAttr)
          else if LAttr is SwagMin     then LSwagMin     := SwagMin(LAttr)
          else if LAttr is SwagMax     then LSwagMax     := SwagMax(LAttr)
          else if LAttr is SwagEnum    then LSwagEnum    := SwagEnum(LAttr)
          else if LAttr is SwagPattern then LSwagPattern := SwagPattern(LAttr);
        end;

        LIsRequired := True;
        LNullable   := False;
        LPropJson   := BuildPropertyJson(LMethod.ReturnType, LIsRequired, LNullable,
                         LSwagProp, LSwagMin, LSwagMax, LSwagEnum, LSwagPattern);

        if LNullable then
          LPropJson.AddPair('nullable', TJSONBool.Create(True));

        LProps.AddPair(LFieldName, LPropJson);
        if LIsRequired then
          LRequired.Add(LFieldName);
      end;
    finally
      LCtx.Free;
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', LProps);
  if LRequired.Count > 0 then
    Result.AddPair('required', LRequired)
  else
    FreeAndNil(LRequired);
end;

class function TRouteDocBuilder.BuildPagedSchema(const AItemSchemaRef: string): TJSONObject;
var
  LProps:    TJSONObject;
  LRequired: TJSONArray;
  LProp:     TJSONObject;
  LItemsRef: TJSONObject;
  LItemsArr: TJSONObject;

  procedure AddIntProp(const AName: string);
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('type', 'integer');
    LProp.AddPair('format', 'int32');
    LProps.AddPair(AName, LProp);
  end;

  procedure AddBoolProp(const AName: string);
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('type', 'boolean');
    LProps.AddPair(AName, LProp);
  end;

begin
  LProps := TJSONObject.Create;
  AddIntProp('page');
  AddIntProp('limit');
  AddIntProp('total');
  AddIntProp('totalPages');
  AddBoolProp('hasNext');
  AddBoolProp('hasPrev');

  LItemsRef := TJSONObject.Create;
  LItemsRef.AddPair('$ref', '#/definitions/' + AItemSchemaRef);
  LItemsArr := TJSONObject.Create;
  LItemsArr.AddPair('type', 'array');
  LItemsArr.AddPair('items', LItemsRef);
  LProps.AddPair('items', LItemsArr);

  LRequired := TJSONArray.Create;
  LRequired.Add('page');
  LRequired.Add('limit');
  LRequired.Add('total');
  LRequired.Add('totalPages');
  LRequired.Add('hasNext');
  LRequired.Add('hasPrev');
  LRequired.Add('items');

  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', LProps);
  Result.AddPair('required', LRequired);
end;

class procedure TRouteDocBuilder.EnsureDefinition(ATypeInfo: PTypeInfo);
var
  LName: string;
  LDef: TSwagDefinition;
  I: Integer;
begin
  if not Assigned(TRouteDoc.FDoc) then Exit;

  LName := SchemaNameFromTypeInfo(ATypeInfo);
  for I := 0 to TRouteDoc.FDoc.Definitions.Count - 1 do
    if TRouteDoc.FDoc.Definitions[I].Name = LName then Exit;

  LDef := TSwagDefinition.Create;
  LDef.Name       := LName;
  LDef.JsonSchema := GenerateSchema(ATypeInfo);
  TRouteDoc.FDoc.Definitions.Add(LDef);
end;

// ---------------------------------------------------------------------------
// TRouteDocBuilder — public
// ---------------------------------------------------------------------------

constructor TRouteDocBuilder.Create(const AUri: string;
  AOp: TSwagPathTypeOperation);
begin
  inherited Create;
  FUri       := AUri;
  FOperation := AOp;
  FTags       := TList<string>.Create;
  FPathParams  := TList<TQueryParamEntry>.Create;
  FQueryParams := TList<TQueryParamEntry>.Create;
  FResponses   := TList<TResponseEntry>.Create;
end;

destructor TRouteDocBuilder.Destroy;
begin
  FreeAndNil(FTags);
  FreeAndNil(FPathParams);
  FreeAndNil(FQueryParams);
  FreeAndNil(FResponses);
  inherited;
end;

function TRouteDocBuilder.Summary(const AText: string): TRouteDocBuilder;
begin
  FSummary := AText;
  Result   := Self;
end;

function TRouteDocBuilder.Descr(const AText: string): TRouteDocBuilder;
begin
  FDescription := AText;
  Result       := Self;
end;

function TRouteDocBuilder.Tag(const ATag: string): TRouteDocBuilder;
begin
  FTags.Add(ATag);
  Result := Self;
end;

function TRouteDocBuilder.PathParam(const AName: string;
  const ADesc: string; AType: TQueryParamType): TRouteDocBuilder;
var
  LEntry: TQueryParamEntry;
begin
  LEntry.Name      := AName;
  LEntry.Desc      := ADesc;
  LEntry.ParamType := AType;
  FPathParams.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.QueryParam(const AName: string;
  const ADesc: string; AType: TQueryParamType): TRouteDocBuilder;
var
  LEntry: TQueryParamEntry;
begin
  LEntry.Name      := AName;
  LEntry.Desc      := ADesc;
  LEntry.ParamType := AType;
  FQueryParams.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.Body<I>(const ADesc: string): TRouteDocBuilder;
begin
  EnsureDefinition(TypeInfo(I));
  FBodySchemaRef := SchemaNameFromTypeInfo(TypeInfo(I));
  FBodyDesc      := ADesc;
  Result         := Self;
end;

function TRouteDocBuilder.Response<I>(const ACode: string;
  const ADesc: string): TRouteDocBuilder;
var
  LEntry: TResponseEntry;
begin
  EnsureDefinition(TypeInfo(I));
  LEntry.Code      := ACode;
  LEntry.Desc      := ADesc;
  LEntry.SchemaRef := SchemaNameFromTypeInfo(TypeInfo(I));
  LEntry.IsArray   := False;
  LEntry.IsPaged   := False;
  FResponses.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.ResponseArray<I>(const ACode: string;
  const ADesc: string): TRouteDocBuilder;
var
  LEntry: TResponseEntry;
begin
  EnsureDefinition(TypeInfo(I));
  LEntry.Code      := ACode;
  LEntry.Desc      := ADesc;
  LEntry.SchemaRef := SchemaNameFromTypeInfo(TypeInfo(I));
  LEntry.IsArray   := True;
  LEntry.IsPaged   := False;
  FResponses.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.ResponsePaged<I>(const ACode: string;
  const ADesc: string): TRouteDocBuilder;
var
  LEntry: TResponseEntry;
begin
  EnsureDefinition(TypeInfo(I));
  LEntry.Code      := ACode;
  LEntry.Desc      := ADesc;
  LEntry.SchemaRef := SchemaNameFromTypeInfo(TypeInfo(I));
  LEntry.IsArray   := False;
  LEntry.IsPaged   := True;
  FResponses.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.NoContent(const ACode: string;
  const ADesc: string): TRouteDocBuilder;
var
  LEntry: TResponseEntry;
begin
  LEntry.Code      := ACode;
  LEntry.Desc      := ADesc;
  LEntry.SchemaRef := '';
  LEntry.IsArray   := False;
  LEntry.IsPaged   := False;
  FResponses.Add(LEntry);
  Result := Self;
end;

function TRouteDocBuilder.ToolName(const AName: string): TRouteDocBuilder;
begin
  FToolName := AName;
  Result    := Self;
end;

function TRouteDocBuilder.NoMcp: TRouteDocBuilder;
begin
  FNoMcp := True;
  Result := Self;
end;

procedure TRouteDocBuilder.Register(const AHandler: THorseCallback);
var
  LPath: TSwagPath;
  LOp: TSwagPathOperation;
  LParam: TSwagRequestParameter;
  LPair: TQueryParamEntry;
  LQPair: TQueryParamEntry;
  LResp: TSwagResponse;
  LEntry: TResponseEntry;
  LItemsSchema, LArraySchema: TJSONObject;
  LTag: string;
begin
  try
    // --- Build Swagger entry (only when Init was called) ---
    if Assigned(TRouteDoc.FDoc) then
    begin
      TRouteDoc.FindOrCreatePath(FUri, LPath);

      LOp := TSwagPathOperation.Create;
      LOp.Operation   := FOperation;
      LOp.Summary     := FSummary;
      LOp.Description := FDescription;
      LOp.OperationId := FToolName;

      for LTag in FTags do
        LOp.Tags.Add(LTag);

      // Path parameters
      for LPair in FPathParams do
      begin
        LParam := TSwagRequestParameter.Create;
        LParam.Name          := LPair.Name;
        LParam.InLocation    := rpiPath;
        if LPair.ParamType = qptInteger then LParam.TypeParameter := stpInteger
                                        else LParam.TypeParameter := stpString;
        LParam.Description   := LPair.Desc;
        LParam.Required      := True;
        LOp.Parameters.Add(LParam);
      end;

      // Query parameters
      for LQPair in FQueryParams do
      begin
        LParam := TSwagRequestParameter.Create;
        LParam.Name          := LQPair.Name;
        LParam.InLocation    := rpiQuery;
        if LQPair.ParamType = qptInteger then LParam.TypeParameter := stpInteger
                                        else LParam.TypeParameter := stpString;
        LParam.Description   := LQPair.Desc;
        LParam.Required      := False;
        LOp.Parameters.Add(LParam);
      end;

      // Body parameter
      if FBodySchemaRef <> '' then
      begin
        LParam := TSwagRequestParameter.Create;
        LParam.Name        := 'body';
        LParam.InLocation  := rpiBody;
        LParam.Description := FBodyDesc;
        LParam.Required    := True;
        LParam.Schema.Name := FBodySchemaRef;
        LOp.Parameters.Add(LParam);
      end;

      // Responses
      for LEntry in FResponses do
      begin
        LResp := TSwagResponse.Create;
        LResp.StatusCode  := LEntry.Code;
        LResp.Description := LEntry.Desc;

        if LEntry.SchemaRef <> '' then
        begin
          if LEntry.IsPaged then
            LResp.Schema.JsonSchema := BuildPagedSchema(LEntry.SchemaRef)
          else if LEntry.IsArray then
          begin
            LItemsSchema := TJSONObject.Create;
            LItemsSchema.AddPair('$ref', '#/definitions/' + LEntry.SchemaRef);
            LArraySchema := TJSONObject.Create;
            LArraySchema.AddPair('type', 'array');
            LArraySchema.AddPair('items', LItemsSchema);
            LResp.Schema.JsonSchema := LArraySchema;
          end
          else
            LResp.Schema.Name := LEntry.SchemaRef;
        end;

        LOp.Responses.Add(LEntry.Code, LResp);
      end;

      LPath.Operations.Add(LOp);

      if FNoMcp then
      begin
        if not Assigned(TRouteDoc.FMcpExcluded) then
          TRouteDoc.FMcpExcluded := TStringList.Create;
        case FOperation of
          ohvGet:    TRouteDoc.FMcpExcluded.Add('GET:'    + NormalizeUri(FUri));
          ohvPost:   TRouteDoc.FMcpExcluded.Add('POST:'   + NormalizeUri(FUri));
          ohvPut:    TRouteDoc.FMcpExcluded.Add('PUT:'    + NormalizeUri(FUri));
          ohvPatch:  TRouteDoc.FMcpExcluded.Add('PATCH:'  + NormalizeUri(FUri));
          ohvDelete: TRouteDoc.FMcpExcluded.Add('DELETE:' + NormalizeUri(FUri));
        end;
      end;
    end;

    // --- Register Horse route ---
    case FOperation of
      ohvGet:    THorse.Get(FUri, AHandler);
      ohvPost:   THorse.Post(FUri, AHandler);
      ohvPut:    THorse.Put(FUri, AHandler);
      ohvPatch:  THorse.Patch(FUri, AHandler);
      ohvDelete: THorse.Delete(FUri, AHandler);
    end;

  finally
    Free; // self-destruct after chaining ends
  end;
end;

// ---------------------------------------------------------------------------
// TRouteDoc
// ---------------------------------------------------------------------------

class destructor TRouteDoc.Destroy;
begin
  FreeAndNil(FDoc);
  FreeAndNil(FMcpExcluded);
end;

class function TRouteDoc.McpExcluded: TStringList;
begin
  if not Assigned(FMcpExcluded) then
    FMcpExcluded := TStringList.Create;
  Result := FMcpExcluded;
end;

class procedure TRouteDoc.FindOrCreatePath(const AUri: string;
  out APath: TSwagPath);
var
  LNormUri: string;
  LExisting: TSwagPath;
begin
  LNormUri := TRouteDocBuilder.NormalizeUri(AUri);
  for LExisting in FDoc.Paths do
    if LExisting.Uri = LNormUri then
    begin
      APath := LExisting;
      Exit;
    end;
  APath     := TSwagPath.Create;
  APath.Uri := LNormUri;
  FDoc.Paths.Add(APath);
end;

class procedure TRouteDoc.Init(const ATitle, AVersion, AHost: string;
  const ABasePath: string; ASchemes: TSwagTransferProtocolSchemes);
begin
  FreeAndNil(FDoc);
  FreeAndNil(FMcpExcluded);
  FDoc := TSwagDoc.Create;
  FDoc.Info.Title   := ATitle;
  FDoc.Info.Version := AVersion;
  FDoc.Host         := AHost;
  FDoc.BasePath     := ABasePath;
  FDoc.Schemes      := ASchemes;
  FDoc.Consumes.Add('application/json');
  FDoc.Produces.Add('application/json');
end;

class function TRouteDoc.CurrentDoc: TSwagDoc;
begin
  Result := FDoc;
end;

class procedure TRouteDoc.Serve(const ABasePath: string);
begin
  if not Assigned(FDoc) then Exit;
  try
    TSwaggerServer.Register(FDoc, ABasePath);
  finally
    FreeAndNil(FDoc);
  end;
end;

class function TRouteDoc.Get(const AUri: string): TRouteDocBuilder;
begin
  Result := TRouteDocBuilder.Create(AUri, ohvGet);
end;

class function TRouteDoc.Post(const AUri: string): TRouteDocBuilder;
begin
  Result := TRouteDocBuilder.Create(AUri, ohvPost);
end;

class function TRouteDoc.Put(const AUri: string): TRouteDocBuilder;
begin
  Result := TRouteDocBuilder.Create(AUri, ohvPut);
end;

class function TRouteDoc.Patch(const AUri: string): TRouteDocBuilder;
begin
  Result := TRouteDocBuilder.Create(AUri, ohvPatch);
end;

class function TRouteDoc.Delete(const AUri: string): TRouteDocBuilder;
begin
  Result := TRouteDocBuilder.Create(AUri, ohvDelete);
end;

end.
