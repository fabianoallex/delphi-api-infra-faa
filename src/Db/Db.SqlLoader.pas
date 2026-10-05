unit Db.SqlLoader;

interface

uses
  System.Classes,
  System.SysUtils,
  System.StrUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Winapi.Windows;

type
  ESQLLoaderException = class(Exception);

  (*
    SELECT *
    FROM
      TB_ENTITY
    WHERE 1=1
      [ENTITY_NAME {] AND ENTITY_NAME = :ENTITY_NAME [} ENTITY_NAME]
      [PK_FIELD {] AND PK_FIELD <= :PK_FIELD [} PK_FIELD]

    [ENTITY_NAME {] --> TAG DE INICIO
    [} ENTITY_NAME] --> TAG DE FIM

    ProcessTag diz se mantém ou remove a condição entre as tags

    Os dois marcadores seguem a mesma regra, no ProcessTag e na limpeza de
    .SQL: espaços opcionais em volta do nome, então [TAG{], [ TAG {], [}TAG]
    e [} TAG ] valem. ProcessTag pareia cada abertura com o fechamento
    seguinte e lança ESQLLoaderException para fechamento sem abertura antes,
    abertura sem fechamento depois, ou bloco aninhado em outro da mesma tag.
    Antes, o fechamento só era reconhecido com exatamente um espaço
    ([} TAG]) e os dois marcadores eram procurados desde o início do texto,
    cada um por conta própria: um [}TAG] não reconhecido deixava as
    marcações no SQL (o FireDAC então reclamava das chaves com um -307 que
    não diz a causa), ou pareava a abertura com o fechamento de outro bloco
    e apagava o SQL entre eles, ou entrava em laço infinito. Portado de
    pascal-db-faa 0.10.0 (16d1649).
  *)

  TSQLCache = TDictionary<string, string>;

  { TSQLResult }

  TSQLResult = record
  public
    class operator Explicit(a: TSQLResult): string;
    class function From(const ASQL: string): TSQLResult; static;
  private
    FSQL: string;
    function GetSQL: string;
  public
    function ProcessTag(const ATag: string; Keep: Boolean): TSQLResult;
    function ReplaceLiteral(const ATag, AValue: string): TSQLResult;
    function ApplyOperator(const ATag: string; const AOperator: string): TSQLResult;
    function ApplyFilter(const Tag: string; const OperatorSQL: string; HasValue: Boolean): TSQLResult;
    property SQL: string read GetSQL;
  end;

  { TSQLLoader }

  TSQLLoader = class
  private
    class var FCache: TSQLCache;
    class var FLock: TCriticalSection;
    class function GetInternal(ASQLDirectory, AResourceName: string): string;
    class function GetFromCacheOrResource(ASQLDirectory, AResourceName: string): string;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure ClearCache;
    class function Load(ASQLDirectory, AResourceName: string): TSQLResult;
  private
    FSQLDirectory: string;
  protected
    function GetSql(const AResourceName: string): TSQLResult; virtual;
  public
    constructor Create(ASQLDirectory: string);
    property SQLDirectory: string read FSQLDirectory;
    property Sql[const AResourceName: string]: TSQLResult read GetSql; default;
  end;

implementation

{ TSQLResult }

class function TSQLResult.From(const ASQL: string): TSQLResult;
begin
  Result.FSQL := ASQL;
end;

