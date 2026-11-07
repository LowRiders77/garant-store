[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# GitHub-hosted Windows Server 2025 images include App Installer. Register its
# package for this runner user before invoking the execution alias.
$package=Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $package){
 $package=Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
}
if($package){
 try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop }
 catch { Write-Host ('App Installer registration returned: '+$_.Exception.Message) }
}

$command=Get-Command winget.exe -ErrorAction SilentlyContinue
if(-not $command){
 $package=Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
 if($package -and $package.InstallLocation){
  $candidate=Join-Path $package.InstallLocation 'winget.exe'
  if(Test-Path -LiteralPath $candidate -PathType Leaf){$env:PATH=$package.InstallLocation+';'+$env:PATH;$command=Get-Item -LiteralPath $candidate}
 }
}
if(-not $command){throw 'RELEASE GATE BLOCKED: Windows Server 2025 runner has no registered App Installer / winget.exe.'}
$winget=if($command.Source){$command.Source}else{$command.FullName}
$versionText=@(& $winget --version 2>&1)
if($LASTEXITCODE -ne 0 -or ($versionText -join ' ') -notmatch '\d+\.\d+\.\d+'){
 throw ('RELEASE GATE BLOCKED: winget --version failed: '+($versionText -join ' '))
}
$sourceText=@(& $winget source list --disable-interactivity 2>&1)
if($LASTEXITCODE -ne 0){throw ('RELEASE GATE BLOCKED: winget source list failed: '+($sourceText -join ' '))}
$sourceJoined=$sourceText -join [Environment]::NewLine
foreach($name in @('winget','msstore')){
 if($sourceJoined -notmatch ('(?im)^\s*'+[regex]::Escape($name)+'\s')){
  throw ('RELEASE GATE BLOCKED: WinGet source is missing: '+$name)
 }
}
Write-Host ('WinGet ready for mandatory integration gate: '+($versionText -join ' ').Trim())
$sourceText | ForEach-Object { Write-Host $_ }
