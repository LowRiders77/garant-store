# Garant Store v0.8 DEV - Windows integration validator (never builds a release).
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($env:OS -ne 'Windows_NT') {
    Write-Host 'VALIDATION REFUSED: this test requires actual Windows.' -ForegroundColor Red
    exit 1
}
$log = Join-Path $root 'DEV-VALIDATION.log'
try {
    Start-Transcript -LiteralPath $log -Force -ErrorAction Stop | Out-Null
    Write-Host 'Garant Store v0.8 DEV / Windows full validation (NO RELEASE)' -ForegroundColor Cyan
    $winPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $winPS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'SelfTest.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'SelfTest failed.' }
    & $winPS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tests\Test-WindowsIntegration.ps1') -Root $root -Phase Source
    if ($LASTEXITCODE -ne 0) { throw 'Windows integration failed.' }
    Write-Host 'DEV VALIDATION PASSED. This does not promote the build to VERIFIED.' -ForegroundColor Green
} catch {
    Write-Host ('DEV VALIDATION FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
exit 0
