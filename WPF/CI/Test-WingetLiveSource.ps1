[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Parser.ps1')
. (Join-Path $project 'GarantStore.Winget.ps1')

$exe=Get-GSWingetPath
if(-not $exe){throw 'RELEASE GATE BLOCKED: WinGet is not installed or registered for this CI user.'}
$version=Get-GSWingetVersion
if(-not $version){throw 'RELEASE GATE BLOCKED: WinGet executable did not return a valid version.'}
$sources=@(Get-GSWingetSources | ForEach-Object { [string]$_.Name })
foreach($required in @('winget','msstore')){
 if($sources -notcontains $required){throw ('RELEASE GATE BLOCKED: required WinGet source is unavailable: '+$required)}
}
$evidence=Join-Path (Split-Path -Parent $PSScriptRoot) 'CI-output'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$checks=@()
foreach($source in @('winget','msstore','')){
 try{
  # This is isolated test-user setup. The application still requires explicit consent.
  $rows=@(Search-GSWinget -Query 'WhatsApp' -Source $source -AcceptAgreements $true)
  $valid=@($rows|Where-Object{$_.Id -and $_.Source})
  if($valid.Count -lt 1){throw 'WinGet returned no parseable package rows.'}
  if($source -and @($valid|Where-Object{$_.Source -eq $source}).Count -lt 1){throw ('No rows mapped to requested source '+$source)}
  $checks+=([pscustomobject]@{Source=$(if($source){$source}else{'aggregate'});Rows=$rows.Count;MappedRows=$valid.Count;Status='passed'})
  Write-Host ('LIVE WINGET SEARCH PASSED: source='+$(if($source){$source}else{'aggregate'})+'; rows='+$valid.Count)
 }catch{
  $checks+=([pscustomobject]@{Source=$(if($source){$source}else{'aggregate'});Status='failed';Error=$_.Exception.Message})
  $checks|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $evidence 'winget-live-search.json') -Encoding UTF8
  throw ('Live WhatsApp search failed for '+$(if($source){$source}else{'aggregate'})+': '+$_.Exception.Message)
 }
}
$checks|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $evidence 'winget-live-search.json') -Encoding UTF8
Write-Host ('LIVE WINGET GATE PASSED: version='+$version+'; sources=winget,msstore; direct and aggregate WhatsApp queries parsed.')
