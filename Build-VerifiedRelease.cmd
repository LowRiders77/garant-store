@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-VerifiedRelease.ps1"
set "GS_BUILD_EXIT=%ERRORLEVEL%"
echo.
if "%GS_BUILD_EXIT%"=="0" (
    echo Verified release build completed successfully.
) else (
    echo Verified release build FAILED. See the release-gate log in the Releases folder.
)
pause
exit /b %GS_BUILD_EXIT%
