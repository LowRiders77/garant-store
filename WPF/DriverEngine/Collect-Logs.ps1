$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$logs=Join-Path $root 'Logs'
$state=Join-Path $root 'State'
if (!(Test-Path $logs)){New-Item -ItemType Directory -Path $logs -Force | Out-Null}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$path=Join-Path $logs ('Garant-PO-Diagnostics-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
$zip=[System.IO.Compression.ZipFile]::Open($path,[System.IO.Compression.ZipArchiveMode]::Create)
try {
 foreach ($name in @('Garant-PO-Latest.log','Garant-PO-Interface.log','Garant-PO-Server.log','Worker-stdout.log','Worker-stderr.log','Remaining.csv','Missing-DRP-Links.txt','Garant-PO-Server-Startup-Error.log')) {
  $file=Join-Path $logs $name
  if(Test-Path $file){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file,$name)|Out-Null}catch{Write-Host ('Skip locked file: '+$name)}}
 }
 foreach ($name in @('status.json','devices.json','curl_diagnostics.log','curl_stderr.txt','curl_headers.txt')) {
  $file=Join-Path $state $name
  if(Test-Path $file){try{[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file,('State/'+$name))|Out-Null}catch{Write-Host ('Skip locked file: '+$name)}}
 }
} finally {$zip.Dispose()}
Write-Host ('Saved: '+$path) -ForegroundColor Green
Start-Process explorer.exe -ArgumentList ('/select,"'+$path+'"')
