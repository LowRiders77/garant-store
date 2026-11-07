@echo off
setlocal
cd /d "%~dp0"
echo [Garant Store v0.8 DEV] Full Windows validation - no release build.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Validate-DEV.ps1"
set "GS_EXIT=%ERRORLEVEL%"
if not "%GS_EXIT%"=="0" echo See DEV-VALIDATION.log for details.
echo.
pause
exit /b %GS_EXIT%
