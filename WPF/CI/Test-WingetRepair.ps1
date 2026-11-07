[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Winget.ps1')
. (Join-Path $project 'GarantStore.Deployment.ps1')

function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected '+$Expected+', got '+$Actual)} }
function Get-AppxPackage { param([string]$Name,[string]$ErrorAction) [pscustomobject]@{Version='1.29.290.0'} }
function Get-GSWingetVersion { return [version]'1.29.290' }
function Invoke-GSWinget { param([string[]]$Arguments,[switch]$AllowNonZero,[int]$TimeoutSeconds) [pscustomobject]@{ExitCode=0;StdOut='Name Source';StdErr=''} }
function Download-GSFileWithRetry { throw 'Healthy WinGet must not be downloaded again.' }
function Assert-GSMicrosoftSignedFile { throw 'Healthy WinGet must not be redeployed.' }
function Invoke-GSAppInstallerDeployment { throw 'Healthy WinGet must not be redeployed.' }
$script:storeNeedsConsent=$true
function Search-GSWinget {
 param([string]$Query,[string]$Source,[bool]$AcceptAgreements)
 if($AcceptAgreements){throw 'Repair must never consent automatically.'}
 if($Source -eq 'winget'){return @([pscustomobject]@{Id='WhatsApp.WhatsApp';Name='WhatsApp'})}
 if($script:storeNeedsConsent){throw (New-GSClassifiedException -Code 'SourceAgreementsRequired' -Message 'Consent is required.')}
 return @([pscustomobject]@{Id='9NKSQGP7F2NH';Name='WhatsApp'})
}
$partial=Repair-GSWinget
Assert-Equal 'healthy package was not redeployed' $false $partial.RepairApplied
Assert-Equal 'working winget source verified' 'SearchVerified' $partial.Sources.Winget.Status
Assert-Equal 'Store consent reported explicitly' 'RequiresConsent' $partial.Sources.MicrosoftStore.Status
Assert-Equal 'aggregate consent reported explicitly' 'RequiresConsent' $partial.Sources.Aggregate.Status
Assert-Equal 'partial result not represented as complete repair' 'RepairPartial' $partial.Status

$script:storeNeedsConsent=$false
$complete=Repair-GSWinget
Assert-Equal 'all three real search paths required' 'RepairVerified' $complete.Status
Assert-Equal 'repair only verifies CLI and search' 'CLIAndSearchOnly' $complete.VerificationScope
Assert-Equal 'search does not prove installation' 'NotTested' $complete.InstallationStatus
Assert-Equal 'search does not prove activation' 'NotTested' $complete.LaunchStatus
Write-Host 'WinGet repair scope and no-unnecessary-reinstall checks passed.'
