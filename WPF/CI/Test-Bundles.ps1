# Bundles gate: Bundles.json schema and the sequential install queue (mocked installs).
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Parser.ps1')
. (Join-Path $project 'GarantStore.Bundles.ps1')

# 1. Schema: every bundle is usable and every item has an exact identity.
$data=Get-Content -LiteralPath (Join-Path $project 'Bundles.json') -Raw -Encoding UTF8|ConvertFrom-Json
$bundles=@($data.Bundles)
if($bundles.Count -lt 4){throw ('Expected at least 4 bundles, found '+$bundles.Count)}
$bundleIds=@{}
foreach($bundle in $bundles){
 foreach($field in @('Id','Title','Description','Items')){if(-not $bundle.PSObject.Properties[$field]){throw ('Bundle is missing '+$field)}}
 if($bundleIds.ContainsKey([string]$bundle.Id)){throw ('Duplicate bundle id '+$bundle.Id)};$bundleIds[[string]$bundle.Id]=$true
 $items=@($bundle.Items)
 if($items.Count -lt 3 -or $items.Count -gt 40){throw ('Bundle '+$bundle.Id+' has '+$items.Count+' items')}
 if(@($items|Where-Object{[bool]$_.Default}).Count -eq 0){throw ('Bundle '+$bundle.Id+' preselects nothing')}
 $seen=@{}
 foreach($item in $items){
  if(-not (Test-GSValidPackageId -Id ([string]$item.Id))){throw ('Invalid package id in '+$bundle.Id+': '+$item.Id)}
  if([string]$item.Source -notin @('winget','msstore')){throw ('Invalid source in '+$bundle.Id+': '+$item.Source)}
  if([string]::IsNullOrWhiteSpace([string]$item.Name)){throw ('Unnamed item in '+$bundle.Id)}
  if($item.Default -isnot [bool]){throw ('Default must be true/false for '+$item.Id)}
  $key=[string]$item.Source+'|'+([string]$item.Id).ToLowerInvariant()
  if($seen.ContainsKey($key)){throw ('Duplicate item '+$item.Id+' in '+$bundle.Id)};$seen[$key]=$true
 }
}

# 2. Queue: sequential, keeps going after a failure, reports every outcome.
function Write-GSProgress{param([string]$Stage,$Percent,[bool]$Indeterminate,[string]$Detail)}
function Write-GSLog{param([string]$Message,[string]$Level)}
function Restore-GSStoreServiceStartupTypes{$script:restores++}
$script:calls=New-Object System.Collections.Generic.List[string]
$script:restores=0
function Invoke-GSPackageInstall{
 param([string]$Id,[string]$Source,[string]$Name,[string]$KnownStatus,[string]$AvailableVersion,[bool]$AgreementConsent,[bool]$AllowServiceChanges)
 $script:calls.Add($Id)
 switch($Id){
  'Broken.Package'{throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'test failure')}
  '9NKSQGP7F2NH'{if(-not $AllowServiceChanges){throw (New-GSClassifiedException -Code 'StoreServiceConsentRequired' -Message 'services')};return [pscustomobject]@{Status='InstalledVerified';Message='ok';NewVersion='1'}}
  'Present.Package'{return [pscustomobject]@{Status='AlreadyCurrent';Message='present';NewVersion='2'}}
  default{return [pscustomobject]@{Status='InstalledVerified';Message='ok';NewVersion='1'}}
 }
}
$items=@(
 [pscustomobject]@{Name='A';Id='Good.Package';Source='winget'},
 [pscustomobject]@{Name='B';Id='Broken.Package';Source='winget'},
 [pscustomobject]@{Name='C';Id='Present.Package';Source='winget'},
 [pscustomobject]@{Name='W';Id='9NKSQGP7F2NH';Source='msstore'},
 [pscustomobject]@{Name='A again';Id='good.package';Source='winget'}
)
$refused=$false
try{$null=Invoke-GSBundleInstall -Items $items}catch{$refused=($_.Exception.Message -match '^GSERR:PackageAgreementsRequired:')}
if(-not $refused -or $script:calls.Count){throw 'A bundle ran without explicit agreement consent'}
$result=Invoke-GSBundleInstall -Items $items -AgreementConsent $true
if(($script:calls -join ',') -ne 'Good.Package,Broken.Package,Present.Package,9NKSQGP7F2NH'){throw ('Unexpected install order or duplicate install: '+($script:calls -join ','))}
if($result.Total -ne 4 -or $result.Installed -ne 1 -or $result.AlreadyPresent -ne 1 -or $result.Failed -ne 2){throw ('Wrong bundle summary: '+($result|ConvertTo-Json -Compress -Depth 4))}
if(@($result.NeedsServiceConsent).Count -ne 1 -or @($result.NeedsServiceConsent)[0] -ne '9NKSQGP7F2NH'){throw 'Store item needing service consent was not reported for a consented retry'}
$broken=@($result.Items|Where-Object{$_.Id -eq 'Broken.Package'})[0]
if($broken.Outcome -ne 'Failed' -or $broken.ErrorCode -ne 'DeploymentFailure'){throw 'Failed item lost its error classification'}
if($script:restores -ne 4){throw 'Store services were not restored after every bundle item'}
$script:calls.Clear()
$retry=Invoke-GSBundleInstall -Items @($items[3]) -AgreementConsent $true -AllowServiceChanges $true
if($retry.Failed -ne 0 -or $retry.Installed -ne 1){throw 'Consented Store retry did not install the item'}

# 3. Request validation.
foreach($bad in @(@([pscustomobject]@{Name='x';Id='bad id;rm';Source='winget'}),@([pscustomobject]@{Name='x';Id='Good.Package';Source='other'}))){
 $rejected=$false;try{$null=ConvertTo-GSBundleItems -Items $bad}catch{$rejected=$true}
 if(-not $rejected){throw 'An invalid bundle item was accepted'}
}
$tooMany=@(1..41|ForEach-Object{[pscustomobject]@{Name='p';Id=('Pkg.N'+$_);Source='winget'}})
$rejected=$false;try{$null=ConvertTo-GSBundleItems -Items $tooMany}catch{$rejected=$true}
if(-not $rejected){throw 'A bundle above 40 packages was accepted'}

Write-Host ('Bundles gate passed: '+$bundles.Count+' bundles, schema, consent, sequential queue, failure isolation, Store consent retry, service restore, request validation.')
