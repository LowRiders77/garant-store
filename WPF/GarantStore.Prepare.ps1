# Garant Store - system preparation: everything WinGet and Microsoft Store
# installs need, checked and fixed in a fixed order before the first install.
# Windows PowerShell 5.1 compatible. ASCII-only source.
#
# Field evidence (Nov 2026): a fresh Windows 11 ships App Installer 1.21 with
# WinGet 1.6, whose msstore source fails with 0x8a15005e (pinned certificate);
# a fresh Windows 10 has no WinGet at all and its App Installer needs VCLibs /
# UI.Xaml / Windows App Runtime frameworks first.

Set-StrictMode -Version Latest

# Oldest WinGet verified against the current msstore source in Windows CI.
$script:GSMinimumWingetVersion = [version]'1.11.0'
$script:GSStoreProbeId = '9NKSQGP7F2NH'
# UI.Xaml is not listed: WinGet 1.10+ no longer depends on it and the current
# DesktopAppInstaller_Dependencies.zip does not ship it (field: "still missing UIXaml").
$script:GSRequiredFrameworks = @(
    [pscustomobject]@{ Name = 'Microsoft.VCLibs.140.00.UWPDesktop'; Label = 'VCLibs' },
    [pscustomobject]@{ Name = 'Microsoft.WindowsAppRuntime.1.8'; Label = 'WindowsAppRuntime' }
)

function Test-GSStoreCertificateFailure {
    param([string]$Text)
    return ([string]$Text -match '(?i)0x8a15005e|server certificate did not match|InternetOpenUrl.*certificate')
}

function Get-GSStoreSourceProbe {
    # Classifies the msstore source without accepting anything:
    # Ok | NeedsConsent | CertificateError | NetworkError | Unavailable | NoWinget
    # Uses `winget show` (what installs use); `search --id` returns "no packages"
    # for Store IDs on current WinGet and was misread as a broken source.
    param([bool]$AcceptAgreements = $false, [int]$TimeoutSeconds = 60, [int]$Attempts = 3)
    $exe = Get-GSWingetPath
    if (-not $exe) { return [pscustomobject]@{ Status = 'NoWinget'; Detail = 'WinGet is not installed.' } }
    $arguments = @('show','--id',$script:GSStoreProbeId,'--source','msstore','--disable-interactivity')
    if ($AcceptAgreements) { $arguments += '--accept-source-agreements' }
    $last = [pscustomobject]@{ Status = 'Unavailable'; Detail = 'not checked' }
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $capture = Invoke-GSNativeProcess -FileName $exe -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
        } catch {
            $last = [pscustomobject]@{ Status = 'Unavailable'; Detail = $_.Exception.Message }
            continue
        }
        $text = [string]$capture.StdOut + [Environment]::NewLine + [string]$capture.StdErr
        if (Test-GSStoreCertificateFailure $text) { return [pscustomobject]@{ Status = 'CertificateError'; Detail = '0x8a15005e: msstore certificate rejected by this WinGet version.' } }
        if ([int]$capture.ExitCode -eq 0 -and $text -match [regex]::Escape($script:GSStoreProbeId)) { return [pscustomobject]@{ Status = 'Ok'; Detail = '' } }
        $agreement = Get-GSWingetAgreementRequirement -ExitCode ([int]$capture.ExitCode) -StdOut ([string]$capture.StdOut) -StdErr ([string]$capture.StdErr)
        if ($agreement -eq 'Source') { return [pscustomobject]@{ Status = 'NeedsConsent'; Detail = 'msstore source terms not accepted yet.' } }
        $code = [regex]::Match($text,'(?i)0x[0-9a-f]{8}').Value
        if (Test-GSNetworkFailureText $text) {
            $last = [pscustomobject]@{ Status = 'NetworkError'; Detail = ('Connection to Microsoft Store failed (' + $(if ($code) { $code } else { 'exit ' + $capture.ExitCode }) + ').') }
        } else {
            $last = [pscustomobject]@{ Status = 'Unavailable'; Detail = ('Exit ' + $capture.ExitCode + $(if ($code) { ' ' + $code } else { '' })) }
        }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds (3 * $attempt) }
    }
    return $last
}

