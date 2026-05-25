unit Common.OrderBy;

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// Levantada quando o cliente envia um campo de ordenação inválido.
  /// Capturar no controller para retornar HTTP 400.
  /// </summary>
  EOrderByException = class(Exception);

  TOrderDir = (odAsc, odDesc);

  /// <summary>
  /// Especificação de ordenação para um endpoint de busca.
  /// Define o mapeamento entre os nomes que o cliente usa e as colunas SQL,
  /// o padrão quando o cliente não envia nada, e o tiebreaker fixo.
  ///
  /// Sintaxe do cliente: campos separados por vírgula; "-campo" = DESC.
  ///   Exemplo: "nome,-uf"  →  NOME ASC, UF DESC
  ///
  /// Uso típico no repositório:
  ///   class function OrderBySpec: TOrderBySpec;
  ///   begin
  ///     Result := TOrderBySpec.New
  ///       .Allow('nome',    'NOME')
  ///       .Allow('codIbge', 'COD_IBGE')
  ///       .Default('nome')
  ///       .AlwaysLast('COD_IBGE');
  ///   end;
  /// </summary>
  TOrderBySpec = record
  private
    type
      TField = record
        ClientName: string;
        SqlExpr:    string;
      end;
      TFixed = record
        SqlExpr: string;
        Dir:     TOrderDir;
      end;
    var
      FAllowed:     TArray<TField>;
      FDefault:     string;
      FTiebreakers: TArray<TFixed>;
    function TryFind(const AName: string; out ASql: string): Boolean;
    function ParseExpr(const AExpr: string): string;
    function DirStr(ADir: TOrderDir): string;
    function AllowedNames: string;
  public
    class function New: TOrderBySpec; static;

    /// <summary>Registra um campo disponível para o cliente.</summary>
    function Allow(const AClientName, ASqlExpr: string): TOrderBySpec;

    /// <summary>
    /// Define a expressão de ordenação usada quando o cliente não envia nada.
    /// Usa a mesma sintaxe do cliente (ex: 'nome' ou '-nome').
    /// </summary>
    function Default(const AClientExpr: string): TOrderBySpec;

    /// <summary>
    /// Adiciona uma ordenação fixa ao FINAL do ORDER BY (tiebreaker).
    /// Sempre presente, independente do que o cliente enviar.
    /// ADir padrão = odAsc.
    /// </summary>
    function AlwaysLast(const ASqlExpr: string;
      ADir: TOrderDir = odAsc): TOrderBySpec;

    /// <summary>
    /// Converte a expressão do cliente em fragmento SQL (sem "ORDER BY").
    /// AOrderBy = '' usa o padrão configurado.
    /// Levanta EOrderByException para campos inválidos.
    /// </summary>
    function Build(const AOrderBy: string): string;

    /// <summary>
    /// Retorna texto descritivo para usar no QueryParam do Swagger/MCP,
    /// listando os campos disponíveis, o padrão e o tiebreaker.
    /// </summary>
    function DocHint: string;
  end;

implementation

// ---------------------------------------------------------------------------

class function TOrderBySpec.New: TOrderBySpec;
begin
  Result.FAllowed     := nil;
  Result.FDefault     := '';
  Result.FTiebreakers := nil;
end;

function TOrderBySpec.Allow(const AClientName, ASqlExpr: string): TOrderBySpec;
begin
  Result := Self;
  SetLength(Result.FAllowed, Length(Result.FAllowed) + 1);
  Result.FAllowed[High(Result.FAllowed)].ClientName := AClientName;
  Result.FAllowed[High(Result.FAllowed)].SqlExpr    := ASqlExpr;
end;

function TOrderBySpec.Default(const AClientExpr: string): TOrderBySpec;
begin
  Result         := Self;
  Result.FDefault := AClientExpr;
end;

function TOrderBySpec.AlwaysLast(const ASqlExpr: string;
  ADir: TOrderDir): TOrderBySpec;
begin
  Result := Self;
  SetLength(Result.FTiebreakers, Length(Result.FTiebreakers) + 1);
  Result.FTiebreakers[High(Result.FTiebreakers)].SqlExpr := ASqlExpr;
  Result.FTiebreakers[High(Result.FTiebreakers)].Dir     := ADir;
end;

function TOrderBySpec.DirStr(ADir: TOrderDir): string;
begin
  if ADir = odAsc then Result := 'ASC' else Result := 'DESC';
end;

function TOrderBySpec.TryFind(const AName: string; out ASql: string): Boolean;
var
  LField: TField;
begin
  for LField in FAllowed do
    if SameText(LField.ClientName, AName) then
    begin
      ASql := LField.SqlExpr;
      Exit(True);
    end;
  Result := False;
  ASql   := '';
end;

function TOrderBySpec.AllowedNames: string;
var
  LField: TField;
begin
  Result := '';
  for LField in FAllowed do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + LField.ClientName;
  end;
end;

function TOrderBySpec.ParseExpr(const AExpr: string): string;
var
  LTokens:   TArray<string>;
  LToken:    string;
  LName:     string;
  LSql:      string;
  LDir:      TOrderDir;
  LFragment: string;
begin
  Result  := '';
  LTokens := AExpr.Trim.Split([',']);
  for LToken in LTokens do
  begin
    LName := LToken.Trim;
    if LName = '' then Continue;

    if LName.StartsWith('-') then
    begin
      LDir  := odDesc;
      LName := LName.Substring(1).Trim;
    end
    else
      LDir := odAsc;

    if LName = '' then Continue;

    if not TryFind(LName, LSql) then
      raise EOrderByException.CreateFmt(
        'Campo de ordenação inválido: "%s". Disponíveis: %s',
        [LName, AllowedNames]);

    LFragment := LSql + ' ' + DirStr(LDir);
    if Result = '' then
      Result := LFragment
    else
      Result := Result + ', ' + LFragment;
  end;
end;

function TOrderBySpec.Build(const AOrderBy: string): string;
var
  LFixed:  TFixed;
  LParsed: string;
begin
  if AOrderBy.Trim <> '' then
    LParsed := ParseExpr(AOrderBy)
  else if FDefault <> '' then
    LParsed := ParseExpr(FDefault)
  else
    LParsed := '';

  Result := LParsed;

  for LFixed in FTiebreakers do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + LFixed.SqlExpr + ' ' + DirStr(LFixed.Dir);
  end;

  if Result = '' then
    raise Exception.Create(
      'TOrderBySpec.Build: nenhuma expressão de ordenação disponível. ' +
      'Configure Default() ou AlwaysLast().');
end;

function TOrderBySpec.DocHint: string;
var
  LFixed:     TFixed;
  LTiePart:   string;
  LExample:   string;
begin
  LTiePart := '';
  for LFixed in FTiebreakers do
  begin
    if LTiePart <> '' then LTiePart := LTiePart + ', ';
    LTiePart := LTiePart + LFixed.SqlExpr + ' ' + DirStr(LFixed.Dir);
  end;

  if FDefault <> '' then
    LExample := FDefault
  else if Length(FAllowed) > 0 then
    LExample := FAllowed[0].ClientName
  else
    LExample := '';

  Result := 'Campos disponíveis: ' + AllowedNames + '.';
  if FDefault <> '' then
    Result := Result + ' Padrão: ' + FDefault + '.';
  if LTiePart <> '' then
    Result := Result + ' Tiebreaker fixo: ' + LTiePart + '.';
  Result := Result + ' Use "-campo" para decrescente; separe múltiplos por vírgula.';
  if LExample <> '' then
    Result := Result + ' Ex: "' + LExample + '"';
end;

end.
