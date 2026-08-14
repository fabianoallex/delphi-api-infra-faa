unit Swagger.SchemaTests;

(*
  Testes de diagnóstico para geração de schema Swagger.
  Objetivo: identificar em qual passo o GenerateSchema falha quando o
  body do Swagger aparece como {}.

  Fluxo esperado:
    1. TJsonMapper.FindImplClass acha a classe concreta via GUID
    2. GetDeclaredMethods retorna os métodos Get* declarados na classe
    3. Os métodos têm MethodKind = mkFunction e ReturnType não-nil
    4. Os atributos [SwagProp] são acessíveis via GetAttributes
    5. LocalGenerateSchema (replica do GenerateSchema) encontra propriedades
*)

interface

uses
  DUnitX.TestFramework,
  System.TypInfo,
  System.Rtti,
  System.JSON,
  System.SysUtils,
  Common.DTO.Base,
  Common.JsonMapper,
  Swagger.Attributes;

type
  // Tipos locais isolados — GUIDs únicos, sem dependência de domínio
  ISchemaTestInsert = interface(IInsertDTOBase)
    ['{C4CA4F72-9C03-493F-9930-6A5FB5749AB0}']
    function GetNome: string;
    function GetCodigo: Integer;
    property Nome: string read GetNome;
    property Codigo: Integer read GetCodigo;
  end;

  TSchemaTestInsert = class(TInsertDTOBase, ISchemaTestInsert)
  private
    FNome: string;
    FCodigo: Integer;
  public
    class constructor Create;
    [SwagProp('Nome de teste', 'Valor')]
    function GetNome: string;
    procedure SetNome(const AValue: string);
    [SwagProp('Código numérico', '42')]
    function GetCodigo: Integer;
    procedure SetCodigo(AValue: Integer);
    property Nome: string read GetNome write SetNome;
    property Codigo: Integer read GetCodigo write SetCodigo;
  end;

  [TestFixture]
  TSwaggerSchemaTests = class
  public
    [Test]
    procedure Test01_FindImplClass_Retorna_TSchemaTestInsert;

    [Test]
    procedure Test02_GetDeclaredMethods_RetornaAlgumMetodo;

    [Test]
    procedure Test03_GetDeclaredMethods_EncontraGetNome;

    [Test]
    procedure Test04_GetNome_MethodKind_EhFunction;

    [Test]
    procedure Test05_GetNome_TemReturnType;

    [Test]
    procedure Test06_SwagPropAtributo_EncontradoViaRtti;

    [Test]
    procedure Test07_GenerateSchemaLocal_TemPropriedades;
  end;

implementation

{ TSchemaTestInsert }

class constructor TSchemaTestInsert.Create;
begin
  TJsonMapper.RegisterMapping<ISchemaTestInsert, TSchemaTestInsert>;
end;

function TSchemaTestInsert.GetNome: string;
begin
  Result := FNome;
end;

procedure TSchemaTestInsert.SetNome(const AValue: string);
begin
  FNome := AValue;
end;

function TSchemaTestInsert.GetCodigo: Integer;
begin
  Result := FCodigo;
end;

procedure TSchemaTestInsert.SetCodigo(AValue: Integer);
begin
  FCodigo := AValue;
end;

// ---------------------------------------------------------------------------
// Replica local do GenerateSchema para testar o algoritmo de forma isolada
// Retorna: {"implClassFound": bool, "propertyCount": N, "properties": {...}}
// ---------------------------------------------------------------------------

function LocalGenerateSchema(ATypeInfo: PTypeInfo): TJSONObject;
var
  LCtx: TRttiContext;
  LImplClass: TClass;
  LRttiType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LProps: TJSONObject;
  LCount: Integer;
begin
  LCount     := 0;
  LProps     := TJSONObject.Create;
  LImplClass := TJsonMapper.FindImplClass(ATypeInfo);

  if Assigned(LImplClass) then
  begin
    LCtx := TRttiContext.Create;
    try
      LRttiType := LCtx.GetType(LImplClass) as TRttiInstanceType;
      for LMethod in LRttiType.GetDeclaredMethods do
      begin
        if LMethod.MethodKind <> mkFunction    then Continue;
        if Length(LMethod.GetParameters) > 0   then Continue;
        if LMethod.ReturnType = nil            then Continue;
        if not LMethod.Name.StartsWith('Get', True) then Continue;
        LProps.AddPair(LMethod.Name.Substring(3), 'found');
        Inc(LCount);
      end;
    finally
      LCtx.Free;
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('implClassFound', TJSONBool.Create(Assigned(LImplClass)));
  Result.AddPair('propertyCount',  TJSONNumber.Create(LCount));
  Result.AddPair('properties',     LProps);
end;

{ TSwaggerSchemaTests }

procedure TSwaggerSchemaTests.Test01_FindImplClass_Retorna_TSchemaTestInsert;
var
  LClass: TClass;
begin
  LClass := TJsonMapper.FindImplClass(TypeInfo(ISchemaTestInsert));
  Assert.AreEqual(TSchemaTestInsert, LClass,
    'FindImplClass não retornou TSchemaTestInsert para ISchemaTestInsert');
end;

