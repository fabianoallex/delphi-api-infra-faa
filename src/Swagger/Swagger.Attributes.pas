unit Swagger.Attributes;

interface

type
  /// <summary>
  /// Enriquece a documentação Swagger com descrição, exemplo e formato opcional.
  /// Aplicar nos métodos Get* da classe de implementação do DTO.
  /// </summary>
  SwagProp = class(TCustomAttribute)
  private
    FDescription: string;
    FExample: string;
    FFormat: string;
  public
    constructor Create(const ADescription: string); overload;
    constructor Create(const ADescription, AExample: string); overload;
    constructor Create(const ADescription, AExample, AFormat: string); overload;
    property Description: string read FDescription;
    property Example: string read FExample;
    property Format: string read FFormat;
  end;

  /// <summary>
  /// Define o valor mínimo do campo no schema JSON.
  /// Strings  → "minLength": N
  /// Números  → "minimum": N
  /// Aplicar junto com [SwagProp] no mesmo método Get*.
  /// </summary>
  SwagMin = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  /// <summary>
  /// Define o valor máximo do campo no schema JSON.
  /// Strings  → "maxLength": N
  /// Números  → "maximum": N
  /// Aplicar junto com [SwagProp] no mesmo método Get*.
  /// </summary>
  SwagMax = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  /// <summary>
  /// Restringe o campo a uma lista de valores válidos — "enum": [...].
  /// Valores separados por vírgula: [SwagEnum('ativo,inativo,suspenso')]
  /// </summary>
  SwagEnum = class(TCustomAttribute)
  private
    FValues: string;
  public
    constructor Create(const AValues: string);
    property Values: string read FValues;
  end;

  /// <summary>
  /// Restringe o campo a um padrão regex — "pattern": "...".
  /// Exemplo: [SwagPattern('^[A-Z]{2}$')]
  /// </summary>
  SwagPattern = class(TCustomAttribute)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue;
  end;

implementation

constructor SwagProp.Create(const ADescription: string);
begin
  inherited Create;
  FDescription := ADescription;
end;

constructor SwagProp.Create(const ADescription, AExample: string);
begin
  inherited Create;
  FDescription := ADescription;
  FExample := AExample;
end;

constructor SwagProp.Create(const ADescription, AExample, AFormat: string);
begin
  inherited Create;
  FDescription := ADescription;
  FExample := AExample;
  FFormat := AFormat;
end;

constructor SwagMin.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

constructor SwagMax.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

constructor SwagEnum.Create(const AValues: string);
begin
  inherited Create;
  FValues := AValues;
end;

constructor SwagPattern.Create(const AValue: string);
begin
  inherited Create;
  FValue := AValue;
end;

end.
