# Unit gate for system preparation (GarantStore.Prepare.ps1) and the
# NeedsPreparation path. Field cases: fresh Windows 11 with WinGet 1.6 whose
# msstore source fails with 0x8a15005e; Windows 10 without WinGet.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Winget.ps1')
. (Join-Path $project 'GarantStore.Deployment.ps1')
. (Join-Path $project 'GarantStore.Prepare.ps1')

function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected '+$Expected+', got '+$Actual)} }
function Assert-Throws { param([string]$Name,[scriptblock]$Block,[string]$Pattern) try{& $Block}catch{if($_.Exception.Message -notmatch $Pattern){throw ($Name+': wrong error: '+$_.Exception.Message)};return}; throw ($Name+': no exception') }

$certText='Failed when searching source: msstore'+"`n"+'An unexpected error occurred while executing the command:'+"`n"+'0x8a15005e : The server certificate did not match any of the expected values.'

# --- Pure helpers ---------------------------------------------------------
Assert-Equal 'certificate text detected' $true (Test-GSStoreCertificateFailure $certText)
Assert-Equal 'unrelated text ignored' $false (Test-GSStoreCertificateFailure 'No package found matching input criteria.')
$info=Get-GSFrameworkPackageInfo -Path (Join-Path 'x64' 'Microsoft.UI.Xaml.2.8_8.2310.30001.0_x64.appx')
Assert-Equal 'framework name' 'Microsoft.UI.Xaml.2.8' $info.Name
Assert-Equal 'framework version' ([version]'8.2310.30001.0') $info.Version
Assert-Equal 'framework arch' 'x64' $info.Architecture
$vclibs=Get-GSFrameworkPackageInfo -Path 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x86.appx'
Assert-Equal 'vclibs name' 'Microsoft.VCLibs.140.00.UWPDesktop' $vclibs.Name
Assert-Equal 'non-framework file ignored' $null (Get-GSFrameworkPackageInfo -Path 'readme.txt')

$classified=ConvertFrom-GSException -Exception ([Exception]::new($certText))
Assert-Equal 'raw 0x8a15005e classified' 'NeedsPreparation' $classified.Code
Assert-Equal 'raw 0x8a15005e status' 'NeedsPreparation' $classified.Status
if($classified.UserMessage -notmatch 'WinGet'){throw 'NeedsPreparation message must name WinGet.'}

Assert-Equal 'nvidia hint' 'NVIDIA' (Get-GSGpuVendorHint -Names @('Intel(R) UHD Graphics 630','NVIDIA GeForce GTX 1060 6GB'))
Assert-Equal 'amd discrete hint' 'AMD' (Get-GSGpuVendorHint -Names @('AMD Radeon RX 6600'))
Assert-Equal 'amd integrated ignored' '' (Get-GSGpuVendorHint -Names @('AMD Radeon(TM) Graphics'))
Assert-Equal 'intel integrated ignored' '' (Get-GSGpuVendorHint -Names @('Intel(R) Iris(R) Xe Graphics'))

