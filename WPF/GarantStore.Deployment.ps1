# Garant Store v0.8 DEV - Deployment and Recovery
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest
$script:GSStoreServiceBaseline=$null
$script:GSDeploymentRoot=$PSScriptRoot

function Invoke-GSElevatedServiceHelper {
    # Core runs with the user's normal rights. Service changes are delegated to a
    # short elevated helper that also restores the original startup types when
    # this Core process exits for any reason, including the Stop button.
    param([int]$ReadyTimeoutSeconds = 180)

    $helper = Join-Path $script:GSDeploymentRoot 'GarantStore.ServiceHelper.ps1'
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
        throw (New-GSClassifiedException -Code 'InternalError' -Message 'Service helper is missing from the installation.')
    }
    $ready = Join-Path ([IO.Path]::GetTempPath()) ('gs-service-helper-' + [guid]::NewGuid().ToString('N') + '.json')
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $helper + '" -CorePid ' + $PID + ' -ReadyFile "' + $ready + '"'
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Write-GSLog -Message 'Requesting administrator rights for the temporary Store service change.' -Level 'INFO'
    try {
        $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch {
        throw (New-GSClassifiedException -Code 'ServiceElevationDeclined' -Message ('Elevation for the service helper was not granted: ' + $_.Exception.Message))
    }
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $ready -PathType Leaf)) {
        $helperExited = $false
        try { $helperExited = $process.HasExited } catch { $helperExited = $false }
        if ($helperExited -and -not (Test-Path -LiteralPath $ready -PathType Leaf)) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not (Test-Path -LiteralPath $ready -PathType Leaf)) {
        throw (New-GSClassifiedException -Code 'StoreServiceDisabled' -Message 'The elevated service helper did not report a result.')
    }
    try {
        $outcome = [IO.File]::ReadAllText($ready,[Text.Encoding]::UTF8) | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
    }
    if (-not [bool]$outcome.Ok) {
        throw (New-GSClassifiedException -Code 'StoreServiceDisabled' -Message ('Service helper failed: ' + [string]$outcome.Error))
    }
    foreach ($entry in @($outcome.PreviouslyRestored)) {
        if ($entry) { Write-GSLog -Message ('Restored service left changed by an interrupted earlier run: ' + [string]$entry) -Level 'INFO' }
    }
    return $outcome
}

function Get-GSStoreServiceSnapshot {
    $wanted = @('wuauserv','BITS','InstallService','ClipSVC','AppXSvc','DoSvc')
    $records = @()
    $found = @{}

    try {
        $filter = "Name='wuauserv' OR Name='BITS' OR Name='InstallService' OR Name='ClipSVC' OR Name='AppXSvc' OR Name='DoSvc'"
        foreach ($service in @(Get-CimInstance Win32_Service -Filter $filter -ErrorAction Stop)) {
            $found[[string]$service.Name] = [pscustomobject]@{
                Name = [string]$service.Name
                DisplayName = [string]$service.DisplayName
                State = [string]$service.State
                StartMode = [string]$service.StartMode
            }
        }
    } catch {
        Write-GSLog -Message ('Fast Store service snapshot failed: ' + $_.Exception.Message) -Level 'WARN'
    }

    foreach ($name in $wanted) {
        if ($found.ContainsKey($name)) {
            $records += $found[$name]
        } else {
            $records += [pscustomobject]@{
                Name = $name
                DisplayName = ''
                State = 'Unavailable'
                StartMode = ''
            }
        }
    }

    return @($records)
}

function Get-GSStorePolicySnapshot {
    $result = [ordered]@{
        RemoveWindowsStore = $null
        DisableWindowsUpdateAccess = $null
        DoNotConnectToWindowsUpdateInternetLocations = $null
        SetDisableUXWUAccess = $null
    }

    try {
        $storePolicy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -ErrorAction SilentlyContinue
        if ($storePolicy -and $storePolicy.PSObject.Properties.Name -contains 'RemoveWindowsStore') {
            $result.RemoveWindowsStore = $storePolicy.RemoveWindowsStore
        }
    } catch {}

    try {
        $wuPolicy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
        foreach ($name in @('DisableWindowsUpdateAccess','DoNotConnectToWindowsUpdateInternetLocations','SetDisableUXWUAccess')) {
            if ($wuPolicy -and $wuPolicy.PSObject.Properties.Name -contains $name) {
                $result[$name] = $wuPolicy.$name
            }
        }
    } catch {}

    return [pscustomobject]$result
}

