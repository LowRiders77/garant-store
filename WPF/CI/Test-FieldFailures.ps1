# Field failures from the 10 Nov 2026 diagnostics:
#  - Store download cut off (0x80d03805) and SSL/WinHTTP errors were shown as
#    "WinGet error" / "package not found" with no way to continue;
#  - WinGet listed "Windows Desktop Runtime 8.0.33" under the WebView2 ID, so a
#    successful WebView2 install failed verification;
#  - WhatsApp was installed but registered with Windows after the check ran.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
foreach($m in @('Common','Progress','Parser','Winget','State','Deployment','Store','Bundles','Diagnostics','SystemSummary')){. (Join-Path $project ('GarantStore.'+$m+'.ps1'))}
function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected <'+$Expected+'>, got <'+$Actual+'>')} }
function Assert-Throws { param([string]$Name,[scriptblock]$Block,[string]$Pattern) try{& $Block}catch{if($_.Exception.Message -notmatch $Pattern){throw ($Name+': wrong error: '+$_.Exception.Message)};return}; throw ($Name+': no exception') }
function Start-Sleep { param([int]$Seconds,[int]$Milliseconds) }
$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-field-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
if(-not $env:LOCALAPPDATA){$env:LOCALAPPDATA=$work}
Initialize-GSContext -OutputFile (Join-Path $work 'out.log') -Action 'test' -OperationId 'TEST-FIELD'

# --- Network failures --------------------------------------------------------
Assert-Equal 'store download stall' $true (Test-GSNetworkFailureText 'Код ошибки: 0x80d03805')
Assert-Equal 'ssl channel' $true (Test-GSNetworkFailureText 'SSL Error: WINHTTP_CALLBACK_STATUS_FLAG_SECURITY_CHANNEL_ERROR internal error. 0x8a15003b')
Assert-Equal 'certificate pin is not network' $false (Test-GSNetworkFailureText '0x8a15005e : The server certificate did not match')
Assert-Equal 'plain failure is not network' $false (Test-GSNetworkFailureText 'Installer failed with exit code: 1603')
$net=ConvertFrom-GSException -Exception ([Exception]::new('GSERR:NetworkFailure:Connection lost'))
Assert-Equal 'network status' 'NetworkUnavailable' $net.Status
if($net.UserMessage -notmatch 'интернет'){throw ('network message must be Russian and actionable: '+$net.UserMessage)}
$generic=ConvertFrom-GSException -Exception ([Exception]::new('GSERR:DeploymentFailure:x'))
if($generic.UserMessage -match '^[A-Za-z ]+\.?$'){throw 'user messages must be Russian'}

$script:nativeExit=-2133837819
$script:nativeOut='Найдено WhatsApp [9NKSQGP7F2NH]'+"`n"+'Не удалось установить или обновить пакет Microsoft Store. Код ошибки: 0x80d03805'
function Get-GSWingetPath { 'C:\winget.exe' }
function Invoke-GSNativeProcess { param([string]$FileName,[string[]]$Arguments,[int]$TimeoutSeconds,[string]$TelemetryKind='None') [pscustomobject]@{ExitCode=$script:nativeExit;StdOut=$script:nativeOut;StdErr='';ElapsedSeconds=1;Telemetry=$null} }
Assert-Throws 'install stall -> NetworkFailure' { Invoke-GSWinget -Arguments @('install','--id','9NKSQGP7F2NH','--source','msstore') -SuppressOutput } '^GSERR:NetworkFailure:.*0x80d03805'
$script:nativeExit=-1978335173;$script:nativeOut='SSL Error: WINHTTP_CALLBACK_STATUS_FLAG_SECURITY_CHANNEL_ERROR internal error.'+"`n"+'0x8a15003b : Внутренняя ошибка REST API'
Assert-Throws 'show ssl -> NetworkFailure (not PackageNotFound)' { Confirm-GSWingetPackage -Id '9NKSQGP7F2NH' -Source 'msstore' -AcceptAgreements $true } '^GSERR:NetworkFailure:'
$script:nativeExit=1;$script:nativeOut='No results'
$search=Invoke-GSWinget -Arguments @('search','x') -AllowNonZero -SuppressOutput
Assert-Equal 'search keeps its own handling' 1 $search.ExitCode

# --- Known-package presence ---------------------------------------------------
$script:webviewPv=''
$script:appx=$null
$script:wingetCalls=0
function Get-ItemProperty { [CmdletBinding()]param([string]$LiteralPath,[string]$Name) if($LiteralPath -like '*WOW6432Node*F3017226*' -and $script:webviewPv){return [pscustomobject]@{pv=$script:webviewPv}}; throw 'absent' }
function Get-AppxPackage { [CmdletBinding()]param([string]$Name) if($Name -eq '5319275A.WhatsAppDesktop' -and $script:appx){return [pscustomobject]@{Name=$Name;Version=$script:appx}}; return $null }
function Get-GSExactPackageStateFromWinget { param([string]$Id,[string]$Source,[bool]$AcceptAgreements) $script:wingetCalls++
 # What WinGet really returned for WebView2: the .NET Desktop Runtime row.
 if($Id -eq 'Microsoft.EdgeWebView2Runtime'){return [pscustomobject]@{Status='UpdateAvailable';InstalledVersion='8.0.33.36622';AvailableVersion='157.0.4341.42';StateOrigin='exact-winget-list'}}
 return [pscustomobject]@{Status='NotInstalled';InstalledVersion='';AvailableVersion='';StateOrigin='exact-winget-no-applications-found'} }