# --- Mocked system --------------------------------------------------------
$script:wingetVersion=[version]'1.6.10121'
$script:wingetPresent=$true
$script:nativeOutput=$certText
$script:nativeExit=-1978335138
$script:frameworks=@{'Microsoft.VCLibs.140.00.UWPDesktop'='14.0.33728.0';'Microsoft.UI.Xaml.2.8'='8.2310.30001.0';'Microsoft.WindowsAppRuntime.1.8'='8000.616.304.0'}
$script:downloads=New-Object 'System.Collections.Generic.List[string]'
$script:deployed=$false
function Get-GSWingetPath { if($script:wingetPresent){'C:\winget.exe'}else{$null} }
function Get-GSWingetVersion { if($script:wingetPresent){$script:wingetVersion}else{$null} }
function Get-GSSystemArchitectureToken { 'x64' }
function Get-AppxPackage {
 param([string]$Name,$ErrorAction)
 if($Name -eq 'Microsoft.DesktopAppInstaller'){ if($script:wingetPresent){return [pscustomobject]@{Version=$(if($script:deployed){'1.29.290.0'}else{'1.21.10120.0'});Architecture='Neutral'}}; return $null }
 if($script:frameworks.ContainsKey($Name)){return [pscustomobject]@{Name=$Name;Version=$script:frameworks[$Name];Architecture='X64'}}
 return $null
}
function Get-CimInstance { param([string]$ClassName,[string]$Filter,$ErrorAction) @() }
function Invoke-GSNativeProcess { param([string]$FileName,[string[]]$Arguments,[int]$TimeoutSeconds,[string]$TelemetryKind='None') [pscustomobject]@{ExitCode=$script:nativeExit;StdOut=$script:nativeOutput;StdErr='';ElapsedSeconds=0.1;Telemetry=$null} }
function Download-GSFileWithRetry { param([string]$Uri,[string]$Destination,[int]$MinimumBytes,[int]$Attempts,[string]$Label) $script:downloads.Add($Uri) }
function Assert-GSMicrosoftSignedFile { param([string]$Path,[string]$Label) }
function Invoke-GSAppInstallerDeployment { param([string]$BundlePath) $script:deployed=$true;$script:wingetVersion=[version]'1.29.290';$script:wingetPresent=$true;[pscustomobject]@{Attempts=1} }
function New-GSAppInstallerDependencyWorkspace { $script:downloads.Add('deps');[pscustomobject]@{Archive='';Root=[IO.Path]::GetTempPath()} }
function Remove-GSAppInstallerDependencyWorkspace { param($Workspace) }
function Install-GSAppInstallerFrameworks { param([string]$WorkspaceRoot) foreach($k in @('Microsoft.VCLibs.140.00.UWPDesktop','Microsoft.UI.Xaml.2.8')){$script:frameworks[$k]='1.0.0.0'}; @('VCLibs','UIXaml') }
function Install-GSWindowsAppRuntime18 { param([string]$MinimumVersion) $script:frameworks['Microsoft.WindowsAppRuntime.1.8']='8000.616.304.0' }
function Clear-GSInventoryCache {}
function Start-Sleep { param([int]$Seconds,[int]$Milliseconds) }

# Asus case: WinGet 1.6, msstore certificate rejected.
$state=Get-GSPreparationState
Assert-Equal 'old winget flagged' 'Outdated' $state.WingetStatus
Assert-Equal 'certificate error surfaced' 'CertificateError' $state.StoreSource
Assert-Equal 'not ready' $false $state.Ready
Assert-Throws 'pre-flight blocks old winget' { Assert-GSPreparedForInstall } '^GSERR:NeedsPreparation:'

# Install against old WinGet: real cause instead of "package not found".
Assert-Throws 'install maps certificate failure' { Invoke-GSWinget -Arguments @('install','--id','9NKSQGP7F2NH','--source','msstore') -AllowNonZero } '^GSERR:NeedsPreparation:'
$script:nativeExit=0;$script:nativeOutput='Name Id Version'
$search=Invoke-GSWinget -Arguments @('search','WhatsApp') -AllowNonZero -SuppressOutput
Assert-Equal 'search unaffected' 0 $search.ExitCode

# Preparation updates WinGet first, then sources.
$script:nativeOutput='WhatsApp 9NKSQGP7F2NH Unknown msstore';$script:nativeExit=0
$result=Invoke-GSSystemPreparation -AcceptStoreTerms $true
Assert-Equal 'prepare ready' $true $result.Ready
Assert-Equal 'step order' 'winget,frameworks,sources,services' (($result.Steps|ForEach-Object{$_.Id}) -join ',')
Assert-Equal 'winget updated' 'Done' $result.Steps[0].Status
Assert-Equal 'frameworks already fine' 'Ok' $result.Steps[1].Status
Assert-Equal 'store source works' 'Done' $result.Steps[2].Status
Assert-Equal 'App Installer downloaded once' 1 @($script:downloads|Where-Object{$_ -eq 'https://aka.ms/getwinget'}).Count
Assert-GSPreparedForInstall