function Ensure-GSStoreServicePrerequisites {
    param([bool]$AllowServiceChanges = $false)
    Write-GSProgress -Stage 'Services' -Indeterminate $true -Detail 'MicrosoftStoreServices'

    $before = @(Get-GSStoreServiceSnapshot)
    $policies = Get-GSStorePolicySnapshot
    $map = @{}
    foreach ($record in $before) { $map[[string]$record.Name] = $record }

    $required = @('wuauserv','BITS','InstallService','ClipSVC','AppXSvc')
    $needsChange = @($required | Where-Object {
        -not $map.ContainsKey($_) -or $map[$_].State -eq 'Unavailable' -or
        $map[$_].StartMode -eq 'Disabled' -or
        $map[$_].State -ne 'Running'
    })
    if ($needsChange.Count -gt 0 -and (
        [int]$policies.RemoveWindowsStore -eq 1 -or
        [int]$policies.DisableWindowsUpdateAccess -eq 1 -or
        [int]$policies.DoNotConnectToWindowsUpdateInternetLocations -eq 1 -or
        [int]$policies.SetDisableUXWUAccess -eq 1
    )) {
        throw (New-GSClassifiedException -Code 'StorePolicyBlocked' -Message ('Store prerequisites require service changes, but Windows Update policy restricts access. Garant Store left system services unchanged. Policy: DisableWindowsUpdateAccess=' + [string]$policies.DisableWindowsUpdateAccess + '; DoNotConnectToWindowsUpdateInternetLocations=' + [string]$policies.DoNotConnectToWindowsUpdateInternetLocations + '; SetDisableUXWUAccess=' + [string]$policies.SetDisableUXWUAccess))
    }
    if ($needsChange.Count -gt 0 -and -not $AllowServiceChanges) {
        throw (New-GSClassifiedException -Code 'StoreServiceConsentRequired' -Message ('Microsoft Store requires a one-time, temporary service change: ' + ($needsChange -join ', ') + '. No service has been changed.'))
    }
    $changed = @()
    $errorsFound = @()
    $needsRefresh = $false

    if ($needsChange.Count -gt 0) {
        # The elevated helper records the baseline in an administrators-only file
        # and restores it after this process exits.
        $helperOutcome = Invoke-GSElevatedServiceHelper
        $changed = @($helperOutcome.Changed | Where-Object { $_ })
        $errorsFound = @($helperOutcome.Errors | Where-Object { $_ })
        $needsRefresh = $true
    }

    $after = if ($needsRefresh) { @(Get-GSStoreServiceSnapshot) } else { $before }
    $afterMap = @{}
    foreach ($record in $after) { $afterMap[[string]$record.Name] = $record }

    $fatal = @()
    foreach ($name in @('wuauserv','BITS','InstallService')) {
        if (-not $afterMap.ContainsKey($name) -or
            $afterMap[$name].State -eq 'Unavailable' -or
            $afterMap[$name].StartMode -eq 'Disabled' -or
            $afterMap[$name].State -ne 'Running') {
            $fatal += $name
        }
    }

    foreach ($name in @('ClipSVC','AppXSvc')) {
        if (-not $afterMap.ContainsKey($name) -or
            $afterMap[$name].State -eq 'Unavailable' -or
            $afterMap[$name].StartMode -eq 'Disabled') {
            $fatal += $name
        }
    }

    foreach ($entry in $errorsFound) {
        Write-GSLog -Message ('Store service preflight: ' + $entry) -Level 'WARN'
    }

    if ($fatal.Count -gt 0) {
        throw (New-GSClassifiedException -Code 'StoreServiceDisabled' -Message ('Required Microsoft Store services are unavailable: ' + ($fatal -join ', ')))
    }

    $doConfig = Get-GSDeliveryOptimizationConfig
    Write-GSLog -Message ('Store service preflight passed. Changes=' + ($changed -join '; ') + '; DO available=' + $doConfig.Available + '; mode=' + $doConfig.DownloadMode) -Level 'INFO'

    return [pscustomobject]@{
        Before = $before
        After = $after
        Changed = $changed
        Policies = Get-GSStorePolicySnapshot
        DeliveryOptimization = $doConfig
    }
}

