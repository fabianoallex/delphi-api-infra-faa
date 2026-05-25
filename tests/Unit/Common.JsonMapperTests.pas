unit Common.JsonMapperTests;

interface

uses
  DUnitX.TestFramework,
  System.TypInfo,
  Common.JsonMapper;

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

  [TestFixture]
  TJsonMapperTests = class
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure TestFindImplClass_InterfaceRegistrada_RetornaClasseCorreta;

    [Test]
    procedure TestFindImplClass_InterfaceNaoRegistrada_RetornaNil;
  end;

implementation

procedure TJsonMapperTests.Setup;
begin
  TJsonMapper.RegisterMapping<IFindImplTest, TFindImplTest>;
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
