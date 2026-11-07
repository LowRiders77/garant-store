[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Deployment.ps1')

$script:storePolicies=[pscustomobject]@{RemoveWindowsStore=$null;DisableWindowsUpdateAccess=$null;DoNotConnectToWindowsUpdateInternetLocations=$null;SetDisableUXWUAccess=$null}
$script:serviceRows=@()
$script:mutationCount=0
function Write-GSProgress{}
function Write-GSLog{}
function Get-GSStoreServiceSnapshot{return @($script:serviceRows)}
function Get-GSStorePolicySnapshot{return $script:storePolicies}
function Get-GSDeliveryOptimizationConfig{return [pscustomobject]@{Available=$true;DownloadMode='CdnOnly'}}
function Set-Service{$script:mutationCount++}
function Start-Service{$script:mutationCount++}

function Assert-StoreError([string]$Expected,[scriptblock]$Action){
 $actual=''
 try{& $Action}catch{if($_.Exception.Message -match '^GSERR:([^:]+):'){$actual=$Matches[1]}else{throw}}
 if($actual -cne $Expected){throw ('Expected '+$Expected+', got '+$actual)}
}

$script:serviceRows=@(
 [pscustomobject]@{Name='wuauserv';State='Stopped';StartMode='Disabled'},
 [pscustomobject]@{Name='BITS';State='Stopped';StartMode='Manual'},
 [pscustomobject]@{Name='InstallService';State='Stopped';StartMode='Manual'},
 [pscustomobject]@{Name='ClipSVC';State='Stopped';StartMode='Manual'},
 [pscustomobject]@{Name='AppXSvc';State='Running';StartMode='Manual'},
 [pscustomobject]@{Name='DoSvc';State='Stopped';StartMode='Manual'}
)
$script:storePolicies.DisableWindowsUpdateAccess=1
Assert-StoreError 'StorePolicyBlocked' {Ensure-GSStoreServicePrerequisites -AllowServiceChanges:$true}
if($script:mutationCount -ne 0){throw 'Windows Update policy was bypassed by mutating services.'}
$policyResult=ConvertFrom-GSException (New-GSClassifiedException -Code 'StorePolicyBlocked' -Message 'DisableWindowsUpdateAccess=1')
$expectedPolicyText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0L/QvtC70LjRgtC40LrQvtC5IFdpbmRvd3M='))
$expectedFallbackText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('V2hhdHNBcHAgV2Vi'))
if($policyResult.Status -ne 'BlockedByPolicy' -or $policyResult.UserMessage -notlike ('*'+$expectedPolicyText+'*') -or $policyResult.UserMessage -notlike ('*'+$expectedFallbackText+'*')){throw 'Store policy block does not provide a safe, actionable user message.'}
$result=New-GSResult -Success $false -Status $policyResult.Status -ErrorCode $policyResult.Code -Message $policyResult.UserMessage -TechnicalMessage $policyResult.TechnicalMessage -PackageId '9NKSQGP7F2NH' -Source 'msstore'
if($result.PackageId -ne '9NKSQGP7F2NH' -or $result.Source -ne 'msstore'){throw 'A blocked Store install lost the exact package identity or source in its diagnostic result.'}
$repairSource=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\WindowsUpdateRepair.ps1') -Raw -Encoding UTF8
$policyCheck=$repairSource.IndexOf('DisableWindowsUpdateAccess')
$serviceMutation=$repairSource.IndexOf("Set-Service -Name `$name")
if($policyCheck -lt 0 -or $serviceMutation -lt 0 -or $policyCheck -gt $serviceMutation -or $repairSource -notmatch 'DisableWindowsUpdateAccess=1'){throw 'The explicit Windows Update repair action does not stop before service changes when the admin policy blocks access.'}

$script:storePolicies.DisableWindowsUpdateAccess=$null
Assert-StoreError 'StoreServiceConsentRequired' {Ensure-GSStoreServicePrerequisites}
if($script:mutationCount -ne 0){throw 'Services changed before explicit user consent.'}

Write-Host 'Store service policy and explicit-consent gate passed.'
