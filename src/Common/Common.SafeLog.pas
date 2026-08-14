unit Common.SafeLog;

interface

/// Escreve no console protegido por uma seção crítica global.
///
/// Handlers HTTP (Horse) e OnRequest de pipe-server rodam em thread pool —
/// Writeln direto nesse contexto corrompe o buffer do console sob
/// concorrência. Use SafeWriteln em qualquer ponto que possa ser chamado
/// fora da main thread.
procedure SafeWriteln(const AText: string); overload;
procedure SafeWriteln(const AFormatStr: string; const AArgs: array of const); overload;

implementation

uses
  System.SysUtils,
  System.SyncObjs;

var
  GConsoleLock: TCriticalSection;

procedure SafeWriteln(const AText: string);
begin
  GConsoleLock.Enter;
  try
    Writeln(AText);
  finally
    GConsoleLock.Leave;
  end;
end;

procedure SafeWriteln(const AFormatStr: string; const AArgs: array of const);
begin
  SafeWriteln(Format(AFormatStr, AArgs));
end;

initialization
  GConsoleLock := TCriticalSection.Create;

finalization
  GConsoleLock.Free;

end.
