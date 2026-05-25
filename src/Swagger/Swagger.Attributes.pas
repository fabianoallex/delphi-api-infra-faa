unit Swagger.Attributes;

interface

type
  /// <summary>
  /// Aplicar nos métodos Get* da interface do DTO para enriquecer a documentação
  /// Swagger com descrição, exemplo de valor e formato opcional.
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

end.
