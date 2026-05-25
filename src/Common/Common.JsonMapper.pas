unit Common.JsonMapper;

interface

uses
  System.SysUtils, System.Generics.Collections, System.TypInfo,
  System.JSON, System.Rtti, System.DateUtils, Common.Optionals;

type
  EJsonMapperException = class(Exception);

  TJsonMapper = class
  private
    class var FRegistry: TDictionary<TGUID, TClass>;
    class var FRttiContext: TRttiContext;

    // --- Deserialization ---
    class function FindJsonValue(AJsonObj: TJSONObject; const AName: string)
      : TJSONValue;
    class function IsOptionalGuid(const AGuid: TGUID): Boolean;
    class function TryResolveOptional(AObj: TObject; AProp: TRttiProperty;
      const AGuid: TGUID; AJsonValue: TJSONValue): Boolean;
    class function JsonValueToTValue(AJsonValue: TJSONValue;
      ARttiType: TRttiType): TValue;
    class function BuildDynArrayFromJson(AJsonArray: TJSONArray;
      AArrayType: TRttiDynamicArrayType): TValue;
    class function DeserializeObject(AClass: TClass;
      AJsonObj: TJSONObject): TObject;
    class procedure SetPropertyFromJson(AObj: TObject; AProp: TRttiProperty;
      AJsonValue: TJSONValue);

    // --- Serialization ---
    class function OptionalToJsonValue(const AIntf: IInterface;
      const AGuid: TGUID): TJSONValue;
    class function TValueToJsonValue(const AValue: TValue; ARttiType: TRttiType)
      : TJSONValue;
    class function BuildJsonObject(const AIntfValue: TValue): TJSONObject;
    class function BuildJsonArray(const AValue: TValue;
      ARttiType: TRttiDynamicArrayType): TJSONArray;
  public
    class constructor Create;
    class destructor Destroy;

    class procedure RegisterMapping<I: IInterface; C: class, constructor>;
    class function FindImplClass(ATypeInfo: PTypeInfo): TClass;
    class function FromJson<I: IInterface>(const AJson: string): I;
    class function ToJson<I: IInterface>(const AIntf: I): string;
  end;

implementation

function LowerFirst(const S: string): string;
begin
  if S.IsEmpty then Exit('');
  Result := LowerCase(Copy(S, 1, 1)) + Copy(S, 2, MaxInt);
end;

{ TJsonMapper }

class constructor TJsonMapper.Create;
begin
  FRegistry := TDictionary<TGUID, TClass>.Create;
  FRttiContext := TRttiContext.Create;
end;

class destructor TJsonMapper.Destroy;
begin
  FRttiContext.Free;
  FRegistry.Free;
end;

class procedure TJsonMapper.RegisterMapping<I, C>;
var
  LGuid: TGUID;
begin
  LGuid := GetTypeData(TypeInfo(I))^.Guid;
  FRegistry.AddOrSetValue(LGuid, C);
end;

class function TJsonMapper.FindImplClass(ATypeInfo: PTypeInfo): TClass;
var
  LGuid: TGUID;
begin
  LGuid := GetTypeData(ATypeInfo)^.Guid;
  if not FRegistry.TryGetValue(LGuid, Result) then
    Result := nil;
end;

{ Deserialization internals }

class function TJsonMapper.FindJsonValue(AJsonObj: TJSONObject;
  const AName: string): TJSONValue;
var
  LPair: TJSONPair;
begin
  for LPair in AJsonObj do
    if SameText(LPair.JsonString.Value, AName) then
      Exit(LPair.JsonValue);
  Result := nil;
end;

class function TJsonMapper.IsOptionalGuid(const AGuid: TGUID): Boolean;
begin
  Result := IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullString))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptString))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullString))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullInteger))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptInteger))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullInteger))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullInt64))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptInt64))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullInt64))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullDouble))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptDouble))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullDouble))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullSingle))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptSingle))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullSingle))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullBoolean))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptBoolean))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullBoolean))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullCurrency))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptCurrency))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullCurrency))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullDateTime))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptDateTime))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullDateTime))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullGuid))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptGuid))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullGuid))^.Guid);
