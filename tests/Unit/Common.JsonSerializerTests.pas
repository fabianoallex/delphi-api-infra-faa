unit Common.JsonSerializerTests;

interface

uses
  DUnitX.TestFramework
  , Common.JsonMapper
  , Common.Optionals;

type

  [TestFixture]
  TJsonSerializerTests = class
  public
    [Test] procedure TestSerialize_Undefined_IsOmitted;
    [Test] procedure TestSerialize_NullExplicit_IsNull;
    [Test] procedure TestSerialize_OptionalString_Value;
    [Test] procedure TestSerialize_OptionalInteger_Value;
    [Test] procedure TestSerialize_OptionalDouble_Value;
    [Test] procedure TestSerialize_OptionalBoolean_True;
    [Test] procedure TestSerialize_OptionalBoolean_False;
    [Test] procedure TestSerialize_OptionalCurrency_Value;
    [Test] procedure TestSerialize_OptionalDateTime_Value;
    [Test] procedure TestSerialize_OptionalGuid_Value;
    [Test] procedure TestSerialize_OptionalInt64_Value;
    [Test] procedure TestSerialize_NestedInterface;
    [Test] procedure TestSerialize_NilInterface_IsOmitted;
    [Test] procedure TestSerialize_ArrayOfStrings;
    [Test] procedure TestSerialize_ArrayOfInterfaces;
    [Test] procedure TestRoundTrip_DeserializeThenSerialize;
  end;

  // --- Interfaces for serializer tests ---

  ISerProduto = interface
    ['{8B9CE2EF-803A-49F7-B697-2413D04A4918}']
    function GetNome: IOptNullString;
    function GetPreco: IOptNullDouble;
    function GetQuantidade: IOptNullInteger;
    function GetAtivo: IOptNullBoolean;
    function GetDescricao: IOptNullString;
    function GetCodigoBanco: IOptNullInt64;
    function GetPrecoUnit: IOptNullCurrency;
    function GetDataCadastro: IOptNullDateTime;
    function GetExternalId: IOptNullGuid;
    procedure SetNome(AValue: IOptNullString);
    procedure SetPreco(AValue: IOptNullDouble);
    procedure SetQuantidade(AValue: IOptNullInteger);
    procedure SetAtivo(AValue: IOptNullBoolean);
    procedure SetDescricao(AValue: IOptNullString);
    procedure SetCodigoBanco(AValue: IOptNullInt64);
    procedure SetPrecoUnit(AValue: IOptNullCurrency);
    procedure SetDataCadastro(AValue: IOptNullDateTime);
    procedure SetExternalId(AValue: IOptNullGuid);
    property Nome: IOptNullString read GetNome write SetNome;
    property Preco: IOptNullDouble read GetPreco write SetPreco;
    property Quantidade: IOptNullInteger read GetQuantidade write SetQuantidade;
    property Ativo: IOptNullBoolean read GetAtivo write SetAtivo;
    property Descricao: IOptNullString read GetDescricao write SetDescricao;
    property CodigoBanco: IOptNullInt64 read GetCodigoBanco
      write SetCodigoBanco;
    property PrecoUnit: IOptNullCurrency read GetPrecoUnit write SetPrecoUnit;
    property DataCadastro: IOptNullDateTime read GetDataCadastro
      write SetDataCadastro;
    property ExternalId: IOptNullGuid read GetExternalId write SetExternalId;
  end;

  TSerProduto = class(TInterfacedObject, ISerProduto)
  private
    FNome: IOptNullString;
    FPreco: IOptNullDouble;
    FQuantidade: IOptNullInteger;
    FAtivo: IOptNullBoolean;
    FDescricao: IOptNullString;
    FCodigoBanco: IOptNullInt64;
    FPrecoUnit: IOptNullCurrency;
    FDataCadastro: IOptNullDateTime;
    FExternalId: IOptNullGuid;
  public
    function GetNome: IOptNullString;
    function GetPreco: IOptNullDouble;
    function GetQuantidade: IOptNullInteger;
    function GetAtivo: IOptNullBoolean;
    function GetDescricao: IOptNullString;
    function GetCodigoBanco: IOptNullInt64;
    function GetPrecoUnit: IOptNullCurrency;
    function GetDataCadastro: IOptNullDateTime;
    function GetExternalId: IOptNullGuid;
    procedure SetNome(AValue: IOptNullString);
    procedure SetPreco(AValue: IOptNullDouble);
    procedure SetQuantidade(AValue: IOptNullInteger);
    procedure SetAtivo(AValue: IOptNullBoolean);
    procedure SetDescricao(AValue: IOptNullString);
    procedure SetCodigoBanco(AValue: IOptNullInt64);
    procedure SetPrecoUnit(AValue: IOptNullCurrency);
    procedure SetDataCadastro(AValue: IOptNullDateTime);
    procedure SetExternalId(AValue: IOptNullGuid);
    property Nome: IOptNullString read GetNome write SetNome;
    property Preco: IOptNullDouble read GetPreco write SetPreco;
    property Quantidade: IOptNullInteger read GetQuantidade write SetQuantidade;
    property Ativo: IOptNullBoolean read GetAtivo write SetAtivo;
    property Descricao: IOptNullString read GetDescricao write SetDescricao;
    property CodigoBanco: IOptNullInt64 read GetCodigoBanco
      write SetCodigoBanco;
    property PrecoUnit: IOptNullCurrency read GetPrecoUnit write SetPrecoUnit;
    property DataCadastro: IOptNullDateTime read GetDataCadastro
      write SetDataCadastro;
    property ExternalId: IOptNullGuid read GetExternalId write SetExternalId;
  end;

  ISerCidade = interface
    ['{83073798-570F-4E02-8B17-C0351E69A87B}']
    function GetNomeCidade: string;
    procedure SetNomeCidade(AValue: string);
    property NomeCidade: string read GetNomeCidade write SetNomeCidade;
  end;

  TSerCidade = class(TInterfacedObject, ISerCidade)
  private
    FNomeCidade: string;
  public
    function GetNomeCidade: string;
    procedure SetNomeCidade(AValue: string);
    property NomeCidade: string read GetNomeCidade write SetNomeCidade;
  end;

  ISerPessoa = interface
    ['{E7C79880-3E40-473F-B685-B9D550F56754}']
    function GetNomePessoa: string;
    procedure SetNomePessoa(AValue: string);
    function GetCidade: ISerCidade;
    procedure SetCidade(AValue: ISerCidade);
    property NomePessoa: string read GetNomePessoa write SetNomePessoa;
    property Cidade: ISerCidade read GetCidade write SetCidade;
  end;

  TSerPessoa = class(TInterfacedObject, ISerPessoa)
  private
    FNomePessoa: string;
    FCidade: ISerCidade;
  public
    function GetNomePessoa: string;
    procedure SetNomePessoa(AValue: string);
    function GetCidade: ISerCidade;
    procedure SetCidade(AValue: ISerCidade);
  end;

  ISerLista = interface
    ['{97125C6D-45A5-4578-A9E7-12E32AD11E56}']
    function GetTags: TArray<string>;
    procedure SetTags(AValue: TArray<string>);
    function GetCidades: TArray<ISerCidade>;
    procedure SetCidades(AValue: TArray<ISerCidade>);
    property Tags: TArray<string> read GetTags write SetTags;
    property Cidades: TArray<ISerCidade> read GetCidades write SetCidades;
  end;

  TSerLista = class(TInterfacedObject, ISerLista)
  private
    FTags: TArray<string>;
    FCidades: TArray<ISerCidade>;
  public
    function GetTags: TArray<string>;
    procedure SetTags(AValue: TArray<string>);
    function GetCidades: TArray<ISerCidade>;
    procedure SetCidades(AValue: TArray<ISerCidade>);
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils;

