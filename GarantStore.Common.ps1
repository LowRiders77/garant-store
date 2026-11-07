# Garant Store v0.8 DEV - Common
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

$script:GSContext = $null


function Get-GSCacheRoot {
    $root = Join-Path $env:LOCALAPPDATA 'GarantStore\Cache'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Get-GSCacheKey {
    param([Parameter(Mandatory=$true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-GSCachePath {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9._-]{1,160}$') {
        throw 'Invalid cache file name.'
    }
    return (Join-Path (Get-GSCacheRoot) $Name)
}

function Read-GSCacheJson {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$MaxAgeSeconds = 60
    )

    $path = Get-GSCachePath -Name $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $age = ((Get-Date) - $item.LastWriteTime).TotalSeconds
        if ($MaxAgeSeconds -ge 0 -and $age -gt $MaxAgeSeconds) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            return $null
        }

        $text = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text | ConvertFrom-Json)
    } catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Write-GSCacheJson {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value
    )

    $path = Get-GSCachePath -Name $Name
    $temp = $path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 12
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Clear-GSCache {
    param([ValidateSet('State','Search','All')][string]$Scope = 'All')

    $root = Get-GSCacheRoot
    $patterns = switch ($Scope) {
        'State' { @('inventory.json','store-snapshot.json') }
        'Search' { @('search-*.json') }
        default { @('*.json') }
    }

    foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $root -Filter $pattern -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-GSCacheStats {
    $root = Get-GSCacheRoot
    $files = @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue)
    $total = 0L
    foreach ($file in $files) { $total += [int64]$file.Length }

    return [pscustomobject]@{
        Directory = $root
        FileCount = $files.Count
        Bytes = $total
        InventoryPresent = (Test-Path -LiteralPath (Join-Path $root 'inventory.json') -PathType Leaf)
        StoreSnapshotPresent = (Test-Path -LiteralPath (Join-Path $root 'store-snapshot.json') -PathType Leaf)
        SearchEntries = @($files | Where-Object { $_.Name -like 'search-*.json' }).Count
    }
}

function New-GSOperationId {
    return ('OP-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
}

function Initialize-GSContext {
    param(
        [Parameter(Mandatory=$true)][string]$OutputFile,
        [Parameter(Mandatory=$true)][string]$Action,
        [string]$OperationId = '',
        [string]$ProgressFile = ''
    )

    if ([string]::IsNullOrWhiteSpace($OperationId)) {
        $OperationId = New-GSOperationId
    }

    $root = Join-Path $env:LOCALAPPDATA 'GarantStore'
    $logs = Join-Path $root 'Logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null

    $sessionLog = Join-Path $logs ('session-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$OperationId.Substring([Math]::Max(0,$OperationId.Length - 8)))
    $jsonLog = [IO.Path]::ChangeExtension($sessionLog,'.jsonl')

    $script:GSContext = [ordered]@{
        Root = $root
        Logs = $logs
        OutputFile = $OutputFile
        SessionLog = $sessionLog
        JsonLog = $jsonLog
        OperationId = $OperationId
        Action = $Action
        Started = (Get-Date)
        ProgressFile = $ProgressFile
    }

    [IO.File]::WriteAllText($OutputFile,'',(New-Object Text.UTF8Encoding($false)))
    if (-not [string]::IsNullOrWhiteSpace($ProgressFile)) {
        [IO.File]::WriteAllText($ProgressFile,'',(New-Object Text.UTF8Encoding($false)))
    }
    Write-GSLog -Message ('Operation started. Action=' + $Action) -Level 'INFO'
}

function Get-GSContext {
    return $script:GSContext
}

function Write-GSLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL','WINGET','WINGET-ERR','DEPLOY')][string]$Level = 'INFO',
        [hashtable]$Data = $null
    )

    $timestamp = Get-Date -Format o
    $operationId = ''
    $sessionLog = $null
    $jsonLog = $null
    $outputFile = $null

    if ($script:GSContext) {
        $operationId = [string]$script:GSContext.OperationId
        $sessionLog = [string]$script:GSContext.SessionLog
        $jsonLog = [string]$script:GSContext.JsonLog
        $outputFile = [string]$script:GSContext.OutputFile
    }

    $prefix = if ([string]::IsNullOrWhiteSpace($operationId)) { '' } else { '[' + $operationId + '] ' }
    $line = '{0} [{1}] {2}{3}' -f $timestamp,$Level,$prefix,$Message
    $utf8 = New-Object Text.UTF8Encoding($false)

    if ($sessionLog) {
        [IO.File]::AppendAllText($sessionLog,$line + [Environment]::NewLine,$utf8)
    }
    if ($outputFile) {
        [IO.File]::AppendAllText($outputFile,$line + [Environment]::NewLine,$utf8)
    }

    if ($jsonLog) {
        $record = [ordered]@{
            timestamp = $timestamp
            level = $Level
            operationId = $operationId
            message = $Message
            data = $Data
        }
        $json = ConvertTo-Json -InputObject $record -Depth 8 -Compress
        [IO.File]::AppendAllText($jsonLog,$json + [Environment]::NewLine,$utf8)
    }
}

