# Garant Store v0.8 DEV - Performance and Progress
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

function Get-GSDeliveryOptimizationSnapshot {
    $cmd = Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return @() }

    try {
        return @(Get-DeliveryOptimizationStatus -ErrorAction Stop -WarningAction SilentlyContinue)
    } catch {
        return @()
    }
}

function Get-GSDeliveryOptimizationConfig {
    $result = [ordered]@{
        Available = $false
        DownloadMode = $null
        ForegroundBandwidthPercent = $null
        BackgroundBandwidthPercent = $null
        ActiveJobs = 0
    }

    if ($null -eq (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue)) {
        return [pscustomobject]$result
    }

    $result.Available = $true

    try {
        if (Get-Command Get-DODownloadMode -ErrorAction SilentlyContinue) {
            $result.DownloadMode = [string](Get-DODownloadMode -ErrorAction Stop -WarningAction SilentlyContinue)
        }
    } catch {}

    try {
        if (Get-Command Get-DOPercentageMaxForegroundBandwidth -ErrorAction SilentlyContinue) {
            $result.ForegroundBandwidthPercent = Get-DOPercentageMaxForegroundBandwidth -ErrorAction Stop -WarningAction SilentlyContinue
        }
    } catch {}

    try {
        if (Get-Command Get-DOPercentageMaxBackgroundBandwidth -ErrorAction SilentlyContinue) {
            $result.BackgroundBandwidthPercent = Get-DOPercentageMaxBackgroundBandwidth -ErrorAction Stop -WarningAction SilentlyContinue
        }
    } catch {}

    try {
        $result.ActiveJobs = @(Get-GSDeliveryOptimizationSnapshot).Count
    } catch {}

    return [pscustomobject]$result
}

function Get-GSPropertyUInt64 {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            try {
                $value = $Object.$name
                if ($null -ne $value) {
                    return [UInt64]$value
                }
            } catch {}
        }
    }

    return [UInt64]0
}

function Get-GSPropertyString {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            try {
                return [string]$Object.$name
            } catch {}
        }
    }

    return ''
}

function Get-GSWinGetNativeLogDirectory {
    return (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir')
}

function Get-GSNativeLogNames {
    $dir = Get-GSWinGetNativeLogDirectory
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }

    try {
        return @(Get-ChildItem -LiteralPath $dir -Filter 'WinGet-*.log' -File -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.FullName })
    } catch {
        return @()
    }
}

function Read-GSTailText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$MaxBytes = 65536
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    try {
        $stream = [IO.File]::Open($Path,'Open','Read','ReadWrite')
        try {
            $length = $stream.Length
            $start = [Math]::Max(0,$length - $MaxBytes)
            [void]$stream.Seek($start,[IO.SeekOrigin]::Begin)
            $count = [int]($length - $start)
            $buffer = New-Object byte[] $count
            $read = $stream.Read($buffer,0,$count)
            if ($read -le 0) { return '' }
            return [Text.Encoding]::UTF8.GetString($buffer,0,$read)
        } finally {
            $stream.Dispose()
        }
    } catch {
        return ''
    }
}

function Start-GSStoreTelemetry {
    $baselineJobs = @{}
    foreach ($job in @(Get-GSDeliveryOptimizationSnapshot)) {
        $id = Get-GSPropertyString -Object $job -Names @('FileId','FileID')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $baselineJobs[$id] = $true
        }
    }

    $baselineLogs = @{}
    foreach ($path in @(Get-GSNativeLogNames)) {
        $baselineLogs[$path] = $true
    }

    $config = Get-GSDeliveryOptimizationConfig
    Write-GSLog -Message ('Delivery Optimization: available=' + $config.Available + '; mode=' + $config.DownloadMode + '; foregroundLimit=' + $config.ForegroundBandwidthPercent + '; backgroundLimit=' + $config.BackgroundBandwidthPercent) -Level 'INFO'

    return @{
        Started = Get-Date
        BaselineJobs = $baselineJobs
        BaselineLogs = $baselineLogs
        SeenJobs = @{}
        LastBytes = [UInt64]0
        LastSample = Get-Date
        LastSpeed = [double]0
        NativeLog = ''
        NativeStage = 'StoreHandshake'
        LastTelemetryWrite = [datetime]::MinValue
    }
}