function Restore-GSStoreServiceStartupTypes {
    if ($null -eq $script:GSStoreServiceBaseline) { return }
    $after=@(Get-GSStoreServiceSnapshot);$afterMap=@{}
    foreach($record in $after){$afterMap[[string]$record.Name]=$record}
    foreach($original in @($script:GSStoreServiceBaseline)){
        if($original.StartMode -notin @('Disabled','Manual','Auto') -or -not $afterMap.ContainsKey([string]$original.Name)){continue}
        $current=$afterMap[[string]$original.Name]
        if([string]$current.StartMode -eq [string]$original.StartMode){continue}
        $startupType=switch([string]$original.StartMode){'Auto'{'Automatic'}'Manual'{'Manual'}'Disabled'{'Disabled'}default{$null}}
        if(-not $startupType){continue}
        try{
            Set-Service -Name ([string]$original.Name) -StartupType $startupType -ErrorAction Stop
            Write-GSLog -Message ('Restored Store service startup type: '+[string]$original.Name+' '+[string]$current.StartMode+' -> '+[string]$original.StartMode+'. Running state is left unchanged to avoid interrupting unrelated system work.') -Level 'INFO'
        }catch{Write-GSLog -Message ('Could not restore service startup type for '+[string]$original.Name+': '+$_.Exception.Message) -Level 'WARN'}
    }
    $script:GSStoreServiceBaseline=$null
}

function Download-GSFileWithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int]$MinimumBytes = 1024,
        [int]$Attempts = 3
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}

    $lastMessage = ''

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            Write-GSLog -Message ('Download attempt ' + $attempt + '/' + $Attempts + ': ' + $Uri) -Level 'INFO'
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination -TimeoutSec 120 -ErrorAction Stop

            $file = Get-Item -LiteralPath $Destination -ErrorAction Stop
            if ($file.Length -lt $MinimumBytes) {
                throw ('Downloaded file is unexpectedly small: ' + $file.Length + ' bytes')
            }

            Write-GSLog -Message ('Downloaded ' + ('{0:N2}' -f ($file.Length / 1MB)) + ' MB') -Level 'INFO'
            return
        } catch {
            $lastMessage = $_.Exception.Message
            Write-GSLog -Message ('Download failed: ' + $lastMessage) -Level 'WARN'
            Start-Sleep -Seconds ([Math]::Min(6,$attempt * 2))
        }
    }

    throw (New-GSClassifiedException -Code 'NetworkFailure' -Message ('Download failed after retries: ' + $lastMessage))
}

function Assert-GSMicrosoftSignedFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (New-GSClassifiedException -Code 'SignatureInvalid' -Message ($Label + ' was not found.'))
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    Write-GSLog -Message ($Label + ' signature=' + $signature.Status) -Level 'INFO'

    if ($signature.SignerCertificate) {
        Write-GSLog -Message ($Label + ' signer=' + $signature.SignerCertificate.Subject) -Level 'INFO'
    }

    if ($signature.Status -ne 'Valid') {
        throw (New-GSClassifiedException -Code 'SignatureInvalid' -Message ($Label + ' signature is not valid. Status=' + $signature.Status))
    }

    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)Microsoft') {
        throw (New-GSClassifiedException -Code 'SignatureInvalid' -Message ($Label + ' is not signed by Microsoft.'))
    }
}

function ConvertTo-GSVersionSafe {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    try {
        return [version]$Value
    } catch {
        return $null
    }
}

function Get-GSDeploymentDependencyRequest {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return $null }

    $nameMatch = [regex]::Match(
        $Message,
        '(?i)Microsoft\.(?:WindowsAppRuntime\.[0-9]+(?:\.[0-9]+)*|VCLibs\.140\.00(?:\.UWPDesktop)?)'
    )

    if (-not $nameMatch.Success) { return $null }

    $name = [string]$nameMatch.Value
    $tailStart = $nameMatch.Index + $nameMatch.Length
    $tail = if ($tailStart -lt $Message.Length) { $Message.Substring($tailStart) } else { '' }

    # Locale-independent: after the framework name/publisher/architecture, AppX
    # deployment emits the required framework version. x64/x86 tokens do not
    # match this dotted-version expression.
    $versionMatch = [regex]::Match($tail,'(?<![0-9])([0-9]+(?:\.[0-9]+){2,3})(?![0-9])')
    $minimumVersion = if ($versionMatch.Success) { [string]$versionMatch.Groups[1].Value } else { '' }

    return [pscustomobject]@{
        Name = $name
        MinimumVersion = $minimumVersion
        Architecture = Get-GSSystemArchitectureToken
    }
}

function Test-GSFrameworkArchitectureCompatible {
    param(
        [AllowEmptyString()][string]$PackageArchitecture,
        [Parameter(Mandatory=$true)][ValidateSet('x64','x86','arm64')][string]$RequiredArchitecture
    )

    if ([string]::IsNullOrWhiteSpace($PackageArchitecture)) { return $false }

    $normalized = $PackageArchitecture.ToLowerInvariant()
    if ($normalized -eq 'neutral') { return $true }
    return ($normalized -eq $RequiredArchitecture.ToLowerInvariant())
}

