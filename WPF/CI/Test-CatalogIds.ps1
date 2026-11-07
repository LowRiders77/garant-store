# Every catalog card with a fixed WinGet identity must resolve to exactly that
# package in the live winget source; a renamed or removed ID fails the gate
# instead of reaching users as a broken card.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$ui=Get-Content -LiteralPath (Join-Path $project 'GarantStore.Next.ps1') -Raw -Encoding UTF8
$catalogEntries=@([regex]::Matches($ui,"Id='([^']+)';Source='(winget|msstore)'")|ForEach-Object{[pscustomobject]@{Id=$_.Groups[1].Value;Source=$_.Groups[2].Value}})
if($catalogEntries.Count -lt 20){throw ('Catalog identity table looks truncated: '+$catalogEntries.Count+' entries')}
# Bundles and the Windows-component installer must use the same verified identities.
$bundleEntries=@((Get-Content -LiteralPath (Join-Path $project 'Bundles.json') -Raw -Encoding UTF8|ConvertFrom-Json).Bundles|ForEach-Object{$_.Items}|ForEach-Object{[pscustomobject]@{Id=[string]$_.Id;Source=[string]$_.Source}})
$libraries=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Libraries.ps1') -Raw -Encoding UTF8
$componentEntries=@([regex]::Matches($libraries,"^\s*'[a-z0-9-]+'='([A-Za-z0-9.+-]+)'\s*$",'Multiline')|ForEach-Object{[pscustomobject]@{Id=$_.Groups[1].Value;Source='winget'}})
if($componentEntries.Count -lt 6){throw ('Component WinGet map looks truncated: '+$componentEntries.Count)}
$entries=@(@($catalogEntries)+@($bundleEntries)+@($componentEntries)|Sort-Object Id,Source -Unique)
$winget=(Get-Command winget.exe -ErrorAction Stop).Source
$failures=New-Object System.Collections.Generic.List[string]
foreach($entry in @($entries|Where-Object{$_.Source -eq 'winget'})){
 $output=& $winget show --id $entry.Id --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String
 if($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape('['+$entry.Id+']')){$failures.Add($entry.Id+' (exit '+$LASTEXITCODE+')')}
}
if($failures.Count){throw ('Catalog WinGet identities did not resolve: '+($failures -join ', '))}
Write-Host ('Catalog, bundle and component identity gate passed: '+@($entries|Where-Object{$_.Source -eq 'winget'}).Count+' WinGet IDs resolve exactly.')
