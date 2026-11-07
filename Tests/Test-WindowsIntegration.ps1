# Garant Store - Real Windows integration tests
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [ValidateSet('Source','Archive')][string]$Phase = 'Source'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'FAIL: Windows integration gate requires Windows.' -ForegroundColor Red
    exit 1
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) { throw 'Windows PowerShell 5.1 executable not found.' }
if (-not (Test-Path -LiteralPath $cmdExe -PathType Leaf)) { throw 'cmd.exe not found.' }

$versionText = & $windowsPowerShell -NoProfile -Command '$PSVersionTable.PSEdition + ''|'' + $PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0) { throw 'Unable to start Windows PowerShell.' }
$versionParts = @((([string]$versionText).Trim() -split '\|'))
if ($versionParts.Count -ne 2 -or $versionParts[0] -ne 'Desktop' -or -not $versionParts[1].StartsWith('5.1')) {
    Write-Host ('FAIL: expected Windows PowerShell Desktop 5.1, got ' + ([string]$versionText).Trim()) -ForegroundColor Red
    exit 1
}
Write-Host ('PASS: Windows PowerShell 5.1 runtime: ' + ([string]$versionText).Trim()) -ForegroundColor Green

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'RunTests.ps1') -Mode ReleaseGate
if ($LASTEXITCODE -ne 0) {
    Write-Host ('FAIL: full regression suite in phase ' + $Phase) -ForegroundColor Red
    exit 1
}
Write-Host ('PASS: full regression suite in phase ' + $Phase) -ForegroundColor Green

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Tests\Test-StrictModeHazards.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { exit 1 }

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Tests\Test-CmdMetacharacters.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { exit 1 }

$oldReleaseSmoke = $env:GS_RELEASE_SMOKE
$oldGuiSmoke = $env:GS_GUI_SMOKE
$oldMarker = $env:GS_GUI_SMOKE_MARKER
try {
    $env:GS_RELEASE_SMOKE = '1'
    $env:GS_GUI_SMOKE = ''
    $env:GS_GUI_SMOKE_MARKER = ''
    $launcherPath = Join-Path $Root 'Start-GarantStore.cmd'
    $launcherCommand = 'call "' + $launcherPath + '"'
    & $cmdExe /d /s /c $launcherCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('FAIL: cmd.exe launcher smoke in phase ' + $Phase) -ForegroundColor Red
        exit 1
    }
    Write-Host ('PASS: cmd.exe Start-GarantStore.cmd smoke in phase ' + $Phase) -ForegroundColor Green

    # GitHub-hosted Windows runners may not have an interactive user desktop.
    # Attempt the real GUI launch anyway; a missing CLOSED marker fails closed.
    # Passing here proves WinForms initialization/layout/start-close, not a
    # human visual review or GPU rendering quality.
    if (-not [Environment]::UserInteractive) {
        Write-Host 'INFO: non-interactive runner; attempting real STA WinForms GUI smoke.' -ForegroundColor Yellow
    }

    $markerPath = Join-Path $env:TEMP ('GarantStore-GUI-smoke-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $env:GS_RELEASE_SMOKE = ''
    $env:GS_GUI_SMOKE = '1'
    $env:GS_GUI_SMOKE_MARKER = $markerPath

    $launcherPath = Join-Path $Root 'Start-GarantStore.cmd'
    $launcherCommand = 'call "' + $launcherPath + '"'
    # Bound the real GUI smoke test: a hung UI or dialog must fail closed.
    $guiPsi = New-Object Diagnostics.ProcessStartInfo
    $guiPsi.FileName = $cmdExe
    $guiPsi.Arguments = '/d /s /c ' + $launcherCommand
    $guiPsi.UseShellExecute = $false
    $guiPsi.CreateNoWindow = $true
    $guiProc = [Diagnostics.Process]::Start($guiPsi)
    if ($null -eq $guiProc) { throw 'Could not start cmd.exe GUI smoke.' }
    try {
        if (-not $guiProc.WaitForExit(25000)) {
            & taskkill.exe /PID $guiProc.Id /T /F | Out-Null
            $lastStage = if (Test-Path -LiteralPath $markerPath -PathType Leaf) { [IO.File]::ReadAllText($markerPath,[Text.Encoding]::UTF8).Trim() } else { 'NO_MARKER' }
            throw ('GUI smoke timed out after 25s in phase ' + $Phase + '; stage=' + $lastStage)
        }
        $guiExit = $guiProc.ExitCode
    } finally { $guiProc.Dispose() }

    $markerValue = ''
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        $markerValue = ([IO.File]::ReadAllText($markerPath,[Text.Encoding]::UTF8)).Trim()
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    }

    if ($guiExit -ne 0 -or $markerValue -ne 'CLOSED') {
        Write-Host ('FAIL: real GUI launcher smoke in phase ' + $Phase + '; exit=' + $guiExit + '; marker=' + $markerValue) -ForegroundColor Red
        exit 1
    }
    Write-Host ('PASS: real Start-GarantStore.cmd -> WinForms GUI startup/close in phase ' + $Phase) -ForegroundColor Green
} finally {
    $env:GS_RELEASE_SMOKE = $oldReleaseSmoke
    $env:GS_GUI_SMOKE = $oldGuiSmoke
    $env:GS_GUI_SMOKE_MARKER = $oldMarker
}

Write-Host ('WINDOWS INTEGRATION GATE PASSED: ' + $Phase) -ForegroundColor Green
exit 0
