@echo off
setlocal
set "AM_LOC=%~dp0"

:: Parse arguments into flags
set "CMD="
set "DEBUG="
set "DRYRUN="

:parse_args
if "%1"=="" goto :done_parse
if "%1"=="upa" set "CMD=upa" & shift & goto :parse_args
if "%1"=="-pm" set "CMD=pm" & shift & goto :parse_args
if "%1"=="--debug" set "DEBUG=1" & shift & goto :parse_args
if "%1"=="-n" set "DRYRUN=1" & shift & goto :parse_args
echo gn: unknown option: %1
echo Usage: gn [upa] [-pm] [--debug] [-n]
goto :eof

:done_parse

:: Build PowerShell args
set "PS_ARGS="
if defined DRYRUN set "PS_ARGS=%PS_ARGS% -n"
if defined DEBUG set "PS_ARGS=%PS_ARGS% -Debug"

:: Route to appropriate handler
if "%CMD%"=="upa" goto :handle_upa
if "%CMD%"=="pm" goto :handle_pm
goto :handle_default

:handle_upa
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\gn-upa.ps1"%PS_ARGS%
goto :eof

:handle_pm
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\gn-pm.ps1"%PS_ARGS%
goto :eof

:handle_default
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\gn.ps1"%PS_ARGS%
endlocal
