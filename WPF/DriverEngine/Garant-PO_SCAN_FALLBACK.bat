@echo off
setlocal
cd /d "%~dp0"
title Garant-PO 6.0 - Scan
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Worker.ps1" -Action scan
echo Check Logs\Remaining.csv and Logs\Garant-PO-Latest.log
pause