function Write-GSProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [object]$Percent = $null,
        [bool]$Indeterminate = $true,
        [UInt64]$BytesDownloaded = 0,
        [UInt64]$BytesTotal = 0,
        [double]$SpeedBytesPerSecond = 0,
        [string]$Detail = ''
    )

    $ctx = Get-GSContext
    if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.ProgressFile)) {
        return
    }

    $elapsed = [Math]::Max(0,((Get-Date) - [datetime]$ctx.Started).TotalSeconds)

    $record = [ordered]@{
        Schema = 1
        Timestamp = (Get-Date -Format o)
        OperationId = [string]$ctx.OperationId
        Action = [string]$ctx.Action
        Stage = $Stage
        Percent = $Percent
        Indeterminate = $Indeterminate
        BytesDownloaded = $BytesDownloaded
        BytesTotal = $BytesTotal
        SpeedBytesPerSecond = [Math]::Max(0,$SpeedBytesPerSecond)
        ElapsedSeconds = [Math]::Round($elapsed,1)
        Detail = $Detail
    }

    try {
        $json = ConvertTo-Json -InputObject $record -Depth 6 -Compress
        [IO.File]::WriteAllText([string]$ctx.ProgressFile,$json,(New-Object Text.UTF8Encoding($false)))
    } catch {
        # Telemetry must never break the package operation.
    }
}

function Complete-GSProgress {
    Write-GSProgress -Stage 'Completed' -Percent 100 -Indeterminate $false
}

function New-GSResult {
    param(
        [bool]$Success,
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$ErrorCode = '',
        [string]$Message = '',
        [string]$TechnicalMessage = '',
        [string]$PackageId = '',
        [string]$Source = '',
        [string]$OldVersion = '',
        [string]$NewVersion = '',
        [bool]$RequiresRestart = $false,
        [object]$Data = $null
    )

    $ctx = Get-GSContext
    return [pscustomobject][ordered]@{
        Schema = 1
        Success = $Success
        Status = $Status
        ErrorCode = $ErrorCode
        Message = $Message
        TechnicalMessage = $TechnicalMessage
        OperationId = if ($ctx) { [string]$ctx.OperationId } else { '' }
        Action = if ($ctx) { [string]$ctx.Action } else { '' }
        PackageId = $PackageId
        Source = $Source
        OldVersion = $OldVersion
        NewVersion = $NewVersion
        RequiresRestart = $RequiresRestart
        Data = $Data
    }
}

function Write-GSResultFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Result
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'GSERR:InternalError:Result file path is missing.'
    }

    $json = ConvertTo-Json -InputObject $Result -Depth 12
    [IO.File]::WriteAllText($Path,$json,(New-Object Text.UTF8Encoding($false)))

    $ctx = Get-GSContext
    if ($ctx) {
        $lastResult = Join-Path ([string]$ctx.Root) 'last-result.json'
        [IO.File]::WriteAllText($lastResult,$json,(New-Object Text.UTF8Encoding($false)))
    }
}

function New-GSClassifiedException {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message
    )
    return New-Object System.Exception(('GSERR:' + $Code + ':' + $Message))
}

