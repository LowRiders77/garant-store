[CmdletBinding()]
param([switch]$CompileInstaller)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$ui=Join-Path $project 'GarantStore.Next.ps1'
$about=Join-Path $project 'AboutWindow.xaml'
$drivers=Join-Path $project 'DriverWindow.xaml'
$driverCode=Join-Path $project 'GarantStore.Drivers.ps1'
$updateCode=Join-Path $project 'DriverEngine\Updates.ps1'
$catalogCode=Join-Path $project 'DriverEngine\UpdateCatalog.ps1'
$librariesCode=Join-Path $project 'DriverEngine\Libraries.ps1'
$coreCode=Join-Path $project 'DriverEngine\Core.ps1'
$workerCode=Join-Path $project 'DriverEngine\Worker.ps1'
$catalogCode=Join-Path $project 'DriverEngine\Catalog.ps1'
$serverCode=Join-Path $project 'DriverEngine\Server.ps1'
$selectedCode=Join-Path $project 'DriverEngine\Selected.ps1'
$networkCode=Join-Path $project 'DriverEngine\NetworkRepair.ps1'
$restorePointCode=Join-Path $project 'DriverEngine\RestorePoint.ps1'
$windowsUpdateRepairCode=Join-Path $project 'DriverEngine\WindowsUpdateRepair.ps1'
$driverSelectionTest=Join-Path $PSScriptRoot 'Test-DriverWindowSelection.ps1'
$setup=Join-Path $project 'Installer\GarantStoreNext.iss'
$dist=Join-Path $project 'dist'
$evidence=Join-Path $project 'CI-output'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

