[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $project 'DriverEngine'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gs-driver-inventory-'+[guid]::NewGuid().ToString('N'))
$oldDataRoot=$env:GARANT_PO_DATA_ROOT
$oldDownloadDir=$env:GARANT_PO_DOWNLOAD_DIR
$oldDriverDir=$env:GARANT_PO_DRIVER_DIR
$oldLibraryDir=$env:GARANT_PO_LIBRARY_DIR
try{
 $env:GARANT_PO_DATA_ROOT=$temp
 $env:GARANT_PO_DOWNLOAD_DIR=Join-Path $temp 'Downloads'
 $env:GARANT_PO_DRIVER_DIR=Join-Path $temp 'Drivers'
 $env:GARANT_PO_LIBRARY_DIR=Join-Path $temp 'Libraries'
 . (Join-Path $engine 'Core.ps1')
 . (Join-Path $engine 'UpdateCatalog.ps1')
 . (Join-Path $engine 'Catalog.ps1')
 $wuFixture=[pscustomobject]@{Identity=[pscustomobject]@{UpdateID='test';RevisionNumber=3};Title='Intel SoftwareComponent';DriverHardwareID='swc\provider_intel_component_iclsclient';DriverClass='OtherHardware';EulaAccepted=$true}
 $wuRow=ConvertTo-GSWuaDriverRow $wuFixture
 if(-not $wuRow.canSelect -or $wuRow.Selected -or $wuRow.instanceId -ne 'test|3'){throw 'WUA producer did not emit a selectable, unselected update with exact revision identity.'}
 $wuFixture.EulaAccepted=$false
 if((ConvertTo-GSWuaDriverRow $wuFixture).canSelect){throw 'Unaccepted WUA license was silently accepted.'}
 $wuFixture.EulaAccepted=$true;$wuFixture.Title='System Firmware';$wuFixture.DriverClass='Firmware'
 if((ConvertTo-GSWuaDriverRow $wuFixture).canSelect){throw 'Firmware entered ordinary driver bulk selection.'}
 $wuFixture.Title='Intel SoftwareComponent';$wuFixture.DriverClass='OtherHardware';$wuFixture.DriverHardwareID=''
 if((ConvertTo-GSWuaDriverRow $wuFixture).canSelect){throw 'Unidentified WUA target entered driver selection.'}

 if(Test-GSDownloadResponse 0 '416' '' 196035 $true){throw 'A stale cached HTML body was accepted after HTTP 416.'}
 if(Test-GSDownloadResponse 0 '206' 'text/html' 500 $true){throw 'A partial HTTP 206 HTML page was accepted as catalog metadata.'}
 if(-not (Test-GSDownloadResponse 0 '200' 'text/html' 500 $true)){throw 'A valid HTTP 200 HTML metadata response was rejected.'}
 if(Test-GSDownloadResponse 0 '200' 'text/html' 196035 $false){throw 'An HTML error page was accepted as a driver archive.'}
 if(Test-GSDownloadResponse 0 '416' 'application/zip' 196035 $false 1000 196035 'bytes */1000'){throw 'A ZIP HTTP 416 response was accepted.'}
 if(-not (Test-GSDownloadResponse 0 '206' 'application/zip' 500 $false 0 196035 'bytes 196035-196534/196535')){throw 'A valid resumed HTTP 206 ZIP response was rejected.'}
 if(Test-GSDownloadResponse 0 '206' 'application/zip' 500 $false 0 196035 'bytes 0-499/500'){throw 'A partial response with a mismatched Range offset was accepted.'}
 $selectedPostScan=@([pscustomobject]@{instanceId='TEST\FIXED';kind='Inventory'},[pscustomobject]@{instanceId='TEST\STILL-MISSING';kind='Missing'},[pscustomobject]@{instanceId='TEST\FIXED';kind='Update'},[pscustomobject]@{instanceId='TEST\FAULTED';kind='Issue'})
 $remainingProblems=@(Get-RemainingSelectedProblemDevices $selectedPostScan @('TEST\FIXED','TEST\STILL-MISSING','TEST\FAULTED'))
 if($remainingProblems.Count -ne 2 -or @($remainingProblems|Where-Object{$_.kind -eq 'Inventory' -or $_.kind -eq 'Update'}).Count -ne 0){throw 'Post-install verification counted inventory/update rows as unresolved PnP problems.'}
 $sessionProfile=[pscustomobject]@{localId='fixture-device-a';capturedUtc=(Get-Date).ToUniversalTime().ToString('o');windows='Windows 10';build='19041'}
 $null=Save-GSDeviceSession $sessionProfile 2 35 0 4
 $sessionPath=Join-Path $temp 'Devices\fixture-device-a\sessions.json'
 if(-not (Test-Path -LiteralPath $sessionPath) -or @(Load-JsonFile $sessionPath @()).Count -ne 1){throw 'Per-device diagnostic session history was not stored in the isolated local device folder.'}
 $metadata=Get-WindowsDriverUpdateMetadata ([pscustomobject]@{DriverManufacturer='Micro-Star';DriverModel='Software Component Interface';DriverHardwareID='ACPI\MBAD0001';DriverVerDate=[datetime]'2024-08-01';DriverProvider='Micro-Star';DriverClass='OtherHardware'})
 if($metadata.hardwareId -ne 'ACPI\MBAD0001' -or $metadata.manufacturer -ne 'Micro-Star' -or $metadata.model -ne 'Software Component Interface'){throw 'Windows Update driver metadata was not read from the IWindowsDriverUpdate properties.'}
 $relatedUpdate=[pscustomobject]@{instanceId='bbd67e1e-02c5-4cdb-a88b-5d05fd193465|1';driverHardwareId='ACPI\MBAD0001'}
 $relatedDevice=[pscustomobject]@{instanceId='TEST\MSI';hwid='ACPI\VEN_MBAD&DEV_0001';hardwareIds=@('ACPI\VEN_MBAD&DEV_0001','ACPI\MBAD0001','*MBAD0001')}
 $related=@(Get-MatchedWindowsDriverUpdateIds @($relatedDevice) @($relatedUpdate))
 if($related.Count -ne 1 -or $related[0] -ne $relatedUpdate.instanceId){throw 'A Windows Update driver with a matching Hardware ID was not associated with the selected device.'}
 $specificDevice=[pscustomobject]@{instanceId='TEST\PCI';hwid='PCI\VEN_1234&DEV_0001&SUBSYS_ABCD1028&REV_02';hardwareIds=@('PCI\VEN_1234&DEV_0001&SUBSYS_ABCD1028&REV_02')}
 $genericUpdate=[pscustomobject]@{instanceId='e306b0d3-28c0-4c77-a7f6-79bfe14ea257|3';driverHardwareId='PCI\VEN_1234&DEV_0001'}
 $genericMatch=@(Get-MatchedWindowsDriverUpdateIds @($specificDevice) @($genericUpdate))
 if($genericMatch.Count -ne 1 -or $genericMatch[0] -ne $genericUpdate.instanceId){throw 'A Windows Update package with a generic VEN/DEV ID was not matched to the device-specific SUBSYS/REV ID.'}
 $exportTest=Join-Path $temp 'WuaExport'
 $fakeDownloadedUpdate=[pscustomobject]@{IsDownloaded=$true}
 $fakeDownloadedUpdate|Add-Member -MemberType ScriptMethod -Name CopyFromCache -Value {param($destination,$extract);[IO.File]::WriteAllText((Join-Path $destination 'driver.cab'),'test')}
 $exported=@(Export-GSWuaUpdateContent $fakeDownloadedUpdate $exportTest)
 if($exported.Count -ne 1 -or $exported[0].Name -ne 'driver.cab'){throw 'Downloaded Windows Update content was not exported into the driver folder.'}
 function Get-CimInstance {
  [CmdletBinding()]
  param([string]$ClassName)
  if($ClassName -eq 'Win32_PnPSignedDriver'){
   return @(
    [pscustomobject]@{DeviceID='TEST\HEALTHY';DeviceName='Healthy test device';DriverVersion='1.2.3.4';DriverDate=[datetime]'2024-03-05';DriverProviderName='Test Vendor';Manufacturer='Test Manufacturer';InfName='oem42.inf';IsSigned=$true}
    [pscustomobject]@{DeviceID='TEST\MISSING';DeviceName='Uninstalled test device';DriverVersion='0.0';DriverProviderName='';IsSigned=$false}
   )
  }
  @(
   [pscustomobject]@{Name='Uninstalled test device';PNPDeviceID='TEST\MISSING';HardwareID=@('PCI\VEN_1234&DEV_0001');ConfigManagerErrorCode=28;PNPClass='System'}
   [pscustomobject]@{Name='Faulted test device';PNPDeviceID='TEST\ISSUE';HardwareID=@('PCI\VEN_1234&DEV_0002');ConfigManagerErrorCode=10;PNPClass='System'}
   [pscustomobject]@{Name='Microsoft Basic Display Adapter';PNPDeviceID='TEST\BASICGPU';HardwareID=@('PCI\VEN_1234&DEV_0003');ConfigManagerErrorCode=0;PNPClass='Display'}
   [pscustomobject]@{Name='Healthy test device';PNPDeviceID='TEST\HEALTHY';HardwareID=@('PCI\VEN_1234&DEV_0004');ConfigManagerErrorCode=0;PNPClass='System'}
  )
 }
 $found=@(Get-TargetDevices)
 if($found.Count -ne 3){throw ('Inventory included '+$found.Count+' entries; expected missing driver, error device, and basic GPU only.')}
 $missing=@($found|Where-Object{$_.instanceId -eq 'TEST\MISSING'})
 $issue=@($found|Where-Object{$_.instanceId -eq 'TEST\ISSUE'})
 $gpu=@($found|Where-Object{$_.instanceId -eq 'TEST\BASICGPU'})
 if($missing.Count -ne 1 -or $missing[0].kind -ne 'Missing' -or $missing[0].reason -ne 'Драйвер не установлен'){throw 'Uninstalled device was not identified as a missing driver.'}
 if($issue.Count -ne 1 -or $issue[0].kind -ne 'Issue' -or $issue[0].code -ne 10){throw 'Device Manager error was not identified as an issue.'}
 if($gpu.Count -ne 1 -or $gpu[0].kind -ne 'GPU'){throw 'Microsoft Basic Display Adapter was not identified as a GPU.'}
 $inventory=@(Get-InstalledDriverInventory -ProblemDevices $found)
 if($inventory.Count -ne 1 -or $inventory[0].instanceId -ne 'TEST\HEALTHY'){throw 'Full installed PnP inventory did not retain the healthy device while excluding devices handled by the repair workflow.'}
 if($inventory[0].currentDriverVersion -ne '1.2.3.4' -or $inventory[0].driverProvider -ne 'Test Vendor' -or $inventory[0].driverDate -ne '2024-03-05' -or -not $inventory[0].isSigned){throw 'Installed driver version/provider/date/signature metadata was not inventoried.'}
 if($inventory[0].actuality -ne 'Unknown' -or $inventory[0].canSelect){throw 'The inventory incorrectly claims that a healthy installed driver is current or eligible for blind replacement.'}
 $libraries=@(Get-SystemLibrarySuggestions)
 $libraryIds=@($libraries|ForEach-Object{[string]$_.instanceId})
 foreach($requiredId in @('LIBRARY|vcredist-x64','LIBRARY|vcredist-x86','LIBRARY|directx-legacy','LIBRARY|netfx3','LIBRARY|webview2','LIBRARY|dotnet-desktop','LIBRARY|physx','LIBRARY|physx-legacy','LIBRARY|openal','LIBRARY|windows-app-runtime')){if($libraryIds -notcontains $requiredId){throw ('System dependency inventory is missing '+$requiredId)}}
 if(@($libraries|Where-Object{[string]$_.name -match '(?i)Unity Web Player'}).Count){throw 'Unsupported Unity Web Player was added to the dependency suggestions.'}
 foreach($library in $libraries){if([string]$library.libraryStatus -notin @('Установлено','Требуется','Можно установить дополнительно','Не поддерживается этой системой','Невозможно определить')){throw ('Unexpected dependency status: '+[string]$library.libraryStatus)};if($library.canSelect -and -not $library.libraryId){throw ('Selectable library has no safe installer mapping: '+[string]$library.name)}}
 $intelUrl=Get-GSDriverSourceUrl ([pscustomobject]@{kind='GPU';hardwareIds=@('PCI\VEN_8086&DEV_4E55&SUBSYS_380B17AA')})
 if($intelUrl -notmatch '^https://www\.intel\.com/.*776137'){throw 'Jasper Lake Intel GPU did not resolve to the official Intel driver page.'}
 $nvidiaUrl=Get-GSDriverSourceUrl ([pscustomobject]@{kind='GPU';hardwareIds=@('PCI\VEN_10DE&DEV_2684')})
 if($nvidiaUrl -notmatch '^https://www\.nvidia\.com/'){throw 'NVIDIA GPU did not resolve to its official driver page.'}
 $amdUrl=Get-GSDriverSourceUrl ([pscustomobject]@{kind='GPU';hardwareIds=@('PCI\VEN_1002&DEV_744C')})
 if($amdUrl -notmatch '^https://www\.amd\.com/'){throw 'AMD GPU did not resolve to its official driver page.'}
 $drpUrl=Get-GSDriverSourceUrl ([pscustomobject]@{kind='Missing';hardwareIds=@('PCI\VEN_1234&DEV_0001')})
 if($drpUrl -notmatch '^https://driverpack\.io/en/hwids/'){throw 'Non-GPU driver did not resolve to a DriverPack Hardware ID search.'}
 function Curl-Fetch([string]$url,[string]$destination,[bool]$isHtml=$false,[long]$knownSize=0){[IO.File]::WriteAllText($destination,'<html><head><title>DriverPack device catalog</title></head><body><h1>Compatible driver package</h1><a href="https://dl.driverpack.io/driverpacks/repack/Test/Vendor/Generic-test-drp.zip">ZIP</a><p>Catalog metadata fixture used by the Windows regression gate.</p></body></html>',[Text.Encoding]::UTF8);return $true}
 function Log([string]$message){}
 $onlineLinks=@(Get-DynamicDrpLinks ([pscustomobject]@{hardwareIds=@('HDAUDIO\FUNC_01&VEN_1234&DEV_ABCD')}))
 if($onlineLinks.Count -ne 1 -or $onlineLinks[0] -ne 'https://dl.driverpack.io/driverpacks/repack/Test/Vendor/Generic-test-drp.zip'){throw 'DRP catalog HTML did not resolve a direct ZIP link.'}
 function Get-DynamicDrpLinks($device){return @()}
 $targets=@(
  [pscustomobject]@{instanceId='GPU';name='Intel GPU';kind='GPU';hardwareIds=@('PCI\VEN_8086&DEV_4E55&SUBSYS_380B17AA&REV_01');hwid='PCI\VEN_8086&DEV_4E55&SUBSYS_380B17AA&REV_01'},
  [pscustomobject]@{instanceId='DPTF';name='DPTF';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4E03&SUBSYS_380817AA&REV_00');hwid='PCI\VEN_8086&DEV_4E03&SUBSYS_380817AA&REV_00'},
  [pscustomobject]@{instanceId='MEI';name='MEI';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DE0&SUBSYS_382517AA&REV_01');hwid='PCI\VEN_8086&DEV_4DE0&SUBSYS_382517AA&REV_01'},
  [pscustomobject]@{instanceId='UART';name='UART';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DA8&SUBSYS_381317AA&REV_01');hwid='PCI\VEN_8086&DEV_4DA8&SUBSYS_381317AA&REV_01'},
  [pscustomobject]@{instanceId='SPI';name='SPI';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DA4&SUBSYS_380117AA&REV_01');hwid='PCI\VEN_8086&DEV_4DA4&SUBSYS_380117AA&REV_01'},
  [pscustomobject]@{instanceId='I2C1';name='I2C1';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DE9&SUBSYS_72708086&REV_01');hwid='PCI\VEN_8086&DEV_4DE9&SUBSYS_72708086&REV_01'},
  [pscustomobject]@{instanceId='I2C2';name='I2C2';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DE8&SUBSYS_381817AA&REV_01');hwid='PCI\VEN_8086&DEV_4DE8&SUBSYS_381817AA&REV_01'},
  [pscustomobject]@{instanceId='SPI2';name='SPI2';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DAB&SUBSYS_381517AA&REV_01');hwid='PCI\VEN_8086&DEV_4DAB&SUBSYS_381517AA&REV_01'},
  [pscustomobject]@{instanceId='SMBus';name='SMBus';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4DA3&SUBSYS_380517AA&REV_01');hwid='PCI\VEN_8086&DEV_4DA3&SUBSYS_380517AA&REV_01'},
  [pscustomobject]@{instanceId='GNA';name='GNA';kind='Missing';hardwareIds=@('PCI\VEN_8086&DEV_4E11&SUBSYS_72708086&REV_00');hwid='PCI\VEN_8086&DEV_4E11&SUBSYS_72708086&REV_00'},
  [pscustomobject]@{instanceId='DPTF-ACPI1';name='DPTF ACPI';kind='Missing';hardwareIds=@('ACPI\VEN_INTC&DEV_1043');hwid='ACPI\VEN_INTC&DEV_1043'},
  [pscustomobject]@{instanceId='DPTF-ACPI2';name='DPTF ACPI duplicate ID';kind='Missing';hardwareIds=@('ACPI\VEN_INTC&DEV_1043');hwid='ACPI\VEN_INTC&DEV_1043'},
  [pscustomobject]@{instanceId='DPTF-ACPI3';name='DPTF ACPI';kind='Missing';hardwareIds=@('ACPI\VEN_INTC&DEV_1040');hwid='ACPI\VEN_INTC&DEV_1040'},
  [pscustomobject]@{instanceId='GPIO';name='GPIO';kind='Missing';hardwareIds=@('ACPI\INT34C8');hwid='ACPI\INT34C8'},
  [pscustomobject]@{instanceId='LenovoACPI';name='Lenovo ACPI';kind='Missing';hardwareIds=@('ACPI\VPC2004');hwid='ACPI\VPC2004'},
  [pscustomobject]@{instanceId='LenovoFN';name='Lenovo FN';kind='Missing';hardwareIds=@('ACPI\LHK2019');hwid='ACPI\LHK2019'}
 )
 $resolved=@(Get-Packages $targets)
 $drpLookup=@(Get-DrpLookupKeys $targets[1])
 if($drpLookup.Count -lt 2 -or $drpLookup[0] -notmatch '^PCI\\VEN_8086&DEV_4E03&SUBSYS_' -or $drpLookup -notcontains 'PCI\VEN_8086&DEV_4E03'){throw 'DRP online lookup did not retain both the exact and normalized PCI Hardware IDs.'}
 $hdaLookup=@(Get-DrpLookupKeys ([pscustomobject]@{hardwareIds=@('HDAUDIO\FUNC_01&VEN_10EC&DEV_0256&SUBSYS_17AA380B')}))
 if($hdaLookup.Count -ne 1 -or $hdaLookup[0] -ne 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0256&SUBSYS_17AA380B'){throw 'DRP lookup does not support non-PCI/USB/ACPI hardware families such as HDAUDIO.'}
 $covered=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
 foreach($pkg in $resolved){foreach($id in @($pkg.ids)){foreach($device in $targets){if(@(Get-NormalIds $device) -contains [string]$id){[void]$covered.Add([string]$device.instanceId)}}}}
 $uncovered=@($targets|Where-Object{-not $covered.Contains([string]$_.instanceId)})
 if($uncovered.Count -gt 0){throw ('Known clean-Windows Lenovo devices have no source packages: '+(($uncovered|ForEach-Object{$_.instanceId}) -join ', '))}
 if(@($resolved|Where-Object{$_.kind -eq 'Zip' -and $_.url -notmatch '^https://dl\.driverpack\.io/'}).Count -gt 0){throw 'A catalog ZIP source is not a direct HTTPS DriverPack CDN link.'}
 if(@($resolved|Where-Object{$_.url -match 'driverpack\.io/en/hwids'}).Count -gt 0){throw 'An HTML Hardware-ID page was mistaken for a downloadable driver package.'}
 $serialPackage=@($resolved|Where-Object{$_.url -match 'SerialIO/10x64/30\.100\.2133\.4_JSL'})
 if($serialPackage.Count -ne 1){throw 'Shared DriverPack SerialIO archive was not deduplicated into one download.'}
 $serialTargets=@(Get-PackageTargets $serialPackage[0] $targets)
 if($serialTargets.Count -ne 5){throw ('Shared SerialIO package matched '+$serialTargets.Count+' devices; expected 5 selected SerialIO devices.')}
 $selectedSerial=@(Get-PackageTargets $serialPackage[0] $targets @('UART'))
 if($selectedSerial.Count -ne 1 -or $selectedSerial[0].instanceId -ne 'UART'){throw 'The install plan did not restrict the shared package to the explicitly selected device.'}
 $utf16Inf=Join-Path $temp 'utf16-serialio.inf'
 [IO.File]::WriteAllText($utf16Inf,"[DeviceList]`r`nPCI\VEN_8086&DEV_4DA8", [Text.Encoding]::Unicode)
 if(-not (Test-InfMatchesTargets $utf16Inf @($targets|Where-Object{$_.instanceId -eq 'UART'}))){throw 'UTF-16LE Intel INF did not match the selected Serial IO Hardware ID.'}
 $acpiInf=Join-Path $temp 'acpi-alias.inf'
 [IO.File]::WriteAllText($acpiInf,"[DeviceList]`r`nACPI\VEN_VPC&DEV_2004", [Text.Encoding]::Unicode)
 $acpiTarget=[pscustomobject]@{instanceId='ACPI-ALIAS';name='Lenovo ACPI';kind='Missing';hardwareIds=@('ACPI\VPC2004');hwid='ACPI\VPC2004'}
 if(-not (Test-InfMatchesTargets $acpiInf @($acpiTarget))){throw 'Normalized ACPI Hardware ID alias did not match the Lenovo ACPI INF.'}
 Write-Host 'Driver inventory gate passed: HTTP status/range validation, false post-install issue regression, device classification, official GPU sources, DriverPack ZIP coverage for the 15 non-GPU devices plus official Intel GPU source, duplicate-ID coverage, shared-package grouping, selection scoping, PCI/ACPI/HDAUDIO DRP lookup keys, UTF-16LE INF matching, normalized ACPI aliases, generic Windows Update hardware-ID matching, and download export.'
}finally{
 $env:GARANT_PO_DATA_ROOT=$oldDataRoot
 $env:GARANT_PO_DOWNLOAD_DIR=$oldDownloadDir
 $env:GARANT_PO_DRIVER_DIR=$oldDriverDir
 $env:GARANT_PO_LIBRARY_DIR=$oldLibraryDir
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

