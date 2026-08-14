unit Common.DTO.Base;

interface

uses
  Common.Optionals;

type

  // ---------------------------------------------------------------------------
  // Marker interfaces — definem a intenção semântica de cada DTO.
  // Não adicionam métodos: servem para tipagem, testes de conformação e
  // future-proofing (restrições genéricas, middleware, etc.).
  // ---------------------------------------------------------------------------

  IDTOBase = interface
    ['{5738C3E0-3925-4858-89DE-1B6437EA086E}']
  end;

  IResponseDTOBase = interface(IDTOBase)
    ['{BE596369-18D4-4DA7-BE51-01CB1516B932}']
  end;

  IInsertDTOBase = interface(IDTOBase)
    ['{4FAB81C8-FF51-41AD-A83B-DF17682ECC4F}']
  end;

  IUpdateDTOBase = interface(IDTOBase)
    ['{78817786-8D66-4138-954A-1D830156DB0A}']
  end;

  IDeleteDTOBase = interface(IDTOBase)
    ['{FAB344F8-6C20-479A-B2F4-A4BFF9C80734}']
  end;

  // ---------------------------------------------------------------------------
  // IFindPaginationDTOBase — parâmetros de consulta paginada.
  // Todos os campos são opcionais: o consumidor envia apenas o que precisa.
  // Page/Limit controlam a página; OrderBy e Search são filtros livres.
  // ---------------------------------------------------------------------------

  IFindPaginationDTOBase = interface(IDTOBase)
    ['{8578DC7F-18F2-4DD3-9051-48EE1F43B04E}']
    function GetPage: IOptInteger;
    function GetLimit: IOptInteger;
    function GetOrderBy: IOptString;
    function GetSearch: IOptString;
    procedure SetPage(AValue: IOptInteger);
    procedure SetLimit(AValue: IOptInteger);
    procedure SetOrderBy(AValue: IOptString);
    procedure SetSearch(AValue: IOptString);
    property Page: IOptInteger read GetPage write SetPage;
    property Limit: IOptInteger read GetLimit write SetLimit;
    property OrderBy: IOptString read GetOrderBy write SetOrderBy;
    property Search: IOptString read GetSearch write SetSearch;
  end;

  // ---------------------------------------------------------------------------
  // IResponsePaginationDTOBase — metadados de paginação na resposta.
  // Os itens ficam em campo específico do DTO concreto.
  // ---------------------------------------------------------------------------

  IResponsePaginationDTOBase = interface(IResponseDTOBase)
    ['{F9DCCB8D-6315-45A9-8257-402924DC43E2}']
    function GetPage: Integer;
    function GetLimit: Integer;
    function GetTotal: Integer;
    procedure SetPage(AValue: Integer);
    procedure SetLimit(AValue: Integer);
    procedure SetTotal(AValue: Integer);
    property Page: Integer read GetPage write SetPage;
    property Limit: Integer read GetLimit write SetLimit;
    property Total: Integer read GetTotal write SetTotal;
  end;

  // ---------------------------------------------------------------------------
  // Classes base — implementam as interfaces marcadoras.
  // DTOs concretos herdam da classe adequada e declaram seus próprios campos.
  //
  // Convenção de registro:
  //   class constructor TMyDTO.Create;
  //   begin
  //     TJsonMapper.RegisterMapping<IMyDTO, TMyDTO>;
  //   end;
  // ---------------------------------------------------------------------------

  TDTOBase = class(TInterfacedObject, IDTOBase)
  end;

  TResponseDTOBase = class(TDTOBase, IResponseDTOBase)
  end;

  TInsertDTOBase = class(TDTOBase, IInsertDTOBase)
  end;

  TUpdateDTOBase = class(TDTOBase, IUpdateDTOBase)
  end;

  TDeleteDTOBase = class(TDTOBase, IDeleteDTOBase)
  end;

  TFindPaginationDTOBase = class(TDTOBase, IFindPaginationDTOBase)
  private
    FPage: IOptInteger;
    FLimit: IOptInteger;
    FOrderBy: IOptString;
    FSearch: IOptString;
  public
    function GetPage: IOptInteger;
    function GetLimit: IOptInteger;
    function GetOrderBy: IOptString;
    function GetSearch: IOptString;
    procedure SetPage(AValue: IOptInteger);
    procedure SetLimit(AValue: IOptInteger);
    procedure SetOrderBy(AValue: IOptString);
    procedure SetSearch(AValue: IOptString);
  end;

  TResponsePaginationDTOBase = class(TResponseDTOBase, IResponsePaginationDTOBase)
  private
    FPage: Integer;
    FLimit: Integer;
    FTotal: Integer;
  public
    function GetPage: Integer;
    function GetLimit: Integer;
    function GetTotal: Integer;
    procedure SetPage(AValue: Integer);
    procedure SetLimit(AValue: Integer);
    procedure SetTotal(AValue: Integer);
  end;

implementation

{ TFindPaginationDTOBase }

function TFindPaginationDTOBase.GetPage: IOptInteger;
begin
  Result := TOptionals.Safe(FPage);
end;

procedure TFindPaginationDTOBase.SetPage(AValue: IOptInteger);
begin
  FPage := AValue;
end;

function TFindPaginationDTOBase.GetLimit: IOptInteger;
begin
  Result := TOptionals.Safe(FLimit);
end;

procedure TFindPaginationDTOBase.SetLimit(AValue: IOptInteger);
begin
  FLimit := AValue;
end;

function TFindPaginationDTOBase.GetOrderBy: IOptString;
begin
  Result := TOptionals.Safe(FOrderBy);
end;

procedure TFindPaginationDTOBase.SetOrderBy(AValue: IOptString);
begin
  FOrderBy := AValue;
end;

function TFindPaginationDTOBase.GetSearch: IOptString;
begin
  Result := TOptionals.Safe(FSearch);
end;

procedure TFindPaginationDTOBase.SetSearch(AValue: IOptString);
begin
  FSearch := AValue;
end;

{ TResponsePaginationDTOBase }

function TResponsePaginationDTOBase.GetPage: Integer;
begin
  Result := FPage;
end;

procedure TResponsePaginationDTOBase.SetPage(AValue: Integer);
begin
  FPage := AValue;
end;

function TResponsePaginationDTOBase.GetLimit: Integer;
begin
  Result := FLimit;
end;

procedure TResponsePaginationDTOBase.SetLimit(AValue: Integer);
begin
  FLimit := AValue;
end;

function TResponsePaginationDTOBase.GetTotal: Integer;
begin
  Result := FTotal;
end;

procedure TResponsePaginationDTOBase.SetTotal(AValue: Integer);
begin
  FTotal := AValue;
end;

end.