function Get-GSFrameworkPackageStatus {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][string]$MinimumVersion = '',
        [AllowEmptyString()][string]$Architecture = ''
    )

    $requiredArchitecture = if ([string]::IsNullOrWhiteSpace($Architecture)) {
        Get-GSSystemArchitectureToken
    } else {
        $Architecture.ToLowerInvariant()
    }

    if ($requiredArchitecture -notin @('x64','x86','arm64')) {
        throw (New-GSClassifiedException -Code 'UnsupportedArchitecture' -Message ('Unsupported framework architecture: ' + $requiredArchitecture))
    }

    $minimum = ConvertTo-GSVersionSafe -Value $MinimumVersion
    $packages = @(Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue |
        Where-Object {
            Test-GSFrameworkArchitectureCompatible `
                -PackageArchitecture ([string]$_.Architecture) `
                -RequiredArchitecture $requiredArchitecture
        } |
        Sort-Object Version -Descending)

    $best = if ($packages.Count -gt 0) { $packages[0] } else { $null }
    $ready = $false

    if ($null -ne $best) {
        if ($null -eq $minimum) {
            $ready = $true
        } else {
            $installedVersion = ConvertTo-GSVersionSafe -Value ([string]$best.Version)
            $ready = ($null -ne $installedVersion -and $installedVersion -ge $minimum)
        }
    }

    return [pscustomobject]@{
        Name = $Name
        MinimumVersion = $MinimumVersion
        RequiredArchitecture = $requiredArchitecture
        Installed = ($null -ne $best)
        InstalledVersion = if ($null -ne $best) { [string]$best.Version } else { '' }
        Architecture = if ($null -ne $best) { [string]$best.Architecture } else { '' }
        Ready = $ready
    }
}

function Install-GSWindowsAppRuntime18 {
    param([AllowEmptyString()][string]$MinimumVersion = '')

    $arch = Get-GSSystemArchitectureToken
    $existing = Get-GSFrameworkPackageStatus -Name 'Microsoft.WindowsAppRuntime.1.8' -MinimumVersion $MinimumVersion -Architecture $arch
    if ($existing.Ready) {
        Write-GSLog -Message ('Windows App Runtime 1.8 already satisfies requirement. Installed=' + $existing.InstalledVersion + '; required=' + $MinimumVersion) -Level 'INFO'
        return $existing
    }

    $urls = @{
        'x64'   = 'https://aka.ms/windowsappsdk/1.8/1.8.260921001/windowsappruntimeinstall-x64.exe'
        'x86'   = 'https://aka.ms/windowsappsdk/1.8/1.8.260921001/windowsappruntimeinstall-x86.exe'
        'arm64' = 'https://aka.ms/windowsappsdk/1.8/1.8.260921001/windowsappruntimeinstall-arm64.exe'
    }

    if (-not $urls.ContainsKey($arch)) {
        throw (New-GSClassifiedException -Code 'UnsupportedArchitecture' -Message ('No Windows App Runtime installer for ' + $arch))
    }

    $installer = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-WindowsAppRuntime18-' + [Guid]::NewGuid().ToString('N') + '.exe')

    try {
        Download-GSFileWithRetry -Uri $urls[$arch] -Destination $installer -MinimumBytes 1048576
        Assert-GSMicrosoftSignedFile -Path $installer -Label 'Windows App Runtime 1.8 installer'

        $result = Invoke-GSNativeProcess -FileName $installer -Arguments @('--quiet') -TimeoutSeconds 600
        if ($result.ExitCode -ne 0) {
            throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message ('Windows App Runtime installer exit code ' + $result.ExitCode))
        }

        $after = Get-GSFrameworkPackageStatus -Name 'Microsoft.WindowsAppRuntime.1.8' -MinimumVersion $MinimumVersion -Architecture $arch
        if (-not $after.Ready) {
            throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message ('Windows App Runtime installer finished but requirement is still not satisfied. Installed=' + $after.InstalledVersion + '; required=' + $MinimumVersion))
        }

        Write-GSLog -Message ('Windows App Runtime 1.8 ready: ' + $after.InstalledVersion) -Level 'DEPLOY'
        return $after
    } finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }
}