$absent=Get-GSExactPackageState -Id 'Microsoft.EdgeWebView2Runtime' -Source 'winget'
Assert-Equal 'webview2 absent by registry' 'NotInstalled' $absent.Status
Assert-Equal 'absence does not ask winget' 0 $script:wingetCalls
$script:webviewPv='157.0.4341.42'
$present=Get-GSExactPackageState -Id 'Microsoft.EdgeWebView2Runtime' -Source 'winget'
Assert-Equal 'webview2 installed despite wrong winget row' 'Installed' $present.Status
Assert-Equal 'webview2 real version' '157.0.4341.42' $present.InstalledVersion
$script:webviewPv='140.0.1.1'
Assert-Equal 'older webview2 -> update' 'UpdateAvailable' (Get-GSExactPackageState -Id 'Microsoft.EdgeWebView2Runtime' -Source 'winget').Status
Assert-Equal 'unknown package -> winget path' 'NotInstalled' (Get-GSExactPackageState -Id '7zip.7zip' -Source 'winget').Status

# Bundle state uses the same correction.
$script:webviewPv='157.0.4341.42'
function Get-GSInstalledInventory { param([bool]$AcceptAgreements,[string]$Source,[switch]$Force) [pscustomobject]@{Map=@{};RawListSuccess=$true} }
function Resolve-GSPackageState { param($SearchRow,$Inventory) [pscustomobject]@{Status='UpdateAvailable';InstalledVersion='8.0.33.36622';AvailableVersion='157.0.4341.42';StateOrigin='inventory'} }
$rows=@(Add-GSPackageStates -Rows @([pscustomobject]@{Name='WebView2';Id='Microsoft.EdgeWebView2Runtime';Version='157.0.4341.42';Match='';Source='winget'}))
Assert-Equal 'bundle row corrected' 'Installed' $rows[0].Status

# --- Store registration delay (WhatsApp) -----------------------------------------
$script:appx=$null
$script:checks=0
function Confirm-GSWingetPackage { param([string]$Id,[string]$Source,[bool]$AcceptAgreements) $true }
function Ensure-GSStoreServicePrerequisites { param([bool]$AllowServiceChanges) $null }
function Ensure-GSAgreementCapabilities { param([string]$Command) $true }
function Invoke-GSWingetPackageAction { param([string]$Command,[string]$Id,[string]$Source,[bool]$AgreementConsent,[switch]$Silent) [pscustomobject]@{ElapsedSeconds=200;Telemetry=$null} }
function Clear-GSInventoryCache { $script:checks++; if($script:checks -ge 3){$script:appx='2.2546.3.0'} }
$store=Invoke-GSStorePackagePipeline -Id '9NKSQGP7F2NH' -Name 'WhatsApp' -AgreementConsent $true
Assert-Equal 'late Store registration accepted' 'InstalledVerified' $store.Outcome
Assert-Equal 'verified through Appx' 'appx-package' $store.After.StateOrigin

# --- One-file diagnostics -------------------------------------------------------
function Get-GSDoctorData { [pscustomobject]@{Ok=$true} }
function Write-GSDoctorLog { param($Doctor) }
function Get-GSAppActivationDiagnostics { @() }
function Get-GSSummaryRaw { [pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Model='Vivobook Go E1504FA_E1504FA';Version='';Board='';ComputerName='X';PcSystemType=2;CpuName='';Cores=0;Threads=0;Gpus=@();MemoryModules=@();Disks=@();Panels=@();Battery=[pscustomobject]@{Present=$false;DesignCapacity=0;FullChargeCapacity=0;CycleCount=0;ChargePercent=-1}} }
$diag=New-GSDiagnosticsArchive -Version '0.0.0-test'
try{
 $name=[IO.Path]::GetFileName($diag.Path)
 if($name -notmatch '^Garant-Diagnostics - ASUS Vivobook Go E1504FA - \d{4}-\d{2}-\d{2} \d{2}-\d{2}\.zip$'){throw ('diagnostics name: '+$name)}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($diag.Path)
 try{
  $entries=@($zip.Entries|ForEach-Object{$_.FullName})
  if($entries -notcontains 'summary.json'){throw ('summary.json missing: '+($entries -join ', '))}
  if(@($entries|Where-Object{$_ -like '*\*'}).Count){throw 'zip entries must use forward slashes'}
 }finally{$zip.Dispose()}
}finally{Remove-Item -LiteralPath $diag.Path -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'Field failure gate passed: network classification, Russian messages, WebView2/WhatsApp verification, Store registration delay, one-file diagnostics.'