end;

class function TJsonMapper.TryResolveOptional(AObj: TObject;
  AProp: TRttiProperty; const AGuid: TGUID; AJsonValue: TJSONValue): Boolean;
var
  LOptObj: TObject;
  LIntf: IInterface;
  LValue: TValue;

  function IsGuid(ATypeInfo: PTypeInfo): Boolean;
  begin
    Result := IsEqualGUID(AGuid, GetTypeData(ATypeInfo)^.Guid);
  end;

begin
  Result := False;
  LOptObj := nil;

  if IsGuid(TypeInfo(IOptNullString)) or IsGuid(TypeInfo(IOptString)) or
    IsGuid(TypeInfo(INullString)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullString.Null
    else
      LOptObj := TOptNullString.From((AJsonValue as TJSONString).Value);
  end
  else if IsGuid(TypeInfo(IOptNullInteger)) or IsGuid(TypeInfo(IOptInteger)) or
    IsGuid(TypeInfo(INullInteger)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullInteger.Null
    else
      LOptObj := TOptNullInteger.From((AJsonValue as TJSONNumber).AsInt);
  end
  else if IsGuid(TypeInfo(IOptNullInt64)) or IsGuid(TypeInfo(IOptInt64)) or
    IsGuid(TypeInfo(INullInt64)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullInt64.Null
    else
      LOptObj := TOptNullInt64.From((AJsonValue as TJSONNumber).AsInt64);
  end
  else if IsGuid(TypeInfo(IOptNullDouble)) or IsGuid(TypeInfo(IOptDouble)) or
    IsGuid(TypeInfo(INullDouble)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullDouble.Null
    else
      LOptObj := TOptNullDouble.From((AJsonValue as TJSONNumber).AsDouble);
  end
  else if IsGuid(TypeInfo(IOptNullSingle)) or IsGuid(TypeInfo(IOptSingle)) or
    IsGuid(TypeInfo(INullSingle)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullSingle.Null
    else
      LOptObj := TOptNullSingle.From((AJsonValue as TJSONNumber).AsDouble);
  end
  else if IsGuid(TypeInfo(IOptNullBoolean)) or IsGuid(TypeInfo(IOptBoolean)) or
    IsGuid(TypeInfo(INullBoolean)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullBoolean.Null
    else if AJsonValue is TJSONTrue then
      LOptObj := TOptNullBoolean.TrueValue
    else
      LOptObj := TOptNullBoolean.FalseValue;
  end
  else if IsGuid(TypeInfo(IOptNullCurrency)) or IsGuid(TypeInfo(IOptCurrency))
    or IsGuid(TypeInfo(INullCurrency)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullCurrency.Null
    else
      LOptObj := TOptNullCurrency.From((AJsonValue as TJSONNumber).AsDouble);
  end
  else if IsGuid(TypeInfo(IOptNullDateTime)) or IsGuid(TypeInfo(IOptDateTime))
    or IsGuid(TypeInfo(INullDateTime)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullDateTime.Null
    else
      LOptObj := TOptNullDateTime.From
        (ISO8601ToDate((AJsonValue as TJSONString).Value));
  end
  else if IsGuid(TypeInfo(IOptNullGuid)) or IsGuid(TypeInfo(IOptGuid)) or
    IsGuid(TypeInfo(INullGuid)) then
  begin
    if AJsonValue is TJSONNull then
      LOptObj := TOptNullGuid.Null
    else
      LOptObj := TOptNullGuid.From
        (StringToGUID((AJsonValue as TJSONString).Value));
  end;

  if Assigned(LOptObj) then
  begin
    if LOptObj.GetInterface(AGuid, LIntf) then
    begin
      TValue.Make(@LIntf, AProp.PropertyType.Handle, LValue);
      AProp.SetValue(AObj, LValue);
    end;
    Result := True;
  end;
end;

class function TJsonMapper.JsonValueToTValue(AJsonValue: TJSONValue;
  ARttiType: TRttiType): TValue;
var
  LGuid: TGUID;
  LClass: TClass;
  LObj: TObject;
  LIntf: IInterface;
  LOptObj: TObject;
begin
  Result := TValue.Empty;

  case ARttiType.TypeKind of
    tkString, tkUString:
      if not(AJsonValue is TJSONNull) then
        Result := TValue.From<string>((AJsonValue as TJSONString).Value);

    tkInteger:
      if not(AJsonValue is TJSONNull) then
        Result := TValue.From<Integer>((AJsonValue as TJSONNumber).AsInt);

    tkInt64:
      if not(AJsonValue is TJSONNull) then
        Result := TValue.From<Int64>((AJsonValue as TJSONNumber).AsInt64);

    tkFloat:
      if not(AJsonValue is TJSONNull) then
        Result := TValue.From<Double>((AJsonValue as TJSONNumber).AsDouble);

    tkEnumeration:
      if (not(AJsonValue is TJSONNull)) and
        (ARttiType.Handle = TypeInfo(Boolean)) then
        Result := TValue.From<Boolean>(AJsonValue is TJSONTrue);

    tkInterface:
      begin
        LGuid := GetTypeData(ARttiType.Handle)^.Guid;
        LOptObj := nil;

        if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullString))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptString))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullString))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullString.Null
          else
            LOptObj := TOptNullString.From((AJsonValue as TJSONString).Value);
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullInteger))^.Guid)
          or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptInteger))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullInteger))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullInteger.Null
          else
            LOptObj := TOptNullInteger.From((AJsonValue as TJSONNumber).AsInt);
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullInt64))^.Guid)
          or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptInt64))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullInt64))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullInt64.Null
          else
            LOptObj := TOptNullInt64.From((AJsonValue as TJSONNumber).AsInt64);
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullDouble))^.Guid)
          or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptDouble))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullDouble))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullDouble.Null
          else
            LOptObj := TOptNullDouble.From((AJsonValue as TJSONNumber)
              .AsDouble);
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullBoolean))^.Guid)
          or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptBoolean))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullBoolean))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullBoolean.Null
          else if AJsonValue is TJSONTrue then
            LOptObj := TOptNullBoolean.TrueValue
          else
            LOptObj := TOptNullBoolean.FalseValue;
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullCurrency))
          ^.Guid) or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptCurrency))
          ^.Guid) or IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullCurrency))
          ^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullCurrency.Null
          else
            LOptObj := TOptNullCurrency.From((AJsonValue as TJSONNumber)
              .AsDouble);
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullDateTime))
          ^.Guid) or IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptDateTime))
          ^.Guid) or IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullDateTime))
          ^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullDateTime.Null
          else
            LOptObj := TOptNullDateTime.From
              (ISO8601ToDate((AJsonValue as TJSONString).Value));
        end
        else if IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptNullGuid))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(IOptGuid))^.Guid) or
          IsEqualGUID(LGuid, GetTypeData(TypeInfo(INullGuid))^.Guid) then
        begin
          if AJsonValue is TJSONNull then
            LOptObj := TOptNullGuid.Null
          else
            LOptObj := TOptNullGuid.From
              (StringToGUID((AJsonValue as TJSONString).Value));
        end;

        if Assigned(LOptObj) then
        begin
          if LOptObj.GetInterface(LGuid, LIntf) then
            TValue.Make(@LIntf, ARttiType.Handle, Result);
        end
        else if not(AJsonValue is TJSONNull) then
        begin
          if FRegistry.TryGetValue(LGuid, LClass) then
          begin
            LObj := DeserializeObject(LClass, AJsonValue as TJSONObject);
            if LObj.GetInterface(LGuid, LIntf) then
              TValue.Make(@LIntf, ARttiType.Handle, Result)
            else
              LObj.Free;
          end;
        end;
      end;
  end;
