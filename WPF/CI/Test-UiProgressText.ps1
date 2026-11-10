# Unit gate for the progress text shown in the status bar: Russian stage names,
# hidden technical tokens, size / speed / time left while downloading.
# Functions are extracted from the UI script by AST; the window is not opened.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'GarantStore.Next.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Get-GSUiObjectValue','Format-GSByteSize','Format-GSEta','Format-GSProgressText','Get-GSPrepareStepText','New-GSRecommendedBundle','Get-GSRetryRequest','Test-GSNetworkRelatedResult')){
 $definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name}.GetNewClosure(),$true)
 if($null -eq $definition){throw ($name+' is missing from the UI script')}
 . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected <'+$Expected+'>, got <'+$Actual+'>')} }
function U([string]$s){[regex]::Unescape($s)}

Assert-Equal 'MB size' ((U '45,2 МБ')) (Format-GSByteSize (45.2*1MB))
Assert-Equal 'GB size' ((U '1,50 ГБ')) (Format-GSByteSize (1.5*1GB))
Assert-Equal 'seconds left' ((U 'осталось ~40 с')) (Format-GSEta 39.2)
Assert-Equal 'no eta for zero' '' (Format-GSEta 0)

$t=Format-GSProgressText ([pscustomobject]@{Stage='Downloading';Detail='App Installer (WinGet)';BytesDownloaded=[double](45.2*1MB);BytesTotal=[double](250*1MB);SpeedBytesPerSecond=[double](6.4*1MB)})
Assert-Equal 'download status' ((U 'Загрузка')) $t.Status
if($t.Detail -notmatch [regex]::Escape((U '45,2 МБ из 250,0 МБ'))){throw ('size missing: '+$t.Detail)}
if($t.Detail -notmatch [regex]::Escape((U '6,4 МБ/с'))){throw ('speed missing: '+$t.Detail)}
if($t.Detail -notmatch (U 'осталось')){throw ('eta missing: '+$t.Detail)}
if($t.Detail -notmatch '^App Installer \(WinGet\)'){throw ('label missing: '+$t.Detail)}

$u2=Format-GSProgressText ([pscustomobject]@{Stage='Downloading';Detail='WinGetDownload';BytesDownloaded=[double](3*1MB);BytesTotal=0;SpeedBytesPerSecond=[double](1*1MB)})
if($u2.Detail -notmatch (U 'Загружено 3,0 МБ')){throw ('unknown-total text: '+$u2.Detail)}
if($u2.Detail -match (U 'осталось')){throw 'eta must not be shown without a total'}

