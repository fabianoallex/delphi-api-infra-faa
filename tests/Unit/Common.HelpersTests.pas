unit Common.HelpersTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Variants,
  System.DateUtils,
  Data.DB,
  Common.Optionals,
  Common.Helpers;

type

  // ---------------------------------------------------------------------------
  // TVariantHelper
  // ---------------------------------------------------------------------------

  [TestFixture]
  TVariantHelperTests = class
  public
    // ToOptional* — null/unassigned → Undefined
    [Test] procedure TestToOptionalString_WithValue;
    [Test] procedure TestToOptionalString_Null_IsUndefined;
    [Test] procedure TestToOptionalString_Unassigned_IsUndefined;
    [Test] procedure TestToOptionalInteger_WithValue;
    [Test] procedure TestToOptionalInteger_Null_IsUndefined;
    [Test] procedure TestToOptionalInt64_WithValue;
    [Test] procedure TestToOptionalBoolean_True;
    [Test] procedure TestToOptionalBoolean_False;
    [Test] procedure TestToOptionalBoolean_Null_IsUndefined;
    [Test] procedure TestToOptionalCurrency_WithValue;
    [Test] procedure TestToOptionalCurrency_Null_IsUndefined;
    [Test] procedure TestToOptionalDateTime_WithValue;
    [Test] procedure TestToOptionalDateTime_Null_IsUndefined;

    // ToNullable* — null/unassigned → Null state
    [Test] procedure TestToNullableString_WithValue;
    [Test] procedure TestToNullableString_Null_IsNull;
    [Test] procedure TestToNullableString_Unassigned_IsNull;
    [Test] procedure TestToNullableInteger_WithValue;
    [Test] procedure TestToNullableInteger_Null_IsNull;
    [Test] procedure TestToNullableCurrency_WithValue;
    [Test] procedure TestToNullableCurrency_Null_IsNull;
    [Test] procedure TestToNullableBoolean_True;
    [Test] procedure TestToNullableBoolean_False;
    [Test] procedure TestToNullableBoolean_Null_IsNull;
    [Test] procedure TestToNullableDateTime_WithValue;
    [Test] procedure TestToNullableDateTime_Null_IsNull;
  end;

  // ---------------------------------------------------------------------------
  // THorseCoreParamHelper — testado em Common.Helpers.HorseTests (projeto API)
  // ---------------------------------------------------------------------------
  // TParamsHelper
  // ---------------------------------------------------------------------------

  [TestFixture]
  TParamsHelperTests = class
  private
    FParams: TParams;
    procedure AddParam(const AName: string; AType: TFieldType);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure TestParamByNameIf_String_ConditionTrue_SetsValue;
    [Test] procedure TestParamByNameIf_String_ConditionFalse_SetsNull;
    [Test] procedure TestParamByNameIf_String_LongerThanSize_GrowsSize;
    [Test] procedure TestParamByNameIf_Integer_ConditionTrue;
    [Test] procedure TestParamByNameIf_Currency_ConditionTrue;
    [Test] procedure TestParamByNameIf_ParamNotFound_DoesNothing;
    [Test] procedure TestParamByNameOptional_Undefined_Skips;
    [Test] procedure TestParamByNameOptional_Null_Clears;
    [Test] procedure TestParamByNameOptional_WithValue;
    [Test] procedure TestParamByNameOptional_Currency_WithValue;
    [Test] procedure TestParamByNameOptional_Fluent_ReturnsParams;
  end;

  // TFDParamsHelper — lógica idêntica a TParamsHelper (coberta acima),
  // incluindo o crescimento de Size em ParamByNameIf(string).
  // TFDParam não permite instanciação standalone sem TFDQuery ativo;
  // validar via testes de integração com banco real ou em memória.

implementation

{ TVariantHelperTests }

procedure TVariantHelperTests.TestToOptionalString_WithValue;
var
  V: Variant;
  R: IOptString;
begin
  V := 'hello';
  R := V.ToOptionalString;
  Assert.IsTrue(R.HasValue);
  Assert.AreEqual('hello', R.Value);
end;

procedure TVariantHelperTests.TestToOptionalString_Null_IsUndefined;
var
  V: Variant;
  R: IOptString;
begin
  V := Null;
  R := V.ToOptionalString;
  Assert.IsFalse(R.HasValue);
end;

procedure TVariantHelperTests.TestToOptionalString_Unassigned_IsUndefined;
var
  V: Variant;
  R: IOptString;
begin
  V := Unassigned;
  R := V.ToOptionalString;
  Assert.IsFalse(R.HasValue);
end;

procedure TVariantHelperTests.TestToOptionalInteger_WithValue;
var
  V: Variant;
  R: IOptInteger;
begin
  V := 42;
  R := V.ToOptionalInteger;
  Assert.IsTrue(R.HasValue);
  Assert.AreEqual(42, R.Value);
end;

procedure TVariantHelperTests.TestToOptionalInteger_Null_IsUndefined;
var
  V: Variant;
