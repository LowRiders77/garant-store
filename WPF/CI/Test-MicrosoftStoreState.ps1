[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Parser.ps1')
. (Join-Path $project 'GarantStore.State.ps1')
. (Join-Path $project 'GarantStore.Store.ps1')

function Assert-Equal {
    param([string]$Name,[object]$Expected,[object]$Actual)
    if ($Expected -cne $Actual) {
        throw ($Name+': expected "'+[string]$Expected+'", got "'+[string]$Actual+'"')
    }
}

$script:testQuery=$null
function Get-GSWingetExactListQueryResult {
    param([string]$Id,[string]$Source,[bool]$AcceptAgreements)
    return $script:testQuery
}

$id='Garant.Test.StoreApp'
$row=[pscustomobject]@{Name='Test Store App';Id=$id;Source='msstore';Version='99.0.0.0'}

# A successful exact list row with no Available version means no update.
# The catalog version from search must not turn this into a false update.
$script:testQuery=[pscustomobject]@{Texts=@('Test Store App '+$id+' 1.0.0.0 msstore');ConfirmedAbsent=$false}
$state=Get-GSStoreSearchRowState -SearchRow $row
Assert-Equal 'exact current Store app' 'Installed' $state.Status
Assert-Equal 'installed Store version' '1.0.0.0' $state.InstalledVersion
Assert-Equal 'no available Store update' '' $state.AvailableVersion

$snapshot=[pscustomobject]@{Reliable=$true;Text='Test Store App '+$id+' 1.0.0.0 msstore'}
$state=Resolve-GSStoreSearchRowFromSnapshot -SearchRow $row -Snapshot $snapshot
Assert-Equal 'batch current Store app' 'Installed' $state.Status

# A newer Available column is the only positive update signal.
$script:testQuery=[pscustomobject]@{Texts=@('Test Store App '+$id+' 1.0.0.0 2.0.0.0 msstore');ConfirmedAbsent=$false}
$state=Get-GSStoreSearchRowState -SearchRow $row
Assert-Equal 'new Store update' 'UpdateAvailable' $state.Status
Assert-Equal 'available Store version' '2.0.0.0' $state.AvailableVersion

# Unknown versions remain explicitly unknown and are not treated as equal.
$script:testQuery=[pscustomobject]@{Texts=@('Test Store App '+$id+' Unknown msstore');ConfirmedAbsent=$false}
$state=Get-GSStoreSearchRowState -SearchRow $row
Assert-Equal 'unknown Store version' 'StoreUpdateUnknown' $state.Status
Assert-Equal 'unknown equals unknown' 'Unknown' (Compare-GSVersionValues -Installed 'Unknown' -Available 'Unknown')

$script:exactState=[pscustomobject]@{Status='Installed';InstalledVersion='1.0.0.0';AvailableVersion='';StateOrigin='test'}
$script:serviceRepairCalled=$false
function Confirm-GSWingetPackage { return $true }
function Write-GSLog { }
function Write-GSProgress { }
function Get-GSExactPackageState { return $script:exactState }
function Ensure-GSStoreServicePrerequisites { $script:serviceRepairCalled=$true; throw 'Already current must not start deployment' }

# A stale search result marked StoreUpdateUnknown must still be re-checked.
# If the exact list says Installed, return a no-op success and never upgrade.
$pipeline=Invoke-GSStorePackagePipeline -Id $id -Name 'Test Store App' -KnownStatus 'StoreUpdateUnknown' -AvailableVersion 'Unknown' -AgreementConsent $true
Assert-Equal 'stale unknown resolves current' 'AlreadyCurrent' $pipeline.Outcome
Assert-Equal 'current app launches no repair/deployment' $false $script:serviceRepairCalled
Assert-Equal 'current app performs no action' 'none' $pipeline.Command

$script:exactState=[pscustomobject]@{Status='StoreUpdateUnknown';InstalledVersion='Unknown';AvailableVersion='';StateOrigin='test'}
$pipeline=Invoke-GSStorePackagePipeline -Id $id -Name 'Test Store App' -KnownStatus 'StoreUpdateUnknown' -AvailableVersion 'Unknown' -AgreementConsent $true
Assert-Equal 'unknown update is reported without action' 'StoreUpdateUnknown' $pipeline.Outcome
Assert-Equal 'unknown app performs no action' 'none' $pipeline.Command

Write-Host 'Microsoft Store installed/current/update state checks passed.'
