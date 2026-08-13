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
    ['{3A1B2C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D}']
  end;

  IResponseDTOBase = interface(IDTOBase)
    ['{7F8E9D0C-1B2A-3C4D-5E6F-7A8B9C0D1E2F}']
  end;

  IInsertDTOBase = interface(IDTOBase)
    ['{2D3E4F5A-6B7C-8D9E-0F1A-2B3C4D5E6F7A}']
  end;

  IUpdateDTOBase = interface(IDTOBase)
    ['{8C9D0E1F-2A3B-4C5D-6E7F-8A9B0C1D2E3F}']
  end;

  IDeleteDTOBase = interface(IDTOBase)
    ['{4E5F6A7B-8C9D-0E1F-2A3B-4C5D6E7F8A9B}']
  end;

  // ---------------------------------------------------------------------------
  // IFindPaginationDTOBase — parâmetros de consulta paginada.
  // Todos os campos são opcionais: o consumidor envia apenas o que precisa.
  // Page/Limit controlam a página; OrderBy e Search são filtros livres.
  // ---------------------------------------------------------------------------

  IFindPaginationDTOBase = interface(IDTOBase)
    ['{1F2A3B4C-5D6E-7F8A-9B0C-1D2E3F4A5B6C}']
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
    ['{6C7D8E9F-0A1B-2C3D-4E5F-6A7B8C9D0E1F}']
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