function New-GSAppInstallerDependencyWorkspace {
    $archiveUri = 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip'
    $archive = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-WinGetDependencies-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $extract = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-WinGetDependencies-' + [Guid]::NewGuid().ToString('N'))

    try {
        Download-GSFileWithRetry -Uri $archiveUri -Destination $archive -MinimumBytes 10240
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

        return [pscustomobject]@{
            Archive = $archive
            Root = $extract
        }
    } catch {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Remove-GSAppInstallerDependencyWorkspace {
    param([object]$Workspace)

    if ($null -eq $Workspace) { return }

    if ($Workspace.PSObject.Properties.Name -contains 'Archive') {
        Remove-Item -LiteralPath ([string]$Workspace.Archive) -Force -ErrorAction SilentlyContinue
    }
    if ($Workspace.PSObject.Properties.Name -contains 'Root') {
        Remove-Item -LiteralPath ([string]$Workspace.Root) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-GSVersionFromDependencyFileName {
    param([Parameter(Mandatory=$true)][string]$Path)

    $name = [IO.Path]::GetFileName($Path)
    $versionMatches = [regex]::Matches($name,'(?<![0-9])([0-9]+(?:\.[0-9]+){3})(?![0-9])')
    if ($versionMatches.Count -eq 0) { return $null }

    return ConvertTo-GSVersionSafe -Value ([string]$versionMatches[0].Groups[1].Value)
}

function Test-GSVCLibsFileNameForPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('Microsoft.VCLibs.140.00','Microsoft.VCLibs.140.00.UWPDesktop')][string]$PackageName
    )

    $fileName = [IO.Path]::GetFileName($Path)

    if ($PackageName -eq 'Microsoft.VCLibs.140.00') {
        return ($fileName -match '(?i)^Microsoft\.VCLibs\.140\.00_' -and
                $fileName -notmatch '(?i)^Microsoft\.VCLibs\.140\.00\.UWPDesktop_')
    }

    return ($fileName -match '(?i)^Microsoft\.VCLibs\.140\.00\.UWPDesktop_')
}

function Select-GSVCLibsDependencyCandidate {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,
        [Parameter(Mandatory=$true)][ValidateSet('Microsoft.VCLibs.140.00','Microsoft.VCLibs.140.00.UWPDesktop')][string]$PackageName,
        [Parameter(Mandatory=$true)][ValidateSet('x64','x86','arm64')][string]$Architecture,
        [AllowEmptyString()][string]$MinimumVersion = ''
    )

    $minimum = ConvertTo-GSVersionSafe -Value $MinimumVersion
    $candidateList = New-Object 'System.Collections.Generic.List[object]'
    $archPattern = '(?i)(?:^|[\\/_\.-])' + [regex]::Escape($Architecture) + '(?:[\\/_\.-]|$)'

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        if (-not (Test-GSVCLibsFileNameForPackage -Path ([string]$path) -PackageName $PackageName)) { continue }
        if ([string]$path -notmatch $archPattern) { continue }

        $version = Get-GSVersionFromDependencyFileName -Path ([string]$path)
        if ($null -eq $version) { continue }
        if ($null -ne $minimum -and $version -lt $minimum) { continue }

        [void]$candidateList.Add([pscustomobject]@{
            Path = [string]$path
            PackageName = $PackageName
            Version = $version
            Architecture = $Architecture
        })
    }

    if ($candidateList.Count -eq 0) { return $null }

    return @($candidateList.ToArray() | Sort-Object Version -Descending)[0]
}

function Install-GSVCLibsFramework {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Microsoft.VCLibs.140.00','Microsoft.VCLibs.140.00.UWPDesktop')][string]$PackageName,
        [AllowEmptyString()][string]$MinimumVersion = '',
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot
    )

    $arch = Get-GSSystemArchitectureToken
    $existing = Get-GSFrameworkPackageStatus -Name $PackageName -MinimumVersion $MinimumVersion -Architecture $arch
    if ($existing.Ready) {
        Write-GSLog -Message ($PackageName + ' already satisfies requirement. Installed=' + $existing.InstalledVersion + '; required=' + $MinimumVersion) -Level 'INFO'
        return $existing
    }

    $paths = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.appx','.msix') } |
        ForEach-Object { [string]$_.FullName })

    $candidate = Select-GSVCLibsDependencyCandidate `
        -Paths $paths `
        -PackageName $PackageName `
        -Architecture $arch `
        -MinimumVersion $MinimumVersion

    if ($null -eq $candidate) {
        throw (New-GSClassifiedException -Code 'DependencyMissing' -Message ('No compatible ' + $PackageName + ' package for architecture=' + $arch + '; minimum=' + $MinimumVersion + ' was found in DesktopAppInstaller_Dependencies.zip.'))
    }

    Write-GSLog -Message ('Selected dependency: ' + $candidate.Path + '; version=' + $candidate.Version) -Level 'DEPLOY'
    Assert-GSMicrosoftSignedFile -Path $candidate.Path -Label ($PackageName + ' ' + [string]$candidate.Version)
    Add-AppxPackage -Path $candidate.Path -ErrorAction Stop

    $after = Get-GSFrameworkPackageStatus -Name $PackageName -MinimumVersion $MinimumVersion -Architecture $arch
    if (-not $after.Ready) {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message ($PackageName + ' installation completed but the required framework version was not detected. Installed=' + $after.InstalledVersion + '; required=' + $MinimumVersion))
    }

    Write-GSLog -Message ($PackageName + ' ready: ' + $after.InstalledVersion) -Level 'DEPLOY'
    return $after
}

