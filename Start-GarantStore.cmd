@echo off
setlocal
cd /d "%~dp0"
rem Release integrity/regressions are validated in Windows CI, not at every startup.
rem Debug-only manual preflight: set GS_VALIDATE_ON_LAUNCH=1
if "%GS_VALIDATE_ON_LAUNCH%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SelfTest.ps1"
    if errorlevel 1 exit /b 1
)
if "%GS_RELEASE_SMOKE%"=="1" (
    echo [Garant Store] CMD launcher smoke passed.
    exit /b 0
)
if not exist "%~dp0GarantStore.GUI.ps1" (
    echo [Garant Store] Program file missing.
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0GarantStore.GUI.ps1"
set "GS_EXIT=%ERRORLEVEL%"
if not "%GS_EXIT%"=="0" echo [Garant Store] GUI exited with code %GS_EXIT%.
exit /b %GS_EXIT%