function Get-GSFrameworkState {
    $result = New-Object 'System.Collections.Generic.List[object]'
    $arch = Get-GSSystemArchitectureToken
    foreach ($framework in $script:GSRequiredFrameworks) {
        $installed = $false
        $version = ''
        try {
            $package = @(Get-AppxPackage -Name $framework.Name -ErrorAction Stop |
                Where-Object { Test-GSFrameworkArchitectureCompatible -PackageArchitecture ([string]$_.Architecture) -RequiredArchitecture $arch } |
                Sort-Object Version -Descending | Select-Object -First 1)
            if ($package.Count) { $installed = $true; $version = [string]$package[0].Version }
        } catch {}
        [void]$result.Add([pscustomobject]@{ Name = $framework.Name; Label = $framework.Label; Installed = $installed; Version = $version })
    }
    return @($result.ToArray())
}

function Get-GSGpuVendorHint {
    # Pure: discrete GPU vendor from adapter names ('' for integrated only).
    param([string[]]$Names = @())
    foreach ($name in @($Names)) {
        $n = [string]$name
        if ($n -match '(?i)NVIDIA|GeForce|Quadro|RTX|GTX') { return 'NVIDIA' }
        if ($n -match '(?i)Radeon\s*(\(TM\)\s*)?(RX|Pro|HD\s*[5-9]\d{3}|R[579])' -and $n -notmatch '(?i)Vega\s*\d+\s*Graphics|Radeon\(TM\)\s*Graphics') { return 'AMD' }
        if ($n -match '(?i)Intel.*Arc\s*A\d') { return 'Intel' }
    }
    return ''
}

function Get-GSHardwareHints {
    $gpuNames = @()
    $isLaptop = $false
    $ramGb = 0
    $gpuVendors = @()
    try {
        $controllers = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
        $gpuNames = @($controllers | ForEach-Object { [string]$_.Name })
        $gpuVendors = @($controllers | ForEach-Object { if ([string]$_.PNPDeviceID -match '^PCI\\VEN_([0-9A-Fa-f]{4})') { $Matches[1].ToUpperInvariant() } } | Select-Object -Unique)
    } catch {}
    # Vendor control panels (desktop right-click entry) present for this user?
    $panels = @()
    foreach ($pair in @(@('10DE','NVIDIACorp.NVIDIAControlPanel'),@('8086','AppUp.IntelGraphicsExperience'),@('1002','AdvancedMicroDevicesInc-RSXCM'))) {
        try { if (@(Get-AppxPackage -Name $pair[1] -ErrorAction Stop).Count) { $panels += $pair[0] } } catch {}
    }
    if ($env:ProgramFiles) {
        if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'NVIDIA Corporation\Control Panel Client\nvcplui.exe')) { $panels += '10DE' }
        if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe')) { $panels += '1002' }
    }
    try { $isLaptop = (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0) } catch {}
    try { $ramGb = [int][Math]::Round(([double](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory) / 1GB) } catch {}
    return [pscustomobject]@{
        DiscreteGpu = Get-GSGpuVendorHint -Names $gpuNames
        GpuVendors = @($gpuVendors)
        GpuPanels = @($panels | Select-Object -Unique)
        IsLaptop = $isLaptop
        RamGB = $ramGb
        Is64Bit = [Environment]::Is64BitOperatingSystem
    }
}

