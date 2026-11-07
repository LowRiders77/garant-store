# Garant Store v0.8 DEV - WinGet Adapter
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

$script:GSWingetCache = @{
    Path = $null
    Version = $null
    Help = @{}
}
$script:GSLastSearchMetadata = [pscustomobject]@{ CacheHit=$false; CacheAgeSeconds=0; Query=''; Source='' }

# Install/upgrade deadline. Large installers (Visual Studio, Office, Adobe, games)
# routinely need far more than five minutes; terminating the process tree in the
# middle of an installation leaves a half-installed application. One hour is a
# last-resort guard against a hung installer, not an expected duration.
$script:GSPackageActionTimeoutSeconds = 3600
if ($env:GS_PACKAGE_ACTION_TIMEOUT_SECONDS -match '^\d+$' -and [int]$env:GS_PACKAGE_ACTION_TIMEOUT_SECONDS -ge 60) {
    $script:GSPackageActionTimeoutSeconds = [int]$env:GS_PACKAGE_ACTION_TIMEOUT_SECONDS
}


function Get-GSLastSearchMetadata {
    return $script:GSLastSearchMetadata
}

function Get-GSSearchCacheName {
    param(
        [Parameter(Mandatory=$true)][string]$Query,
        [string]$Source = ''
    )
    $normalized = $Source.ToLowerInvariant() + '|' + $Query.Trim().ToLowerInvariant()
    return ('search-' + (Get-GSCacheKey -Text $normalized) + '.json')
}

function Get-GSWingetPath {
    if ($script:GSWingetCache.Path -and (Test-Path -LiteralPath $script:GSWingetCache.Path -PathType Leaf)) {
        return [string]$script:GSWingetCache.Path
    }

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd -and $cmd.Source) {
        $script:GSWingetCache.Path = [string]$cmd.Source
        return [string]$cmd.Source
    }

    try {
        $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop
        $candidate = Join-Path $pkg.InstallLocation 'winget.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $script:GSWingetCache.Path = $candidate
            return $candidate
        }
    } catch {}

    return $null
}

