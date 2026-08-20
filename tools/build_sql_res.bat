@echo off
REM build_sql_res.bat - recompila TODOS os .rc sob sql\ para .res, sempre.
REM
REM Uso: copie este arquivo para o projeto consumidor (ex.: tools\build_sql_res.bat,
REM um nivel abaixo da raiz do projeto, ao lado da pasta sql\) e registre como
REM Pre-Build Event do .dproj:
REM
REM   Project Options > Building > Build Events > Pre-build event:
REM     call tools\build_sql_res.bat
REM
REM A pasta sql\ e resolvida a partir da propria localizacao deste .bat
REM (sempre "..\sql" relativo a ele), nao do diretorio de onde foi chamado -
REM por isso funciona tanto via Pre-Build Event (CWD = raiz do projeto) quanto
REM rodando manualmente de dentro de tools\ ou de qualquer outro lugar.
REM
REM Qualquer falha de brcc32 aborta com exit code != 0 - isso interrompe a
REM compilacao (tanto na IDE quanto via msbuild no .dproj). NAO cobre build
REM feito com "dcc32 projeto.dpr" direto, que ignora o .dproj e portanto os
REM Build Events - para esse caso, ver a checagem de hash em runtime descrita
REM no CLAUDE.md / README desta lib.

setlocal enabledelayedexpansion

set "BRCC32="
where brcc32.exe >nul 2>nul
if not errorlevel 1 set "BRCC32=brcc32.exe"
if not defined BRCC32 if defined BDS if exist "%BDS%\bin\brcc32.exe" set "BRCC32=%BDS%\bin\brcc32.exe"

if not defined BRCC32 (
    echo [ERRO] brcc32.exe nao encontrado no PATH nem em %%BDS%%\bin.
    echo Rode a partir da IDE do RAD Studio ou de um prompt com rsvars.bat carregado.
    exit /b 1
)

set "SQL_ROOT=%~dp0..\sql"
if not exist "%SQL_ROOT%" (
    echo [AVISO] Pasta "%SQL_ROOT%" nao encontrada - nada a compilar.
    exit /b 0
)

set "FOUND=0"
set "FAILED=0"

for /r "%SQL_ROOT%" %%F in (*.rc) do (
    set "FOUND=1"
    echo Compilando %%~fF ...
    pushd "%%~dpF"
    "%BRCC32%" "%%~nxF" -fo "%%~nF.res"
    if errorlevel 1 (
        echo [ERRO] Falha ao compilar %%~fF
        set "FAILED=1"
    )
    popd
)

if "!FOUND!"=="0" (
    echo [AVISO] Nenhum arquivo .rc encontrado em "%SQL_ROOT%".
)

if "!FAILED!"=="1" (
    echo.
    echo [ERRO] Um ou mais arquivos .rc falharam ao compilar. Build abortado.
    exit /b 1
)

echo Recursos SQL ^(.res^) atualizados com sucesso.
exit /b 0