function ConvertFrom-GSException {
    param([Parameter(Mandatory=$true)][System.Exception]$Exception)

    $message = [string]$Exception.Message
    $code = 'UnknownError'
    $status = 'Failed'
    $userMessage = 'Operation failed.'

    $explicitError = [regex]::Match($message,'^GSERR:([A-Za-z0-9_]+):(.*)$')
    if ($explicitError.Success) {
        $code = [string]$explicitError.Groups[1].Value
        $message = ([string]$explicitError.Groups[2].Value).Trim()
    } elseif ($message -match '(?i)0xC0000005|ACCESS_VIOLATION|WINGET_ACCESS_VIOLATION') {
        $code = 'AccessViolation'
    } elseif ($message -match '(?i)0x80073CF3|dependency') {
        $code = 'DependencyMissing'
    } elseif ($message -match '(?i)access.*denied|unauthorized|permission') {
        $code = 'PermissionDenied'
    } elseif ($message -match '(?i)signature.*invalid|not trusted|signer') {
        $code = 'SignatureInvalid'
    } elseif ($message -match '(?i)source.*unavailable|source.*failed|source.*not found') {
        $code = 'SourceUnavailable'
    } elseif ($message -match '(?i)network|dns|tls|resolve.*host|timed out|timeout|connection') {
        $code = 'NetworkFailure'
    } elseif ($message -match '(?i)package.*not found|no package found') {
        $code = 'PackageNotFound'
    }

    switch ($code) {
        'NeedsRepair' {
            $status = 'NeedsRepair'
            $userMessage = 'WinGet or App Installer requires repair.'
        }
        'AccessViolation' {
            $status = 'NeedsRepair'
            $userMessage = 'WinGet is damaged or unstable and should be repaired.'
        }
        'DependencyMissing' {
            $status = 'NeedsDependency'
            $userMessage = 'A required Windows package dependency is missing.'
        }
        'PermissionDenied' {
            $userMessage = 'The operation requires additional permissions.'
        }
        'SignatureInvalid' {
            $userMessage = 'The package signature could not be verified.'
        }
        'SourceUnavailable' {
            $status = 'SourceUnavailable'
            $userMessage = 'The selected package source is unavailable.'
        }
        'NetworkFailure' {
            $status = 'NetworkUnavailable'
            $userMessage = 'The network connection or remote endpoint is unavailable.'
        }
        'StoreServiceDisabled' {
            $status = 'NeedsRepair'
            $userMessage = 'A Windows service required by Microsoft Store is disabled or cannot start.'
        }
        'PackageAgreementsRequired' {
            $status = 'AgreementsRequired'
            $userMessage = 'The package requires agreement acceptance before installation.'
        }
        'SourceAgreementsRequired' {
            $status = 'AgreementsRequired'
            $userMessage = 'The package source requires agreement acceptance before use.'
        }
        'AgreementHandshakeFailed' {
            $status = 'AgreementsRequired'
            $userMessage = 'WinGet refused agreements even after explicit consent was supplied.'
        }
        'PackageNotFound' {
            $userMessage = 'The selected package could not be found.'
        }
        'NoApplicationsFound' {
            $status = 'NotInstalled'
            $userMessage = 'The selected package is not installed.'
        }
        'UnsupportedArchitecture' {
            $status = 'Unsupported'
            $userMessage = 'The current architecture is not supported.'
        }
        'DeploymentFailure' {
            $userMessage = 'Windows could not deploy the package.'
        }
        'VerificationInconclusive' {
            $status = 'VerificationInconclusive'
            $userMessage = 'Windows accepted the operation, but Garant Store could not independently verify the final state.'
        }
        'WingetError' {
            $userMessage = 'WinGet returned an error. See the technical log for details.'
        }
        'InternalError' {
            $userMessage = 'Garant Store encountered an internal error.'
        }
        default {
            $userMessage = 'Operation failed. See the log for technical details.'
        }
    }

    return [pscustomobject]@{
        Code = $code
        Status = $status
        UserMessage = $userMessage
        TechnicalMessage = $message
    }
}

function Get-GSSystemArchitectureToken {
    $os64 = [Environment]::Is64BitOperatingSystem
    $arch = [string]$env:PROCESSOR_ARCHITECTURE

    if ($arch.ToUpperInvariant() -eq 'ARM64') { return 'arm64' }
    if ($os64) { return 'x64' }
    return 'x86'
}