begin
  V := Null;
  Assert.IsFalse(V.ToOptionalInteger.HasValue);
end;

procedure TVariantHelperTests.TestToOptionalInt64_WithValue;
var
  V: Variant;
  R: IOptInt64;
begin
  V := Int64(9876543210);
  R := V.ToOptionalInt64;
  Assert.IsTrue(R.HasValue);
  Assert.AreEqual(Int64(9876543210), R.Value);
end;

procedure TVariantHelperTests.TestToOptionalBoolean_True;
var
  V: Variant;
begin
  V := True;
  Assert.IsTrue(V.ToOptionalBoolean.Value);
end;

procedure TVariantHelperTests.TestToOptionalBoolean_False;
var
  V: Variant;
begin
  V := False;
  Assert.IsFalse(V.ToOptionalBoolean.Value);
end;

procedure TVariantHelperTests.TestToOptionalBoolean_Null_IsUndefined;
var
  V: Variant;
begin
  V := Null;
  Assert.IsFalse(V.ToOptionalBoolean.HasValue);
end;

procedure TVariantHelperTests.TestToOptionalCurrency_WithValue;
var
  V: Variant;
  R: IOptCurrency;
begin
  V := Currency(19.99);
  R := V.ToOptionalCurrency;
  Assert.IsTrue(R.HasValue);
  Assert.AreEqual(Currency(19.99), R.Value);
end;

procedure TVariantHelperTests.TestToOptionalCurrency_Null_IsUndefined;
var
  V: Variant;
begin
  V := Null;
  Assert.IsFalse(V.ToOptionalCurrency.HasValue);
end;

procedure TVariantHelperTests.TestToOptionalDateTime_WithValue;
var
  V: Variant;
  R: IOptDateTime;
  LDate: TDateTime;
begin
  LDate := EncodeDate(2024, 6, 15);
  V := LDate;
  R := V.ToOptionalDateTime;
  Assert.IsTrue(R.HasValue);
  Assert.AreEqual(LDate, R.Value);
end;

procedure TVariantHelperTests.TestToOptionalDateTime_Null_IsUndefined;
var
  V: Variant;
begin
  V := Null;
  Assert.IsFalse(V.ToOptionalDateTime.HasValue);
end;

procedure TVariantHelperTests.TestToNullableString_WithValue;
var
  V: Variant;
  R: INullString;
begin
  V := 'world';
  R := V.ToNullableString;
  Assert.IsFalse(R.IsNull);
  Assert.AreEqual('world', R.Value);
end;

procedure TVariantHelperTests.TestToNullableString_Null_IsNull;
var
  V: Variant;
  R: INullString;
begin
  V := Null;
  R := V.ToNullableString;
  Assert.IsTrue(R.IsNull);
end;

procedure TVariantHelperTests.TestToNullableString_Unassigned_IsNull;
var
  V: Variant;
  R: INullString;
begin
  V := Unassigned;
  R := V.ToNullableString;
  Assert.IsTrue(R.IsNull);
end;

procedure TVariantHelperTests.TestToNullableInteger_WithValue;
var
  V: Variant;
  R: INullInteger;
begin
  V := 100;
  R := V.ToNullableInteger;
  Assert.IsFalse(R.IsNull);
  Assert.AreEqual(100, R.Value);
end;

procedure TVariantHelperTests.TestToNullableInteger_Null_IsNull;
var
  V: Variant;
begin
  V := Null;
  Assert.IsTrue(V.ToNullableInteger.IsNull);
end;

procedure TVariantHelperTests.TestToNullableCurrency_WithValue;
var
  V: Variant;
  R: INullCurrency;
begin
  V := Currency(5.75);
  R := V.ToNullableCurrency;
  Assert.IsFalse(R.IsNull);
  Assert.AreEqual(Currency(5.75), R.Value);
end;

procedure TVariantHelperTests.TestToNullableCurrency_Null_IsNull;
var
  V: Variant;
begin
  V := Null;
  Assert.IsTrue(V.ToNullableCurrency.IsNull);
end;

procedure TVariantHelperTests.TestToNullableBoolean_True;
var
  V: Variant;
begin
  V := True;
  Assert.IsTrue(V.ToNullableBoolean.Value);
end;

procedure TVariantHelperTests.TestToNullableBoolean_False;
var
  V: Variant;
begin
  V := False;
  Assert.IsFalse(V.ToNullableBoolean.Value);
end;

procedure TVariantHelperTests.TestToNullableBoolean_Null_IsNull;
var
  V: Variant;
begin
  V := Null;
  Assert.IsTrue(V.ToNullableBoolean.IsNull);
end;

procedure TVariantHelperTests.TestToNullableDateTime_WithValue;
var
  V: Variant;
  R: INullDateTime;
  LDate: TDateTime;
begin
  LDate := EncodeDate(2024, 12, 31);
  V := LDate;
  R := V.ToNullableDateTime;
  Assert.IsFalse(R.IsNull);
  Assert.AreEqual(LDate, R.Value);
end;

procedure TVariantHelperTests.TestToNullableDateTime_Null_IsNull;
var
  V: Variant;
