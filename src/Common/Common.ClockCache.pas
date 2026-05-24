unit Common.ClockCache;

{-------------------------------------------------------------------------------
  AI VISION & ARCHITECTURAL OVERVIEW: TClockCache
  ------------------------------------------------------------------------------
  OBJETIVO:
    Prover um cache Flyweight de alta performance, thread-safe e previsível,
    projetado para execução ininterrupta (7/24) com baixo overhead de CPU.

  ALGORITMO DE EVICÇÃO: "G-Clock Híbrido com Busca de Vítima Amortizada"
    Diferente de caches tradicionais que usam LRU (caro em multi-thread) ou
    FIFO (ineficiente), este motor utiliza uma lógica de ciclo único:

    1. CICLO ÚNICO (CPU BOUND): Em caso de cache cheio, o algoritmo realiza no
       máximo UM giro completo no anel de memória (FCapacity). Isso garante
       que a latência do 'Put' seja constante e previsível (O(N)).

    2. SISTEMA DE VIDAS (LIVES): Cada item possui um contador de "vidas".
       - Get/Update: Incrementa a vida (recompensa por frequência).
       - Evict (Giro): Decrementa a vida (punição por ociosidade).

    3. BUSCA PELA VÍTIMA IDEAL:
       Durante o giro, o algoritmo tenta encontrar um item com 0 vidas. Se não
       encontrar nenhum após o giro completo, ele sacrifica o "Elo mais Fraco"
       (o item que possuía a menor contagem de vidas encontrada durante o giro).

    4. MODO DE ADIMISSÃO DE NOVOS ITENS:
       A propriedade AdmissionPolicy determina quando que um item novo poderá
       entrar no cache. Com o valor setado para apAlwaysAdmit um item novo sempre
       irá entrar no cache, substiuindo o item menos 'quente', mesmo que o alive
       dele seja superior a zero. No Modo apProtectHotItems um novo item só entra
       no cache se pelo algum item já está com alive em zero.

  BENEFÍCIOS PARA SISTEMAS 7/24:
    - Imutabilidade Garantida: Projetado para trabalhar com Interfaces (ARC).
    - Memória Estável: Ocupação de memória fixa definida no Create.
    - Proteção de Elite: Dados altamente frequentes ("quentes") dificilmente
      são expulsos, protegendo o Hit Rate durante picos de carga.
    - Zero Fragmentation: Pré-alocação de slots evita pressões no Heap Manager.

  IMPLEMENTAÇÃO:
    - Telemetria: Integrado com TCacheHitRate para monitoramento em produção.
-------------------------------------------------------------------------------}

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, Common.SystemContext, 
  System.SyncObjs, System.Rtti, System.Math, System.Generics.Defaults;

type
  TClockItem<K, V> = record
    Key: K;
    Value: V;
    Lives: Integer;     // Contador de frequência (G-Clock)
    InUse: Boolean;
  end;

  TCacheStats = record
    Hits: Int64;
    Misses: Int64;
    Efficiency: Double;
    BeginTime: TDateTime;
    EndTime: TDateTime;
    Uptime: TDateTime;
  end;

  { TCacheHitRate }

  TCacheHitRate = class
  private
    FHits: Int64;
    FMisses: Int64;
    FStartTime: TDateTime;
    FStopTime: TDateTime;
    FActive: Boolean;
    procedure SetStartTime(AValue: TDateTime);
  public
    constructor Create;
    procedure Start;
    procedure Stop;
    procedure IncHits;
    procedure IncMisses;
    function GetCacheStats: TCacheStats;
    property Hits: Int64 read FHits;
    property Misses: Int64 read FMisses;
    property StartTime: TDateTime read FStartTime write SetStartTime;
  end;

  TAdmissionPolicy = (apAlwaysAdmit, apProtectHotItems);

  { TClockCache }

  TClockCache<K, V> = class
  type
    TItem = TClockItem<K, V>;
    TMap = TDictionary<K, Integer>; // Mapeia Chave -> Índice no Array
    TRemoveEvent = procedure(var AValue: V) of object;
  private
    FItems: array of TItem;
    FAdmissionPolicy: TAdmissionPolicy;
    FMap: TMap;
    FCapacity: Integer;
    FHand: Integer;
    FOnRemoveItem: TRemoveEvent;
    FMaxLives: Byte;
    FCacheHitRate: TCacheHitRate;
    FLock: TMultiReadExclusiveWriteSynchronizer;
    function Evict: Boolean;
    procedure Eject;
  public
    constructor Create(ACapacity: Integer; AMaxLives: Byte = 3; const AComparer: IEqualityComparer<K> = nil);
    destructor Destroy; override;
    procedure Put(const AKey: K; const AValue: V; AInitialLives: Byte = 1);
    function Get(const AKey: K; out AValue: V): Boolean;
    property OnRemoveItem: TRemoveEvent read FOnRemoveItem write FOnRemoveItem;
    property CacheHitRate: TCacheHitRate read FCacheHitRate;
    property AdmissionPolicy: TAdmissionPolicy read FAdmissionPolicy write FAdmissionPolicy;
  end;

implementation

{ TCacheHitRate }

procedure TCacheHitRate.SetStartTime(AValue: TDateTime);
begin
  if FStartTime = AValue then Exit;
  FStartTime := AValue;
