unit Common.JsonResolverTests;

interface

uses
  DUnitX.TestFramework, Common.JsonMapper, Common.Optionals;

type
  [TestFixture]
  TJsonResolverTests = class
  public
    [Test] procedure TestMappingAndDeserialization;
    [Test] procedure TestMappingAndDeserialization2;
    [Test] procedure TestMappingWithOptionals;
    [Test] procedure TestDeserialize_CaseInsensitiveKeys;
    [Test] procedure TestDeserialize_OptionalInt64;
    [Test] procedure TestDeserialize_OptionalCurrency;
    [Test] procedure TestDeserialize_OptionalDateTime;
    [Test] procedure TestDeserialize_OptionalGuid;
    [Test] procedure TestDeserialize_ArrayOfStrings;
    [Test] procedure TestDeserialize_ArrayOfIntegers;
    [Test] procedure TestDeserialize_ArrayOfInterfaces;
  end;

  ITestInterface = interface
    ['{0FDE4EA1-428E-46BD-B596-385C4C97E3F0}']
    function GetName: string;
  end;

  TTestImplementation = class(TInterfacedObject, ITestInterface)
  private
    FName: string;
  public
    function GetName: string;
    property Name: string read GetName write FName;
  end;

  ICidade = interface
    ['{C3EA2896-71CE-450C-95D3-1F365B7554A9}']
    function GetNomeCidade: string;
    procedure SetNomeCidade(AValue: string);
    property NomeCidade: string read GetNomeCidade write SetNomeCidade;
  end;

  TCidade = class(TInterfacedObject, ICidade)
  private
    FNomeCidade: string;
  public
    function GetNomeCidade: string;
    procedure SetNomeCidade(AValue: string);
    property NomeCidade: string read GetNomeCidade write SetNomeCidade;
  end;

  IPessoa = interface
    ['{6CF85555-EA12-4AB2-ADC8-6555E48F25D3}']
    function GetNomePessoa: string;
    procedure SetNomePessoa(AValue: string);
    function GetCidade: ICidade;
    procedure SetCidade(AValue: ICidade);
    property NomePessoa: string read GetNomePessoa write SetNomePessoa;
    property Cidade: ICidade read GetCidade write SetCidade;
  end;

  TPessoa = class(TInterfacedObject, IPessoa)
  private
    FNomePessoa: string;
    FCidade: ICidade;
  public
    function GetNomePessoa: string;
    procedure SetNomePessoa(AValue: string);
    function GetCidade: ICidade;
    procedure SetCidade(AValue: ICidade);
    property NomePessoa: string read GetNomePessoa write SetNomePessoa;
    property Cidade: ICidade read GetCidade write SetCidade;
  end;

  // --- Produto: classe com campos Optional ---

  IProduto = interface
    ['{1A2B3C4D-5E6F-4789-ABCD-EF0123456789}']
    function GetNome: IOptNullString;
    procedure SetNome(AValue: IOptNullString);
    function GetPreco: IOptNullDouble;
    procedure SetPreco(AValue: IOptNullDouble);
    function GetQuantidade: IOptNullInteger;
    procedure SetQuantidade(AValue: IOptNullInteger);
    function GetAtivo: IOptNullBoolean;
    procedure SetAtivo(AValue: IOptNullBoolean);
    function GetDescricao: IOptNullString;
    procedure SetDescricao(AValue: IOptNullString);
    function GetObservacao: IOptNullString;
    procedure SetObservacao(AValue: IOptNullString);
    property Nome: IOptNullString read GetNome write SetNome;
    property Preco: IOptNullDouble read GetPreco write SetPreco;
    property Quantidade: IOptNullInteger read GetQuantidade write SetQuantidade;
    property Ativo: IOptNullBoolean read GetAtivo write SetAtivo;
    property Descricao: IOptNullString read GetDescricao write SetDescricao;
    property Observacao: IOptNullString read GetObservacao write SetObservacao;
  end;

  TProduto = class(TInterfacedObject, IProduto)
  private
    FNome: IOptNullString;
    FPreco: IOptNullDouble;
    FQuantidade: IOptNullInteger;
    FAtivo: IOptNullBoolean;
    FDescricao: IOptNullString;
    FObservacao: IOptNullString;
  public
    function GetNome: IOptNullString;
    procedure SetNome(AValue: IOptNullString);
    function GetPreco: IOptNullDouble;
    procedure SetPreco(AValue: IOptNullDouble);
    function GetQuantidade: IOptNullInteger;
    procedure SetQuantidade(AValue: IOptNullInteger);
    function GetAtivo: IOptNullBoolean;
    procedure SetAtivo(AValue: IOptNullBoolean);
    function GetDescricao: IOptNullString;
    procedure SetDescricao(AValue: IOptNullString);
    function GetObservacao: IOptNullString;
    procedure SetObservacao(AValue: IOptNullString);
    property Nome: IOptNullString read GetNome write SetNome;
    property Preco: IOptNullDouble read GetPreco write SetPreco;
    property Quantidade: IOptNullInteger read GetQuantidade write SetQuantidade;
    property Ativo: IOptNullBoolean read GetAtivo write SetAtivo;
    property Descricao: IOptNullString read GetDescricao write SetDescricao;
    property Observacao: IOptNullString read GetObservacao write SetObservacao;
  end;

  // --- Produto2: campos Int64, Currency, DateTime, Guid ---

  IProduto2 = interface
    ['{AABBCCDD-EE11-2233-4455-667788990011}']
    function GetCodigoBanco: IOptNullInt64;
    procedure SetCodigoBanco(AValue: IOptNullInt64);
    function GetPrecoUnit: IOptNullCurrency;
    procedure SetPrecoUnit(AValue: IOptNullCurrency);
    function GetDataCadastro: IOptNullDateTime;
    procedure SetDataCadastro(AValue: IOptNullDateTime);
    function GetExternalId: IOptNullGuid;
    procedure SetExternalId(AValue: IOptNullGuid);
    property CodigoBanco: IOptNullInt64 read GetCodigoBanco write SetCodigoBanco;
    property PrecoUnit: IOptNullCurrency read GetPrecoUnit write SetPrecoUnit;
    property DataCadastro: IOptNullDateTime read GetDataCadastro write SetDataCadastro;
    property ExternalId: IOptNullGuid read GetExternalId write SetExternalId;
  end;

  TProduto2 = class(TInterfacedObject, IProduto2)
  private
    FCodigoBanco: IOptNullInt64;
    FPrecoUnit: IOptNullCurrency;
    FDataCadastro: IOptNullDateTime;
    FExternalId: IOptNullGuid;
  public
    function GetCodigoBanco: IOptNullInt64;
    procedure SetCodigoBanco(AValue: IOptNullInt64);
    function GetPrecoUnit: IOptNullCurrency;
    procedure SetPrecoUnit(AValue: IOptNullCurrency);
    function GetDataCadastro: IOptNullDateTime;
    procedure SetDataCadastro(AValue: IOptNullDateTime);
    function GetExternalId: IOptNullGuid;
    procedure SetExternalId(AValue: IOptNullGuid);
    property CodigoBanco: IOptNullInt64 read GetCodigoBanco write SetCodigoBanco;
    property PrecoUnit: IOptNullCurrency read GetPrecoUnit write SetPrecoUnit;
    property DataCadastro: IOptNullDateTime read GetDataCadastro write SetDataCadastro;
    property ExternalId: IOptNullGuid read GetExternalId write SetExternalId;
  end;

  // --- Arrays ---

  IListaTags = interface
    ['{DEADBEEF-CAFE-BABE-1234-567890ABCDEF}']
    function GetTags: TArray<string>;
    procedure SetTags(AValue: TArray<string>);
    function GetIds: TArray<Integer>;
    procedure SetIds(AValue: TArray<Integer>);
    function GetCidades: TArray<ICidade>;
    procedure SetCidades(AValue: TArray<ICidade>);
    property Tags: TArray<string> read GetTags write SetTags;
    property Ids: TArray<Integer> read GetIds write SetIds;
    property Cidades: TArray<ICidade> read GetCidades write SetCidades;
  end;

  TListaTags = class(TInterfacedObject, IListaTags)
  private
    FTags: TArray<string>;
    FIds: TArray<Integer>;
    FCidades: TArray<ICidade>;
  public
    function GetTags: TArray<string>;
    procedure SetTags(AValue: TArray<string>);
    function GetIds: TArray<Integer>;
    procedure SetIds(AValue: TArray<Integer>);
    function GetCidades: TArray<ICidade>;
    procedure SetCidades(AValue: TArray<ICidade>);
    property Tags: TArray<string> read GetTags write SetTags;
    property Ids: TArray<Integer> read GetIds write SetIds;
    property Cidades: TArray<ICidade> read GetCidades write SetCidades;
  end;