{ TSerProduto }

function TSerProduto.GetNome: IOptNullString;
begin
  Result := FNome;
end;

procedure TSerProduto.SetNome(AValue: IOptNullString);
begin
  FNome := AValue;
end;

function TSerProduto.GetPreco: IOptNullDouble;
begin
  Result := FPreco;
end;

procedure TSerProduto.SetPreco(AValue: IOptNullDouble);
begin
  FPreco := AValue;
end;

function TSerProduto.GetQuantidade: IOptNullInteger;
begin
  Result := FQuantidade;
end;

procedure TSerProduto.SetQuantidade(AValue: IOptNullInteger);
begin
  FQuantidade := AValue;
end;

function TSerProduto.GetAtivo: IOptNullBoolean;
begin
  Result := FAtivo;
end;

procedure TSerProduto.SetAtivo(AValue: IOptNullBoolean);
begin
  FAtivo := AValue;
end;

function TSerProduto.GetDescricao: IOptNullString;
begin
  Result := FDescricao;
end;

procedure TSerProduto.SetDescricao(AValue: IOptNullString);
begin
  FDescricao := AValue;
end;

function TSerProduto.GetCodigoBanco: IOptNullInt64;
begin
  Result := FCodigoBanco;
end;

procedure TSerProduto.SetCodigoBanco(AValue: IOptNullInt64);
begin
  FCodigoBanco := AValue;
end;

function TSerProduto.GetPrecoUnit: IOptNullCurrency;
begin
  Result := FPrecoUnit;
end;

procedure TSerProduto.SetPrecoUnit(AValue: IOptNullCurrency);
begin
  FPrecoUnit := AValue;
end;

function TSerProduto.GetDataCadastro: IOptNullDateTime;
begin
  Result := FDataCadastro;
end;