function Get-GSPreparationState {
    # Fast, side-effect free snapshot used at startup and before installs.
    param([switch]$SkipStoreProbe)
    $path = Get-GSWingetPath
    $version = if ($path) { Get-GSWingetVersion } else { $null }
    $appInstaller = ''
    try { $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1; if ($pkg) { $appInstaller = [string]$pkg.Version } } catch {}
    $wingetStatus = if (-not $path -or -not $version) { 'Missing' } elseif ($version -lt $script:GSMinimumWingetVersion) { 'Outdated' } else { 'Ok' }
    $frameworks = @(Get-GSFrameworkState)
    $missingFrameworks = @($frameworks | Where-Object { -not $_.Installed } | ForEach-Object { $_.Label })
    $store = if ($SkipStoreProbe -or $wingetStatus -eq 'Missing') { [pscustomobject]@{ Status = $(if ($wingetStatus -eq 'Missing') { 'NoWinget' } else { 'NotChecked' }); Detail = '' } } else { Get-GSStoreSourceProbe }
    $disabledServices = @()
    try {
        $filter = "Name='wuauserv' OR Name='BITS' OR Name='InstallService' OR Name='ClipSVC' OR Name='AppXSvc'"
        $disabledServices = @(Get-CimInstance Win32_Service -Filter $filter -ErrorAction Stop | Where-Object { [string]$_.StartMode -eq 'Disabled' } | ForEach-Object { [string]$_.Name })
    } catch {}
    $blocking = ($wingetStatus -ne 'Ok' -or $store.Status -eq 'CertificateError')
    return [pscustomobject]@{
        Ready = (-not $blocking)
        WingetStatus = $wingetStatus
        WingetVersion = if ($version) { [string]$version } else { '' }
        MinimumWingetVersion = [string]$script:GSMinimumWingetVersion
        AppInstallerVersion = $appInstaller
        StoreSource = [string]$store.Status
        StoreSourceDetail = [string]$store.Detail
        MissingFrameworks = $missingFrameworks
        Frameworks = $frameworks
        DisabledStoreServices = $disabledServices
        Hardware = Get-GSHardwareHints
    }
}

function Assert-GSPreparedForInstall {
    # Cheap pre-flight before any install: an old or missing WinGet must be
    # fixed by the preparation flow, not discovered half-way through.
    $path = Get-GSWingetPath
    if (-not $path) { throw (New-GSClassifiedException -Code 'NeedsPreparation' -Message 'WinGet is not installed.') }
    $version = Get-GSWingetVersion
    if ($null -eq $version) { throw (New-GSClassifiedException -Code 'NeedsPreparation' -Message 'WinGet version could not be read.') }
    if ($version -lt $script:GSMinimumWingetVersion) {
        throw (New-GSClassifiedException -Code 'NeedsPreparation' -Message ('WinGet ' + $version + ' is older than ' + $script:GSMinimumWingetVersion + '; the Microsoft Store source rejects it (0x8a15005e).'))
    }
}

