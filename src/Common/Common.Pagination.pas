unit Common.Pagination;

interface

uses
  Common.Optionals;

const
  PAGE_DEFAULT  = 1;
  LIMIT_DEFAULT = 20;
  LIMIT_MAX     = 100;

type

  // ---------------------------------------------------------------------------
  // TPageParams — parâmetros de entrada normalizados.
  // Recebe os valores opcionais do cliente, aplica defaults e clamp,
  // e expõe o Offset já calculado para uso no SQL.
  // ---------------------------------------------------------------------------

  TPageParams = record
    Page:   Integer;
    Limit:  Integer;
    Offset: Integer;
    class function From(APage, ALimit: IOptInteger;
      ADefaultPage:  Integer = PAGE_DEFAULT;
      ADefaultLimit: Integer = LIMIT_DEFAULT;
      AMaxLimit:     Integer = LIMIT_MAX): TPageParams; static;
  end;

  // ---------------------------------------------------------------------------
  // TPageMeta — metadados de saída de uma consulta paginada.
  // Calcula TotalPages/HasNext/HasPrev e monta o envelope JSON padrão.
  // ---------------------------------------------------------------------------

  TPageMeta = record
    Page:  Integer;
    Limit: Integer;
    Total: Integer;
    function TotalPages: Integer;
    function HasNext: Boolean;
    function HasPrev: Boolean;
    function WrapJson(const AItemsJson: string): string;
  end;

// ---------------------------------------------------------------------------
// Helpers de parsing para query params do Horse (Req.Query[]).
// ---------------------------------------------------------------------------

function ParseQueryInt(const AStr: string): IOptInteger;
function ParseQueryStr(const AStr: string): IOptString;

implementation

uses
  System.SysUtils;

{ TPageParams }

class function TPageParams.From(APage, ALimit: IOptInteger;
  ADefaultPage, ADefaultLimit, AMaxLimit: Integer): TPageParams;
begin
  if Assigned(APage)  and APage.HasValue  then Result.Page  := APage.Value
                                          else Result.Page  := ADefaultPage;
  if Assigned(ALimit) and ALimit.HasValue then Result.Limit := ALimit.Value
                                          else Result.Limit := ADefaultLimit;

  if Result.Page  < 1        then Result.Page  := ADefaultPage;
  if Result.Limit < 1        then Result.Limit := ADefaultLimit;
  if Result.Limit > AMaxLimit then Result.Limit := AMaxLimit;

  Result.Offset := (Result.Page - 1) * Result.Limit;
end;

{ TPageMeta }

function TPageMeta.TotalPages: Integer;
begin
  if Limit <= 0 then Exit(1);
  Result := (Total + Limit - 1) div Limit;
  if Result < 1 then Result := 1;
end;

function TPageMeta.HasNext: Boolean;
begin
  Result := Page < TotalPages;
end;

function TPageMeta.HasPrev: Boolean;
begin
  Result := Page > 1;
end;

function TPageMeta.WrapJson(const AItemsJson: string): string;
begin
  Result := Format(
    '{"page":%d,"limit":%d,"total":%d,"totalPages":%d,"hasNext":%s,"hasPrev":%s,"items":%s}',
    [Page, Limit, Total, TotalPages,
     LowerCase(BoolToStr(HasNext, True)),
     LowerCase(BoolToStr(HasPrev, True)),
     AItemsJson]);
end;

{ Helpers }

function ParseQueryInt(const AStr: string): IOptInteger;
var
  N: Integer;
begin
  if (AStr <> '') and TryStrToInt(AStr, N) then
    Result := TOptNullInteger.From(N)
  else
    Result := nil;
end;

function ParseQueryStr(const AStr: string): IOptString;
begin
  if AStr <> '' then
    Result := TOptNullString.From(AStr)
  else
    Result := nil;
end;

end.
