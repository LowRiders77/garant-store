@echo off
setlocal
cd /d "%~dp0"
set "script=%~dp0Collect-Logs.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%script%"
echo.
pause