end;

class function TJsonMapper.BuildDynArrayFromJson(AJsonArray: TJSONArray;
  AArrayType: TRttiDynamicArrayType): TValue;
var
  LElements: array of TValue;
  I: Integer;
begin
  SetLength(LElements, AJsonArray.Count);
  for I := 0 to AJsonArray.Count - 1 do
    LElements[I] := JsonValueToTValue(AJsonArray.Items[I],
      AArrayType.ElementType);
  Result := TValue.FromArray(AArrayType.Handle, LElements);
end;

class procedure TJsonMapper.SetPropertyFromJson(AObj: TObject;
  AProp: TRttiProperty; AJsonValue: TJSONValue);
var
  LGuid: TGUID;
  LClass: TClass;
  LObj: TObject;
  LIntf: IInterface;
  LValue: TValue;
begin
  case AProp.PropertyType.TypeKind of
    tkString, tkUString:
      if not(AJsonValue is TJSONNull) then
        AProp.SetValue(AObj, (AJsonValue as TJSONString).Value);

    tkInteger:
      if not(AJsonValue is TJSONNull) then
        AProp.SetValue(AObj, (AJsonValue as TJSONNumber).AsInt);

    tkInt64:
      if not(AJsonValue is TJSONNull) then
        AProp.SetValue(AObj, (AJsonValue as TJSONNumber).AsInt64);

    tkFloat:
      if not(AJsonValue is TJSONNull) then
        AProp.SetValue(AObj, (AJsonValue as TJSONNumber).AsDouble);

    tkEnumeration:
      if (not(AJsonValue is TJSONNull)) and
        (AProp.PropertyType.Handle = TypeInfo(Boolean)) then
        AProp.SetValue(AObj, AJsonValue is TJSONTrue);

    tkInterface:
      begin
        LGuid := GetTypeData(AProp.PropertyType.Handle)^.Guid;

        if TryResolveOptional(AObj, AProp, LGuid, AJsonValue) then
          Exit;

        if AJsonValue is TJSONNull then
          Exit;

        if FRegistry.TryGetValue(LGuid, LClass) then
        begin
          LObj := DeserializeObject(LClass, AJsonValue as TJSONObject);
          if LObj.GetInterface(LGuid, LIntf) then
          begin
            TValue.Make(@LIntf, AProp.PropertyType.Handle, LValue);
            AProp.SetValue(AObj, LValue);
          end
          else
          begin
            LObj.Free;
            raise EJsonMapperException.CreateFmt
              ('Classe registrada para "%s" n�o implementa a interface.',
              [GUIDToString(LGuid)]);
          end;
        end;
      end;

    tkDynArray:
      begin
        if not(AJsonValue is TJSONArray) then
          Exit;
        LValue := BuildDynArrayFromJson(AJsonValue as TJSONArray,
          AProp.PropertyType as TRttiDynamicArrayType);
        if not LValue.IsEmpty then
          AProp.SetValue(AObj, LValue);
      end;
  end;
