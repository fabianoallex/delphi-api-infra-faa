unit Common.Helpers;

interface

uses
  System.SysUtils,
  System.Variants,
  System.DateUtils,
  Data.DB,
  FireDAC.Stan.Param,
  Common.Optionals;

type

  { TParamsHelper
    Preenche parâmetros SQL a partir de Optionals de forma fluente.
    Undefined → ignora o parâmetro (mantém o estado anterior).
    Null      → chama Clear (define NULL no banco).
    Valor     → atribui o valor.

    Uso:
      Query.Params
        .ParamByNameOptional('Nome', LDto.Nome)
        .ParamByNameOptional('Preco', LDto.Preco);

    Para FireDAC use TFDParamsHelper (mesmo arquivo). }

  TParamsHelper = class helper for TParams
  public
    function ParamByNameIf(const AName: string; const AValue: string;
      const ACondition: Boolean): TParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Integer;
      const ACondition: Boolean): TParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Int64;
      const ACondition: Boolean): TParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Currency;
      const ACondition: Boolean): TParams; overload;
    function ParamByNameIf(const AName: string; const AValue: TDateTime;
      const ACondition: Boolean): TParams; overload;

    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullString): TParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullInteger): TParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullInt64): TParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullCurrency): TParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullDateTime): TParams; overload;
  end;

  { TFDParamsHelper
    Mesma semântica de TParamsHelper, mas para TFDParams (FireDAC).
    TFDQuery.Params retorna TFDParams — use este helper com FireDAC. }

  TFDParamsHelper = class helper for TFDParams
  public
    function ParamByNameIf(const AName: string; const AValue: string;
      const ACondition: Boolean): TFDParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Integer;
      const ACondition: Boolean): TFDParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Int64;
      const ACondition: Boolean): TFDParams; overload;
    function ParamByNameIf(const AName: string; const AValue: Currency;
      const ACondition: Boolean): TFDParams; overload;
    function ParamByNameIf(const AName: string; const AValue: TDateTime;
      const ACondition: Boolean): TFDParams; overload;

    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullString): TFDParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullInteger): TFDParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullInt64): TFDParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullCurrency): TFDParams; overload;
    function ParamByNameOptional(const AName: string;
      const AParam: IOptNullDateTime): TFDParams; overload;
  end;

  { TVariantHelper
    Converte valores Variant (campos de TDataSet) em Optional/Nullable.
    VarIsNull ou VarIsEmpty → Undefined (ToOptional*) ou Null (ToNullable*).

    Uso em repositório:
      LDto.Nome     := Dataset.FieldByName('nome').Value.ToNullableString;
      LDto.Telefone := Dataset.FieldByName('telefone').Value.ToNullableString;
      LDto.Preco    := Dataset.FieldByName('preco').Value.ToNullableCurrency; }

  TVariantHelper = record helper for Variant
  public
    function ToOptionalString: IOptString;
    function ToOptionalInteger: IOptInteger;
    function ToOptionalInt64: IOptInt64;
    function ToOptionalBoolean: IOptBoolean;
    function ToOptionalSingle: IOptSingle;
    function ToOptionalDouble: IOptDouble;
    function ToOptionalCurrency: IOptCurrency;
    function ToOptionalDateTime: IOptDateTime;

    function ToNullableString: INullString;
    function ToNullableInteger: INullInteger;
    function ToNullableInt64: INullInt64;
    function ToNullableBoolean: INullBoolean;
    function ToNullableSingle: INullSingle;
    function ToNullableDouble: INullDouble;
    function ToNullableCurrency: INullCurrency;
    function ToNullableDateTime: INullDateTime;
  end;

implementation

{ TParamsHelper }

function TParamsHelper.ParamByNameIf(const AName, AValue: string;
  const ACondition: Boolean): TParams;
var
  LParam: TParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TParamsHelper.ParamByNameIf(const AName: string; const AValue: Integer;
  const ACondition: Boolean): TParams;
var
  LParam: TParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TParamsHelper.ParamByNameIf(const AName: string; const AValue: Int64;
  const ACondition: Boolean): TParams;
var
  LParam: TParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TParamsHelper.ParamByNameIf(const AName: string; const AValue: Currency;
  const ACondition: Boolean): TParams;
var
  LParam: TParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TParamsHelper.ParamByNameIf(const AName: string; const AValue: TDateTime;
  const ACondition: Boolean): TParams;
