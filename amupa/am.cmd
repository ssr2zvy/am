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
if "%1"=="-u" set "CMD=u" & shift & goto :parse_args
if "%1"=="--debug" set "DEBUG=1" & shift & goto :parse_args
if "%1"=="-n" set "DRYRUN=1" & shift & goto :parse_args
if "%1"=="--help" set "CMD=help" & shift & goto :parse_args
if "%1"=="-h" set "CMD=help" & shift & goto :parse_args
if "%1"=="help" set "CMD=help" & shift & goto :parse_args
if "%1"=="--upaupa" set "CMD=upaupa" & shift & goto :parse_args
echo am: unknown option: %1
echo Usage: am [upa] [-pm] [-u] [--debug] [-n] [--help] [--upaupa]
goto :eof

:done_parse

:: Build PowerShell args
set "PS_ARGS="
if defined DRYRUN set "PS_ARGS=%PS_ARGS% -n"
if defined DEBUG set "PS_ARGS=%PS_ARGS% -Debug"

:: Route to appropriate handler
if "%CMD%"=="upa" goto :handle_upa
if "%CMD%"=="pm" goto :handle_pm
if "%CMD%"=="u" goto :handle_u
if "%CMD%"=="help" goto :handle_help
if "%CMD%"=="upaupa" goto :handle_upaupa
goto :handle_default

:handle_upa
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\am-upa.ps1"%PS_ARGS%
goto :eof

:handle_pm
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\am-pm.ps1"%PS_ARGS%
goto :eof

:handle_u
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\am-u.ps1"%PS_ARGS%
goto :eof

:handle_help
echo use --upaupa for help
goto :eof

:handle_upaupa
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\am-help.ps1"
goto :eof

:handle_default
powershell -ExecutionPolicy Bypass -File "%AM_LOC%upaupa\am.ps1"%PS_ARGS%
endlocal
