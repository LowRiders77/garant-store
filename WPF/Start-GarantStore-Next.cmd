@echo off
setlocal
cd /d "%~dp0"
if "%GS_RELEASE_SMOKE%"=="1" exit /b 0
start "" "%SystemRoot%\System32\wscript.exe" //B "%~dp0GarantStore.Launcher.vbs"
exit /b 0