end;

class function TJsonMapper.DeserializeObject(AClass: TClass;
  AJsonObj: TJSONObject): TObject;
var
  LRttiType: TRttiType;
  LProp: TRttiProperty;
  LJsonValue: TJSONValue;
begin
  Result := AClass.Create;
  try
    LRttiType := FRttiContext.GetType(AClass);
    for LProp in LRttiType.GetProperties do
    begin
      if not LProp.IsWritable then
        Continue;
      LJsonValue := FindJsonValue(AJsonObj, LProp.Name);
      if Assigned(LJsonValue) then
        SetPropertyFromJson(Result, LProp, LJsonValue);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonMapper.FromJson<I>(const AJson: string): I;
var
  LIntfGuid: TGUID;
  LClass: TClass;
  LJsonObj: TJSONObject;
  LObj: TObject;
begin
  Result := Default (I);
  LIntfGuid := GetTypeData(TypeInfo(I))^.Guid;

  if not FRegistry.TryGetValue(LIntfGuid, LClass) then
    raise EJsonMapperException.Create
      ('Nenhuma classe registrada para esta interface.');

  LJsonObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if not Assigned(LJsonObj) then
    raise EJsonMapperException.Create('JSON inv�lido ou n�o � um objeto.');
  try
    LObj := DeserializeObject(LClass, LJsonObj);
    if not LObj.GetInterface(LIntfGuid, Result) then
    begin
      LObj.Free;
      raise EJsonMapperException.Create
        ('A classe registrada n�o implementa a interface esperada.');
    end;
  finally
    LJsonObj.Free;
  end;