procedure TSerProduto.SetDataCadastro(AValue: IOptNullDateTime);
begin
  FDataCadastro := AValue;
end;

function TSerProduto.GetExternalId: IOptNullGuid;
begin
  Result := FExternalId;
end;

procedure TSerProduto.SetExternalId(AValue: IOptNullGuid);
begin
  FExternalId := AValue;
end;

{ TSerCidade }

function TSerCidade.GetNomeCidade: string;
begin
  Result := FNomeCidade;
end;

procedure TSerCidade.SetNomeCidade(AValue: string);
begin
  FNomeCidade := AValue;
end;

{ TSerPessoa }

function TSerPessoa.GetNomePessoa: string;
begin
  Result := FNomePessoa;
end;

procedure TSerPessoa.SetNomePessoa(AValue: string);
begin
  FNomePessoa := AValue;
end;

function TSerPessoa.GetCidade: ISerCidade;
begin
  Result := FCidade;
end;

procedure TSerPessoa.SetCidade(AValue: ISerCidade);
begin
  FCidade := AValue;
end;

{ TSerLista }

function TSerLista.GetTags: TArray<string>;
begin
  Result := FTags;
end;

procedure TSerLista.SetTags(AValue: TArray<string>);
begin
  FTags := AValue;
end;

function TSerLista.GetCidades: TArray<ISerCidade>;
begin
  Result := FCidades;
end;

procedure TSerLista.SetCidades(AValue: TArray<ISerCidade>);
begin
  FCidades := AValue;
end;

{ Helpers }

function MakeProduto: ISerProduto;
begin
  Result := TSerProduto.Create;
end;

