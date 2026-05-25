unit Common.JsonMapperTests;

interface

uses
  DUnitX.TestFramework,
  System.TypInfo,
  Common.JsonMapper;

type
  // Interfaces exclusivas deste arquivo — GUIDs únicos garantem isolamento
  IFindImplTest = interface
    ['{F1A2B3C4-D5E6-4F78-9012-3456789ABCDE}']
  end;

  IFindImplNotRegistered = interface
    ['{02345678-9ABC-4DEF-0123-456789ABCDEF}']
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

end.
