[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$EvidenceRoot,
 [Parameter(Mandatory=$true)][string]$BuildGateResult,
 [Parameter(Mandatory=$true)][string]$UiGateResult,
 [Parameter(Mandatory=$true)][string]$WebView2GateResult,
 [string]$OutputPath=(Join-Path $EvidenceRoot 'integration-report.md')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$expected=@('webview2-install','webview2-installed','search-winget','search-msstore','search-aggregate','consent-accept','consent-decline','consent-cancel','network-error','lifecycle')
$records=@{}
foreach($file in @(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)){
 try {
  $item=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
  if($item.Scenario){$records[[string]$item.Scenario]=$item}
 }catch{}
}
$lines=[System.Collections.Generic.List[string]]::new()
$lines.Add('# Garant Store Windows integration report')
$lines.Add('')
$lines.Add(('Generated UTC: '+(Get-Date).ToUniversalTime().ToString('o')))
$lines.Add(('Build gate: '+$BuildGateResult))
$lines.Add(('WPF UI integration matrix: '+$UiGateResult))
$lines.Add(('REAL WebView2 installation: '+$WebView2GateResult))
$lines.Add('')
$lines.Add('| Scenario | Result | Evidence |')
$lines.Add('|---|---|---|')
$scenarioStates=@()
foreach($scenario in $expected){
 if($records.ContainsKey($scenario)){
  $result=[string]$records[$scenario].Result
  if($result -eq 'passed'){$label='PASSED'}
  elseif($scenario -eq 'webview2-install' -and $result -eq 'unavailable' -and
    $records[$scenario].PSObject.Properties['Reason'] -and $records[$scenario].Reason -eq 'PreinstalledWebView2' -and
    $records[$scenario].PSObject.Properties['InstalledVersion'] -and $records[$scenario].InstalledVersion){$label='UNAVAILABLE'}
  else{$label='FAILED'}
  $errorText=''
  if($records[$scenario].PSObject.Properties.Name -contains 'Error'){$errorText=[string]$records[$scenario].Error}
  $scenarioStates+=([pscustomobject]@{Scenario=$scenario;Result=$label;Error=$errorText})
  $note=if($label -eq 'UNAVAILABLE'){'preinstalled version '+$records[$scenario].InstalledVersion}else{$scenario+'.json'}
  $lines.Add('| '+$scenario+' | '+$label+' | '+$note+' |')
 }else{
  $scenarioStates+=([pscustomobject]@{Scenario=$scenario;Result='UNAVAILABLE';Error='No UI automation evidence was produced.'})
  $lines.Add('| '+$scenario+' | UNAVAILABLE | no scenario output |')
 }
}
$lines.Add('')
$lines.Add('## Measured UI and operation metrics')
$lines.Add('')
$lines.Add('| Scenario | Check | Measurements |')
$lines.Add('|---|---|---|')
foreach($scenario in $expected){
 if(-not $records.ContainsKey($scenario)){continue}
 $record=$records[$scenario]
 if($record.PSObject.Properties.Name -notcontains 'Metrics'){continue}
 foreach($metric in @($record.Metrics)){
  if($null -eq $metric){continue}
  $parts=@()
  foreach($field in @('Source','Rows','ElapsedMs','NavigationLatencyMs','LimitMs','Version','Status','Action','ConsentPassedToCore','RePrompted')){
   if($metric.PSObject.Properties.Name -contains $field){$parts+=($field+'='+([string]$metric.$field -replace '\|','/'))}
  }
  if($parts.Count -gt 0){$lines.Add('| '+$scenario+' | '+[string]$metric.Check+' | '+($parts -join '; ')+' |')}
 }
}
$liveFiles=@(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -Filter 'winget-live-search.json' -ErrorAction SilentlyContinue)
if($liveFiles.Count -gt 0){
 $live=Get-Content -LiteralPath $liveFiles[0].FullName -Raw -Encoding UTF8|ConvertFrom-Json
 $lines.Add('')
 $lines.Add('## Live WinGet source search')
 foreach($row in @($live)){$lines.Add(('- '+$row.Source+': '+$row.Status+'; rows='+$row.MappedRows))}
}else{
 $lines.Add('')
 $lines.Add('## Live WinGet source search')
 $lines.Add('UNAVAILABLE: no live-source evidence was uploaded.')
}
$failed=@($scenarioStates|Where-Object{$_.Result -eq 'FAILED'})
$unavailable=@($scenarioStates|Where-Object{$_.Result -eq 'UNAVAILABLE'})
$blockingUnavailable=@($unavailable|Where-Object{$_.Scenario -ne 'webview2-install' -or -not $records.ContainsKey('webview2-install')})
$overall=if($BuildGateResult -ne 'success' -or $UiGateResult -ne 'success' -or $WebView2GateResult -ne 'success' -or $failed.Count -gt 0 -or $blockingUnavailable.Count -gt 0){'FAILED'}else{'RELEASE CANDIDATE'}
$lines.Add('')
$lines.Add(('## Overall: '+$overall))
if($failed.Count -gt 0){$lines.Add('Failed checks: '+(($failed|ForEach-Object{$_.Scenario+': '+$_.Error}) -join '; '))}
if($unavailable.Count -gt 0){$lines.Add('Unavailable checks: '+(($unavailable|ForEach-Object{$_.Scenario}) -join ', '))}
$lines.Add('')
$lines.Add('A passed automation report is not a VERIFIED release: hardware-dependent driver installation scenarios still require verification on real user devices.')
[IO.File]::WriteAllLines($OutputPath,$lines,[Text.UTF8Encoding]::new($false))
$summary=$lines -join [Environment]::NewLine
if($env:GITHUB_STEP_SUMMARY){Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding UTF8}
$scenarioStates|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $EvidenceRoot 'integration-report.json') -Encoding UTF8
Write-Host $summary
if($overall -eq 'FAILED'){exit 1}