function ParseJson(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

{ TJsonSerializerTests }

procedure TJsonSerializerTests.TestSerialize_Undefined_IsOmitted;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetNome(TOptNullString.Undefined);

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsNull(LObj.GetValue('nome'), 'Undefined field must be omitted');
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_NullExplicit_IsNull;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetNome(TOptNullString.Null);

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsNotNull(LObj.GetValue('nome'), 'Null field must appear in JSON');
    Assert.IsTrue(LObj.GetValue('nome') is TJSONNull,
      'Null field must be JSON null');
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalString_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetNome(TOptNullString.From('Produto A'));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual('Produto A', (LObj.GetValue('nome') as TJSONString).Value);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalInteger_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetQuantidade(TOptNullInteger.From(42));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual(42, (LObj.GetValue('quantidade') as TJSONNumber).AsInt);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalDouble_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetPreco(TOptNullDouble.From(9.99));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual(9.99, (LObj.GetValue('preco') as TJSONNumber)
      .AsDouble, 0.001);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalBoolean_True;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetAtivo(TOptNullBoolean.TrueValue);

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsTrue(LObj.GetValue('ativo') is TJSONTrue);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalBoolean_False;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetAtivo(TOptNullBoolean.FalseValue);

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsTrue(LObj.GetValue('ativo') is TJSONFalse);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalCurrency_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetPrecoUnit(TOptNullCurrency.From(199.90));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual(199.90, (LObj.GetValue('precoUnit') as TJSONNumber)
      .AsDouble, 0.001);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalDateTime_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
  LDt: TDateTime;
begin
  LDt := EncodeDate(2024, 6, 15);
  LP := MakeProduto;
  LP.SetDataCadastro(TOptNullDateTime.From(LDt));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsNotNull(LObj.GetValue('dataCadastro'));
    Assert.IsTrue(LObj.GetValue('dataCadastro') is TJSONString);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalGuid_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
  LGuid: TGUID;
begin
  LGuid := StringToGUID('{AABBCCDD-1122-3344-5566-778899AABBCC}');
  LP := MakeProduto;
  LP.SetExternalId(TOptNullGuid.From(LGuid));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.IsNotNull(LObj.GetValue('externalId'));
    Assert.IsTrue(LObj.GetValue('externalId') is TJSONString);
    Assert.IsTrue(IsEqualGUID(LGuid,
      StringToGUID((LObj.GetValue('externalId') as TJSONString).Value)));
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_OptionalInt64_Value;
var
  LP: ISerProduto;
  LJson: string;
  LObj: TJSONObject;
begin
  LP := MakeProduto;
  LP.SetCodigoBanco(TOptNullInt64.From(9876543210));

  LJson := TJsonMapper.ToJson<ISerProduto>(LP);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual(Int64(9876543210),
      (LObj.GetValue('codigoBanco') as TJSONNumber).AsInt64);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_NestedInterface;
var
  LPessoa: ISerPessoa;
  LCidade: ISerCidade;
  LJson: string;
  LObj: TJSONObject;
  LCidadeObj: TJSONObject;
begin
  LCidade := TSerCidade.Create;
  LCidade.NomeCidade := 'Cuiab�';

  LPessoa := TSerPessoa.Create;
  LPessoa.NomePessoa := 'Fabiano';
  LPessoa.Cidade := LCidade;

  LJson := TJsonMapper.ToJson<ISerPessoa>(LPessoa);
  LObj := ParseJson(LJson);
  try
    Assert.AreEqual('Fabiano',
      (LObj.GetValue('nomePessoa') as TJSONString).Value);
    LCidadeObj := LObj.GetValue('cidade') as TJSONObject;
    Assert.IsNotNull(LCidadeObj);
    Assert.AreEqual('Cuiab�', (LCidadeObj.GetValue('nomeCidade')
      as TJSONString).Value);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_NilInterface_IsOmitted;
var
  LPessoa: ISerPessoa;
  LJson: string;
  LObj: TJSONObject;
begin
  LPessoa := TSerPessoa.Create;
  LPessoa.NomePessoa := 'Fabiano';
  // Cidade is nil — must be omitted

  LJson := TJsonMapper.ToJson<ISerPessoa>(LPessoa);
  LObj := ParseJson(LJson);
  try
    Assert.IsNotNull(LObj.GetValue('nomePessoa'));
    Assert.IsNull(LObj.GetValue('cidade'), 'Nil interface must be omitted');
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_ArrayOfStrings;
var
  LLista: ISerLista;
  LJson: string;
  LObj: TJSONObject;
  LArr: TJSONArray;
begin
  LLista := TSerLista.Create;
  LLista.Tags := ['alpha', 'beta', 'gamma'];

  LJson := TJsonMapper.ToJson<ISerLista>(LLista);
  LObj := ParseJson(LJson);
  try
    LArr := LObj.GetValue('tags') as TJSONArray;
    Assert.IsNotNull(LArr);
    Assert.AreEqual(3, LArr.Count);
    Assert.AreEqual('alpha', (LArr.Items[0] as TJSONString).Value);
    Assert.AreEqual('beta', (LArr.Items[1] as TJSONString).Value);
    Assert.AreEqual('gamma', (LArr.Items[2] as TJSONString).Value);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestSerialize_ArrayOfInterfaces;
var
  LLista: ISerLista;
  LC1, LC2: ISerCidade;
  LJson: string;
  LObj: TJSONObject;
  LArr: TJSONArray;
begin
  LC1 := TSerCidade.Create;
  LC1.NomeCidade := 'Cuiab�';
  LC2 := TSerCidade.Create;
  LC2.NomeCidade := 'V�rzea Grande';

  LLista := TSerLista.Create;
  LLista.Cidades := [LC1, LC2];

  LJson := TJsonMapper.ToJson<ISerLista>(LLista);
  LObj := ParseJson(LJson);
  try
    LArr := LObj.GetValue('cidades') as TJSONArray;
    Assert.IsNotNull(LArr);
    Assert.AreEqual(2, LArr.Count);
    Assert.AreEqual('Cuiab�',
      ((LArr.Items[0] as TJSONObject).GetValue('nomeCidade')
      as TJSONString).Value);
    Assert.AreEqual('V�rzea Grande',
      ((LArr.Items[1] as TJSONObject).GetValue('nomeCidade')
      as TJSONString).Value);
  finally
    LObj.Free;
  end;
end;

procedure TJsonSerializerTests.TestRoundTrip_DeserializeThenSerialize;
var
  LJson: string;
  LP: ISerProduto;
  LJson2: string;
  LObj1, LObj2: TJSONObject;
begin
  TJsonMapper.RegisterMapping<ISerProduto, TSerProduto>;

  LJson := '{"nome":"Produto X","preco":55.50,"quantidade":3,"ativo":true,"descricao":null}';
  LP := TJsonMapper.FromJson<ISerProduto>(LJson);

  LJson2 := TJsonMapper.ToJson<ISerProduto>(LP);

  LObj1 := ParseJson(LJson);
  LObj2 := ParseJson(LJson2);
  try
    Assert.AreEqual((LObj1.GetValue('nome') as TJSONString).Value,
      (LObj2.GetValue('nome') as TJSONString).Value);
    Assert.AreEqual((LObj1.GetValue('preco') as TJSONNumber).AsDouble,
      (LObj2.GetValue('preco') as TJSONNumber).AsDouble, 0.001);
    Assert.AreEqual((LObj1.GetValue('quantidade') as TJSONNumber).AsInt,
      (LObj2.GetValue('quantidade') as TJSONNumber).AsInt);
    Assert.IsTrue(LObj1.GetValue('ativo') is TJSONTrue);
    Assert.IsTrue(LObj2.GetValue('ativo') is TJSONTrue);
    Assert.IsTrue(LObj2.GetValue('descricao') is TJSONNull);
  finally
    LObj1.Free;
    LObj2.Free;
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TJsonSerializerTests);

end.