end;

{ Serialization internals }

class function TJsonMapper.OptionalToJsonValue(const AIntf: IInterface;
  const AGuid: TGUID): TJSONValue;
var
  LBase: IOptionalNullableBase;
  LStr: IOptNullString;
  LInt: IOptNullInteger;
  LInt64v: IOptNullInt64;
  LDbl: IOptNullDouble;
  LSng: IOptNullSingle;
  LBool: IOptNullBoolean;
  LCur: IOptNullCurrency;
  LDt: IOptNullDateTime;
  LGuidv: IOptNullGuid;
begin
  Result := nil;

  if not Supports(AIntf, IOptionalNullableBase, LBase) then
    Exit;

  if not LBase.HasValue then
    Exit(nil);

  if LBase.IsNull then
    Exit(TJSONNull.Create);

  if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullString))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptString))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullString))^.Guid) then
  begin
    if Supports(AIntf, IOptNullString, LStr) then
      Result := TJSONString.Create(LStr.Value);
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullInteger))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptInteger))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullInteger))^.Guid) then
  begin
    if Supports(AIntf, IOptNullInteger, LInt) then
      Result := TJSONNumber.Create(LInt.Value);
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullInt64))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptInt64))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullInt64))^.Guid) then
  begin
    if Supports(AIntf, IOptNullInt64, LInt64v) then
      Result := TJSONObject.ParseJSONValue(IntToStr(LInt64v.Value))
        as TJSONNumber;
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullDouble))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptDouble))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullDouble))^.Guid) then
  begin
    if Supports(AIntf, IOptNullDouble, LDbl) then
      Result := TJSONNumber.Create(LDbl.Value);
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullSingle))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptSingle))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullSingle))^.Guid) then
  begin
    if Supports(AIntf, IOptNullSingle, LSng) then
      Result := TJSONNumber.Create(LSng.Value);
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullBoolean))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptBoolean))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullBoolean))^.Guid) then
  begin
    if Supports(AIntf, IOptNullBoolean, LBool) then
    begin
      if LBool.Value then
        Result := TJSONTrue.Create
      else
        Result := TJSONFalse.Create;
    end;
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullCurrency))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptCurrency))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullCurrency))^.Guid) then
  begin
    if Supports(AIntf, IOptNullCurrency, LCur) then
      Result := TJSONNumber.Create(Double(LCur.Value));
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullDateTime))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptDateTime))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullDateTime))^.Guid) then
  begin
    if Supports(AIntf, IOptNullDateTime, LDt) then
      Result := TJSONString.Create(DateToISO8601(LDt.Value));
  end
  else if IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptNullGuid))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(IOptGuid))^.Guid) or
    IsEqualGUID(AGuid, GetTypeData(TypeInfo(INullGuid))^.Guid) then
  begin
    if Supports(AIntf, IOptNullGuid, LGuidv) then
      Result := TJSONString.Create(GUIDToString(LGuidv.Value));
  end;
end;

class function TJsonMapper.TValueToJsonValue(const AValue: TValue;
  ARttiType: TRttiType): TJSONValue;
