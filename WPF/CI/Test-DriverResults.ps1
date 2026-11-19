# Regressions from field diagnostics (NoviSea / Asus, 9 Nov 2026):
#  - Selected.ps1 crashed with 'instanceId not found' under the strict mode that
#    UpdateCatalog.ps1 enables, when devices.json held a row without that field;
#  - Windows Update driver offers refused with 0x80070103 were counted as errors.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
function Import-GSFunction([string]$File,[string]$Name){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($File,[ref]$t,[ref]$e)
 $f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
 if(-not $f){throw ($Name+' is missing from '+$File)}
 return $f.Extent.Text
}
. ([scriptblock]::Create((Import-GSFunction (Join-Path $project 'DriverEngine\Core.ps1') 'Get-RemainingSelectedProblemDevices')))
. ([scriptblock]::Create((Import-GSFunction (Join-Path $project 'DriverEngine\UpdateCatalog.ps1') 'Get-GSWuaInstallOutcome')))
. ([scriptblock]::Create((Import-GSFunction (Join-Path $project 'DriverEngine\UpdateCatalog.ps1') 'Format-GSHResult')))

$rows=@([pscustomobject]@{instanceId='A';kind='Missing'},[pscustomobject]@{status='no identity'},$null,[pscustomobject]@{instanceId='B';kind='Inventory'},[pscustomobject]@{instanceId='C'},[pscustomobject]@{instanceId='D';kind='GPU'})
$remaining=@(Get-RemainingSelectedProblemDevices $rows @('A','B','C','D'))
if($remaining.Count -ne 2 -or ($remaining.instanceId -join ',') -ne 'A,D'){throw ('Strict-mode remaining-device filter returned: '+(($remaining|ForEach-Object{$_.instanceId}) -join ','))}

if((Get-GSWuaInstallOutcome 2 0) -ne 'Installed' -or (Get-GSWuaInstallOutcome 3 0) -ne 'Installed'){throw 'Succeeded WU results were not treated as installed'}
if((Get-GSWuaInstallOutcome 4 -2147024637) -ne 'NotNeeded'){throw '0x80070103 (better driver already installed) was treated as a failure'}
if((Get-GSWuaInstallOutcome 4 -2145124329) -ne 'Failed'){throw 'A real WU failure was hidden'}
if((Format-GSHResult -2147024637) -ne '0x80070103'){throw ('HRESULT formatting is wrong: '+(Format-GSHResult -2147024637))}

$updates=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Updates.ps1') -Raw -Encoding UTF8
if($updates -match "Осталось предложений Windows Update: '\+\`$remaining\.Count\)"){throw 'Remaining Windows Update offers are reported as the operation result again'}
if($updates -match 'installResult\.ResultCode -notin'){throw 'The batch WU result code aborts the run before per-update evaluation'}
Write-Host 'Driver result gate passed: strict-mode safe remaining-device filter, per-update WU evaluation, 0x80070103 not an error.'