procedure TSwaggerSchemaTests.Test02_GetDeclaredMethods_RetornaAlgumMetodo;
var
  LCtx: TRttiContext;
  LType: TRttiInstanceType;
  LMethods: TArray<TRttiMethod>;
begin
  LCtx := TRttiContext.Create;
  try
    LType    := LCtx.GetType(TSchemaTestInsert) as TRttiInstanceType;
    LMethods := LType.GetDeclaredMethods;
    Assert.IsTrue(Length(LMethods) > 0,
      Format('GetDeclaredMethods retornou 0 métodos para TSchemaTestInsert ' +
             '(esperado: GetNome, SetNome, GetCodigo, SetCodigo)', []));
  finally
    LCtx.Free;
  end;
end;

procedure TSwaggerSchemaTests.Test03_GetDeclaredMethods_EncontraGetNome;
var
  LCtx: TRttiContext;
  LType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LFound: Boolean;
begin
  LCtx   := TRttiContext.Create;
  LFound := False;
  try
    LType := LCtx.GetType(TSchemaTestInsert) as TRttiInstanceType;
    for LMethod in LType.GetDeclaredMethods do
      if SameText(LMethod.Name, 'GetNome') then
        LFound := True;
  finally
    LCtx.Free;
  end;
  Assert.IsTrue(LFound,
    'GetDeclaredMethods não encontrou "GetNome" em TSchemaTestInsert');
end;

procedure TSwaggerSchemaTests.Test04_GetNome_MethodKind_EhFunction;
var
  LCtx: TRttiContext;
  LType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LKind: TMethodKind;
  LFound: Boolean;
begin
  LCtx   := TRttiContext.Create;
  LFound := False;
  LKind  := mkProcedure;
  try
    LType := LCtx.GetType(TSchemaTestInsert) as TRttiInstanceType;
    for LMethod in LType.GetDeclaredMethods do
    begin
      if not SameText(LMethod.Name, 'GetNome') then Continue;
      LFound := True;
      LKind  := LMethod.MethodKind;
      Break;
    end;
  finally
    LCtx.Free;
  end;
  Assert.IsTrue(LFound, 'GetNome não encontrado');
  Assert.AreEqual(Integer(mkFunction), Integer(LKind),
    Format('MethodKind de GetNome: esperado mkFunction(%d), obtido %d',
      [Integer(mkFunction), Integer(LKind)]));
end;

procedure TSwaggerSchemaTests.Test05_GetNome_TemReturnType;
var
  LCtx: TRttiContext;
  LType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LHasReturn: Boolean;
begin
  LCtx       := TRttiContext.Create;
  LHasReturn := False;
  try
    LType := LCtx.GetType(TSchemaTestInsert) as TRttiInstanceType;
    for LMethod in LType.GetDeclaredMethods do
    begin
      if not SameText(LMethod.Name, 'GetNome') then Continue;
      LHasReturn := Assigned(LMethod.ReturnType);
      Break;
    end;
  finally
    LCtx.Free;
  end;
  Assert.IsTrue(LHasReturn,
    'GetNome não tem ReturnType acessível via RTTI (sem ele GenerateSchema pula o método)');
end;

procedure TSwaggerSchemaTests.Test06_SwagPropAtributo_EncontradoViaRtti;
var
  LCtx: TRttiContext;
  LType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LAttr: TCustomAttribute;
  LFoundMethod, LFoundAttr: Boolean;
begin
  LCtx         := TRttiContext.Create;
  LFoundMethod := False;
  LFoundAttr   := False;
  try
    LType := LCtx.GetType(TSchemaTestInsert) as TRttiInstanceType;
    for LMethod in LType.GetDeclaredMethods do
    begin
      if not SameText(LMethod.Name, 'GetNome') then Continue;
      LFoundMethod := True;
      for LAttr in LMethod.GetAttributes do
        if LAttr is SwagProp then
        begin
          LFoundAttr := True;
          Break;
        end;
      Break;
    end;
  finally
    LCtx.Free;
  end;
  Assert.IsTrue(LFoundMethod,
    'GetNome não encontrado — teste 03 já deveria ter falhado antes');
  Assert.IsTrue(LFoundAttr,
    '[SwagProp] não encontrado nos atributos de GetNome via GetAttributes ' +
    '(sem {$STRONGLINKTYPES ON}? atributo não linkado?)');
end;

procedure TSwaggerSchemaTests.Test07_GenerateSchemaLocal_TemPropriedades;
var
  LSchema: TJSONObject;
  LImplFound: Boolean;
  LPropCount: Integer;
begin
  LSchema := LocalGenerateSchema(TypeInfo(ISchemaTestInsert));
  try
    LImplFound := (LSchema.GetValue('implClassFound') as TJSONBool).AsBoolean;
    LPropCount := (LSchema.GetValue('propertyCount') as TJSONNumber).AsInt;

    Assert.IsTrue(LImplFound,
      'LocalGenerateSchema: FindImplClass retornou nil para ISchemaTestInsert');
    Assert.IsTrue(LPropCount > 0,
      Format('LocalGenerateSchema: nenhuma propriedade Get* passou pelos filtros ' +
             '(count=%d). Checar: GetDeclaredMethods, MethodKind, ReturnType',
        [LPropCount]));
  finally
    LSchema.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSwaggerSchemaTests);

end.
