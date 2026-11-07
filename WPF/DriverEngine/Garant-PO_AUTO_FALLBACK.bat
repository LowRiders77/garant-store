@echo off
setlocal
cd /d "%~dp0"
title Garant-PO 6.0 - Fallback without browser
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
del /q "%~dp0State\selection.json" >nul 2>&1
del /q "%~dp0State\cancel.flag" >nul 2>&1
echo Running standalone driver search without web interface...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Worker.ps1" -Action auto
echo.
echo Check Logs\Garant-PO-Latest.log for details.
pause
