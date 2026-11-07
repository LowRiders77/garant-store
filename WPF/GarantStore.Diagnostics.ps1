# Garant Store v0.8 DEV - Diagnostics
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

function Get-GSDoctorData {
    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}

    $wingetVersion = Get-GSWingetVersion
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    $sources = Get-GSWingetSources

    $services = @()
    foreach ($serviceName in @('wuauserv','BITS','UsoSvc','AppXSvc','ClipSVC','InstallService','DoSvc')) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $services += [pscustomobject]@{
                Name = $serviceName
                Status = [string]$service.Status
                StartType = [string]$service.StartType
            }
        } catch {
            $services += [pscustomobject]@{
                Name = $serviceName
                Status = 'Unavailable'
                StartType = ''
            }
        }
    }

    $runtimePackages = @(Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.*' -ErrorAction SilentlyContinue |
        Sort-Object Name,Version | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                Version = [string]$_.Version
                Architecture = [string]$_.Architecture
                Status = [string]$_.Status
            }
        })

    $vclibs = @(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00*' -ErrorAction SilentlyContinue |
        Sort-Object Name,Version | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                Version = [string]$_.Version
                Architecture = [string]$_.Architecture
                Status = [string]$_.Status
            }
        })

    $systemDriveFree = ''
    try {
        $driveName = $env:SystemDrive.TrimEnd(':')
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        $systemDriveFree = [Math]::Round($drive.Free / 1GB,2)
    } catch {}

    return [pscustomobject]@{
        WindowsVersion = [Environment]::OSVersion.VersionString
        WindowsBuild = if ($os) { [string]$os.BuildNumber } else { '' }
        OSEdition = if ($os) { [string]$os.Caption } else { '' }
        OSArchitecture = if ($os) { [string]$os.OSArchitecture } else { '' }
        Process64Bit = [Environment]::Is64BitProcess
        OS64Bit = [Environment]::Is64BitOperatingSystem
        PowerShellVersion = [string]$PSVersionTable.PSVersion
        DotNetVersion = [string][Environment]::Version
        IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        WinGetPath = [string](Get-GSWingetPath)
        WinGetVersion = if ($wingetVersion) { [string]$wingetVersion } else { '' }
        AppInstallerVersion = if ($appInstaller) { [string]$appInstaller.Version } else { '' }
        AppInstallerStatus = if ($appInstaller) { [string]$appInstaller.Status } else { '' }
        Sources = $sources
        Services = $services
        StorePolicies = Get-GSStorePolicySnapshot
        DeliveryOptimization = Get-GSDeliveryOptimizationConfig
        WindowsAppRuntime = $runtimePackages
        VCLibs = $vclibs
        SystemDriveFreeGB = $systemDriveFree
        AgreementModel = 'Explicit per-operation confirmation'
        PerformanceCache = Get-GSCacheStats
    }
}

function Write-GSDoctorLog {
    param([Parameter(Mandatory=$true)][object]$Doctor)

    Write-GSLog -Message ('Windows=' + $Doctor.WindowsVersion + '; build=' + $Doctor.WindowsBuild + '; arch=' + $Doctor.OSArchitecture) -Level 'INFO'
    Write-GSLog -Message ('PowerShell=' + $Doctor.PowerShellVersion + '; .NET=' + $Doctor.DotNetVersion + '; admin=' + $Doctor.IsAdmin) -Level 'INFO'
    Write-GSLog -Message ('WinGet=' + $Doctor.WinGetVersion + '; AppInstaller=' + $Doctor.AppInstallerVersion) -Level 'INFO'
    Write-GSLog -Message ('System drive free GB=' + $Doctor.SystemDriveFreeGB) -Level 'INFO'
}


function Get-GSAppActivationDiagnostics {
    $packages = @(Get-AppxPackage -Name '*WhatsApp*' -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ Name=[string]$_.Name; PackageFullName=[string]$_.PackageFullName; Version=[string]$_.Version; Architecture=[string]$_.Architecture; Status=[string]$_.Status }
    })
    $channels = @()
    foreach ($channel in @('Microsoft-Windows-AppModel-Runtime/Admin','Microsoft-Windows-TWinUI/Operational','Microsoft-Windows-AppXDeploymentServer/Operational','Application')) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{LogName=$channel;StartTime=(Get-Date).AddHours(-2);Level=@(2,3)} -MaxEvents 50 -ErrorAction Stop |
                Where-Object { $_.Message -match '(?i)WhatsApp' } | ForEach-Object {
                    [pscustomobject]@{Time=$_.TimeCreated.ToString('o');Id=$_.Id;Provider=$_.ProviderName;Message=$_.Message}
                })
            $channels += [pscustomobject]@{Channel=$channel;Status='Read';Events=$events;Error=''}
        } catch {
            $noEvents=([string]$_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*')
            $channels += [pscustomobject]@{Channel=$channel;Status=$(if($noEvents){'NoRecentEvents'}else{'Unavailable'});Events=@();Error=$(if($noEvents){''}else{$_.Exception.Message})}
        }
    }
    return [pscustomobject]@{Context='Current process user; no automatic activation';LaunchStatus='NotTested';LookbackHours=2;MaxEventsPerChannel=50;Packages=$packages;Channels=$channels}
}

function New-GSDiagnosticsArchive {
    param(
        [Parameter(Mandatory=$true)][string]$Version,
        [object]$BuildInfo = $null
    )

    $ctx = Get-GSContext
    $doctor = Get-GSDoctorData
    Write-GSDoctorLog -Doctor $doctor

    $zip = Join-Path ([string]$ctx.Root) ('diagnostics-{0}.zip' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-diag-' + [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Get-GSAppActivationDiagnostics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'app-activation.json') -Encoding UTF8
        $appLogs = Join-Path $stage 'GarantStore'
        $wingetLogs = Join-Path $stage 'WinGet'
        New-Item -ItemType Directory -Force -Path $appLogs | Out-Null
        New-Item -ItemType Directory -Force -Path $wingetLogs | Out-Null

        foreach ($file in @(Get-ChildItem -LiteralPath ([string]$ctx.Logs) -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 40)) {
            Copy-Item -LiteralPath $file.FullName -Destination $appLogs -Force -ErrorAction SilentlyContinue
        }

        $nativeDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
        if (Test-Path -LiteralPath $nativeDir) {
            foreach ($file in @(Get-ChildItem -LiteralPath $nativeDir -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 30)) {
                Copy-Item -LiteralPath $file.FullName -Destination $wingetLogs -Force -ErrorAction SilentlyContinue
            }
        }

        $summary = [ordered]@{
            Schema = 1
            GarantStoreVersion = $Version
            BuildInfo = $BuildInfo
            Created = (Get-Date -Format o)
            OperationId = [string]$ctx.OperationId
            Doctor = $doctor
        }

        $summaryJson = ConvertTo-Json -InputObject $summary -Depth 12
        [IO.File]::WriteAllText((Join-Path $stage 'summary.json'),$summaryJson,(New-Object Text.UTF8Encoding($false)))

        $lastResult = Join-Path ([string]$ctx.Root) 'last-result.json'
        if (Test-Path -LiteralPath $lastResult -PathType Leaf) {
            Copy-Item -LiteralPath $lastResult -Destination (Join-Path $stage 'last-result.json') -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $zip) {
            Remove-Item -LiteralPath $zip -Force
        }

        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        Write-GSLog -Message ('Diagnostics ZIP created: ' + $zip) -Level 'INFO'

        return [pscustomobject]@{
            Path = $zip
            Doctor = $doctor
        }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
