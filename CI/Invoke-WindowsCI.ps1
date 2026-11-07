# Garant Store - automated Windows CI. Works on v0.8 DEV without publishing anything.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$winPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ($env:OS -ne 'Windows_NT' -or -not (Test-Path -LiteralPath $winPS -PathType Leaf)) {
    throw 'A real Windows runner with Windows PowerShell 5.1 is required.'
}
. (Join-Path $PSScriptRoot 'PackageTools.ps1')

$version = ([IO.File]::ReadAllText((Join-Path $root 'VERSION.txt'))).Trim()
$work = Join-Path $env:TEMP ('GS-CI-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path (Join-Path $work 'stage') ('GarantStore-v' + $version)
$archive = Join-Path $work ('GarantStore-v' + $version + '-candidate.zip')
$extractParent = Join-Path $work 'extract'
$output = Join-Path $root 'CI-output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$log = Join-Path $output 'windows-ci.log'
$started = $false
$phase = 'initialization'

try {
    Start-Transcript -LiteralPath $log -Force | Out-Null
    $started = $true

    $phase = 'source-gate'
    Write-Host '=== CI 1/3: source Windows release gate ===' -ForegroundColor Cyan
    & $winPS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'ReleaseGate.ps1') -Phase Source
    if ($LASTEXITCODE -ne 0) { throw 'Windows source gate failed.' }

    $phase = 'package'
    Write-Host '=== CI 2/3: create real package, SHA256 manifest, ZIP ===' -ForegroundColor Cyan
    Copy-GSPackagePayload -SourceRoot $root -DestinationRoot $stage
    Compress-Archive -LiteralPath $stage -DestinationPath $archive -CompressionLevel Optimal

    $phase = 'archive-gate'
    Write-Host '=== CI 3/3: extract exact ZIP, SHA256 check, Windows release gate ===' -ForegroundColor Cyan
    $extractedRoot = Expand-GSVerifiedCandidate -ArchivePath $archive -DestinationParent $extractParent -Version $version
    & $winPS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $extractedRoot 'ReleaseGate.ps1') -Phase Archive
    if ($LASTEXITCODE -ne 0) { throw 'Extracted-archive gate failed.' }

    $phase = 'wpf-preview-gate'
    Write-Host '=== Additional Windows gate: Garant Store Next WPF + Setup.exe ===' -ForegroundColor Cyan
    & $winPS -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'WPF\\CI\\Invoke-WindowsGate.ps1') -CompileInstaller
    if ($LASTEXITCODE -ne 0) { throw 'Garant Store Next WPF/installer gate failed.' }

    $wpfSetup = Join-Path $root 'WPF\\dist\\GarantStore-Setup.exe'
    if (-not (Test-Path -LiteralPath $wpfSetup -PathType Leaf)) { throw 'WPF setup.exe was not produced.' }
    $previewSetup = Join-Path $output 'GarantStore-Setup.exe'
    Copy-Item -LiteralPath $wpfSetup -Destination $previewSetup -Force
    $wpfEvidence = Join-Path $output 'WPF-evidence'
    New-Item -ItemType Directory -Force -Path $wpfEvidence | Out-Null
    $wpfEvidenceSource = Join-Path $root 'WPF\\CI-output'
    if (Test-Path -LiteralPath $wpfEvidenceSource) {
        Copy-Item -Path (Join-Path $wpfEvidenceSource '*') -Destination $wpfEvidence -Recurse -Force
    }

    $report = [ordered]@{
        schema = 1
        version = $version
        status = 'ci-passed-no-release'
        windows = [Environment]::OSVersion.VersionString
        windowsPowerShell = '5.1 Desktop'
        sourceGate = 'passed'
        archiveGate = 'passed'
        wpfPreviewGate = 'passed'
        setupSha256 = (Get-FileHash -LiteralPath $previewSetup -Algorithm SHA256).Hash.ToLowerInvariant()
        sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'windows-ci-report.json') -Encoding UTF8
    Write-Host 'WINDOWS CI PASSED; NO RELEASE WAS CREATED.' -ForegroundColor Green
} catch {
    $report = [ordered]@{schema=1;version=$version;status='ci-failed';phase=$phase;error=$_.Exception.Message}
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'windows-ci-report.json') -Encoding UTF8
    Write-Host ('WINDOWS CI FAILED during ' + $phase + ': ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($started) { try { Stop-Transcript | Out-Null } catch {} }
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