$s=Format-GSProgressText ([pscustomobject]@{Stage='StoreExecution';Detail='MicrosoftStoreBroker'})
Assert-Equal 'store stage localized' ((U 'Связь с Microsoft Store...')) $s.Status
Assert-Equal 'technical token hidden' '' $s.Detail
foreach($stage in @('Starting','CheckingState','ResolvingPackage','StoreHandshake','Authorizing','Services','PreparingInstall','DownloadRetry','DownloadingDependencies','InstallingFramework','InstallingAppInstaller','PrepareWinget','PrepareFrameworks','PrepareSources','Installing','Verifying','Completed','Failed')){
 $x=Format-GSProgressText ([pscustomobject]@{Stage=$stage;Detail=''})
 if($x.Status -cmatch '^[A-Za-z]+$'){throw ('stage not localized: '+$stage)}
}
$step=Get-GSPrepareStepText ([pscustomobject]@{Id='winget';Status='Done';Detail=''})
if($step -notmatch 'WinGet'){throw ('prepare step text: '+$step)}
$desktop=New-GSRecommendedBundle ([pscustomobject]@{Ready=$true;MissingFrameworks=@();Hardware=[pscustomobject]@{DiscreteGpu='NVIDIA';IsLaptop=$false;RamGB=16;Is64Bit=$true}})
$ids=@($desktop.Items|ForEach-Object{$_.Id})
foreach($id in @('Microsoft.VCRedist.2015+.x64','Microsoft.VCRedist.2015+.x86','Microsoft.DotNet.DesktopRuntime.8','Microsoft.EdgeWebView2Runtime','Microsoft.DirectX','7zip.7zip')){if($ids -notcontains $id){throw ('desktop recommendation missing '+$id)}}
if($ids -contains 'Microsoft.WindowsAppRuntime.1.8'){throw 'runtime recommended although present'}
if($desktop.Description -notmatch 'NVIDIA'){throw 'GPU driver hint missing'}
foreach($item in $desktop.Items){if(-not [string]$item.Reason){throw ('reason missing for '+$item.Id)};if([string]$item.Source -ne 'winget'){throw 'unexpected source'}}
$laptop=New-GSRecommendedBundle ([pscustomobject]@{Ready=$false;MissingFrameworks=@('WindowsAppRuntime');Hardware=[pscustomobject]@{DiscreteGpu='';IsLaptop=$true;RamGB=8;Is64Bit=$true}})
$lids=@($laptop.Items|ForEach-Object{$_.Id})
if($lids -contains 'Microsoft.DirectX'){throw 'DirectX recommended without a discrete GPU'}
if($lids -notcontains 'Microsoft.WindowsAppRuntime.1.8'){throw 'missing runtime not recommended'}
if(-not [bool](@($laptop.Items|Where-Object{$_.Id -eq 'CrystalDewWorld.CrystalDiskInfo'})[0].Default)){throw 'disk health tool should be preselected on laptops'}
$x86=New-GSRecommendedBundle ([pscustomobject]@{Ready=$true;MissingFrameworks=@();Hardware=[pscustomobject]@{DiscreteGpu='';IsLaptop=$false;RamGB=4;Is64Bit=$false}})
if(@($x86.Items|Where-Object{$_.Id -eq 'Microsoft.VCRedist.2015+.x64'}).Count){throw 'x64 runtime offered on 32-bit Windows'}
if($null -ne (New-GSRecommendedBundle $null)){throw 'no state must give no card'}
# "Продолжить" after a failure.
$bundleOp=[pscustomobject]@{Action='bundle';Request=@{Action='bundle';AgreementConsent=$true;Items=@(@{Id='Microsoft.VCRedist.2015+.x64';Source='winget';Name='VC'},@{Id='Microsoft.EdgeWebView2Runtime';Source='winget';Name='WebView2'},@{Id='9NKSQGP7F2NH';Source='msstore';Name='WhatsApp'})}}
$bundleResult=[pscustomobject]@{Success=$false;ErrorCode='BundlePartial';Data=[pscustomobject]@{Items=@([pscustomobject]@{Id='Microsoft.VCRedist.2015+.x64';Outcome='InstalledVerified';ErrorCode='';Message=''},[pscustomobject]@{Id='Microsoft.EdgeWebView2Runtime';Outcome='Failed';ErrorCode='NetworkFailure';Message='x'},[pscustomobject]@{Id='9NKSQGP7F2NH';Outcome='Failed';ErrorCode='StoreServiceConsentRequired';Message='y'})}}
$retry=Get-GSRetryRequest $bundleOp $bundleResult
if($null -eq $retry){throw 'failed bundle must be offered to continue'}
Assert-Equal 'only failed items retried' 'Microsoft.EdgeWebView2Runtime' ((@($retry.Items)|ForEach-Object{$_.Id}) -join ',')
Assert-Equal 'original request untouched' 3 @($bundleOp.Request.Items).Count
Assert-Equal 'network detected in bundle' $true (Test-GSNetworkRelatedResult $bundleResult)
$installOp=[pscustomobject]@{Action='install';Request=@{Action='install';Id='9NKSQGP7F2NH';Source='msstore';AgreementConsent=$true}}
$netFail=[pscustomobject]@{Success=$false;ErrorCode='NetworkFailure';TechnicalMessage='Connection lost (0x80d03805)'}
Assert-Equal 'install retried after network loss' '9NKSQGP7F2NH' (Get-GSRetryRequest $installOp $netFail).Id
if($null -ne (Get-GSRetryRequest $installOp ([pscustomobject]@{Success=$false;ErrorCode='PackageAgreementsRequired'}))){throw 'agreement refusal must not be auto-retried'}
if($null -ne (Get-GSRetryRequest $installOp ([pscustomobject]@{Success=$true;ErrorCode=''}))){throw 'success must not offer a retry'}
Assert-Equal 'prepare continued' 'prepare' (Get-GSRetryRequest ([pscustomobject]@{Action='prepare';Request=@{Action='prepare';AgreementConsent=$true}}) ([pscustomobject]@{Success=$false;ErrorCode='PreparationIncomplete'})).Action
Assert-Equal 'non-network failure' $false (Test-GSNetworkRelatedResult ([pscustomobject]@{Success=$false;ErrorCode='DeploymentFailure';TechnicalMessage='exit 1603'}))
Write-Host 'UI progress text, recommendation and retry checks passed.'