$buildInfoPath=Join-Path $project 'BuildInfo.json'
$componentHashes=[ordered]@{}
$componentFiles=@(Get-ChildItem -LiteralPath $project -Recurse -File | Where-Object {
 $_.FullName -notmatch '[\\/]CI-output[\\/]|[\\/]dist[\\/]' -and
 ($_.Extension -in @('.ps1','.xaml','.vbs','.cmd','.iss','.cs','.ico','.png','.svg') -or $_.Name -eq 'GarantServer.cs')
})
foreach($file in $componentFiles){
 $relative=$file.FullName.Substring($project.Length+1).Replace('\','/')
 $componentHashes[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$buildInfo=[ordered]@{
 Schema=1
 AppVersion='0.11.0.1'
 ProductVersion='0.11.0 Preview'
 SourceCommit=if($env:GITHUB_SHA){$env:GITHUB_SHA}else{'unavailable'}
 BuildId=if($env:GITHUB_RUN_ID){$env:GITHUB_RUN_ID}else{'local'}
 BuildAttempt=if($env:GITHUB_RUN_ATTEMPT){$env:GITHUB_RUN_ATTEMPT}else{'1'}
 BuiltUtc=(Get-Date).ToUniversalTime().ToString('o')
 Components=$componentHashes
}
[IO.File]::WriteAllText($buildInfoPath,(ConvertTo-Json -InputObject $buildInfo -Depth 8),(New-Object Text.UTF8Encoding($false)))

# Parse every shipped PowerShell component with the runner's Windows PowerShell
# 5.1 parser before executing focused regression and smoke tests.
$shippedScripts=@(Get-ChildItem -LiteralPath $project -Recurse -File -Filter '*.ps1' | Where-Object {
 $_.FullName -notmatch '[\\/]CI-output[\\/]|[\\/]dist[\\/]'
})
foreach($scriptFile in $shippedScripts){
 $tokens=$null;$parseErrors=$null
 [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
 if($parseErrors.Count -gt 0){throw ('PowerShell 5.1 parse errors in '+$scriptFile.FullName+': '+(($parseErrors|ForEach-Object{('{0} at {1}:{2}' -f $_.Message,$_.Extent.StartLineNumber,$_.Extent.StartColumnNumber)}) -join '; '))}
}

$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($ui,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count -gt 0){throw ('PowerShell parse errors: '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($driverCode,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count -gt 0){throw ('Driver module parse errors: '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($updateCode,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count -gt 0){throw ('Driver update module parse errors: '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
[Management.Automation.Language.Parser]::ParseFile($catalogCode,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count -gt 0){throw ('Windows Update catalog parse errors: '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
foreach($engineCode in @($coreCode,$catalogCode,$workerCode,$serverCode,$librariesCode,$selectedCode,$networkCode,$restorePointCode,$windowsUpdateRepairCode)){
 $tokens=$null;$parseErrors=$null
 [Management.Automation.Language.Parser]::ParseFile($engineCode,[ref]$tokens,[ref]$parseErrors) | Out-Null
 if($parseErrors.Count -gt 0){throw ('Driver engine parse errors in '+[IO.Path]::GetFileName($engineCode)+': '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
}
[xml]$aboutXml=Get-Content -LiteralPath $about -Raw -Encoding UTF8
[xml]$driverXml=Get-Content -LiteralPath $drivers -Raw -Encoding UTF8
Add-Type -AssemblyName PresentationFramework
$driverReader=New-Object System.Xml.XmlNodeReader($driverXml)
$loadedDriverWindow=[Windows.Markup.XamlReader]::Load($driverReader)
$driverReader.Close()
$requiredNames=@('BrandMark','BuildIdentity','ContactInstagram','ContactWhatsApp','ContactEmail','CopySbp','CopyFeedback')
foreach($name in $requiredNames){if(-not $aboutXml.OuterXml.Contains('x:Name="'+$name+'"')){throw ('About window is missing '+$name)}}
$driverControls=@('DriverState','DriverDetail','DriverDevices','DriverScan','DriverSelectionActions','DriverInstall','DriverDownload','DriverSource','DriverNetwork','DriverLocal','DriverRestore','DriverWuRepair','DriverCancel','DriverDiagnostics')
foreach($name in $driverControls){if(-not $driverXml.OuterXml.Contains('x:Name="'+$name+'"')){throw ('Driver window is missing '+$name)};if($null -eq $loadedDriverWindow.FindName($name)){throw ('Driver WPF did not load control '+$name)}}
if(-not (Test-Path -LiteralPath (Join-Path $project 'Assets\GarantStoreMark.ico'))){throw 'Application icon is missing'}
if(-not (Test-Path -LiteralPath (Join-Path $project 'GarantStore.Launcher.vbs'))){throw 'Hidden launcher is missing'}
& (Join-Path $PSScriptRoot 'Test-MicrosoftStoreState.ps1')
& (Join-Path $PSScriptRoot 'Test-StoreServiceConsent.ps1')
& (Join-Path $PSScriptRoot 'Test-ServiceHelper.ps1')
& (Join-Path $PSScriptRoot 'Test-UiLogTail.ps1')
& (Join-Path $PSScriptRoot 'Test-WingetSearch.ps1')
& (Join-Path $PSScriptRoot 'Test-WingetRepair.ps1')
& (Join-Path $PSScriptRoot 'Test-WingetLiveSource.ps1')
& (Join-Path $PSScriptRoot 'Test-CatalogIds.ps1')
& (Join-Path $PSScriptRoot 'Test-DriverInventory.ps1')
& (Join-Path $PSScriptRoot 'Test-SecureRoot.ps1')
& (Join-Path $PSScriptRoot 'Test-DriverEngine.ps1')
& (Join-Path $PSScriptRoot 'Test-WebView2Failures.ps1')
$powershellExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershellExe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $driverSelectionTest
if($LASTEXITCODE -ne 0){throw ('Driver WPF UI Automation failed with exit code '+$LASTEXITCODE)}

$runSmoke={
 param([string]$WorkingProject,[string]$Marker,[string]$ScreenshotFolder)
 Remove-Item -LiteralPath $Marker -Force -ErrorAction SilentlyContinue
 New-Item -ItemType Directory -Force -Path $ScreenshotFolder | Out-Null
 $env:GS_WPF_SMOKE='1';$env:GS_WPF_SMOKE_MARKER=$Marker;$env:GS_WPF_SCREENSHOT_DIR=$ScreenshotFolder
 $exe=Join-Path $env:WINDIR 'System32\wscript.exe'
 $launcher=Join-Path $WorkingProject 'GarantStore.Launcher.vbs'
 $p=Start-Process -FilePath $exe -ArgumentList @('//B',('"'+$launcher+'"')) -WorkingDirectory $WorkingProject -PassThru
 $until=(Get-Date).AddSeconds(35)
 while((Get-Date) -lt $until -and -not (Test-Path -LiteralPath $Marker)){
  Start-Sleep -Milliseconds 250
 }
 if(-not (Test-Path -LiteralPath $Marker)){throw 'WPF smoke did not close cleanly within 35 seconds'}
 $result=(Get-Content -LiteralPath $Marker -Raw).Trim()
 $p.WaitForExit(10000)
 if(-not $p.HasExited){throw 'WScript launcher did not exit'}
 if($result -ne 'CLOSED'){throw ('WPF smoke failed: '+$result)}
 foreach($mode in @('normal','wide','about')){
  $shot=Join-Path $ScreenshotFolder ('garant-next-'+$mode+'.png')
  if(-not (Test-Path -LiteralPath $shot) -or (Get-Item -LiteralPath $shot).Length -lt 4096){throw ('Missing or empty WPF screenshot: '+$mode)}
 }
 Remove-Item Env:\GS_WPF_SMOKE -ErrorAction SilentlyContinue
 Remove-Item Env:\GS_WPF_SMOKE_MARKER -ErrorAction SilentlyContinue
 Remove-Item Env:\GS_WPF_SCREENSHOT_DIR -ErrorAction SilentlyContinue
}

$sourceShots=Join-Path $evidence 'source-screenshots'
& $runSmoke $project (Join-Path $evidence 'source-smoke.marker') $sourceShots

if($CompileInstaller){
 $iscc=(Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
 if(-not $iscc){
  if(-not (Get-Command choco.exe -ErrorAction SilentlyContinue)){throw 'Inno Setup compiler is missing and Chocolatey is unavailable'}
  choco install innosetup --yes --no-progress
  $iscc=(Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
 }
 if(-not $iscc){$candidate=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe';if(Test-Path -LiteralPath $candidate){$iscc=$candidate}}
 if(-not $iscc){throw 'ISCC.exe was not found after installing Inno Setup'}
 & $iscc /Qp $setup
 if($LASTEXITCODE -ne 0){throw ('Inno Setup failed with exit code '+$LASTEXITCODE)}
 $installer=Join-Path $dist 'GarantStore-Setup.exe'
 if(-not (Test-Path -LiteralPath $installer)){throw 'Installer output is missing'}
 Start-Process -FilePath $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait
 $installed=Join-Path ${env:ProgramFiles} 'Garant Store Next'
 if(-not (Test-Path -LiteralPath (Join-Path $installed 'GarantStore.Next.ps1'))){throw 'Installed application files were not found'}
 $installedBuildInfo=Join-Path $installed 'BuildInfo.json'
 if(-not (Test-Path -LiteralPath $installedBuildInfo)){throw 'Installed build identity manifest is missing'}
 if((Get-FileHash -LiteralPath $installedBuildInfo -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $buildInfoPath -Algorithm SHA256).Hash){throw 'Installed build identity does not match the tested source build'}
 $installedShots=Join-Path $evidence 'installed-screenshots'
 & $runSmoke $installed (Join-Path $evidence 'installed-smoke.marker') $installedShots
 $uninstaller=Join-Path $installed 'unins000.exe'
 if(-not (Test-Path -LiteralPath $uninstaller)){throw 'Uninstaller was not registered'}
 Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait
 if(Test-Path -LiteralPath $installed){throw 'Silent uninstall left the application directory behind'}
}

Write-Host 'Garant Store Next Windows gate passed.'

