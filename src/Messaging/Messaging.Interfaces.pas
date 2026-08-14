unit Messaging.Interfaces;

{
  Interfaces de mensageria — protocolo e broker agnósticos.
  Adapters concretos (AMQP, STOMP, etc.) implementam IMessageConsumer e IMessagePublisher.

  Uso típico (consumidor):
    LConsumer := TRabbitMQConsumer.Create(LConfig);
    LConsumer.Subscribe('minha_queue', TMinhaHandler.Create(LService));
    LConsumer.Start;
    ...
    LConsumer.Stop;

  O projeto implementa apenas IMessageHandler — o que fazer quando a mensagem chega.
  O adapter concreto é responsável por conexão, reconexão e thread de consumo.
}

interface

type
  TMessagingConfig = class
  public
    Host:     string;
    Port:     Integer;
    User:     string;
    Password: string;
    VHost:    string;
    constructor Create;
  end;

  IMessagePayload = interface
    ['{C4D949FE-2C33-4481-9814-AC3299B5849A}']
    function GetBody: string;
    function GetRoutingKey: string;
    function GetHeader(const AKey: string): string;
    property Body: string read GetBody;
    property RoutingKey: string read GetRoutingKey;
  end;

  IMessageHandler = interface
    ['{BAFF6F9A-C377-405E-BB79-AE6393429F6A}']
    procedure Handle(const APayload: IMessagePayload);
  end;

  IMessageConsumer = interface
    ['{E66DAB5C-2F44-43C7-83DC-EAF25F6A3143}']
    procedure Subscribe(const AQueue: string; const AHandler: IMessageHandler);
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
  end;

  IMessagePublisher = interface
    ['{2F7D889A-4A97-40D5-AA5F-FFACA3800A7A}']
    procedure Publish(const AExchange, ARoutingKey, ABody: string);
  end;

  { IMessagingFactory
    Implementada pelo adapter concreto (fora desta biblioteca — ver
    Messaging.Adapters.Registry). Cria consumers/publishers sem que o
    projeto de negócio precise referenciar o adapter diretamente. }

  IMessagingFactory = interface
    ['{DB3CA3AB-DDD6-45F1-BDF1-CF34CD5A86E2}']
    function CreateConsumer(const AConfig: TMessagingConfig): IMessageConsumer;
    function CreatePublisher(const AConfig: TMessagingConfig): IMessagePublisher;
  end;

implementation

constructor TMessagingConfig.Create;
begin
  Host     := 'localhost';
  Port     := 5672;
  User     := 'guest';
  Password := 'guest';
  VHost    := '/';
end;

end.