function ConvertTo-GSNativeArgument {
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $slashCount = 0

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashCount++
            continue
        }

        if ($character -eq '"') {
            if ($slashCount -gt 0) {
                [void]$builder.Append((('\' * ($slashCount * 2)) -join ''))
            }
            [void]$builder.Append('\')
            [void]$builder.Append('"')
            $slashCount = 0
            continue
        }

        if ($slashCount -gt 0) {
            [void]$builder.Append((('\' * $slashCount) -join ''))
            $slashCount = 0
        }

        [void]$builder.Append($character)
    }

    if ($slashCount -gt 0) {
        [void]$builder.Append((('\' * ($slashCount * 2)) -join ''))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-GSNativeProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 300,
        [ValidateSet('None','Store')][string]$TelemetryKind = 'None'
    )

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-GSNativeArgument ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    try {
        if ($psi.PSObject.Properties.Name -contains 'StandardOutputEncoding') {
            $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
            $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        }
    } catch {}

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    $telemetry = $null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    try {
        if ($TelemetryKind -eq 'Store') {
            $telemetry = Start-GSStoreTelemetry
        }

        if (-not $process.Start()) {
            throw (New-GSClassifiedException -Code 'InternalError' -Message ('Failed to start process: ' + $FileName))
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timeoutMs = [Math]::Max(1000,$TimeoutSeconds * 1000)

        while (-not $process.WaitForExit(500)) {
            if ($stopwatch.ElapsedMilliseconds -ge $timeoutMs) {
                $timedOutPid = [int]$process.Id
                try {
                    $taskkill = Join-Path $env:WINDIR 'System32\taskkill.exe'
                    if (Test-Path -LiteralPath $taskkill) {
                        $killer = Start-Process -FilePath $taskkill -ArgumentList @('/PID',[string]$timedOutPid,'/T','/F') -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
                        if ($killer.ExitCode -ne 0 -and -not $process.HasExited) { $process.Kill() }
                    } else { $process.Kill() }
                } catch { try { if (-not $process.HasExited) { $process.Kill() } } catch {} }
                try { $process.WaitForExit() } catch {}
                throw (New-GSClassifiedException -Code 'ProcessTimeout' -Message ('Process exceeded its ' + $TimeoutSeconds + ' second deadline and was terminated with child processes. Executable=' + $FileName + '; PID=' + $timedOutPid + '. A timeout does not by itself prove a network failure.'))
            }

            if ($TelemetryKind -eq 'Store' -and $null -ne $telemetry) {
                Update-GSStoreTelemetry -State $telemetry
            }
        }

        try { $process.WaitForExit() } catch {}

        $telemetrySummary = $null
        if ($TelemetryKind -eq 'Store' -and $null -ne $telemetry) {
            Update-GSStoreTelemetry -State $telemetry
            $telemetrySummary = Finish-GSStoreTelemetry -State $telemetry
        }

        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            StdOut = [string]$stdoutTask.Result
            StdErr = [string]$stderrTask.Result
            ElapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds,2)
            Telemetry = $telemetrySummary
        }
    } finally {
        $stopwatch.Stop()
        $process.Dispose()
    }
}

function Write-GSWingetOutput {
    param(
        [string]$Text,
        [string]$Level = 'WINGET'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    $clean = $Text.Replace(([string][char]8),'')
    foreach ($rawLine in ($clean -split "`r?`n")) {
        $line = ([string]$rawLine).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^[\s\-\\\|/]+$') { continue }
        Write-GSLog -Message $line -Level $Level
    }
}

function Get-GSWingetAgreementRequirement {
    param(
        [int]$ExitCode,
        [string]$StdOut = '',
        [string]$StdErr = ''
    )

    $combinedOutput = ([string]$StdOut + [Environment]::NewLine + [string]$StdErr)

    if ($ExitCode -eq -1978335167 -or $combinedOutput -match '(?i)0x8A150041') {
        return 'Package'
    }

    if ($ExitCode -eq -1978335162 -or $combinedOutput -match '(?i)0x8A150046') {
        return 'Source'
    }

    return ''
}

function Test-GSWingetPackageCapability {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$true)][string]$Option,
        [hashtable]$Capabilities = $null
    )

    if ($null -ne $Capabilities -and $Capabilities.ContainsKey($Option)) {
        return [bool]$Capabilities[$Option]
    }

    return (Test-GSWingetOption -Command $Command -Option $Option)
}

function New-GSWingetPackageArguments {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('install','upgrade')][string]$Command,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Source,
        [bool]$AgreementConsent = $false,
        [switch]$IncludeUnknown,
        [switch]$Force,
        [switch]$Silent,
        [hashtable]$Capabilities = $null
    )

    $arguments = @($Command,'--id',$Id,'--source',$Source)

    if (Test-GSWingetPackageCapability -Command $Command -Option '--exact' -Capabilities $Capabilities) {
        $arguments += '--exact'
    }

    if ($AgreementConsent) {
        if (Test-GSWingetPackageCapability -Command $Command -Option '--accept-package-agreements' -Capabilities $Capabilities) {
            $arguments += '--accept-package-agreements'
        }
        if (Test-GSWingetPackageCapability -Command $Command -Option '--accept-source-agreements' -Capabilities $Capabilities) {
            $arguments += '--accept-source-agreements'
        }
    }

    if ($Command -eq 'upgrade' -and $IncludeUnknown -and
        (Test-GSWingetPackageCapability -Command $Command -Option '--include-unknown' -Capabilities $Capabilities)) {
        $arguments += '--include-unknown'
    }

    if ($Force -and
        (Test-GSWingetPackageCapability -Command $Command -Option '--force' -Capabilities $Capabilities)) {
        $arguments += '--force'
    }

    if ($Silent -and
        (Test-GSWingetPackageCapability -Command $Command -Option '--silent' -Capabilities $Capabilities)) {
        $arguments += '--silent'
    }

    if (Test-GSWingetPackageCapability -Command $Command -Option '--disable-interactivity' -Capabilities $Capabilities) {
        $arguments += '--disable-interactivity'
    }

    return @($arguments)
}

function Get-GSWingetAgreementCapabilities {
    param([Parameter(Mandatory=$true)][ValidateSet('install','upgrade')][string]$Command)

    return [pscustomobject]@{
        PackageAgreements = [bool](Test-GSWingetOption -Command $Command -Option '--accept-package-agreements')
        SourceAgreements = [bool](Test-GSWingetOption -Command $Command -Option '--accept-source-agreements')
        DisableInteractivity = [bool](Test-GSWingetOption -Command $Command -Option '--disable-interactivity')
    }
}

function Get-GSWingetTelemetryKind {
    param([string[]]$Arguments = @())

    $argList = @($Arguments)
    if ($argList.Count -gt 0 -and $argList[0] -in @('install','upgrade') -and
        ($argList -contains '--source') -and ($argList -contains 'msstore')) {
        return 'Store'
    }

    return 'None'
}

function Invoke-GSWinget {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$AllowNonZero,
        [switch]$SuppressOutput,
        [int]$TimeoutSeconds = 300
    )

    $exe = Get-GSWingetPath
    if (-not $exe) {
        throw (New-GSClassifiedException -Code 'NeedsRepair' -Message 'WinGet is not available. App Installer may be missing or damaged.')
    }

    Write-GSLog -Message ('winget ' + ($Arguments -join ' ')) -Level 'INFO'

    $telemetryKind = Get-GSWingetTelemetryKind -Arguments $Arguments

    $result = Invoke-GSNativeProcess -FileName $exe -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -TelemetryKind $telemetryKind

    if (-not $SuppressOutput) {
        Write-GSWingetOutput -Text $result.StdOut -Level 'WINGET'
        Write-GSWingetOutput -Text $result.StdErr -Level 'WINGET-ERR'
    }

    $combinedOutput = ([string]$result.StdOut + [Environment]::NewLine + [string]$result.StdErr)

    if ($result.ExitCode -eq -1073741819) {
        throw (New-GSClassifiedException -Code 'AccessViolation' -Message 'WinGet crashed with 0xC0000005.')
    }

    if ($result.ExitCode -eq -2147023838 -or $combinedOutput -match '(?i)0x80070422') {
        throw (New-GSClassifiedException -Code 'StoreServiceDisabled' -Message 'Microsoft Store operation failed with 0x80070422 (ERROR_SERVICE_DISABLED).')
    }

    $agreementRequirement = Get-GSWingetAgreementRequirement `
        -ExitCode ([int]$result.ExitCode) `
        -StdOut ([string]$result.StdOut) `
        -StdErr ([string]$result.StdErr)

    if ($agreementRequirement -eq 'Package') {
        throw (New-GSClassifiedException -Code 'PackageAgreementsRequired' -Message 'WinGet requires package agreement acceptance.')
    }

    if ($agreementRequirement -eq 'Source') {
        throw (New-GSClassifiedException -Code 'SourceAgreementsRequired' -Message 'WinGet requires source agreement acceptance.')
    }

    if (-not $AllowNonZero -and $result.ExitCode -ne 0) {
        throw (New-GSClassifiedException -Code 'WingetError' -Message ('WinGet exited with code ' + $result.ExitCode))
    }

    return $result
}

function Get-GSWingetHelpText {
    param([Parameter(Mandatory=$true)][string]$Command)

    if ($script:GSWingetCache.Help.ContainsKey($Command)) {
        return [string]$script:GSWingetCache.Help[$Command]
    }

    $exe = Get-GSWingetPath
    if (-not $exe) { return '' }

    # Native help probing is expensive when every GUI request spawns PowerShell.
    # A successful repair invalidates this persistent capability cache.
    $helpKey = 'capabilities-help-v08-' + ($Command -replace '[^A-Za-z0-9]','') + '.json'
    $diskHelp = Read-GSCacheJson -Name $helpKey -MaxAgeSeconds 86400
    if ($null -ne $diskHelp -and $diskHelp.PSObject.Properties.Name -contains 'Text') {
        $script:GSWingetCache.Help[$Command] = [string]$diskHelp.Text
        return [string]$diskHelp.Text
    }

    try {
        $result = Invoke-GSNativeProcess -FileName $exe -Arguments @($Command,'--help') -TimeoutSeconds 30
        $text = if ($result.ExitCode -eq 0) { ($result.StdOut + [Environment]::NewLine + $result.StdErr) } else { '' }
        $script:GSWingetCache.Help[$Command] = $text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-GSCacheJson -Name $helpKey -Value ([ordered]@{ Text = $text; Schema = 1 })
        }
        return $text
    } catch {
        $script:GSWingetCache.Help[$Command] = ''
        return ''
    }
}

function Test-GSWingetOption {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$true)][string]$Option
    )

    $helpText = Get-GSWingetHelpText -Command $Command
    if ([string]::IsNullOrWhiteSpace($helpText)) { return $false }
    return ($helpText.IndexOf($Option,[StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-GSWingetVersion {
    if ($script:GSWingetCache.Version) {
        return $script:GSWingetCache.Version
    }

    $exe = Get-GSWingetPath
    if (-not $exe) { return $null }

    try {
        $result = Invoke-GSNativeProcess -FileName $exe -Arguments @('--version') -TimeoutSeconds 30
        if ($result.ExitCode -ne 0) { return $null }

        $match = [regex]::Match(($result.StdOut + ' ' + $result.StdErr),'(?i)v?(\d+\.\d+\.\d+(?:\.\d+)?)')
        if (-not $match.Success) { return $null }

        $script:GSWingetCache.Version = [version]$match.Groups[1].Value
        return $script:GSWingetCache.Version
    } catch {
        return $null
    }
}

function Clear-GSWingetCache {
    $script:GSWingetCache.Path = $null
    $script:GSWingetCache.Version = $null
    $script:GSWingetCache.Help.Clear()
}

function Get-GSWingetSources {
    try {
        $capture = Invoke-GSWinget -Arguments @('source','export') -AllowNonZero -SuppressOutput -TimeoutSeconds 60
        if ($capture.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($capture.StdOut)) {
            return @()
        }

        $sources = @()
        foreach ($rawLine in ([string]$capture.StdOut -split "`r?`n")) {
            $line = ([string]$rawLine).Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $sources += ($line | ConvertFrom-Json)
            } catch {
                Write-GSLog -Message ('Unable to parse winget source export line: ' + $line) -Level 'WARN'
            }
        }

        return @($sources)
    } catch {
        Write-GSLog -Message ('winget source export failed: ' + $_.Exception.Message) -Level 'WARN'
        return @()
    }
}

function Export-GSWingetInventory {
    param([bool]$AcceptAgreements)

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-export-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $arguments = @('export','--output',$temp,'--include-versions')

        if (Test-GSWingetOption -Command 'export' -Option '--disable-interactivity') {
            $arguments += '--disable-interactivity'
        }
        if ($AcceptAgreements -and (Test-GSWingetOption -Command 'export' -Option '--accept-source-agreements')) {
            $arguments += '--accept-source-agreements'
        }

        $capture = Invoke-GSWinget -Arguments $arguments -AllowNonZero -SuppressOutput -TimeoutSeconds 180

        if (-not (Test-Path -LiteralPath $temp -PathType Leaf)) {
            return [pscustomobject]@{
                Success = $false
                ExitCode = $capture.ExitCode
                Items = @()
                TechnicalMessage = 'winget export did not create a JSON file.'
            }
        }

        $jsonText = [IO.File]::ReadAllText($temp,[Text.Encoding]::UTF8)
        $exportObject = $jsonText | ConvertFrom-Json
        $items = @(ConvertFrom-GSWingetExportObject -ExportObject $exportObject)

        return [pscustomobject]@{
            Success = ($capture.ExitCode -eq 0)
            ExitCode = $capture.ExitCode
            Items = $items
            TechnicalMessage = ''
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            ExitCode = -1
            Items = @()
            TechnicalMessage = $_.Exception.Message
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Get-GSWingetRawList {
    param(
        [bool]$AcceptAgreements,
        [string]$Source = ''
    )

    $arguments = @('list')
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        if (-not (Test-GSWingetOption -Command 'list' -Option '--source')) {
            return [pscustomobject]@{
                Success = $false
                ExitCode = -1
                Text = 'WinGet list does not support source-scoped inventory.'
            }
        }
        $arguments += @('--source',$Source)
    }
    if (Test-GSWingetOption -Command 'list' -Option '--disable-interactivity') {
        $arguments += '--disable-interactivity'
    }
    if ($AcceptAgreements -and (Test-GSWingetOption -Command 'list' -Option '--accept-source-agreements')) {
        $arguments += '--accept-source-agreements'
    }

    try {
        $capture = Invoke-GSWinget -Arguments $arguments -AllowNonZero -TimeoutSeconds 120
        return [pscustomobject]@{
            Success = ($capture.ExitCode -eq 0)
            ExitCode = $capture.ExitCode
            Text = [string]$capture.StdOut
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            ExitCode = -1
            Text = ''
        }
    }
}

function ConvertFrom-GSWingetSearchCapture {
    param(
        [Parameter(Mandatory=$true)][int]$ExitCode,
        [AllowEmptyString()][string]$StdOut = '',
        [AllowEmptyString()][string]$StdErr = '',
        [string]$FallbackSource = ''
    )

    # A source can fail after another source has already written valid rows.
    # Preserve those rows instead of turning a partial search into an empty/error
    # result. This also prevents a localized "no packages" message from one
    # source from masking results emitted by another source.
    $rows = @(ConvertFrom-WingetSearchText -Text $StdOut -FallbackSource $FallbackSource)
    if ($rows.Count -gt 0) {
        return $rows
    }

    if (Test-GSWingetNoApplicationsFound -ExitCode $ExitCode -StdOut $StdOut -StdErr $StdErr) {
        return @()
    }

    if ($ExitCode -ne 0) {
        $detail = 'WinGet search exited with code ' + $ExitCode
        if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
            $detail += ': ' + ([string]$StdErr).Trim()
        }
        throw (New-GSClassifiedException -Code 'WingetError' -Message $detail)
    }

    return @()
}

function New-GSWingetSearchArguments {
    param(
        [Parameter(Mandatory=$true)][string]$Query,
        [string]$Source = '',
        [bool]$AcceptAgreements = $false,
        [hashtable]$Capabilities = $null
    )

    # A pure argument builder can be tested independently from network and WinGet.
    # On first use Store terms are never accepted without an explicit GUI action.
    $supports = {
        param([string]$Option)
        if ($null -ne $Capabilities) { return ($Capabilities.ContainsKey($Option) -and [bool]$Capabilities[$Option]) }
        return (Test-GSWingetOption -Command 'search' -Option $Option)
    }

    $argsList = @('search')
    if (& $supports '--query') { $argsList += @('--query',$Query) } else { $argsList += $Query }
    if ($Source -in @('msstore','winget')) { $argsList += @('--source',$Source) }
    if (& $supports '--count') { $argsList += @('--count','50') }
    if (& $supports '--disable-interactivity') { $argsList += '--disable-interactivity' }
    # This is a documented WinGet command option. Once the user explicitly
    # accepts the source terms, do not silently omit it because localized or
    # truncated --help output failed capability detection. The runtime result
    # remains authoritative if an older WinGet build rejects the option.
    if ($AcceptAgreements) {
        $argsList += '--accept-source-agreements'
    }
    return @($argsList)
}

function Search-GSWinget {
    param(
        [Parameter(Mandatory=$true)][string]$Query,
        [string]$Source = '',
        [bool]$AcceptAgreements = $false
    )

    $cacheName = Get-GSSearchCacheName -Query $Query -Source $Source
    $cached = Read-GSCacheJson -Name $cacheName -MaxAgeSeconds 45
    if ($null -ne $cached -and $cached.PSObject.Properties.Name -contains 'Rows') {
        $script:GSLastSearchMetadata = [pscustomobject]@{
            CacheHit = $true
            CacheAgeSeconds = 0
            Query = $Query
            Source = $Source
        }
        Write-GSLog -Message ('Search cache hit. Query=' + $Query + '; source=' + $Source) -Level 'INFO'
        return @($cached.Rows)
    }

    $arguments = @(New-GSWingetSearchArguments -Query $Query -Source $Source -AcceptAgreements $AcceptAgreements)

    $capture = Invoke-GSWinget -Arguments $arguments -AllowNonZero -TimeoutSeconds 120
    $rows = @(ConvertFrom-GSWingetSearchCapture `
        -ExitCode ([int]$capture.ExitCode) `
        -StdOut ([string]$capture.StdOut) `
        -StdErr ([string]$capture.StdErr) `
        -FallbackSource $Source)

    $record = [ordered]@{
        Schema = 1
        Created = (Get-Date -Format o)
        Query = $Query
        Source = $Source
        Rows = $rows
    }
    Write-GSCacheJson -Name $cacheName -Value $record

    $script:GSLastSearchMetadata = [pscustomobject]@{
        CacheHit = $false
        CacheAgeSeconds = 0
        Query = $Query
        Source = $Source
    }

    return $rows
}

function Confirm-GSWingetPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Source,
        [bool]$AcceptAgreements = $false
    )

    $arguments = @('show','--id',$Id,'--source',$Source)

    if ($Source -eq 'winget' -and (Test-GSWingetOption -Command 'show' -Option '--exact')) {
        $arguments += '--exact'
    }
    if (Test-GSWingetOption -Command 'show' -Option '--disable-interactivity') {
        $arguments += '--disable-interactivity'
    }
    if ($AcceptAgreements -and (Test-GSWingetOption -Command 'show' -Option '--accept-source-agreements')) {
        $arguments += '--accept-source-agreements'
    }

    $capture = Invoke-GSWinget -Arguments $arguments -AllowNonZero -TimeoutSeconds 120
    if ($capture.ExitCode -ne 0) {
        throw (New-GSClassifiedException -Code 'PackageNotFound' -Message ('Package verification failed: ' + $Id + ' from ' + $Source))
    }

    return $true
}

function Invoke-GSWingetPackageAction {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('install','upgrade')][string]$Command,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Source,
        [bool]$AgreementConsent = $false,
        [switch]$IncludeUnknown,
        [switch]$Force,
        [switch]$Silent,
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -le 0) { $TimeoutSeconds = $script:GSPackageActionTimeoutSeconds }

    $arguments = New-GSWingetPackageArguments `
        -Command $Command `
        -Id $Id `
        -Source $Source `
        -AgreementConsent $AgreementConsent `
        -IncludeUnknown:$IncludeUnknown `
        -Force:$Force `
        -Silent:$Silent

    return (Invoke-GSWinget -Arguments $arguments -TimeoutSeconds $TimeoutSeconds)
}

function Test-GSWingetNoApplicationsFound {
    param(
        [int]$ExitCode,
        [string]$StdOut = '',
        [string]$StdErr = ''
    )

    if ($ExitCode -eq -1978335212) { return $true }

    $combined = ([string]$StdOut + [Environment]::NewLine + [string]$StdErr)
    if ($combined -match '(?i)0x8A150014') { return $true }
    if ($combined -match '(?i)No app found matching input criteria') { return $true }
    if ($combined -match '(?i)No packages found') { return $true }

    return $false
}

function Get-GSWingetSourceListSnapshot {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('msstore','winget')][string]$Source,
        [bool]$AcceptAgreements = $false
    )

    $arguments = @('list','--source',$Source)

    if (Test-GSWingetOption -Command 'list' -Option '--disable-interactivity') {
        $arguments += '--disable-interactivity'
    }
    if ($AcceptAgreements -and (Test-GSWingetOption -Command 'list' -Option '--accept-source-agreements')) {
        $arguments += '--accept-source-agreements'
    }

    try {
        $capture = Invoke-GSWinget -Arguments $arguments -AllowNonZero -TimeoutSeconds 120
        $notFound = Test-GSWingetNoApplicationsFound `
            -ExitCode ([int]$capture.ExitCode) `
            -StdOut ([string]$capture.StdOut) `
            -StdErr ([string]$capture.StdErr)

        if ($notFound) {
            return [pscustomobject]@{
                Reliable = $true
                Empty = $true
                Text = ''
                ExitCode = [int]$capture.ExitCode
            }
        }

        if ($capture.ExitCode -eq 0) {
            return [pscustomobject]@{
                Reliable = $true
                Empty = [string]::IsNullOrWhiteSpace([string]$capture.StdOut)
                Text = [string]$capture.StdOut
                ExitCode = 0
            }
        }

        Write-GSLog -Message ('Source list snapshot returned code ' + $capture.ExitCode + '; source=' + $Source) -Level 'WARN'
    } catch {
        Write-GSLog -Message ('Source list snapshot failed for ' + $Source + ': ' + $_.Exception.Message) -Level 'WARN'
    }

    return [pscustomobject]@{
        Reliable = $false
        Empty = $false
        Text = ''
        ExitCode = $null
    }
}

function Get-GSWingetExactListQueryResult {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [string]$Source = '',
        [bool]$AcceptAgreements = $false
    )

    $baseArgs = @('list','--id',$Id)

    if (Test-GSWingetOption -Command 'list' -Option '--exact') {
        $baseArgs += '--exact'
    }
    if (Test-GSWingetOption -Command 'list' -Option '--disable-interactivity') {
        $baseArgs += '--disable-interactivity'
    }
    if ($AcceptAgreements -and (Test-GSWingetOption -Command 'list' -Option '--accept-source-agreements')) {
        $baseArgs += '--accept-source-agreements'
    }

    if ($Source -in @('msstore','winget')) {
        try {
            $sourceCapture = Invoke-GSWinget -Arguments @($baseArgs + @('--source',$Source)) -AllowNonZero -TimeoutSeconds 120
            $sourceNotFound = Test-GSWingetNoApplicationsFound -ExitCode ([int]$sourceCapture.ExitCode) -StdOut ([string]$sourceCapture.StdOut) -StdErr ([string]$sourceCapture.StdErr)

            if ($sourceNotFound) {
                Write-GSLog -Message ('Exact package query confirms absence from source: ' + $Id + '; source=' + $Source) -Level 'INFO'
                return [pscustomobject]@{
                    Id = $Id
                    Source = $Source
                    QueryReliable = $true
                    ConfirmedAbsent = $true
                    Texts = @()
                    Attempts = @([pscustomobject]@{ Name='source-specific'; ExitCode=[int]$sourceCapture.ExitCode; NotFound=$true })
                }
            }

            if ($sourceCapture.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$sourceCapture.StdOut)) {
                return [pscustomobject]@{
                    Id = $Id
                    Source = $Source
                    QueryReliable = $true
                    ConfirmedAbsent = $false
                    Texts = @([string]$sourceCapture.StdOut)
                    Attempts = @([pscustomobject]@{ Name='source-specific'; ExitCode=0; NotFound=$false })
                }
            }

            Write-GSLog -Message ('Source-specific exact query returned unexpected code ' + $sourceCapture.ExitCode + '; falling back to aggregate list.') -Level 'WARN'
        } catch {
            Write-GSLog -Message ('Source-specific exact query failed; falling back to aggregate list: ' + $_.Exception.Message) -Level 'WARN'
        }
    }

    try {
        $capture = Invoke-GSWinget -Arguments $baseArgs -AllowNonZero -TimeoutSeconds 120
        $notFound = Test-GSWingetNoApplicationsFound -ExitCode ([int]$capture.ExitCode) -StdOut ([string]$capture.StdOut) -StdErr ([string]$capture.StdErr)

        if ($notFound) {
            return [pscustomobject]@{
                Id = $Id
                Source = $Source
                QueryReliable = $true
                ConfirmedAbsent = $true
                Texts = @()
                Attempts = @([pscustomobject]@{ Name='aggregate'; ExitCode=[int]$capture.ExitCode; NotFound=$true })
            }
        }

        if ($capture.ExitCode -eq 0) {
            return [pscustomobject]@{
                Id = $Id
                Source = $Source
                QueryReliable = $true
                ConfirmedAbsent = $false
                Texts = if ([string]::IsNullOrWhiteSpace([string]$capture.StdOut)) { @() } else { @([string]$capture.StdOut) }
                Attempts = @([pscustomobject]@{ Name='aggregate'; ExitCode=0; NotFound=$false })
            }
        }
    } catch {
        Write-GSLog -Message ('Aggregate exact query failed: ' + $_.Exception.Message) -Level 'WARN'
    }

    return [pscustomobject]@{
        Id = $Id
        Source = $Source
        QueryReliable = $false
        ConfirmedAbsent = $false
        Texts = @()
        Attempts = @()
    }
}

function Get-GSWingetExactListText {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [string]$Source = '',
        [bool]$AcceptAgreements = $false
    )

    $query = Get-GSWingetExactListQueryResult -Id $Id -Source $Source -AcceptAgreements $AcceptAgreements
    return @($query.Texts)
}



