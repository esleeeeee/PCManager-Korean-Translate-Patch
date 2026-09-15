@echo off
setlocal
title PC Manager Korean Translation Patch
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0src\install.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [FAIL] src\install.ps1 was not found.
    echo Extract the full repository ZIP before running install.bat.
    echo.
    pause
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Done.
) else (
    echo Installation failed with exit code %RC%.
)
echo.
pause
exit /b %RC%