function IsTagNameChar(C: Char): Boolean;
begin
  Result := not ((C = ' ') or (C = #9) or (C = #10) or (C = #13) or
    (C = '[') or (C = ']') or (C = '{') or (C = '}'));
end;

procedure SkipSpaces(const S: string; var I: Integer);
begin
  while (I <= Length(S)) and (S[I] = ' ') do
    Inc(I);
end;

// S[AStart] é '['. Abertura: [ nome {]; fechamento: [} nome ]; espaços
// opcionais em volta do nome. AName = '' casa com qualquer nome. Quando casa,
// AEnd é o índice do último caractere do marcador (o seu ']').
function MatchMarker(const S, AName: string; AOpening: Boolean;
  AStart: Integer; out AEnd: Integer): Boolean;
var
  J, LNameStart: Integer;
begin
  Result := False;
  AEnd := 0;
  J := AStart + 1;
  if not AOpening then
  begin
    if (J > Length(S)) or (S[J] <> '}') then Exit;
    Inc(J);
  end;
  SkipSpaces(S, J);
  if AName <> '' then
  begin
    if Copy(S, J, Length(AName)) <> AName then Exit;
    Inc(J, Length(AName));
  end
  else
  begin
    LNameStart := J;
    while (J <= Length(S)) and IsTagNameChar(S[J]) do
      Inc(J);
    if J = LNameStart then Exit;
  end;
  SkipSpaces(S, J);
  if AOpening then
  begin
    if (J >= Length(S)) or (S[J] <> '{') or (S[J + 1] <> ']') then Exit;
    Inc(J);
  end
  else if (J > Length(S)) or (S[J] <> ']') then
    Exit;
  AEnd := J;
  Result := True;
end;

// Primeiro marcador em AFrom ou depois; AStart = 0 quando não há nenhum.
function FindMarker(const S, AName: string; AOpening: Boolean; AFrom: Integer;
  out AStart, AEnd: Integer): Boolean;
begin
  AStart := PosEx('[', S, AFrom);
  while AStart > 0 do
  begin
    if MatchMarker(S, AName, AOpening, AStart, AEnd) then
      Exit(True);
    AStart := PosEx('[', S, AStart + 1);
  end;
  AEnd := 0;
  Result := False;
end;

function TSQLResult.ProcessTag(const ATag: string; Keep: Boolean): TSQLResult;
var
  LFrom, LOpenStart, LOpenEnd, LCloseStart, LCloseEnd, LNextStart, LNextEnd: Integer;
begin
  if ATag = '' then
    raise ESQLLoaderException.Create('ProcessTag: o nome da tag é obrigatório');

  // Tudo antes de LFrom já foi processado e não tem marcador de ATag.
  LFrom := 1;
  while True do
  begin
    if not FindMarker(FSQL, ATag, True, LFrom, LOpenStart, LOpenEnd) then
    begin
      if FindMarker(FSQL, ATag, False, LFrom, LCloseStart, LCloseEnd) then
        raise ESQLLoaderException.CreateFmt(
          'Tag SQL %s: marcador de fechamento sem abertura antes dele', [ATag]);
      Break;
    end;

    if FindMarker(FSQL, ATag, False, LFrom, LCloseStart, LCloseEnd) and
       (LCloseStart < LOpenStart) then
      raise ESQLLoaderException.CreateFmt(
        'Tag SQL %s: marcador de fechamento sem abertura antes dele', [ATag]);

    if not FindMarker(FSQL, ATag, False, LOpenEnd + 1, LCloseStart, LCloseEnd) then
      raise ESQLLoaderException.CreateFmt(
        'Tag SQL %s: marcador de abertura sem fechamento depois dele', [ATag]);

    if FindMarker(FSQL, ATag, True, LOpenEnd + 1, LNextStart, LNextEnd) and
       (LNextStart < LCloseStart) then
      raise ESQLLoaderException.CreateFmt(
        'Tag SQL %s: um bloco desta tag está aninhado em outro', [ATag]);

    if Keep then
    begin
      Delete(FSQL, LCloseStart, LCloseEnd - LCloseStart + 1);
      Delete(FSQL, LOpenStart, LOpenEnd - LOpenStart + 1);
      LFrom := LCloseStart - (LOpenEnd - LOpenStart + 1);
    end
    else
    begin
      Delete(FSQL, LOpenStart, LCloseEnd - LOpenStart + 1);
      LFrom := LOpenStart;
    end;
  end;
  Result := Self;
end;

function TSQLResult.ReplaceLiteral(const ATag, AValue: string): TSQLResult;
begin
  FSQL := StringReplace(FSQL, '${' + ATag + '}', AValue, [rfReplaceAll]);
  Result := Self;
end;

function TSQLResult.ApplyOperator(const ATag: string; const AOperator: string): TSQLResult;
begin
  Result := ReplaceLiteral(ATag + '_OP', AOperator);
end;

function TSQLResult.ApplyFilter(const Tag: string; const OperatorSQL: string; HasValue: Boolean): TSQLResult;
begin
  Result := ProcessTag(Tag, HasValue);
  if HasValue then
    Result := ReplaceLiteral(Tag + '_OP', OperatorSQL);
end;

class operator TSQLResult.Explicit(a: TSQLResult): string;
begin
  Result := a.FSQL;
end;

function TSQLResult.GetSQL: string;
var
  LStart, LEnd: Integer;
begin
  ProcessTag('COMMENTS', False);

  Result := FSQL;

  // Marcadores de tags que ninguém processou: some o marcador, fica o conteúdo
  LStart := 1;
  while FindMarker(Result, '', True, LStart, LStart, LEnd) do
    Delete(Result, LStart, LEnd - LStart + 1);

  LStart := 1;
  while FindMarker(Result, '', False, LStart, LStart, LEnd) do
    Delete(Result, LStart, LEnd - LStart + 1);
end;

{ TSQLLoader }

class constructor TSQLLoader.Create;
begin
  FCache := TSQLCache.Create;
  FLock  := TCriticalSection.Create;
end;

class destructor TSQLLoader.Destroy;
begin
  FCache.Free;
  FLock.Free;
end;

class procedure TSQLLoader.ClearCache;
begin
  FLock.Enter;
  try
    FCache.Clear;
  finally
    FLock.Leave;
  end;
end;

class function TSQLLoader.Load(ASQLDirectory, AResourceName: string): TSQLResult;
begin
  if ASQLDirectory.IsEmpty or AResourceName.IsEmpty then
    raise ESQLLoaderException.Create(
      'ASQLDirectory e AResourceName são obrigatórios'
    );

  Result.FSQL := GetFromCacheOrResource(ASQLDirectory, AResourceName);
end;

function TSQLLoader.GetSql(const AResourceName: string): TSQLResult;
begin
  Result := TSQLLoader.Load(FSQLDirectory, AResourceName);
end;

constructor TSQLLoader.Create(ASQLDirectory: string);
begin
  FSQLDirectory := ASQLDirectory;
end;

class function TSQLLoader.GetFromCacheOrResource(ASQLDirectory, AResourceName: string): string;
var
  LKey: string;
  LValue: string;
begin
  LKey := ASQLDirectory + AResourceName;

  FLock.Enter;
  try
    if FCache.TryGetValue(LKey, LValue) then
      Exit(LValue);
  finally
    FLock.Leave;
  end;

  Result := GetInternal(ASQLDirectory, AResourceName);

  // Double-checked locking: outra thread pode ter carregado enquanto chamávamos GetInternal
  FLock.Enter;
  try
    if FCache.TryGetValue(LKey, LValue) then
      Exit(LValue);

    FCache.Add(LKey, Result);
  finally
    FLock.Leave;
  end;
end;

class function TSQLLoader.GetInternal(ASQLDirectory, AResourceName: string): string;
var
  RS: TResourceStream;
  SL: TStringList;
  RSName: string;
begin
  Result := '';

  RSName := 'SQL_'
    + ASQLDirectory + '_'
    + StringReplace(AResourceName, '.', '_', [rfReplaceAll]);

  if FindResource(HInstance, PChar(RSName), RT_RCDATA) = 0 then
    raise ESQLLoaderException.CreateFmt(
      'SQL resource não encontrado: %s. Procurando por: %s',
      [AResourceName, RSName]
    );

  RS := TResourceStream.Create(HInstance, RSName, RT_RCDATA);
  SL := TStringList.Create;
  try
    SL.LoadFromStream(RS, TEncoding.UTF8);
    Result := SL.Text;
  finally
    SL.Free;
    RS.Free;
  end;
end;

end.
