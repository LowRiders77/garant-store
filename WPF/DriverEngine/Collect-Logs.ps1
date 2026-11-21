$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$dataRoot=if([string]::IsNullOrWhiteSpace($env:GARANT_PO_DATA_ROOT)){$root}else{[IO.Path]::GetFullPath($env:GARANT_PO_DATA_ROOT)}
$logs=Join-Path $dataRoot 'Logs'
$state=Join-Path $dataRoot 'State'
if (!(Test-Path $logs)){New-Item -ItemType Directory -Path $logs -Force | Out-Null}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$path=Join-Path $logs ('Garant-PO-Diagnostics-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
$zip=[System.IO.Compression.ZipFile]::Open($path,[System.IO.Compression.ZipArchiveMode]::Create)
try {
 foreach ($name in @('Garant-PO-Latest.log','Garant-PO-Interface.log','Garant-PO-Server.log','Worker-stdout.log','Worker-stderr.log','Remaining.csv','Missing-DRP-Links.txt','Garant-PO-Server-Startup-Error.log','device-decisions.jsonl')) {
  $file=Join-Path $logs $name
  if(Test-Path $file){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file,$name)|Out-Null}catch{Write-Host ('Skip locked file: '+$name)}}
 }
 $operations=Join-Path $logs 'Operations'
 if(Test-Path -LiteralPath $operations){foreach($file in @(Get-ChildItem -LiteralPath $operations -File -Filter '*.log'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 30)){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,('Operations/'+$file.Name))|Out-Null}catch{}}}
 foreach($pattern in @('selected-*.stdout.txt','selected-*.stderr.txt')){foreach($file in @(Get-ChildItem -LiteralPath $logs -File -Filter $pattern -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 20)){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,('ChildProcesses/'+$file.Name))|Out-Null}catch{}}}
 foreach($pattern in @('pnputil-*.out.txt','pnputil-*.err.txt')){foreach($file in @(Get-ChildItem -LiteralPath $state -File -Filter $pattern -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 40)){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,('PnPUtil/'+$file.Name))|Out-Null}catch{}}}
 foreach ($name in @('status.json','devices.json','selection.json','source-health.json','curl_diagnostics.log','curl_stderr.txt','curl_headers.txt','system-profile.json','device-session.json','device-history.json')) {
  $file=Join-Path $state $name
  if(Test-Path $file){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file,('State/'+$name))|Out-Null}catch{Write-Host ('Skip locked file: '+$name)}}
 }
} finally {$zip.Dispose()}
Write-Host ('Saved: '+$path) -ForegroundColor Green
Start-Process explorer.exe -ArgumentList ('/select,"'+$path+'"')