var
  LGuid: TGUID;
  LIntf: IInterface;
  LBase: IOptionalNullableBase;
begin
  Result := nil;

  case ARttiType.TypeKind of
    tkString, tkUString:
      Result := TJSONString.Create(AValue.AsString);

    tkInteger:
      Result := TJSONNumber.Create(AValue.AsInteger);

    tkInt64:
      Result := TJSONObject.ParseJSONValue(IntToStr(AValue.AsInt64))
        as TJSONNumber;

    tkFloat:
      begin
        if ARttiType.Handle = TypeInfo(TDateTime) then
          Result := TJSONString.Create(DateToISO8601(AValue.AsExtended))
        else
          Result := TJSONNumber.Create(AValue.AsExtended);
      end;

    tkEnumeration:
      if ARttiType.Handle = TypeInfo(Boolean) then
      begin
        if AValue.AsBoolean then
          Result := TJSONTrue.Create
        else
          Result := TJSONFalse.Create;
      end;

    tkInterface:
      begin
        LIntf := AValue.AsInterface;
        if not Assigned(LIntf) then
          Exit(nil);

        LGuid := GetTypeData(ARttiType.Handle)^.Guid;

        if Supports(LIntf, IOptionalNullableBase, LBase) then
          Result := OptionalToJsonValue(LIntf, LGuid)
        else
          Result := BuildJsonObject(AValue);
      end;

    tkDynArray:
      Result := BuildJsonArray(AValue, ARttiType as TRttiDynamicArrayType);
  end;
end;

class function TJsonMapper.BuildJsonObject(const AIntfValue: TValue)
  : TJSONObject;
var
  LIntf: IInterface;
  LObj: TObject;
  LRttiType: TRttiInstanceType;
  LMethod: TRttiMethod;
  LPropName: string;
  LRetVal: TValue;
  LJsonVal: TJSONValue;
begin
  Result := TJSONObject.Create;
  try
    LIntf := AIntfValue.AsInterface;
    if not Assigned(LIntf) then
      Exit;

    LObj := LIntf as TObject;
    LRttiType := FRttiContext.GetType(LObj.ClassType) as TRttiInstanceType;

    for LMethod in LRttiType.GetDeclaredMethods do
    begin
      if LMethod.MethodKind <> mkFunction then
        Continue;
      if Length(LMethod.GetParameters) <> 0 then
        Continue;
      if LMethod.ReturnType = nil then
        Continue;
      if not LMethod.Name.StartsWith('Get', True) then
        Continue;

      LPropName := LowerFirst(Copy(LMethod.Name, 4, MaxInt));
      if LPropName = '' then
        Continue;

      LRetVal := LMethod.Invoke(LObj, []);
      LJsonVal := TValueToJsonValue(LRetVal, LMethod.ReturnType);

      if Assigned(LJsonVal) then
        Result.AddPair(LPropName, LJsonVal);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonMapper.BuildJsonArray(const AValue: TValue;
  ARttiType: TRttiDynamicArrayType): TJSONArray;
var
  LElementType: TRttiType;
  I: Integer;
  LElem: TValue;
  LJsonVal: TJSONValue;
begin
  Result := TJSONArray.Create;
  try
    LElementType := ARttiType.ElementType;
    for I := 0 to AValue.GetArrayLength - 1 do
    begin
      LElem := AValue.GetArrayElement(I);
      LJsonVal := TValueToJsonValue(LElem, LElementType);
      if Assigned(LJsonVal) then
        Result.AddElement(LJsonVal)
      else
        Result.AddElement(TJSONNull.Create);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonMapper.ToJson<I>(const AIntf: I): string;
var
  LValue: TValue;
  LJsonObj: TJSONObject;
begin
  TValue.Make(@AIntf, TypeInfo(I), LValue);
  LJsonObj := BuildJsonObject(LValue);
  try
    Result := LJsonObj.ToJson;
  finally
    LJsonObj.Free;
  end;
end;

end.
