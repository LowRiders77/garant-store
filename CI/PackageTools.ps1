# Garant Store - single package contract for CI and verified release builder.
# Windows PowerShell 5.1, ASCII only. Do not include .git, secrets, cache, or diagnostics.
Set-StrictMode -Version Latest

function Copy-GSPackagePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )

    $required = @(
        'GarantStore.GUI.ps1', 'GarantStore.Core.ps1', 'GarantStore.Common.ps1',
        'GarantStore.Progress.ps1', 'GarantStore.Parser.ps1', 'GarantStore.Winget.ps1',
        'GarantStore.State.ps1', 'GarantStore.Deployment.ps1', 'GarantStore.Store.ps1',
        'GarantStore.Diagnostics.ps1', 'RunTests.ps1', 'SelfTest.ps1',
        'ReleaseGate.ps1', 'Build-VerifiedRelease.ps1', 'Build-VerifiedRelease.cmd',
        'Start-GarantStore.cmd', 'VERSION.txt', 'README.md', 'CHANGELOG.md',
        'RELEASE_POLICY.md', 'TEST_PLAN.txt', 'TEST_REPORT.md'
    )

    $optional = @('PRESENTATION_DESIGN.md')
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

    foreach ($name in $required) {
        $source = Join-Path $SourceRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw ('Missing required package file: ' + $name)
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $name) -Force
    }
    foreach ($name in $optional) {
        $source = Join-Path $SourceRoot $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $name) -Force
        }
    }

    $testsSource = Join-Path $SourceRoot 'Tests'
    if (-not (Test-Path -LiteralPath $testsSource -PathType Container)) {
        throw 'Missing required Tests directory.'
    }
    Copy-Item -LiteralPath $testsSource -Destination (Join-Path $DestinationRoot 'Tests') -Recurse -Force

    # Do not copy CI workflows or helper scripts into the user-facing package.
    # Build-VerifiedRelease.ps1 is retained as an entrypoint but requires the
    # separate source-repository CI helpers to build a new verified release.
    Write-GSPackageManifest -PackageRoot $DestinationRoot
}

function Get-GSPackageFileList {
    param([Parameter(Mandatory=$true)][string]$PackageRoot)
    return @(
        Get-ChildItem -LiteralPath $PackageRoot -File -Recurse -Force |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName
    )
}

function Write-GSPackageManifest {
    param([Parameter(Mandatory=$true)][string]$PackageRoot)
    $prefix = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char[]]@([char]92,[char]47)) + [IO.Path]::DirectorySeparatorChar
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in @(Get-GSPackageFileList -PackageRoot $PackageRoot)) {
        $rel = $file.FullName.Substring($prefix.Length).Replace('\','/')
        $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$lines.Add(($sha + '  ' + $rel))
    }
    [IO.File]::WriteAllLines(
        (Join-Path $PackageRoot 'SHA256SUMS.txt'),
        [string[]]$lines.ToArray(),
        (New-Object Text.UTF8Encoding($false))
    )
}

function Test-GSPackageManifest {
    param([Parameter(Mandatory=$true)][string]$PackageRoot)
    $manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw 'Package SHA256SUMS.txt missing.'
    }
    $prefix = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char[]]@([char]92,[char]47)) + [IO.Path]::DirectorySeparatorChar
    $found = @{}
    foreach ($line in [IO.File]::ReadAllLines($manifest)) {
        $lineMatch = [regex]::Match([string]$line,'^([a-fA-F0-9]{64})  ([^\r\n]+)$')
        if (-not $lineMatch.Success) {
            throw ('Malformed package manifest line: ' + $line)
        }
        $sha = $lineMatch.Groups[1].Value.ToLowerInvariant()
        $rel = $lineMatch.Groups[2].Value
        if ($rel.StartsWith('/') -or $rel.StartsWith('\') -or $rel.Contains('..') -or $rel.Contains(':')) {
            throw ('Unsafe package manifest path: ' + $rel)
        }
        if ($found.ContainsKey($rel)) { throw ('Duplicate package manifest entry: ' + $rel) }
        $target = Join-Path $PackageRoot ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw ('File referenced in manifest is missing: ' + $rel)
        }
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $sha) { throw ('SHA256 mismatch in archive: ' + $rel) }
        $found[$rel] = $true
    }
    foreach ($file in @(Get-GSPackageFileList -PackageRoot $PackageRoot)) {
        $rel = $file.FullName.Substring($prefix.Length).Replace('\','/')
        if (-not $found.ContainsKey($rel)) { throw ('Unlisted file in package: ' + $rel) }
    }
    foreach ($excluded in @('.git','.github','CI','Releases','CI-output')) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $excluded)) {
            throw ('Developer-only directory leaked into package: ' + $excluded)
        }
    }
    Write-Host ('PASS: exact package manifest, ' + $found.Count + ' files') -ForegroundColor Green
}

function Expand-GSVerifiedCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$DestinationParent,
        [Parameter(Mandatory=$true)][string]$Version
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $expected = 'GarantStore-v' + $Version + '/'
        $sawManifest = $false
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if (-not $name.StartsWith($expected,[StringComparison]::Ordinal) -or
                $name.Contains('../') -or $name.Contains('/./') -or
                $name.StartsWith('/') -or $name.Contains(':')) {
                throw ('Unsafe or unexpected ZIP entry: ' + $name)
            }
            if ($name -eq ($expected + 'SHA256SUMS.txt')) { $sawManifest = $true }
        }
        if (-not $sawManifest) { throw 'ZIP manifest entry missing.' }
    } finally {
        $zip.Dispose()
    }

    New-Item -ItemType Directory -Force -Path $DestinationParent | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationParent -Force
    $root = Join-Path $DestinationParent ('GarantStore-v' + $Version)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'ZIP extraction root missing.' }
    Test-GSPackageManifest -PackageRoot $root
    return $root
}
