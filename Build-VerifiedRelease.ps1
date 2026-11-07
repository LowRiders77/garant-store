# Garant Store - Verified Release Builder
# This script is the ONLY supported path for creating a publishable release ZIP.

[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsPath = Join-Path $base 'CI\PackageTools.ps1'
if (-not (Test-Path -LiteralPath $toolsPath -PathType Leaf)) {
    throw 'Release builder requires the source repository (CI/PackageTools.ps1), not an extracted runtime archive.'
}
. $toolsPath
if ($env:OS -ne 'Windows_NT') {
    Write-Host 'BUILD REFUSED: a verified release must be built on real Windows.' -ForegroundColor Red
    exit 1
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw 'Windows PowerShell 5.1 executable not found.'
}

$version = ([IO.File]::ReadAllText((Join-Path $base 'VERSION.txt'),[Text.Encoding]::ASCII)).Trim()
if ([string]::IsNullOrWhiteSpace($version)) { throw 'VERSION.txt is empty.' }

if ($version -match '(?i)-dev$') {
    Write-Host ('BUILD REFUSED: ' + $version + ' is the active development branch, not a public release milestone.') -ForegroundColor Yellow
    Write-Host 'Run SelfTest.ps1 / Start-GarantStore.cmd for development validation. Promote VERSION.txt only when the milestone has meaningful user-visible changes.' -ForegroundColor Yellow
    exit 2
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $base 'Releases'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$workRoot = Join-Path $env:TEMP ('GarantStore-release-' + [Guid]::NewGuid().ToString('N'))
$stageParent = Join-Path $workRoot 'stage'
$stageRoot = Join-Path $stageParent ('GarantStore-v' + $version)
$extractParent = Join-Path $workRoot 'extract'
$candidateZip = Join-Path $workRoot ('GarantStore-v' + $version + '-candidate.zip')
$finalZip = Join-Path $OutputDirectory ('GarantStore-v' + $version + '-VERIFIED.zip')
$reportPath = Join-Path $OutputDirectory ('GarantStore-v' + $version + '-VERIFIED.release-report.json')
$gateLogPath = Join-Path $OutputDirectory ('GarantStore-v' + $version + '-release-gate.log')
$transcriptStarted = $false

try {
    try {
        Start-Transcript -Path $gateLogPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Host ('WARNING: could not start transcript: ' + $_.Exception.Message) -ForegroundColor Yellow
    }

    Write-Host '=== PHASE 1: source tree gate ===' -ForegroundColor Cyan
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'ReleaseGate.ps1') -Phase Source
    if ($LASTEXITCODE -ne 0) { throw 'Source-tree release gate failed.' }

    # Explicit allowlist: never ship .git, CI workflows, logs, diagnostics or secrets.
    Copy-GSPackagePayload -SourceRoot $base -DestinationRoot $stageRoot

    if (Test-Path -LiteralPath $candidateZip) { Remove-Item -LiteralPath $candidateZip -Force }
    Compress-Archive -LiteralPath $stageRoot -DestinationPath $candidateZip -CompressionLevel Optimal

    Write-Host '=== PHASE 2: extract exact candidate ZIP ===' -ForegroundColor Cyan
    $extractedRoot = Expand-GSVerifiedCandidate -ArchivePath $candidateZip -DestinationParent $extractParent -Version $version

    Write-Host '=== PHASE 3: full gate from extracted candidate ===' -ForegroundColor Cyan
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $extractedRoot 'ReleaseGate.ps1') -Phase Archive
    if ($LASTEXITCODE -ne 0) { throw 'Extracted-archive release gate failed.' }

    Copy-Item -LiteralPath $candidateZip -Destination $finalZip -Force
    $sha = (Get-FileHash -LiteralPath $finalZip -Algorithm SHA256).Hash.ToLowerInvariant()

    $report = [ordered]@{
        schema = 1
        version = $version
        verified = $true
        verifiedAt = (Get-Date -Format o)
        machine = $env:COMPUTERNAME
        userInteractive = [Environment]::UserInteractive
        windowsPowerShell = ((@(& $windowsPowerShell -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') -join "`n").Trim())
        sourceGate = 'passed'
        extractedArchiveGate = 'passed'
        finalArchive = [IO.Path]::GetFileName($finalZip)
        sha256 = $sha
    }
    $json = ConvertTo-Json -InputObject $report -Depth 5
    [IO.File]::WriteAllText($reportPath,$json,(New-Object Text.UTF8Encoding($false)))

    Write-Host '=== VERIFIED RELEASE CREATED ===' -ForegroundColor Green
    Write-Host ('ZIP: ' + $finalZip) -ForegroundColor Green
    Write-Host ('SHA256: ' + $sha) -ForegroundColor Green
    Write-Host ('REPORT: ' + $reportPath) -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('RELEASE BUILD FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