function Invoke-GSAppInstallerDependencyRecovery {
    param(
        [Parameter(Mandatory=$true)][object]$Request,
        [object]$DependencyWorkspace = $null
    )

    switch ([string]$Request.Name) {
        'Microsoft.WindowsAppRuntime.1.8' {
            $status = Install-GSWindowsAppRuntime18 -MinimumVersion ([string]$Request.MinimumVersion)
            return [pscustomobject]@{
                Handled = $true
                Workspace = $DependencyWorkspace
                Status = $status
            }
        }

        'Microsoft.VCLibs.140.00' {
            if ($null -eq $DependencyWorkspace) {
                $DependencyWorkspace = New-GSAppInstallerDependencyWorkspace
            }
            $status = Install-GSVCLibsFramework `
                -PackageName 'Microsoft.VCLibs.140.00' `
                -MinimumVersion ([string]$Request.MinimumVersion) `
                -WorkspaceRoot ([string]$DependencyWorkspace.Root)

            return [pscustomobject]@{
                Handled = $true
                Workspace = $DependencyWorkspace
                Status = $status
            }
        }

        'Microsoft.VCLibs.140.00.UWPDesktop' {
            if ($null -eq $DependencyWorkspace) {
                $DependencyWorkspace = New-GSAppInstallerDependencyWorkspace
            }
            $status = Install-GSVCLibsFramework `
                -PackageName 'Microsoft.VCLibs.140.00.UWPDesktop' `
                -MinimumVersion ([string]$Request.MinimumVersion) `
                -WorkspaceRoot ([string]$DependencyWorkspace.Root)

            return [pscustomobject]@{
                Handled = $true
                Workspace = $DependencyWorkspace
                Status = $status
            }
        }

        default {
            return [pscustomobject]@{
                Handled = $false
                Workspace = $DependencyWorkspace
                Status = $null
            }
        }
    }
}

function Invoke-GSAppInstallerDeployment {
    param([Parameter(Mandatory=$true)][string]$BundlePath)

    # Enough room for a dependency chain such as:
    # WindowsAppRuntime -> VCLibs base -> VCLibs UWPDesktop -> App Installer.
    $maxCycles = 6
    $dependencyWorkspace = $null
    $recovered = New-Object 'System.Collections.Generic.List[object]'
    $handledKeys = @{}

    try {
        for ($cycle = 1; $cycle -le $maxCycles; $cycle++) {
            try {
                Write-GSLog -Message ('App Installer deployment cycle ' + $cycle + '/' + $maxCycles) -Level 'DEPLOY'
                $command = Get-Command Add-AppxPackage -ErrorAction Stop
                $parameters = @{
                    Path = $BundlePath
                    ErrorAction = 'Stop'
                }

                if ($command.Parameters.ContainsKey('ForceApplicationShutdown')) {
                    $parameters['ForceApplicationShutdown'] = $true
                }

                Add-AppxPackage @parameters

                return [pscustomobject]@{
                    Cycles = $cycle
                    RecoveredDependencies = @($recovered.ToArray())
                }
            } catch {
                $message = [string]$_.Exception.Message
                Write-GSLog -Message ('App Installer deployment failed: ' + $message) -Level 'WARN'

                $request = Get-GSDeploymentDependencyRequest -Message $message
                if ($null -ne $request) {
                    $key = ([string]$request.Name).ToLowerInvariant() + '|' + [string]$request.MinimumVersion
                    if ($handledKeys.ContainsKey($key)) {
                        throw (New-GSClassifiedException -Code 'DependencyMissing' -Message ('Dependency is still reported after recovery: ' + $request.Name + ' >= ' + $request.MinimumVersion))
                    }

                    Write-GSLog -Message ('Dependency requested by App Installer: ' + $request.Name + '; minimum=' + $request.MinimumVersion + '; architecture=' + $request.Architecture) -Level 'DEPLOY'
                    $recovery = Invoke-GSAppInstallerDependencyRecovery -Request $request -DependencyWorkspace $dependencyWorkspace
                    $dependencyWorkspace = $recovery.Workspace

                    if (-not $recovery.Handled) {
                        throw (New-GSClassifiedException -Code 'DependencyMissing' -Message ('Unsupported App Installer dependency: ' + $request.Name + ' >= ' + $request.MinimumVersion))
                    }

                    $handledKeys[$key] = $true
                    [void]$recovered.Add([pscustomobject]@{
                        Name = [string]$request.Name
                        RequiredVersion = [string]$request.MinimumVersion
                        InstalledVersion = [string]$recovery.Status.InstalledVersion
                        Architecture = [string]$recovery.Status.Architecture
                    })
                    continue
                }

                if ($message -match '(?i)dependency') {
                    throw (New-GSClassifiedException -Code 'DependencyMissing' -Message ('Unrecognized App Installer dependency failure: ' + $message))
                }

                throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message $message)
            }
        }

        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'App Installer deployment exceeded dependency recovery cycles.')
    } finally {
        Remove-GSAppInstallerDependencyWorkspace -Workspace $dependencyWorkspace
    }
}

