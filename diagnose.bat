@echo off
setlocal
title PC Manager Korean Translation Patch Diagnostic
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0src\diagnose.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [FAIL] src\diagnose.ps1 was not found.
    echo Extract the full repository ZIP before running diagnose.bat.
    echo.
    pause
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