# Healthy system: nothing is downloaded or reinstalled.
$script:downloads.Clear();$script:deployed=$false
$healthy=Invoke-GSSystemPreparation -AcceptStoreTerms $false
Assert-Equal 'healthy winget untouched' 'Ok' $healthy.Steps[0].Status
Assert-Equal 'healthy: no downloads' 0 $script:downloads.Count
Assert-Equal 'healthy: no redeploy' $false $script:deployed

# NoviSea case: Windows 10 without WinGet and without frameworks.
$script:wingetPresent=$false;$script:wingetVersion=$null;$script:downloads.Clear()
$script:frameworks=@{}
$missing=Get-GSPreparationState
Assert-Equal 'missing winget' 'Missing' $missing.WingetStatus
Assert-Equal 'missing frameworks listed (UI.Xaml no longer required)' 'VCLibs,WindowsAppRuntime' ($missing.MissingFrameworks -join ',')
Assert-Throws 'pre-flight blocks missing winget' { Assert-GSPreparedForInstall } '^GSERR:NeedsPreparation:'
$fresh=Invoke-GSSystemPreparation -AcceptStoreTerms $true
Assert-Equal 'fresh: winget installed' 'Done' $fresh.Steps[0].Status
Assert-Equal 'fresh: frameworks before App Installer' 'deps' $script:downloads[0]
Assert-Equal 'fresh: ready' $true $fresh.Ready

# Failure keeps going and reports every step.
$script:wingetPresent=$false;$script:wingetVersion=$null
function Invoke-GSAppInstallerDeployment { param([string]$BundlePath) throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message '0x80073CF3') }
$failed=Invoke-GSSystemPreparation -AcceptStoreTerms $true
Assert-Equal 'failure: not ready' $false $failed.Ready
Assert-Equal 'failure: winget failed' 'Failed' $failed.Steps[0].Status
Assert-Equal 'failure: sources skipped without winget' 'Skipped' $failed.Steps[2].Status
Assert-Equal 'failure: all steps reported' 4 @($failed.Steps).Count

# Repair-GSWinget now also replaces an outdated WinGet.
$script:wingetPresent=$true;$script:wingetVersion=[version]'1.6.10121';$script:downloads.Clear()
function Invoke-GSAppInstallerDeployment { param([string]$BundlePath) $script:deployed=$true;$script:wingetVersion=[version]'1.29.290';[pscustomobject]@{Attempts=1} }
function Invoke-GSWinget { param([string[]]$Arguments,[switch]$AllowNonZero,[switch]$SuppressOutput,[int]$TimeoutSeconds) [pscustomobject]@{ExitCode=0;StdOut='Name Source';StdErr=''} }
function Search-GSWinget { param([string]$Query,[string]$Source,[bool]$AcceptAgreements) @([pscustomobject]@{Id='9NKSQGP7F2NH';Name='WhatsApp'}) }
$repair=Repair-GSWinget
Assert-Equal 'outdated winget redeployed by repair' 1 $script:downloads.Count
Assert-Equal 'repair verified' 'RepairVerified' $repair.Status

# Store probe: network drop is reported as such and retried; a healthy source answers to `show`.
$script:wingetPresent=$true;$script:wingetVersion=[version]'1.29.290'
$script:probeCalls=0
function Invoke-GSNativeProcess { param([string]$FileName,[string[]]$Arguments,[int]$TimeoutSeconds,[string]$TelemetryKind='None') $script:probeCalls++
 if($Arguments[0] -ne 'show'){throw 'probe must use winget show'}
 if($script:probeCalls -lt 3){return [pscustomobject]@{ExitCode=-2147012867;StdOut='WinHttpSendRequest: 12029'+"`n"+'0x80072efd : unknown error';StdErr='';ElapsedSeconds=1;Telemetry=$null}}
 return [pscustomobject]@{ExitCode=0;StdOut='WhatsApp [9NKSQGP7F2NH]';StdErr='';ElapsedSeconds=1;Telemetry=$null} }
Assert-Equal 'probe survives two network drops' 'Ok' (Get-GSStoreSourceProbe).Status
$script:probeCalls=-10
Assert-Equal 'persistent drop is a network error' 'NetworkError' (Get-GSStoreSourceProbe).Status
Write-Host 'System preparation checks passed.'