var
  LParam: TParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullString): TParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullInteger): TParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullInt64): TParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullCurrency): TParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullDateTime): TParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

{ TFDParamsHelper }

function TFDParamsHelper.ParamByNameIf(const AName, AValue: string;
  const ACondition: Boolean): TFDParams;
var
  LParam: TFDParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TFDParamsHelper.ParamByNameIf(const AName: string; const AValue: Integer;
  const ACondition: Boolean): TFDParams;
var
  LParam: TFDParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TFDParamsHelper.ParamByNameIf(const AName: string; const AValue: Int64;
  const ACondition: Boolean): TFDParams;
var
  LParam: TFDParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TFDParamsHelper.ParamByNameIf(const AName: string; const AValue: Currency;
  const ACondition: Boolean): TFDParams;
var
  LParam: TFDParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TFDParamsHelper.ParamByNameIf(const AName: string; const AValue: TDateTime;
  const ACondition: Boolean): TFDParams;
var
  LParam: TFDParam;
begin
  Result := Self;
  LParam := FindParam(AName);
  if not Assigned(LParam) then
    Exit;
  if ACondition then
    LParam.Value := AValue
  else
    LParam.Clear;
end;

function TFDParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullString): TFDParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TFDParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullInteger): TFDParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TFDParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullInt64): TFDParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TFDParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullCurrency): TFDParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

function TFDParamsHelper.ParamByNameOptional(const AName: string;
  const AParam: IOptNullDateTime): TFDParams;
begin
  if not AParam.HasValue then
    Exit(Self);
  Result := ParamByNameIf(AName, AParam.Value, not AParam.IsNull);
end;

{ TVariantHelper }

function TVariantHelper.ToOptionalString: IOptString;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullString.Undefined
  else
    Result := TOptNullString.From(Self);
end;

function TVariantHelper.ToOptionalInteger: IOptInteger;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullInteger.Undefined
  else
    Result := TOptNullInteger.From(Self);
end;

function TVariantHelper.ToOptionalInt64: IOptInt64;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullInt64.Undefined
  else
    Result := TOptNullInt64.From(Self);
end;

function TVariantHelper.ToOptionalBoolean: IOptBoolean;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullBoolean.Undefined
  else
    Result := TOptNullBoolean.From(Self) as IOptBoolean;
end;

function TVariantHelper.ToOptionalSingle: IOptSingle;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullSingle.Undefined
  else
    Result := TOptNullSingle.From(Self);
end;

function TVariantHelper.ToOptionalDouble: IOptDouble;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullDouble.Undefined
  else
    Result := TOptNullDouble.From(Self);
end;

function TVariantHelper.ToOptionalCurrency: IOptCurrency;
var
  LVal: Currency;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullCurrency.Undefined
  else
  begin
    LVal := Self;
    Result := TOptNullCurrency.From(LVal);
  end;
end;

function TVariantHelper.ToOptionalDateTime: IOptDateTime;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullDateTime.Undefined
  else
    Result := TOptNullDateTime.From(TDateTime(Self));
end;

function TVariantHelper.ToNullableString: INullString;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullString.Null
  else
    Result := TOptNullString.From(Self);
end;

function TVariantHelper.ToNullableInteger: INullInteger;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullInteger.Null
  else
    Result := TOptNullInteger.From(Self);
end;

function TVariantHelper.ToNullableInt64: INullInt64;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullInt64.Null
  else
    Result := TOptNullInt64.From(Self);
end;

function TVariantHelper.ToNullableBoolean: INullBoolean;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullBoolean.Null
  else
    Result := TOptNullBoolean.From(Self) as INullBoolean;
end;

function TVariantHelper.ToNullableSingle: INullSingle;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullSingle.Null
  else
    Result := TOptNullSingle.From(Self);
end;

function TVariantHelper.ToNullableDouble: INullDouble;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullDouble.Null
  else
    Result := TOptNullDouble.From(Self);
end;

function TVariantHelper.ToNullableCurrency: INullCurrency;
var
  LVal: Currency;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullCurrency.Null
  else
  begin
    LVal := Self;
    Result := TOptNullCurrency.From(LVal);
  end;
end;

function TVariantHelper.ToNullableDateTime: INullDateTime;
begin
  if VarIsNull(Self) or VarIsEmpty(Self) then
    Result := TOptNullDateTime.Null
  else
    Result := TOptNullDateTime.From(TDateTime(Self));
end;

end.