implementation

uses
  System.SysUtils, System.DateUtils;

{ TTestImplementation }

function TTestImplementation.GetName: string;
begin
  Result := FName;
end;

{ TJsonResolverTests }

procedure TJsonResolverTests.TestMappingAndDeserialization;
var
  LIntf: ITestInterface;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<ITestInterface, TTestImplementation>;

  LJson := '{"Name": "Gemini"}';
  LIntf := TJsonMapper.FromJson<ITestInterface>(LJson);

  Assert.IsNotNull(LIntf);
  Assert.AreEqual('Gemini', LIntf.GetName);
end;

procedure TJsonResolverTests.TestMappingAndDeserialization2;
var
  LPessoa: IPessoa;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<ICidade, TCidade>;
  TJsonMapper.RegisterMapping<IPessoa, TPessoa>;

  LJson := '''
    {
      "NomePessoa": "Fabiano",
      "Cidade": {
        "NomeCidade": "Vï¿½rzea Grande"
      }
    }
    ''';

  LPessoa := TJsonMapper.FromJson<IPessoa>(LJson);

  Assert.IsNotNull(LPessoa);
  Assert.AreEqual('Fabiano', LPessoa.NomePessoa);
  Assert.IsNotNull(LPessoa.Cidade);
  Assert.AreEqual('Vï¿½rzea Grande', LPessoa.Cidade.NomeCidade);
