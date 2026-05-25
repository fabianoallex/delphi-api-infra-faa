unit Swagger.Builder;

interface

uses
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
    class procedure FindOrCreatePath(const AUri: string; out APath: TSwagPath);
  public
    class procedure Init(const ATitle, AVersion, AHost: string;
      const ABasePath: string = '/';
      ASchemes: TSwagTransferProtocolSchemes = [tpsHttp]);
    class procedure Serve(const ABasePath: string = '/swagger');

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
      end;

  private
    FUri: string;
    FOperation: TSwagPathTypeOperation;
    FSummary: string;
    FDescription: string;
    FTags: TList<string>;
    FPathParams: TList<TPair<string, string>>;
    FBodySchemaRef: string;
    FBodyDesc: string;
    FResponses: TList<TResponseEntry>;

    class function NormalizeUri(const AUri: string): string; static;
    class function SchemaNameFromTypeInfo(ATypeInfo: PTypeInfo): string; static;
    class function GenerateSchema(ATypeInfo: PTypeInfo): TJSONObject; static;
    class procedure EnsureDefinition(ATypeInfo: PTypeInfo); static;

  public
    constructor Create(const AUri: string; AOp: TSwagPathTypeOperation);
    destructor Destroy; override;

    function Summary(const AText: string): TRouteDocBuilder;
    function Descr(const AText: string): TRouteDocBuilder;
    function Tag(const ATag: string): TRouteDocBuilder;
    function PathParam(const AName: string;
      const ADesc: string = ''): TRouteDocBuilder;

    function Body<I: IInterface>(
      const ADesc: string = ''): TRouteDocBuilder;
    function Response<I: IInterface>(
      const ACode: string;
      const ADesc: string = ''): TRouteDocBuilder;
    function ResponseArray<I: IInterface>(
      const ACode: string;
      const ADesc: string = ''): TRouteDocBuilder;
    function NoContent(
      const ACode: string = '204';
      const ADesc: string = 'No Content'): TRouteDocBuilder;

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
  Horse;

// ---------------------------------------------------------------------------
// Schema generation helpers (standalone, implementation-only)
// ---------------------------------------------------------------------------

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
  AAttr: SwagProp): TJSONObject;
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
  LType: TRttiInterfaceType;
  LMethod: TRttiMethod;
  LFieldName: string;
  LPropJson: TJSONObject;
  LProps: TJSONObject;
  LRequired: TJSONArray;
  LIsRequired, LNullable: Boolean;
  LAttr: TCustomAttribute;
  LSwagProp: SwagProp;
begin
  LCtx := TRttiContext.Create;
  try
    LType  := LCtx.GetType(ATypeInfo) as TRttiInterfaceType;
    LProps   := TJSONObject.Create;
    LRequired := TJSONArray.Create;

    if Assigned(LType) then
    begin
      for LMethod in LType.GetMethods do
      begin
        if not LMethod.Name.StartsWith('Get') then Continue;
        if Length(LMethod.GetParameters) > 0   then Continue;
        if LMethod.ReturnType = nil             then Continue;
        LFieldName := LMethod.Name.Substring(3);
        if LFieldName.IsEmpty then Continue;

        // Read SwagProp attribute from the getter (if present)
        LSwagProp := nil;
        for LAttr in LMethod.GetAttributes do
          if LAttr is SwagProp then
          begin
            LSwagProp := SwagProp(LAttr);
            Break;
          end;

        LIsRequired := True;
        LNullable   := False;
        LPropJson   := BuildPropertyJson(
          LMethod.ReturnType, LIsRequired, LNullable, LSwagProp);

        if LNullable then
          LPropJson.AddPair('nullable', TJSONBool.Create(True));

        LProps.AddPair(LFieldName, LPropJson);
        if LIsRequired then
          LRequired.Add(LFieldName);
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('type', 'object');
    Result.AddPair('properties', LProps);
    if LRequired.Count > 0 then
      Result.AddPair('required', LRequired)
    else
      FreeAndNil(LRequired);

  finally
    LCtx.Free;
  end;
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
  FPathParams := TList<TPair<string, string>>.Create;
  FResponses  := TList<TResponseEntry>.Create;
end;

destructor TRouteDocBuilder.Destroy;
begin
  FreeAndNil(FTags);
  FreeAndNil(FPathParams);
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
  const ADesc: string): TRouteDocBuilder;
begin
  FPathParams.Add(TPair<string, string>.Create(AName, ADesc));
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
  FResponses.Add(LEntry);
  Result := Self;
end;

procedure TRouteDocBuilder.Register(const AHandler: THorseCallback);
var
  LPath: TSwagPath;
  LOp: TSwagPathOperation;
  LParam: TSwagRequestParameter;
  LPair: TPair<string, string>;
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

      for LTag in FTags do
        LOp.Tags.Add(LTag);

      // Path parameters
      for LPair in FPathParams do
      begin
        LParam := TSwagRequestParameter.Create;
        LParam.Name          := LPair.Key;
        LParam.InLocation    := rpiPath;
        LParam.TypeParameter := stpInteger;
        LParam.Description   := LPair.Value;
        LParam.Required      := True;
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
          if LEntry.IsArray then
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
  FDoc := TSwagDoc.Create;
  FDoc.Info.Title   := ATitle;
  FDoc.Info.Version := AVersion;
  FDoc.Host         := AHost;
  FDoc.BasePath     := ABasePath;
  FDoc.Schemes      := ASchemes;
  FDoc.Consumes.Add('application/json');
  FDoc.Produces.Add('application/json');
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
