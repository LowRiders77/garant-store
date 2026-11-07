# Garant Store - elevated helper for temporary Microsoft Store service changes.
# Windows PowerShell 5.1 compatible. ASCII-only source.
#
# Core runs with the user's normal rights and cannot change services. After the
# user explicitly consents, Core starts this script elevated. The helper:
#   1. restores any baseline left behind by an earlier helper that never finished;
#   2. records the current startup types in an administrators-only file;
#   3. enables (Disabled -> Manual) and starts only the Store services;
#   4. reports the outcome to Core through ReadyFile;
#   5. waits until the Core process exits - normally, by error or by the Stop
#      button - and then restores the original startup types.
# Dot-sourcing this file without -CorePid only defines the functions (for tests).

[CmdletBinding()]
param(
    [int]$CorePid = 0,
    [string]$ReadyFile = '',
    [string]$BaselineFile = '',
    [int]$MaxWaitSeconds = 14400
)

$script:GSHelperServices = @('wuauserv','BITS','InstallService','ClipSVC','AppXSvc')
$script:GSHelperStartServices = @('wuauserv','BITS','InstallService','ClipSVC','AppXSvc')

function Get-GSHelperServiceRows {
    $rows = @()
    foreach ($name in $script:GSHelperServices) {
        try {
            $service = Get-CimInstance Win32_Service -Filter ("Name='" + $name + "'") -ErrorAction Stop
            if ($null -eq $service) { $rows += [pscustomobject]@{ Name=$name; State='Unavailable'; StartMode='' }; continue }
            $rows += [pscustomobject]@{ Name=$name; State=[string]$service.State; StartMode=[string]$service.StartMode }
        } catch {
            $rows += [pscustomobject]@{ Name=$name; State='Unavailable'; StartMode='' }
        }
    }
    return @($rows)
}

function ConvertTo-GSHelperStartupType([string]$StartMode) {
    switch ($StartMode) {
        'Auto' { return 'Automatic' }
        'Manual' { return 'Manual' }
        'Disabled' { return 'Disabled' }
        default { return $null }
    }
}

function Write-GSHelperJson([string]$Path, $Value) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Value -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Restore-GSHelperBaseline {
    # Restores only services whose startup type this helper changed, back to the
    # recorded value. Running state is left alone so unrelated system work is not
    # interrupted. Returns the list of restored services.
    param([Parameter(Mandatory=$true)][string]$BaselineFile)
    $restored = @()
    if (-not (Test-Path -LiteralPath $BaselineFile -PathType Leaf)) { return @() }
    $baseline = Get-Content -LiteralPath $BaselineFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $current = @{}
    foreach ($row in @(Get-GSHelperServiceRows)) { $current[[string]$row.Name] = $row }
    foreach ($entry in @($baseline.Changed)) {
        $name = [string]$entry.Name
        $startupType = ConvertTo-GSHelperStartupType ([string]$entry.StartMode)
        if (-not $startupType -or -not $current.ContainsKey($name)) { continue }
        if ([string]$current[$name].StartMode -eq [string]$entry.StartMode) { continue }
        Set-Service -Name $name -StartupType $startupType -ErrorAction Stop
        $restored += ($name + ':' + [string]$current[$name].StartMode + '->' + [string]$entry.StartMode)
    }
    Remove-Item -LiteralPath $BaselineFile -Force -ErrorAction SilentlyContinue
    return @($restored)
}

function Enable-GSHelperServices {
    # Records the baseline before the first change, so a crash after any
    # mutation can still be undone by the next helper run.
    param([Parameter(Mandatory=$true)][string]$BaselineFile)
    $before = @(Get-GSHelperServiceRows)
    $disabled = @($before | Where-Object { [string]$_.StartMode -eq 'Disabled' })
    $record = [ordered]@{
        Schema = 1
        Created = (Get-Date).ToString('o')
        Changed = @($disabled | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; StartMode=[string]$_.StartMode } })
    }
    if ($disabled.Count -gt 0) { Write-GSHelperJson -Path $BaselineFile -Value $record }

    $changed = @()
    $errors = @()
    foreach ($row in $disabled) {
        try {
            Set-Service -Name ([string]$row.Name) -StartupType Manual -ErrorAction Stop
            $changed += ([string]$row.Name + ':Disabled->Manual')
        } catch {
            $errors += ([string]$row.Name + ': cannot change startup type: ' + $_.Exception.Message)
        }
    }
    foreach ($row in @(Get-GSHelperServiceRows)) {
        if ($script:GSHelperStartServices -notcontains [string]$row.Name) { continue }
        if ([string]$row.State -eq 'Running' -or [string]$row.State -eq 'Unavailable' -or [string]$row.StartMode -eq 'Disabled') { continue }
        try {
            Start-Service -Name ([string]$row.Name) -ErrorAction Stop
            $changed += ([string]$row.Name + ':Started')
        } catch {
            # ClipSVC and AppXSvc are trigger-start services and may refuse a manual start.
            $errors += ([string]$row.Name + ': cannot start: ' + $_.Exception.Message)
        }
    }
    return [pscustomobject]@{ Changed=@($changed); Errors=@($errors); BaselineRecorded=($disabled.Count -gt 0) }
}

function Wait-GSHelperCoreExit {
    param([int]$ProcessId, [int]$MaxWaitSeconds = 14400)
    $process = $null
    try { $process = [Diagnostics.Process]::GetProcessById($ProcessId) } catch { return $true }
    try { return $process.WaitForExit([Math]::Max(1,$MaxWaitSeconds) * 1000) } finally { $process.Dispose() }
}

if ($CorePid -gt 0) {
    $ErrorActionPreference = 'Stop'
    $outcome = [ordered]@{ Ok=$false; Changed=@(); Errors=@(); PreviouslyRestored=@(); Error='' }
    try {
        if ([string]::IsNullOrWhiteSpace($BaselineFile)) {
            . (Join-Path $PSScriptRoot 'DriverEngine\SecureRoot.ps1')
            $secureRoot = Initialize-GSSecureDataRoot -Path (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GarantStoreEngine')
            $BaselineFile = Join-Path $secureRoot 'store-service-baseline.json'
        }
        # A baseline left by a helper that was killed (power loss, reboot) is undone first.
        $outcome.PreviouslyRestored = @(Restore-GSHelperBaseline -BaselineFile $BaselineFile)
        $enable = Enable-GSHelperServices -BaselineFile $BaselineFile
        $outcome.Changed = @($enable.Changed)
        $outcome.Errors = @($enable.Errors)
        $outcome.Ok = $true
    } catch {
        $outcome.Error = $_.Exception.Message
    }
    Write-GSHelperJson -Path $ReadyFile -Value $outcome
    if ($outcome.Ok) {
        [void](Wait-GSHelperCoreExit -ProcessId $CorePid -MaxWaitSeconds $MaxWaitSeconds)
        try { [void](Restore-GSHelperBaseline -BaselineFile $BaselineFile) } catch {}
    }
    exit $(if ($outcome.Ok) { 0 } else { 1 })
}