function Get-GSRepairPostCheckPlan {
    return [pscustomobject]@{
        SourceList = @('source','list')
        WingetSearch = @{ Query='WhatsApp'; Source='winget' }
        StoreSearch = @{ Query='WhatsApp'; Source='msstore' }
        AggregateSearch = @{ Query='WhatsApp'; Source='' }
    }
}

function Test-GSWingetRepairSearch {
    param([Parameter(Mandatory=$true)][string]$Query,[string]$Source='')
    try {
        $rows = @(Search-GSWinget -Query $Query -Source $Source -AcceptAgreements $false)
        return [pscustomobject]@{
            Status = if ($rows.Count -gt 0) { 'SearchVerified' } else { 'NoResults' }
            Count = $rows.Count
            ErrorCode = ''
            Message = if ($rows.Count -gt 0) { 'Search returned package results.' } else { 'Search completed but returned no packages.' }
        }
    } catch {
        $classification = ConvertFrom-GSException -Exception $_.Exception
        $status = if ($classification.Code -eq 'SourceAgreementsRequired') { 'RequiresConsent' } else { 'Unavailable' }
        return [pscustomobject]@{
            Status = $status
            Count = 0
            ErrorCode = [string]$classification.Code
            Message = [string]$classification.UserMessage
        }
    }
}

