unit Common.JsonMapperTests;

interface

uses
  DUnitX.TestFramework,
  System.TypInfo,
  Common.JsonMapper,
  Common.DTO.Base,
  Common.Optionals;

type
  // Interfaces exclusivas deste arquivo — GUIDs únicos garantem isolamento
  IFindImplTest = interface
    ['{2AA7DBC2-A739-4F07-B2E6-74BF74A7703A}']
  end;

  IFindImplNotRegistered = interface
    ['{ED8AA6C9-02EC-4626-9857-1E051741D275}']
  end;

  TFindImplTest = class(TInterfacedObject, IFindImplTest)
  end;

  // Regressão: DTO de Find que herda de IFindPaginationDTOBase/TFindPaginationDTOBase
  // sem redeclarar Page/Limit/OrderBy/Search (é o padrão documentado no CLAUDE.md,
  // "não redeclare"). FromJson<I> precisa enxergar esses campos herdados mesmo
  // assim — regressão do bug em que TFindPaginationDTOBase não declarava a
  // `property` na classe, só na interface.
  IPagInheritTest = interface(IFindPaginationDTOBase)
    ['{6C9E6E8A-2C2F-4C1A-8B0F-0D2B6E9C3F41}']
    function GetNome: string;
    procedure SetNome(AValue: string);
    property Nome: string read GetNome write SetNome;
  end;

  TPagInheritTest = class(TFindPaginationDTOBase, IPagInheritTest)
  private
    FNome: string;
  public
    class constructor Create;
    function GetNome: string;
    procedure SetNome(AValue: string);
  end;

  [TestFixture]
  TJsonMapperTests = class
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure TestFindImplClass_InterfaceRegistrada_RetornaClasseCorreta;

    [Test]
    procedure TestFindImplClass_InterfaceNaoRegistrada_RetornaNil;

    [Test]
    procedure TestFromJson_CamposHerdadosDeFindPaginationDTOBase_SaoPopulados;
  end;

implementation

{ TPagInheritTest }

class constructor TPagInheritTest.Create;
begin
  TJsonMapper.RegisterMapping<IPagInheritTest, TPagInheritTest>;
end;

function TPagInheritTest.GetNome: string;
begin
  Result := FNome;
end;

procedure TPagInheritTest.SetNome(AValue: string);
begin
  FNome := AValue;
end;

procedure TJsonMapperTests.Setup;
begin
  TJsonMapper.RegisterMapping<IFindImplTest, TFindImplTest>;
end;

procedure TJsonMapperTests.TestFromJson_CamposHerdadosDeFindPaginationDTOBase_SaoPopulados;
var
  LDto: IPagInheritTest;
begin
  LDto := TJsonMapper.FromJson<IPagInheritTest>(
    '{"nome":"teste","page":2,"limit":5,"orderBy":"id","search":"foo"}');

  Assert.AreEqual('teste', LDto.Nome);
  Assert.IsTrue(LDto.Page.HasValue, 'Page (herdado) deveria ter sido populado');
  Assert.AreEqual(2, LDto.Page.Value);
  Assert.IsTrue(LDto.Limit.HasValue, 'Limit (herdado) deveria ter sido populado');
  Assert.AreEqual(5, LDto.Limit.Value);
  Assert.IsTrue(LDto.OrderBy.HasValue, 'OrderBy (herdado) deveria ter sido populado');
  Assert.AreEqual('id', LDto.OrderBy.Value);
  Assert.IsTrue(LDto.Search.HasValue, 'Search (herdado) deveria ter sido populado');
  Assert.AreEqual('foo', LDto.Search.Value);
end;

procedure TJsonMapperTests.TestFindImplClass_InterfaceRegistrada_RetornaClasseCorreta;
var
  LClass: TClass;
begin
  LClass := TJsonMapper.FindImplClass(TypeInfo(IFindImplTest));
  Assert.AreEqual(TFindImplTest, LClass);
end;

procedure TJsonMapperTests.TestFindImplClass_InterfaceNaoRegistrada_RetornaNil;
var
  LClass: TClass;
begin
  LClass := TJsonMapper.FindImplClass(TypeInfo(IFindImplNotRegistered));
  Assert.IsNull(LClass);
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonMapperTests);

end.
