@echo off
setlocal
cd /d "%~dp0"
title Garant-PO 6.0
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Requesting administrator permissions...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Server.ps1"
if errorlevel 1 (
 echo.
 echo Could not start Garant-PO. See the console error above.
 pause
)