function Repair-GSWinget {
    $beforePackage = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    $beforeVersion = if ($beforePackage) { [string]$beforePackage.Version } else { '' }
    $beforeWinget = Get-GSWingetVersion
    $deployment = $null

    # Repair only a missing package/executable. A healthy App Installer is not
    # downloaded and redeployed merely because the user opened this action.
    if (-not $beforePackage -or -not $beforeWinget) {
        $bundle = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-AppInstaller-' + [Guid]::NewGuid().ToString('N') + '.msixbundle')
        try {
            Download-GSFileWithRetry -Uri 'https://aka.ms/getwinget' -Destination $bundle -MinimumBytes 1048576
            Assert-GSMicrosoftSignedFile -Path $bundle -Label 'Microsoft Desktop App Installer'
            $deployment = Invoke-GSAppInstallerDeployment -BundlePath $bundle
            Clear-GSWingetCache
            Clear-GSInventoryCache
            Start-Sleep -Seconds 2
        } finally {
            Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue
        }
    }

    $afterPackage = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    $afterWinget = Get-GSWingetVersion
    if (-not $afterPackage -or -not $afterWinget) {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'App Installer or the WinGet executable is still unavailable after the targeted repair.')
    }
    if ($beforeWinget -and $afterWinget -lt $beforeWinget) {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'WinGet version decreased after repair.')
    }

    $postCheckPlan = Get-GSRepairPostCheckPlan
    $sourceList = Invoke-GSWinget -Arguments @($postCheckPlan.SourceList) -AllowNonZero -TimeoutSeconds 60
    if ($sourceList.ExitCode -ne 0) {
        throw (New-GSClassifiedException -Code 'NeedsRepair' -Message 'WinGet is present, but its source list cannot be read.')
    }

    # Probe sources separately and through the same aggregate search path as
    # the UI. No source agreement is ever accepted by a repair operation.
    $wingetSearch = Test-GSWingetRepairSearch -Query $postCheckPlan.WingetSearch.Query -Source $postCheckPlan.WingetSearch.Source
    $storeSearch = Test-GSWingetRepairSearch -Query $postCheckPlan.StoreSearch.Query -Source $postCheckPlan.StoreSearch.Source
    $aggregateSearch = Test-GSWingetRepairSearch -Query $postCheckPlan.AggregateSearch.Query -Source $postCheckPlan.AggregateSearch.Source
    $requiredChecks = @($wingetSearch,$storeSearch,$aggregateSearch)
    $allSearchesVerified = @($requiredChecks | Where-Object { $_.Status -ne 'SearchVerified' }).Count -eq 0
    $hasConsentBlock = @(@($storeSearch,$aggregateSearch) | Where-Object { $_.Status -eq 'RequiresConsent' }).Count -gt 0
    $status = if ($allSearchesVerified) { 'RepairVerified' } elseif ($hasConsentBlock -and $wingetSearch.Status -eq 'SearchVerified') { 'RepairPartial' } else { 'RepairIncomplete' }
    $message = switch ($status) {
        'RepairVerified' { 'Проверены WinGet и поиск в каталогах winget и Microsoft Store. Установка, службы развёртывания Store и запуск приложений не проверялись.'; break }
        'RepairPartial' { 'WinGet and winget search work. Microsoft Store search needs explicit source-agreement consent; no agreement was accepted automatically.'; break }
        default { 'WinGet repair checks did not verify every required search path. See per-source results.' }
    }

    return [pscustomobject]@{
        Success = ($status -ne 'RepairIncomplete')
        Status = $status
        Message = $message
        VerificationScope = 'CLIAndSearchOnly'
        InstallationStatus = 'NotTested'
        LaunchStatus = 'NotTested'
        StoreDeploymentStatus = 'NotTested'
        RepairApplied = ($null -ne $deployment)
        BeforeAppInstaller = $beforeVersion
        AfterAppInstaller = [string]$afterPackage.Version
        BeforeWinGet = if ($beforeWinget) { [string]$beforeWinget } else { '' }
        AfterWinGet = [string]$afterWinget
        SourceListExitCode = [int]$sourceList.ExitCode
        Sources = [pscustomobject]@{ Winget = $wingetSearch; MicrosoftStore = $storeSearch; Aggregate = $aggregateSearch }
        DependencyRecovery = $deployment
    }
}

function Assert-GSLocalPackage {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (New-GSClassifiedException -Code 'PackageNotFound' -Message ('Local package not found: ' + $Path))
    }

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.appx','.msix','.appxbundle','.msixbundle')) {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message ('Unsupported package extension: ' + $extension))
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        throw (New-GSClassifiedException -Code 'SignatureInvalid' -Message ('Local package signature status: ' + $signature.Status))
    }

    return $signature
}

function Get-GSAppxSnapshot {
    $map = @{}
    foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
        $map[[string]$package.PackageFullName] = [string]$package.Version
    }
    return $map
}

function Install-GSLocalPackage {
    param([Parameter(Mandatory=$true)][string]$Path)

    $signature = Assert-GSLocalPackage -Path $Path
    $before = Get-GSAppxSnapshot

    Write-GSLog -Message ('Installing local signed package. Signer=' + $signature.SignerCertificate.Subject) -Level 'DEPLOY'

    try {
        Add-AppxPackage -Path (Resolve-Path -LiteralPath $Path).Path -ErrorAction Stop
    } catch {
        $message = [string]$_.Exception.Message
        if ($message -match '(?i)dependency') {
            throw (New-GSClassifiedException -Code 'DependencyMissing' -Message $message)
        }
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message $message)
    }

    Start-Sleep -Milliseconds 400
    $after = Get-GSAppxSnapshot

    $newPackages = @($after.Keys | Where-Object { -not $before.ContainsKey($_) })
    $changed = @()

    foreach ($key in $after.Keys) {
        if ($before.ContainsKey($key) -and $before[$key] -ne $after[$key]) {
            $changed += [pscustomobject]@{
                PackageFullName = $key
                Before = $before[$key]
                After = $after[$key]
            }
        }
    }

    if ($newPackages.Count -eq 0 -and $changed.Count -eq 0) {
        return [pscustomobject]@{
            Verified = $false
            NewPackages = @()
            ChangedPackages = @()
        }
    }

    return [pscustomobject]@{
        Verified = $true
        NewPackages = $newPackages
        ChangedPackages = $changed
    }
}

