unit Messaging.Adapters.Registry;

interface

uses
  System.Generics.Collections,
  Messaging.Interfaces;

type

  { TMessagingRegistry
    Registro de factories de mensageria por nome (ex.: 'rabbitmq', 'stomp').
    Mesmo padrão de Db.Adapters.Registry.TDBRegistry: o projeto de negócio
    resolve o adapter por string, sem referenciar o pacote concreto. O
    adapter concreto se registra sozinho na sua própria unit initialization. }

  TMessagingRegistry = class
  private
    class var FFactories: TDictionary<string, IMessagingFactory>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure RegisterFactory(const AName: string; AFactory: IMessagingFactory);
    class function GetFactory(const AName: string): IMessagingFactory;
  end;

implementation

{ TMessagingRegistry }

class constructor TMessagingRegistry.Create;
begin
  FFactories := TDictionary<string, IMessagingFactory>.Create;
end;

class destructor TMessagingRegistry.Destroy;
begin
  FFactories.Clear;
  FFactories.Free;
end;

class procedure TMessagingRegistry.RegisterFactory(const AName: string; AFactory: IMessagingFactory);
begin
  FFactories.AddOrSetValue(AName, AFactory);
end;

class function TMessagingRegistry.GetFactory(const AName: string): IMessagingFactory;
begin
  if not FFactories.TryGetValue(AName, Result) then
    Result := nil;
end;

end.