begin
  V := Null;
  Assert.IsTrue(V.ToNullableDateTime.IsNull);
end;

{ TParamsHelperTests }

procedure TParamsHelperTests.Setup;
begin
  FParams := TParams.Create(nil);
end;

procedure TParamsHelperTests.TearDown;
begin
  FParams.Free;
end;

procedure TParamsHelperTests.AddParam(const AName: string; AType: TFieldType);
var
  LParam: TParam;
begin
  LParam := TParam.Create(FParams);
  LParam.Name := AName;
  LParam.DataType := AType;
end;

procedure TParamsHelperTests.TestParamByNameIf_String_ConditionTrue_SetsValue;
begin
  AddParam('Nome', ftString);
  FParams.ParamByNameIf('Nome', 'Produto X', True);
  Assert.AreEqual('Produto X', string(FParams.FindParam('Nome').Value));
end;

procedure TParamsHelperTests.TestParamByNameIf_String_ConditionFalse_SetsNull;
begin
  AddParam('Nome', ftString);
  FParams.FindParam('Nome').Value := 'valor anterior';
  FParams.ParamByNameIf('Nome', 'Produto X', False);
  Assert.IsTrue(FParams.FindParam('Nome').IsNull);
end;

procedure TParamsHelperTests.TestParamByNameIf_String_LongerThanSize_GrowsSize;
var
  LValue: string;
begin
  AddParam('XmlEnvio', ftString);
  FParams.FindParam('XmlEnvio').Size := 50; // simula Size curto descrito pelo driver
  LValue := StringOfChar('X', 200);

  FParams.ParamByNameIf('XmlEnvio', LValue, True);

  Assert.IsTrue(FParams.FindParam('XmlEnvio').Size >= 200,
    'Size deve crescer para acomodar o valor');
  Assert.AreEqual(LValue, string(FParams.FindParam('XmlEnvio').Value));
end;

procedure TParamsHelperTests.TestParamByNameIf_Integer_ConditionTrue;
begin
  AddParam('Quantidade', ftInteger);
  FParams.ParamByNameIf('Quantidade', 10, True);
  Assert.AreEqual(10, Integer(FParams.FindParam('Quantidade').Value));
end;

procedure TParamsHelperTests.TestParamByNameIf_Currency_ConditionTrue;
begin
  AddParam('Preco', ftCurrency);
  FParams.ParamByNameIf('Preco', Currency(29.90), True);
  Assert.AreEqual(Currency(29.90), Currency(FParams.FindParam('Preco').Value));
end;

procedure TParamsHelperTests.TestParamByNameIf_ParamNotFound_DoesNothing;
begin
  // não deve levantar exceção
  FParams.ParamByNameIf('Inexistente', 'valor', True);
  Assert.Pass;
end;

procedure TParamsHelperTests.TestParamByNameOptional_Undefined_Skips;
begin
  AddParam('Nome', ftString);
  FParams.FindParam('Nome').Value := 'original';
  FParams.ParamByNameOptional('Nome', TOptNullString.Undefined);
  // valor não deve ter sido alterado
  Assert.AreEqual('original', string(FParams.FindParam('Nome').Value));
end;

procedure TParamsHelperTests.TestParamByNameOptional_Null_Clears;
begin
  AddParam('Telefone', ftString);
  FParams.FindParam('Telefone').Value := '(65) 99999-0000';
  FParams.ParamByNameOptional('Telefone', TOptNullString.Null);
  Assert.IsTrue(FParams.FindParam('Telefone').IsNull);
end;

procedure TParamsHelperTests.TestParamByNameOptional_WithValue;
begin
  AddParam('Nome', ftString);
  FParams.ParamByNameOptional('Nome', TOptNullString.From('Maria'));
  Assert.AreEqual('Maria', string(FParams.FindParam('Nome').Value));
end;

procedure TParamsHelperTests.TestParamByNameOptional_Currency_WithValue;
begin
  AddParam('Preco', ftCurrency);
  FParams.ParamByNameOptional('Preco', TOptNullCurrency.From(Currency(9.99)));
  Assert.AreEqual(Currency(9.99), Currency(FParams.FindParam('Preco').Value));
end;

procedure TParamsHelperTests.TestParamByNameOptional_Fluent_ReturnsParams;
var
  LResult: TParams;
begin
  AddParam('Nome', ftString);
  AddParam('Preco', ftCurrency);
  LResult := FParams
    .ParamByNameOptional('Nome', TOptNullString.From('Arroz'))
    .ParamByNameOptional('Preco', TOptNullCurrency.From(Currency(4.50)));
  Assert.AreSame(FParams, LResult);
  Assert.AreEqual('Arroz', string(FParams.FindParam('Nome').Value));
  Assert.AreEqual(Currency(4.50), Currency(FParams.FindParam('Preco').Value));
end;

initialization
  TDUnitX.RegisterTestFixture(TVariantHelperTests);
  TDUnitX.RegisterTestFixture(TParamsHelperTests);

end.