end;

procedure TJsonResolverTests.TestMappingWithOptionals;
var
  LProduto: IProduto;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<IProduto, TProduto>;

  LJson := '''
    {
      "Nome": "Produto Teste",
      "Preco": 99.90,
      "Quantidade": 10,
      "Ativo": true,
      "Descricao": null
    }
    ''';

  LProduto := TJsonMapper.FromJson<IProduto>(LJson);

  Assert.IsNotNull(LProduto);

  // Nome: campo com valor string
  Assert.IsNotNull(LProduto.Nome);
  Assert.IsTrue(LProduto.Nome.HasValue);
  Assert.IsFalse(LProduto.Nome.IsNull);
  Assert.AreEqual('Produto Teste', LProduto.Nome.Value);

  // Preco: campo com valor numï¿½rico
  Assert.IsNotNull(LProduto.Preco);
  Assert.IsTrue(LProduto.Preco.HasValue);
  Assert.IsFalse(LProduto.Preco.IsNull);
  Assert.AreEqual(99.90, LProduto.Preco.Value, 0.001);

  // Quantidade: campo com valor inteiro
  Assert.IsNotNull(LProduto.Quantidade);
  Assert.IsTrue(LProduto.Quantidade.HasValue);
  Assert.IsFalse(LProduto.Quantidade.IsNull);
  Assert.AreEqual(10, LProduto.Quantidade.Value);

  // Ativo: campo com valor booleano
  Assert.IsNotNull(LProduto.Ativo);
  Assert.IsTrue(LProduto.Ativo.HasValue);
  Assert.IsFalse(LProduto.Ativo.IsNull);
  Assert.IsTrue(LProduto.Ativo.Value);

  // Descricao: campo explicitamente null no JSON â†’ HasValue=True, IsNull=True
  Assert.IsNotNull(LProduto.Descricao);
  Assert.IsTrue(LProduto.Descricao.HasValue);
  Assert.IsTrue(LProduto.Descricao.IsNull);

  // Observacao: campo ausente no JSON â†’ propriedade permanece nil
  Assert.IsNull(LProduto.Observacao);
end;

procedure TJsonResolverTests.TestDeserialize_CaseInsensitiveKeys;
var
  LPessoa: IPessoa;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<ICidade, TCidade>;
  TJsonMapper.RegisterMapping<IPessoa, TPessoa>;

  LJson := '{"nomePessoa": "Fabiano", "cidade": {"nomeCidade": "Cuiabï¿½"}}';
  LPessoa := TJsonMapper.FromJson<IPessoa>(LJson);

  Assert.IsNotNull(LPessoa);
  Assert.AreEqual('Fabiano', LPessoa.NomePessoa);
  Assert.IsNotNull(LPessoa.Cidade);
  Assert.AreEqual('Cuiabï¿½', LPessoa.Cidade.NomeCidade);
