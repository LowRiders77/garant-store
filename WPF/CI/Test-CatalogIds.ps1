# Every catalog card with a fixed WinGet identity must resolve to exactly that
# package in the live winget source; a renamed or removed ID fails the gate
# instead of reaching users as a broken card.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$ui=Get-Content -LiteralPath (Join-Path $project 'GarantStore.Next.ps1') -Raw -Encoding UTF8
$entries=@([regex]::Matches($ui,"Id='([^']+)';Source='(winget|msstore)'")|ForEach-Object{[pscustomobject]@{Id=$_.Groups[1].Value;Source=$_.Groups[2].Value}}|Sort-Object Id,Source -Unique)
if($entries.Count -lt 20){throw ('Catalog identity table looks truncated: '+$entries.Count+' entries')}
$winget=(Get-Command winget.exe -ErrorAction Stop).Source
$failures=New-Object System.Collections.Generic.List[string]
foreach($entry in @($entries|Where-Object{$_.Source -eq 'winget'})){
 $output=& $winget show --id $entry.Id --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String
 if($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape('['+$entry.Id+']')){$failures.Add($entry.Id+' (exit '+$LASTEXITCODE+')')}
}
if($failures.Count){throw ('Catalog WinGet identities did not resolve: '+($failures -join ', '))}
Write-Host ('Catalog identity gate passed: '+@($entries|Where-Object{$_.Source -eq 'winget'}).Count+' WinGet IDs resolve exactly.')
