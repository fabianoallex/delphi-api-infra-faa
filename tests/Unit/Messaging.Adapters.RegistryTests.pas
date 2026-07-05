unit Messaging.Adapters.RegistryTests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Messaging.Interfaces,
  Messaging.Adapters.Registry;

type

  { TFakeMessagingFactory
    Stub só pra ter uma instância de IMessagingFactory a registrar/resolver -
    nenhum teste aqui chama CreateConsumer/CreatePublisher de verdade. }

  TFakeMessagingFactory = class(TInterfacedObject, IMessagingFactory)
  public
    function CreateConsumer(const AConfig: TMessagingConfig): IMessageConsumer;
    function CreatePublisher(const AConfig: TMessagingConfig): IMessagePublisher;
  end;

  [TestFixture]
  TMessagingRegistryTests = class
  public
    [Test] procedure RegisterFactory_GetFactory_ReturnsSameInstance;
    [Test] procedure GetFactory_UnknownName_ReturnsNil;
    [Test] procedure RegisterFactory_SameName_OverwritesPrevious;
  end;

implementation

{ TFakeMessagingFactory }

function TFakeMessagingFactory.CreateConsumer(const AConfig: TMessagingConfig): IMessageConsumer;
begin
  Result := nil;
end;

function TFakeMessagingFactory.CreatePublisher(const AConfig: TMessagingConfig): IMessagePublisher;
begin
  Result := nil;
end;

{ TMessagingRegistryTests }

procedure TMessagingRegistryTests.RegisterFactory_GetFactory_ReturnsSameInstance;
var
  LName: string;
  LFactory, LResolved: IMessagingFactory;
begin
  LName    := 'fake-' + TGuid.NewGuid.ToString;
  LFactory := TFakeMessagingFactory.Create;
  TMessagingRegistry.RegisterFactory(LName, LFactory);
  LResolved := TMessagingRegistry.GetFactory(LName);
  Assert.IsNotNull(LResolved, 'GetFactory deve retornar a factory registrada');
  Assert.IsTrue(LResolved = LFactory, 'GetFactory deve retornar a mesma instância registrada');
end;

procedure TMessagingRegistryTests.GetFactory_UnknownName_ReturnsNil;
begin
  Assert.IsNull(TMessagingRegistry.GetFactory('nao-existe-' + TGuid.NewGuid.ToString),
    'Nome não registrado deve retornar nil');
end;

procedure TMessagingRegistryTests.RegisterFactory_SameName_OverwritesPrevious;
var
  LName: string;
  LFirst, LSecond, LResolved: IMessagingFactory;
begin
  LName   := 'fake-' + TGuid.NewGuid.ToString;
  LFirst  := TFakeMessagingFactory.Create;
  LSecond := TFakeMessagingFactory.Create;
  TMessagingRegistry.RegisterFactory(LName, LFirst);
  TMessagingRegistry.RegisterFactory(LName, LSecond);
  LResolved := TMessagingRegistry.GetFactory(LName);
  Assert.IsTrue(LResolved = LSecond, 'Registrar o mesmo nome deve sobrescrever a factory anterior');
end;

initialization
  TDUnitX.RegisterTestFixture(TMessagingRegistryTests);

end.