function Get-GSFrameworkPackageInfo {
    # Microsoft.UI.Xaml.2.8_8.2310.30001.0_x64.appx -> name, version, arch
    param([Parameter(Mandatory=$true)][string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $match = [regex]::Match($name, '^(?<name>[A-Za-z0-9.]+?)_(?<version>\d+(?:\.\d+){1,3})_(?<arch>x64|x86|arm64|arm|neutral)')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{ Name = $match.Groups['name'].Value; Version = ConvertTo-GSVersionSafe -Value $match.Groups['version'].Value; Architecture = $match.Groups['arch'].Value; Path = $Path }
}

function Install-GSAppInstallerFrameworks {
    # Installs, ahead of App Installer, every framework package shipped in
    # DesktopAppInstaller_Dependencies.zip that this PC lacks or has older.
    # Doing it first avoids the 0x80073CF3 retry cycles seen in the field.
    param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)
    $arch = Get-GSSystemArchitectureToken
    $installed = New-Object 'System.Collections.Generic.List[object]'
    $files = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.appx','.msix') })
    $candidates = @($files | ForEach-Object { Get-GSFrameworkPackageInfo -Path $_.FullName } | Where-Object { $null -ne $_ -and $null -ne $_.Version -and (Test-GSFrameworkArchitectureCompatible -PackageArchitecture $_.Architecture -RequiredArchitecture $arch) })
    foreach ($group in @($candidates | Group-Object Name)) {
        $best = @($group.Group | Sort-Object Version -Descending)[0]
        $status = Get-GSFrameworkPackageStatus -Name $best.Name -MinimumVersion ([string]$best.Version) -Architecture $arch
        if ($status.Ready) { continue }
        Write-GSProgress -Stage 'InstallingFramework' -Indeterminate $true -Detail $best.Name
        try {
            Assert-GSMicrosoftSignedFile -Path $best.Path -Label ($best.Name + ' ' + [string]$best.Version)
            Add-AppxPackage -Path $best.Path -ErrorAction Stop
            [void]$installed.Add($best.Name + ' ' + [string]$best.Version)
            Write-GSLog -Message ('Framework installed ahead of App Installer: ' + $best.Name + ' ' + $best.Version) -Level 'DEPLOY'
        } catch {
            # 0x80073D06: a higher version is already present - not a problem.
            if ([string]$_.Exception.Message -notmatch '(?i)0x80073D06') {
                Write-GSLog -Message ('Framework pre-install failed (deployment will retry reactively): ' + $best.Name + ' - ' + $_.Exception.Message) -Level 'WARN'
            }
        }
    }
    return @($installed.ToArray())
}

function Install-GSLatestAppInstaller {
    # Downloads the current App Installer bundle with visible progress, puts its
    # frameworks in place first and deploys it; dependency recovery stays as a
    # fallback for anything the archive does not cover.
    $bundle = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-AppInstaller-' + [Guid]::NewGuid().ToString('N') + '.msixbundle')
    $workspace = $null
    try {
        Write-GSProgress -Stage 'DownloadingDependencies' -Indeterminate $true -Detail 'DesktopAppInstaller_Dependencies.zip'
        try {
            $workspace = New-GSAppInstallerDependencyWorkspace
            $frameworks = @(Install-GSAppInstallerFrameworks -WorkspaceRoot ([string]$workspace.Root))
        } catch {
            Write-GSLog -Message ('Dependency archive unavailable; App Installer deployment will recover dependencies reactively: ' + $_.Exception.Message) -Level 'WARN'
            $frameworks = @()
        }
        $runtime = @(Get-GSFrameworkState | Where-Object { $_.Name -eq 'Microsoft.WindowsAppRuntime.1.8' -and -not $_.Installed })
        if ($runtime.Count) {
            try { [void](Install-GSWindowsAppRuntime18); $frameworks += 'Microsoft.WindowsAppRuntime.1.8' } catch { Write-GSLog -Message ('Windows App Runtime 1.8 pre-install failed: ' + $_.Exception.Message) -Level 'WARN' }
        }
        Download-GSFileWithRetry -Uri 'https://aka.ms/getwinget' -Destination $bundle -MinimumBytes 1048576 -Label 'App Installer (WinGet)'
        Assert-GSMicrosoftSignedFile -Path $bundle -Label 'Microsoft Desktop App Installer'
        Write-GSProgress -Stage 'InstallingAppInstaller' -Indeterminate $true -Detail 'Microsoft.DesktopAppInstaller'
        $deployment = Invoke-GSAppInstallerDeployment -BundlePath $bundle
        Clear-GSWingetCache
        Clear-GSInventoryCache
        Start-Sleep -Seconds 2
        return [pscustomobject]@{ Frameworks = $frameworks; Deployment = $deployment }
    } finally {
        Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($bundle + '.partial') -Force -ErrorAction SilentlyContinue
        if ($null -ne $workspace) { Remove-GSAppInstallerDependencyWorkspace -Workspace $workspace }
    }
}

function Invoke-GSSystemPreparation {
    # Fixed order: WinGet -> frameworks -> sources -> Microsoft Store terms.
    # Each step reports Ok / Done / Failed / Skipped; later steps still run so the
    # user sees the whole picture.
    param([bool]$AcceptStoreTerms = $false)
    $steps = New-Object 'System.Collections.Generic.List[object]'
    function Add-Step([string]$Id,[string]$Status,[string]$Detail) { [void]$steps.Add([pscustomobject]@{ Id = $Id; Status = $Status; Detail = $Detail }) }

    $before = Get-GSPreparationState -SkipStoreProbe

    # 1. WinGet / App Installer.
    Write-GSProgress -Stage 'PrepareWinget' -Indeterminate $true -Detail ([string]$before.WingetVersion)
    if ($before.WingetStatus -eq 'Ok') {
        Add-Step 'winget' 'Ok' ('WinGet ' + $before.WingetVersion)
    } else {
        try {
            $update = Install-GSLatestAppInstaller
            $afterVersion = Get-GSWingetVersion
            if ($null -eq $afterVersion -or $afterVersion -lt $script:GSMinimumWingetVersion) {
                throw ('WinGet is still ' + $(if ($afterVersion) { [string]$afterVersion } else { 'missing' }) + ' after the update.')
            }
            Add-Step 'winget' 'Done' ('WinGet ' + $before.WingetVersion + ' -> ' + $afterVersion + '; frameworks: ' + (@($update.Frameworks) -join ', '))
        } catch {
            Add-Step 'winget' 'Failed' $_.Exception.Message
        }
    }

    # 2. Frameworks used by Store apps (WhatsApp and other WinUI apps fail to start without them).
    Write-GSProgress -Stage 'PrepareFrameworks' -Indeterminate $true -Detail ''
    $missing = @(Get-GSFrameworkState | Where-Object { -not $_.Installed })
    if (-not $missing.Count) {
        Add-Step 'frameworks' 'Ok' 'All frameworks present.'
    } else {
        $workspace = $null
        $failures = New-Object 'System.Collections.Generic.List[string]'
        try {
            if (@($missing | Where-Object { $_.Name -ne 'Microsoft.WindowsAppRuntime.1.8' }).Count) {
                try { $workspace = New-GSAppInstallerDependencyWorkspace; [void](Install-GSAppInstallerFrameworks -WorkspaceRoot ([string]$workspace.Root)) } catch { [void]$failures.Add('dependency archive: ' + $_.Exception.Message) }
            }
            if (@($missing | Where-Object { $_.Name -eq 'Microsoft.WindowsAppRuntime.1.8' }).Count) {
                try { [void](Install-GSWindowsAppRuntime18) } catch { [void]$failures.Add('Windows App Runtime 1.8: ' + $_.Exception.Message) }
            }
        } finally {
            if ($null -ne $workspace) { Remove-GSAppInstallerDependencyWorkspace -Workspace $workspace }
        }
        $still = @(Get-GSFrameworkState | Where-Object { -not $_.Installed } | ForEach-Object { $_.Label })
        if ($still.Count) { Add-Step 'frameworks' 'Failed' ('Still missing: ' + ($still -join ', ') + '. ' + ($failures -join '; ')) }
        else { Add-Step 'frameworks' 'Done' ('Installed: ' + (@($missing | ForEach-Object { $_.Label }) -join ', ')) }
    }

    # 3. Sources: refresh, then make sure the Microsoft Store source opens.
    Write-GSProgress -Stage 'PrepareSources' -Indeterminate $true -Detail 'winget source update'
    $exe = Get-GSWingetPath
    if (-not $exe) {
        Add-Step 'sources' 'Skipped' 'WinGet is unavailable.'
    } else {
        try { [void](Invoke-GSWinget -Arguments @('source','update','--disable-interactivity') -AllowNonZero -SuppressOutput -TimeoutSeconds 120) } catch {}
        $probe = Get-GSStoreSourceProbe -AcceptAgreements $AcceptStoreTerms
        if ($probe.Status -eq 'CertificateError') {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if ($isAdmin) {
                try { [void](Invoke-GSWinget -Arguments @('source','reset','--force','--disable-interactivity') -AllowNonZero -SuppressOutput -TimeoutSeconds 120) } catch {}
                $probe = Get-GSStoreSourceProbe -AcceptAgreements $AcceptStoreTerms
            }
        }
        switch ([string]$probe.Status) {
            'Ok' { Add-Step 'sources' $(if ($AcceptStoreTerms) { 'Done' } else { 'Ok' }) 'Microsoft Store source responds.' }
            'NeedsConsent' { Add-Step 'sources' 'Skipped' 'Microsoft Store terms were not accepted; the source will ask on first use.' }
            'NetworkError' { Add-Step 'sources' 'Failed' ('NetworkFailure: ' + [string]$probe.Detail) }
            default { Add-Step 'sources' 'Failed' ([string]$probe.Status + ': ' + [string]$probe.Detail) }
        }
    }

    # 4. Store services are changed only temporarily, per install, with consent.
    $disabled = @($before.DisabledStoreServices)
    Add-Step 'services' $(if ($disabled.Count) { 'Info' } else { 'Ok' }) ($disabled -join ', ')

    Clear-GSWingetCache
    $after = Get-GSPreparationState -SkipStoreProbe
    $failed = @($steps | Where-Object { $_.Status -eq 'Failed' })
    return [pscustomobject]@{
        Ready = ($after.WingetStatus -eq 'Ok' -and -not @($failed | Where-Object { $_.Id -in @('winget','sources') }).Count)
        Steps = @($steps.ToArray())
        Before = $before
        After = $after
    }
}
