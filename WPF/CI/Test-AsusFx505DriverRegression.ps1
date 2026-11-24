# Regression fixture from Garant-PO-Diagnostics, ASUS TUF Gaming FX505GE,
# Windows 11 Pro 24H2 build 26100, 2026-11-24. This protects the catalog
# fallback and INF matching paths; it does not claim a physical installation.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $project 'DriverEngine'
$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-asus-fx505-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work|Out-Null
$oldData=$env:GARANT_PO_DATA_ROOT;$env:GARANT_PO_DATA_ROOT=(Join-Path $work 'data')
try{
 . (Join-Path $engine 'Core.ps1')
 . (Join-Path $engine 'Catalog.ps1')
 . (Join-Path $engine 'UpdateCatalog.ps1')

 $targets=@(Get-GSDrpOsTargets -Caption 'Microsoft Windows 11 Pro' -Build 26100 -Is64Bit $true)
 if($targets.Count -ne 2 -or $targets[0] -ne 'windows-11-x64' -or $targets[1] -ne 'windows-10-x64'){
  throw ('Windows 11 DRP compatibility catalogs are incorrect: '+($targets -join ', '))
 }
 $win10Targets=@(Get-GSDrpOsTargets -Caption 'Microsoft Windows 10 Pro' -Build 19041 -Is64Bit $true)
 if($win10Targets.Count -ne 1 -or $win10Targets[0] -ne 'windows-10-x64'){throw 'Windows 10 must not search an unrelated OS catalog'}

 $rows=@(
  @('PCI\VEN_8086&DEV_3E9B&SUBSYS_1A4E1043&REV_00','PCI\VEN_8086&DEV_3E9B'),
  @('PCI\VEN_8086&DEV_1903&SUBSYS_13B11043&REV_07','PCI\VEN_8086&DEV_1903'),
  @('PCI\VEN_8086&DEV_A379&SUBSYS_13B11043&REV_10','PCI\VEN_8086&DEV_A379'),
  @('PCI\VEN_8086&DEV_A328&SUBSYS_13B11043&REV_10','PCI\VEN_8086&DEV_A328'),
  @('PCI\VEN_8086&DEV_A360&SUBSYS_13B11043&REV_10','PCI\VEN_8086&DEV_A360'),
  @('PCI\VEN_8086&DEV_A324&SUBSYS_13B11043&REV_10','PCI\VEN_8086&DEV_A324'),
  @('PCI\VEN_8086&DEV_A323&SUBSYS_13B11043&REV_10','PCI\VEN_8086&DEV_A323'),
  @('ACPI\VEN_ASUS&DEV_7000','ACPI\ASUS7000'),
  @('USB\VID_8087&PID_0AAA&REV_0002','USB\VID_8087&PID_0AAA'),
  @('ACPI\VEN_ATK&DEV_4002','ACPI\ATK4002'),
  @('ACPI\VEN_INT&DEV_3403','ACPI\INT3403'),
  @('ACPI\VEN_INT&DEV_3400','ACPI\INT3400'),
  @('ACPI\VEN_ASUS&DEV_1000','ACPI\ASUS1000'),
  @('PCI\VEN_8086&DEV_1911&SUBSYS_13B11043&REV_00','PCI\VEN_8086&DEV_1911')
 )
 $devices=New-Object System.Collections.Generic.List[object]
 for($i=0;$i -lt $rows.Count;$i++){
  $isPci=([string]$rows[$i][0] -match '^PCI\\')
  $device=[pscustomobject]@{instanceId=($rows[$i][0]+'\TEST'+$i);name=('FX505 device '+$i);kind='Missing';code=28;category='';hardwareIds=$(if($isPci){@($rows[$i][0])}else{@($rows[$i][0],$rows[$i][1])});compatibleIds=$(if($isPci){@($rows[$i][1])}else{@()})}
  $keys=@(Get-DrpLookupKeys $device)
  if($keys -notcontains $rows[$i][1]){throw ('Canonical lookup key missing for '+$rows[$i][0]+': '+($keys -join ', '))}
  $devices.Add($device)
 }
 if($devices.Count -ne 14){throw 'ASUS fixture must contain the 14 remaining problem devices'}
 $compatibleOnly=[pscustomobject]@{hardwareIds=@('PCI\VEN_8086&DEV_A323&SUBSYS_13B11043');compatibleIds=@('PCI\VEN_8086&DEV_A323&CC_0C05')}
 if(@(Get-NormalIds $compatibleOnly) -notcontains 'PCI\VEN_8086&DEV_A323&CC_0C05'){throw 'Compatible IDs are missing from source lookup keys'}

 $models=for($i=0;$i -lt $rows.Count;$i++){'%D'+$i+'%=Install,'+$rows[$i][1]}
 $inf=Join-Path $work 'Asus-FX505-compatible.inf'
 $body="[Version]`r`nClass=System`r`nDriverVer=10/01/2026,10.1.18838.8284`r`nCatalogFile=Asus.cat`r`n[Manufacturer]`r`n%Vendor%=Models,NTamd64.10.0`r`n[Models.NTamd64.10.0]`r`n"+($models -join "`r`n")+"`r`n"
 [IO.File]::WriteAllText($inf,$body,[Text.Encoding]::Unicode)
 [IO.File]::WriteAllBytes((Join-Path $work 'Asus.cat'),[byte[]](1,2,3))
 $model=Get-GSInfModel -Path $inf -Architecture x64 -Build 26100
 foreach($device in $devices){
  $selected=Select-GSInfForDevice -Device $device -Models @($model) -PackageName 'DriverPack-10x64.zip'
  if($null -eq $selected.Model){throw ('Windows 10 compatible INF was rejected on Windows 11: '+$device.hardwareIds[0]+' | '+$selected.Reason)}
 }

 $zip='https://dl.driverpack.io/driverpacks/repack/Vendor/Asus/ATK/FORCED/10x64/SCI_1.0.21.0/Asus-ATK-FORCED-10x64-SCI_1.0.21.0-drp.zip'
 $fixture='<a href="'+$zip+'">driver</a><a href="https:\/\/dl.driverpack.io\/driverpacks\/repack\/Vendor\/Asus\/duplicate.zip">escaped</a><a href="https://evil.invalid/bad.zip">bad</a>'
 $links=@(Get-GSDrpLinksFromHtml $fixture)
 if($links.Count -ne 2 -or $links -notcontains $zip -or @($links|Where-Object{$_ -match 'evil\.invalid'}).Count){throw 'DriverPack HTML link extraction is incorrect'}

 $preflight=Get-GSWuaInstallPreflight @('PendingFileRenameOperations') 11
 if($preflight.CanInstall -or -not $preflight.NeedReboot -or $preflight.Deferred -ne 11 -or $preflight.Phase -ne 'Ожидается перезагрузка'){throw 'Windows Update pending reboot was not deferred correctly'}
 if((Get-GSWuaInstallPreflight @() 11).CanInstall -ne $true){throw 'Windows Update install was blocked without a reboot reason'}
 if((Get-GSRemainingDriverOutcome 14 $true) -ne 'PendingReboot'){throw 'Remaining devices became a false failure while reboot verification is pending'}
 if((Get-GSRemainingDriverOutcome 14 $false) -ne 'Failed'){throw 'A real unresolved device set was not reported as failed'}

 Write-Host 'ASUS FX505GE regression passed: 14 device IDs, compatible IDs, Windows 11 -> Windows 10 catalog fallback, INF applicability, safe ZIP URL parsing and pending-reboot result handling.'
}finally{
 $env:GARANT_PO_DATA_ROOT=$oldData
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
