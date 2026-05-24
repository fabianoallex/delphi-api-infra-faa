unit Db.Adapters.Registry;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Db.Interfaces;

type

  { TDBRegistry }

  TDBRegistry = class
  private
    class var FFactories: TDictionary<string, IDBFactory>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure RegisterFactory(const AFactoryName: string; AFactory: IDBFactory);
    class function GetFactory(const AFactoryName: string): IDBFactory;
  end;

implementation

{ TDBRegistry }

class constructor TDBRegistry.Create;
begin
  FFactories := TDictionary<string, IDBFactory>.Create;
end;

class destructor TDBRegistry.Destroy;
begin
  FFactories.Clear;
  FFactories.Free;
end;

class procedure TDBRegistry.RegisterFactory(const AFactoryName: string; AFactory: IDBFactory);
begin
  FFactories.Add(AFactoryName, AFactory);
end;

class function TDBRegistry.GetFactory(const AFactoryName: string): IDBFactory;
begin
  if not FFactories.TryGetValue(AFactoryName, Result) then
    Result := nil;
end;

end.