end;

constructor TCacheHitRate.Create;
begin
  FActive := False;
end;

procedure TCacheHitRate.Start;
begin
  if FActive then Exit;
  FHits := 0;
  FMisses := 0;
  FActive := True;
  FStartTime := TClock.Now;
end;

procedure TCacheHitRate.Stop;
begin
  if not FActive then Exit;
  FActive := False;
  FStopTime := TClock.Now;
end;

procedure TCacheHitRate.IncHits;
begin
  if not FActive then Exit;
  TInterlocked.Increment(FHits);
end;

procedure TCacheHitRate.IncMisses;
begin
  if not FActive then Exit;
  TInterlocked.Increment(FMisses);
end;

function TCacheHitRate.GetCacheStats: TCacheStats;
var
  Total: Int64;
begin
  Result.Hits := FHits;
  Result.Misses := FMisses;

  Total := FHits + FMisses;

  if Total > 0 then
    Result.Efficiency := (FHits / Total) * 100
  else
    Result.Efficiency := 0;

  Result.BeginTime := FStartTime;

  if FActive then
    Result.EndTime := TClock.Now
  else
    Result.EndTime := FStopTime;

  Result.Uptime := Result.EndTime - Result.BeginTime;
end;

{ TClockCache }

constructor TClockCache<K, V>.Create(ACapacity: Integer; AMaxLives: Byte; const AComparer: IEqualityComparer<K>);
begin
  FAdmissionPolicy := apAlwaysAdmit;
  FCacheHitRate := TCacheHitRate.Create;
  FMaxLives := AMaxLives;
  if FMaxLives <= 0 then
    FMaxLives := 1;
  FCapacity := ACapacity;
  SetLength(FItems, FCapacity);
  FMap := TMap.Create(AComparer);
  FLock := TMultiReadExclusiveWriteSynchronizer.Create;
  FHand := 0;
end;

destructor TClockCache<K, V>.Destroy;
var
  I: Integer;
begin
  FLock.Free;
  FMap.Free;
  FCacheHitRate.Free;
  for I := 0 to FCapacity - 1 do
  begin
    FItems[I].Value := Default(V);
    FItems[I].Key := Default(K);
  end;
  inherited;
end;

function TClockCache<K, V>.Evict: Boolean;
var
  WeakestIdx: Integer;
  MinLives: Integer;
  I: Integer;
begin
  WeakestIdx := FHand;
  MinLives := High(Integer);

  for I := 1 to FCapacity do
  begin
    // 1. Cache ainda tem posições sem uso
    if not FItems[FHand].InUse then
      Exit(True);

    // 2. Já achamos alguém que morreu naturalmente?
    if FItems[FHand].Lives = 0 then
    begin
      Eject;
      Exit(True);
    end;

    // 3. Senão, monitoramos quem é o mais fraco deste ciclo
    if FItems[FHand].Lives < MinLives then
    begin
      MinLives := FItems[FHand].Lives;
      WeakestIdx := FHand;
    end;

    Dec(FItems[FHand].Lives);  // Segunda chance: tira a marcação
    FHand := (FHand + 1) mod FCapacity;
  end;

  if FAdmissionPolicy = apProtectHotItems then
  begin
    if MinLives > 1 then
      Exit(False);
  end;

  FHand := WeakestIdx; // posiciona o hand
  Eject;
  Result := True;
end;

procedure TClockCache<K, V>.Eject;
begin
  FMap.Remove(FItems[FHand].Key);

  if Assigned(OnRemoveItem) then
    OnRemoveItem(FItems[FHand].Value);

  FItems[FHand].Value := Default(V);
  FItems[FHand].Key := Default(K);
  FItems[FHand].InUse := False;
end;

procedure TClockCache<K, V>.Put(const AKey: K; const AValue: V; AInitialLives: Byte);
var
  Idx: Integer;
begin
  FLock.BeginWrite;
  try
    if FMap.TryGetValue(AKey, Idx) then
    begin
      FItems[Idx].Value := AValue;
      FItems[Idx].Lives := System.Math.Min(FMaxLives, FItems[Idx].Lives + AInitialLives);
      Exit;
    end;

    CacheHitRate.IncMisses;

    if FMap.Count >= FCapacity then
      if not Evict then
        Exit;

    // O Evict parou no FHand que deve ser usado.
    FItems[FHand].Key := AKey;
    FItems[FHand].Value := AValue;
    FItems[FHand].Lives := System.Math.Min(FMaxLives, AInitialLives);
    FItems[FHand].InUse := True;

    FMap.AddOrSetValue(AKey, FHand);

    // Avança o ponteiro APÓS a inserção ter sido concluída no mapa
    FHand := (FHand + 1) mod FCapacity;
  finally
    FLock.EndWrite;
  end;
end;

function TClockCache<K, V>.Get(const AKey: K; out AValue: V): Boolean;
var
  Idx: Integer;
begin
  FLock.BeginRead;
  try
    Result := FMap.TryGetValue(AKey, Idx);
    if Result then
    begin
      AValue := FItems[Idx].Value;
      if FItems[Idx].Lives < FMaxLives then  // limite
        TInterlocked.Increment(FItems[Idx].Lives);

      CacheHitRate.IncHits;
    end;
  finally
    FLock.EndRead;
  end;
end;

end.