function Update-GSStoreTelemetry {
    param([Parameter(Mandatory=$true)][hashtable]$State)

    $now = Get-Date
    if (($now - [datetime]$State.LastTelemetryWrite).TotalMilliseconds -lt 700) {
        return
    }
    $State.LastTelemetryWrite = $now

    if ([string]::IsNullOrWhiteSpace([string]$State.NativeLog)) {
        foreach ($path in @(Get-GSNativeLogNames)) {
            if (-not $State.BaselineLogs.ContainsKey($path)) {
                $State.NativeLog = $path
                break
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$State.NativeLog)) {
        $tail = Read-GSTailText -Path ([string]$State.NativeLog)
        if ($tail -match '(?i)Started MSStore package execution') {
            $State.NativeStage = 'StoreExecution'
        } elseif ($tail -match '(?i)Getting entitlement') {
            $State.NativeStage = 'Authorizing'
        } elseif ($tail -match '(?i)Found one app|Manifest fields') {
            $State.NativeStage = 'ResolvingPackage'
        }
    }

    $currentJobs = @(Get-GSDeliveryOptimizationSnapshot)
    $newJobs = @()

    foreach ($job in $currentJobs) {
        $id = Get-GSPropertyString -Object $job -Names @('FileId','FileID')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        if (-not $State.BaselineJobs.ContainsKey($id)) {
            $newJobs += $job
            $State.SeenJobs[$id] = $true
        } elseif ($State.SeenJobs.ContainsKey($id)) {
            $newJobs += $job
        }
    }

    $bytesDownloaded = [UInt64]0
    $bytesTotal = [UInt64]0
    $hasDownloading = $false
    $hasCompleted = $false

    foreach ($job in $newJobs) {
        $status = Get-GSPropertyString -Object $job -Names @('Status')
        $downloaded = Get-GSPropertyUInt64 -Object $job -Names @('TotalBytesDownloaded','BytesTransferred')
        $total = Get-GSPropertyUInt64 -Object $job -Names @('FileSize','BytesTotal')

        $bytesDownloaded += $downloaded
        $bytesTotal += $total

        if ($status -match '(?i)Downloading') { $hasDownloading = $true }
        if ($status -match '(?i)Complete|Caching') { $hasCompleted = $true }
    }

    $sampleSeconds = [Math]::Max(0.1,($now - [datetime]$State.LastSample).TotalSeconds)
    if ($bytesDownloaded -ge [UInt64]$State.LastBytes) {
        $instantSpeed = ([double]($bytesDownloaded - [UInt64]$State.LastBytes)) / $sampleSeconds
        if ($instantSpeed -gt 0) {
            if ([double]$State.LastSpeed -gt 0) {
                $State.LastSpeed = ([double]$State.LastSpeed * 0.65) + ($instantSpeed * 0.35)
            } else {
                $State.LastSpeed = $instantSpeed
            }
        }
    }

    $State.LastBytes = $bytesDownloaded
    $State.LastSample = $now

    if ($hasDownloading -or ($bytesDownloaded -gt 0 -and $bytesTotal -gt 0 -and $bytesDownloaded -lt $bytesTotal)) {
        $percent = $null
        if ($bytesTotal -gt 0) {
            $percent = [Math]::Min(100,[Math]::Max(0,([double]$bytesDownloaded / [double]$bytesTotal) * 100))
        }

        Write-GSProgress `
            -Stage 'Downloading' `
            -Percent $percent `
            -Indeterminate ($null -eq $percent) `
            -BytesDownloaded $bytesDownloaded `
            -BytesTotal $bytesTotal `
            -SpeedBytesPerSecond ([double]$State.LastSpeed) `
            -Detail 'DeliveryOptimization'
        return
    }

    if ($hasCompleted -or ($State.SeenJobs.Count -gt 0 -and $bytesDownloaded -gt 0)) {
        Write-GSProgress -Stage 'Installing' -Indeterminate $true -BytesDownloaded $bytesDownloaded -BytesTotal $bytesTotal -SpeedBytesPerSecond ([double]$State.LastSpeed) -Detail 'StoreDeployment'
        return
    }

    switch ([string]$State.NativeStage) {
        'ResolvingPackage' {
            Write-GSProgress -Stage 'ResolvingPackage' -Indeterminate $true -Detail 'WinGetStoreManifest'
        }
        'Authorizing' {
            Write-GSProgress -Stage 'Authorizing' -Indeterminate $true -Detail 'StoreEntitlement'
        }
        'StoreExecution' {
            Write-GSProgress -Stage 'StoreExecution' -Indeterminate $true -Detail 'MicrosoftStoreBroker'
        }
        default {
            Write-GSProgress -Stage 'StoreHandshake' -Indeterminate $true -Detail 'MicrosoftStore'
        }
    }
}

function Finish-GSStoreTelemetry {
    param([hashtable]$State)

    Write-GSProgress -Stage 'Installing' -Indeterminate $true -Detail 'StoreProcessCompleted'

    $elapsed = [Math]::Max(0,((Get-Date) - [datetime]$State.Started).TotalSeconds)
    $summary = [pscustomobject]@{
        ElapsedSeconds = [Math]::Round($elapsed,2)
        BytesDownloaded = [UInt64]$State.LastBytes
        LastSpeedBytesPerSecond = [Math]::Round([double]$State.LastSpeed,2)
        DeliveryOptimizationJobsSeen = [int]$State.SeenJobs.Count
        LastNativeStage = [string]$State.NativeStage
        NativeLog = [string]$State.NativeLog
    }

    Write-GSLog -Message (
        'Store telemetry summary: elapsed=' + $summary.ElapsedSeconds +
        's; bytes=' + $summary.BytesDownloaded +
        '; speed=' + $summary.LastSpeedBytesPerSecond +
        '; DO jobs=' + $summary.DeliveryOptimizationJobsSeen +
        '; stage=' + $summary.LastNativeStage
    ) -Level 'INFO'

    return $summary
}
