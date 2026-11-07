# Garant Store v0.8 DEV - Preflight SelfTest
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path

$criticalFiles = @(
    'GarantStore.GUI.ps1',
    'GarantStore.Core.ps1',
    'GarantStore.Common.ps1',
    'GarantStore.Progress.ps1',
    'GarantStore.Parser.ps1',
    'GarantStore.Winget.ps1',
    'GarantStore.State.ps1',
    'GarantStore.Deployment.ps1',
    'GarantStore.Store.ps1',
    'GarantStore.Diagnostics.ps1',
    'RunTests.ps1',
    'ReleaseGate.ps1',
    'Build-VerifiedRelease.ps1',
    'Build-VerifiedRelease.cmd',
    'Tests\Test-StrictModeHazards.ps1',
    'Tests\Test-CmdMetacharacters.ps1',
    'Tests\Test-WindowsIntegration.ps1'
)

$sourceFiles = @(
    'GarantStore.GUI.ps1',
    'GarantStore.Core.ps1',
    'GarantStore.Common.ps1',
    'GarantStore.Progress.ps1',
    'GarantStore.Parser.ps1',
    'GarantStore.Winget.ps1',
    'GarantStore.State.ps1',
    'GarantStore.Deployment.ps1',
    'GarantStore.Store.ps1',
    'GarantStore.Diagnostics.ps1',
    'RunTests.ps1',
    'SelfTest.ps1',
    'ReleaseGate.ps1',
    'Build-VerifiedRelease.ps1',
    'Tests\Test-StrictModeHazards.ps1',
    'Tests\Test-CmdMetacharacters.ps1',
    'Tests\Test-WindowsIntegration.ps1'
)

$forbiddenAutomaticVariables = @(
    'input','args','error','host','home','pid','psitem','this','matches'
)

foreach ($cmdName in @('Start-GarantStore.cmd','Build-VerifiedRelease.cmd')) {
    $cmdPath = Join-Path $base $cmdName
    if (-not (Test-Path -LiteralPath $cmdPath -PathType Leaf)) {
        Write-Host ('CRITICAL MISSING FILE: ' + $cmdName) -ForegroundColor Red
        exit 1
    }
    foreach ($cmdByte in [IO.File]::ReadAllBytes($cmdPath)) {
        if ($cmdByte -gt 127) {
            Write-Host ('CRITICAL NON-ASCII SOURCE BYTE: ' + $cmdName) -ForegroundColor Red
            exit 1
        }
    }
}

$critical = $false
$warnings = New-Object 'System.Collections.Generic.List[string]'

foreach ($relative in $criticalFiles) {
    $path = Join-Path $base $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host ('CRITICAL MISSING FILE: ' + $relative) -ForegroundColor Red
        $critical = $true
    }
}

if ($critical) {
    Write-Host 'SELF-TEST FAILED: package is incomplete.' -ForegroundColor Red
    exit 1
}

foreach ($relative in $sourceFiles) {
    $path = Join-Path $base $relative
    $bytes = [IO.File]::ReadAllBytes($path)

    foreach ($byteValue in $bytes) {
        if ($byteValue -gt 127) {
            Write-Host ('CRITICAL NON-ASCII SOURCE BYTE: ' + $relative) -ForegroundColor Red
            $critical = $true
            break
        }
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)

    if (@($parseErrors).Count -gt 0) {
        Write-Host ('CRITICAL SYNTAX ERROR: ' + $relative) -ForegroundColor Red
        foreach ($parseError in $parseErrors) {
            Write-Host ('  ' + $parseError.ToString()) -ForegroundColor Red
        }
        $critical = $true
        continue
    }

    $variables = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.VariableExpressionAst]
    },$true)

    foreach ($variableNode in $variables) {
        $name = $variableNode.VariablePath.UserPath.ToLowerInvariant()
        if ($forbiddenAutomaticVariables -contains $name) {
            Write-Host ('CRITICAL FORBIDDEN AUTOMATIC VARIABLE $' + $name + ' in ' + $relative) -ForegroundColor Red
            $critical = $true
        }
    }

    Write-Host ('PARSE/ASCII/AUTOVAR OK: ' + $relative) -ForegroundColor Green
}

if ($critical) {
    Write-Host 'SELF-TEST FAILED: critical source validation error.' -ForegroundColor Red
    exit 1
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'RunTests.ps1') -Mode SelfTest
if ($LASTEXITCODE -ne 0) {
    Write-Host 'SELF-TEST FAILED: regression suite failed.' -ForegroundColor Red
    exit 1
}

# Environment checks are warnings, never a reason to block the GUI.
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    [void]$warnings.Add('WinGet is not currently available. Recovery remains accessible from the GUI.')
}

foreach ($warning in $warnings) {
    Write-Host ('WARNING: ' + $warning) -ForegroundColor Yellow
}

Write-Host 'SELF-TEST PASSED.' -ForegroundColor Green
exit 0