end;

procedure TJsonResolverTests.TestDeserialize_OptionalInt64;
var
  LP: IProduto2;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<IProduto2, TProduto2>;

  LJson := '{"CodigoBanco": 9999999999}';
  LP := TJsonMapper.FromJson<IProduto2>(LJson);

  Assert.IsNotNull(LP.CodigoBanco);
  Assert.IsTrue(LP.CodigoBanco.HasValue);
  Assert.IsFalse(LP.CodigoBanco.IsNull);
  Assert.AreEqual(Int64(9999999999), LP.CodigoBanco.Value);
  Assert.IsNull(LP.PrecoUnit);
end;

procedure TJsonResolverTests.TestDeserialize_OptionalCurrency;
var
  LP: IProduto2;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<IProduto2, TProduto2>;

  LJson := '{"PrecoUnit": 149.99}';
  LP := TJsonMapper.FromJson<IProduto2>(LJson);

  Assert.IsNotNull(LP.PrecoUnit);
  Assert.IsTrue(LP.PrecoUnit.HasValue);
  Assert.IsFalse(LP.PrecoUnit.IsNull);
  Assert.AreEqual(Currency(149.99), LP.PrecoUnit.Value, 0.001);
end;

procedure TJsonResolverTests.TestDeserialize_OptionalDateTime;
var
  LP: IProduto2;
  LJson: string;
  LExpected: TDateTime;
begin
  TJsonMapper.RegisterMapping<IProduto2, TProduto2>;

  LJson := '{"DataCadastro": "2024-01-15"}';
  LP := TJsonMapper.FromJson<IProduto2>(LJson);

  LExpected := ISO8601ToDate('2024-01-15');

  Assert.IsNotNull(LP.DataCadastro);
  Assert.IsTrue(LP.DataCadastro.HasValue);
  Assert.IsFalse(LP.DataCadastro.IsNull);
  Assert.AreEqual(LExpected, LP.DataCadastro.Value, 0);
end;

procedure TJsonResolverTests.TestDeserialize_OptionalGuid;
var
  LP: IProduto2;
  LJson: string;
  LExpected: TGUID;
begin
  TJsonMapper.RegisterMapping<IProduto2, TProduto2>;

  LExpected := StringToGUID('{12345678-1234-1234-1234-123456789ABC}');
  LJson := '{"ExternalId": "{12345678-1234-1234-1234-123456789ABC}"}';
  LP := TJsonMapper.FromJson<IProduto2>(LJson);

  Assert.IsNotNull(LP.ExternalId);
  Assert.IsTrue(LP.ExternalId.HasValue);
  Assert.IsFalse(LP.ExternalId.IsNull);
  Assert.IsTrue(IsEqualGUID(LExpected, LP.ExternalId.Value));
end;

procedure TJsonResolverTests.TestDeserialize_ArrayOfStrings;
var
  LLista: IListaTags;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<IListaTags, TListaTags>;

  LJson := '{"Tags": ["alpha", "beta", "gamma"]}';
  LLista := TJsonMapper.FromJson<IListaTags>(LJson);

  Assert.IsNotNull(LLista);
  Assert.AreEqual(3, Length(LLista.Tags));
  Assert.AreEqual('alpha', LLista.Tags[0]);
  Assert.AreEqual('beta', LLista.Tags[1]);
  Assert.AreEqual('gamma', LLista.Tags[2]);
end;

procedure TJsonResolverTests.TestDeserialize_ArrayOfIntegers;
var
  LLista: IListaTags;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<IListaTags, TListaTags>;

  LJson := '{"Ids": [10, 20, 30]}';
  LLista := TJsonMapper.FromJson<IListaTags>(LJson);

  Assert.IsNotNull(LLista);
  Assert.AreEqual(3, Length(LLista.Ids));
  Assert.AreEqual(10, LLista.Ids[0]);
  Assert.AreEqual(20, LLista.Ids[1]);
  Assert.AreEqual(30, LLista.Ids[2]);
end;

procedure TJsonResolverTests.TestDeserialize_ArrayOfInterfaces;
var
  LLista: IListaTags;
  LJson: string;
