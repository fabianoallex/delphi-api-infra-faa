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
    ['{A3F1C2D4-B5E6-4F78-9A0B-C1D2E3F4A5B6}']
    function GetBody: string;
    function GetRoutingKey: string;
    function GetHeader(const AKey: string): string;
    property Body: string read GetBody;
    property RoutingKey: string read GetRoutingKey;
  end;

  IMessageHandler = interface
    ['{B4E2D3C5-A6F7-4089-0B1C-D2E3F4A5B6C7}']
    procedure Handle(const APayload: IMessagePayload);
  end;

  IMessageConsumer = interface
    ['{C5F3E4D6-B7A8-4190-1C2D-E3F4A5B6C7D8}']
    procedure Subscribe(const AQueue: string; const AHandler: IMessageHandler);
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
  end;

  IMessagePublisher = interface
    ['{D6A4F5E7-C8B9-4201-2D3E-F4A5B6C7D8E9}']
    procedure Publish(const AExchange, ARoutingKey, ABody: string);
  end;

  { IMessagingFactory
    Implementada pelo adapter concreto (fora desta biblioteca — ver
    Messaging.Adapters.Registry). Cria consumers/publishers sem que o
    projeto de negócio precise referenciar o adapter diretamente. }

  IMessagingFactory = interface
    ['{E7B5A6D8-D9CA-4312-3E4F-A5B6C7D8E9FA}']
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
