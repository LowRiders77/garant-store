# Garant Store v0.8 DEV - Windows Release Gate
# A release is not verified unless this gate succeeds on real Windows.

[CmdletBinding()]
param(
    [ValidateSet('Source','Archive')][string]$Phase = 'Source'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'RELEASE GATE REFUSED: real Windows is required.' -ForegroundColor Red
    exit 1
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    Write-Host 'RELEASE GATE FAILED: Windows PowerShell 5.1 executable not found.' -ForegroundColor Red
    exit 1
}

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'SelfTest.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'Tests\Test-WindowsIntegration.ps1') -Root $base -Phase $Phase
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host ('RELEASE GATE PASSED ON REAL WINDOWS: ' + $Phase) -ForegroundColor Green
exit 0