begin
  TJsonMapper.RegisterMapping<ICidade, TCidade>;
  TJsonMapper.RegisterMapping<IListaTags, TListaTags>;

  LJson := '{"Cidades": [{"NomeCidade": "Cuiabï¿½"}, {"NomeCidade": "Vï¿½rzea Grande"}]}';
  LLista := TJsonMapper.FromJson<IListaTags>(LJson);

  Assert.IsNotNull(LLista);
  Assert.AreEqual(2, Length(LLista.Cidades));
  Assert.IsNotNull(LLista.Cidades[0]);
  Assert.AreEqual('Cuiabï¿½', LLista.Cidades[0].NomeCidade);
  Assert.IsNotNull(LLista.Cidades[1]);
  Assert.AreEqual('Vï¿½rzea Grande', LLista.Cidades[1].NomeCidade);
end;

{ TCidade }

function TCidade.GetNomeCidade: string;
begin
  Result := FNomeCidade;
end;

procedure TCidade.SetNomeCidade(AValue: string);
begin
  FNomeCidade := AValue;
end;

{ TPessoa }

function TPessoa.GetCidade: ICidade;
begin
  Result := FCidade;
end;

function TPessoa.GetNomePessoa: string;
begin
  Result := FNomePessoa;
end;

procedure TPessoa.SetCidade(AValue: ICidade);
begin
  FCidade := AValue;
end;

procedure TPessoa.SetNomePessoa(AValue: string);
begin
  FNomePessoa := AValue;
end;

{ TProduto }

function TProduto.GetNome: IOptNullString;
begin
  Result := FNome;
end;

procedure TProduto.SetNome(AValue: IOptNullString);
begin
  FNome := AValue;
end;

function TProduto.GetPreco: IOptNullDouble;
begin
  Result := FPreco;
end;

procedure TProduto.SetPreco(AValue: IOptNullDouble);
begin
  FPreco := AValue;
end;

function TProduto.GetQuantidade: IOptNullInteger;
begin
  Result := FQuantidade;
end;

procedure TProduto.SetQuantidade(AValue: IOptNullInteger);
begin
  FQuantidade := AValue;
end;

function TProduto.GetAtivo: IOptNullBoolean;
begin
  Result := FAtivo;
end;

procedure TProduto.SetAtivo(AValue: IOptNullBoolean);
begin
  FAtivo := AValue;
end;

function TProduto.GetDescricao: IOptNullString;
begin
  Result := FDescricao;
end;

procedure TProduto.SetDescricao(AValue: IOptNullString);
begin
  FDescricao := AValue;
end;

function TProduto.GetObservacao: IOptNullString;
begin
  Result := FObservacao;
end;

procedure TProduto.SetObservacao(AValue: IOptNullString);
begin
  FObservacao := AValue;
end;

{ TProduto2 }

function TProduto2.GetCodigoBanco: IOptNullInt64;
begin
  Result := FCodigoBanco;
end;

procedure TProduto2.SetCodigoBanco(AValue: IOptNullInt64);
begin
  FCodigoBanco := AValue;
end;

function TProduto2.GetPrecoUnit: IOptNullCurrency;
begin
  Result := FPrecoUnit;
end;

procedure TProduto2.SetPrecoUnit(AValue: IOptNullCurrency);
begin
  FPrecoUnit := AValue;
end;

function TProduto2.GetDataCadastro: IOptNullDateTime;
begin
  Result := FDataCadastro;
end;

procedure TProduto2.SetDataCadastro(AValue: IOptNullDateTime);
begin
  FDataCadastro := AValue;
end;

function TProduto2.GetExternalId: IOptNullGuid;
begin
  Result := FExternalId;
end;

procedure TProduto2.SetExternalId(AValue: IOptNullGuid);
begin
  FExternalId := AValue;
end;

{ TListaTags }

function TListaTags.GetTags: TArray<string>;
begin
  Result := FTags;
end;

procedure TListaTags.SetTags(AValue: TArray<string>);
begin
  FTags := AValue;
end;

function TListaTags.GetIds: TArray<Integer>;
begin
  Result := FIds;
end;

procedure TListaTags.SetIds(AValue: TArray<Integer>);
begin
  FIds := AValue;
end;

function TListaTags.GetCidades: TArray<ICidade>;
begin
  Result := FCidades;
end;

procedure TListaTags.SetCidades(AValue: TArray<ICidade>);
begin
  FCidades := AValue;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonResolverTests);

end.

