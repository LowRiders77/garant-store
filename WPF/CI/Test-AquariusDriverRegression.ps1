# Regression fixture from Garant-PO-Diagnostics, Aquarius Cmp NS483,
# Windows 10 Pro 19041, 2026-11-21. This does not claim a physical install:
# it protects the exact 23 Code 28 identities, INF selection, cache isolation,
# dependency order, archive safety and WU_E_INSTALL_NOT_ALLOWED handling.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $project 'DriverEngine'
$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-aquarius-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work|Out-Null
$oldData=$env:GARANT_PO_DATA_ROOT;$env:GARANT_PO_DATA_ROOT=(Join-Path $work 'data')
try{
 . (Join-Path $engine 'Core.ps1')
 . (Join-Path $engine 'Catalog.ps1')
 . (Join-Path $engine 'UpdateCatalog.ps1')

 $rows=@(
  @('PCI\VEN_8086&DEV_9A03&SUBSYS_00000000&REV_01','PCI\VEN_8086&DEV_9A03','PCI data acquisition controller'),
  @('PCI\VEN_8086&DEV_A0A8&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0A8','PCI Simple Communications Controller'),
  @('PCI\VEN_8086&DEV_A0C5&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0C5','PCI device A0C5'),
  @('PCI\VEN_8086&DEV_A0EB&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0EB','PCI device A0EB'),
  @('PCI\VEN_8086&DEV_A0AB&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0AB','PCI device A0AB'),
  @('PCI\VEN_8086&DEV_A0E9&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0E9','PCI device A0E9'),
  @('PCI\VEN_8086&DEV_A0EA&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0EA','PCI device A0EA'),
  @('PCI\VEN_8086&DEV_A0C6&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0C6','PCI device A0C6'),
  @('PCI\VEN_8086&DEV_A0A4&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0A4','PCI device A0A4'),
  @('PCI\VEN_8086&DEV_A0E8&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0E8','PCI device A0E8'),
  @('PCI\VEN_8086&DEV_A0A3&SUBSYS_00000000&REV_20','PCI\VEN_8086&DEV_A0A3','SM Bus Controller'),
  @('PCI\VEN_8086&DEV_9A1D&SUBSYS_11112222&REV_01','PCI\VEN_8086&DEV_9A1D','USB controller 9A1D'),
  @('PCI\VEN_8086&DEV_9A1B&SUBSYS_11112222&REV_01','PCI\VEN_8086&DEV_9A1B','USB controller 9A1B'),
  @('PCI\VEN_8086&DEV_A0C8&SUBSYS_02062782&REV_20','PCI\VEN_8086&DEV_A0C8','Multimedia audio controller'),
  @('ACPI\VEN_INTC&DEV_1047','ACPI\INTC1047','INTC1047'),
  @('ACPI\VEN_INTC&DEV_1043','ACPI\INTC1043','INTC1043 SEN4'),
  @('ACPI\VEN_INTC&DEV_1044','ACPI\INTC1044','INTC1044'),
  @('ACPI\VEN_INTC&DEV_1051','ACPI\INTC1051','INTC1051'),
  @('ACPI\VEN_INTC&DEV_1040','ACPI\INTC1040','INTC1040'),
  @('ACPI\VEN_INT&DEV_34C5','ACPI\INT34C5','INT34C5'),
  @('ACPI\VEN_INTC&DEV_1043','ACPI\INTC1043','INTC1043 SEN3'),
  @('ACPI\VEN_INTC&DEV_1043','ACPI\INTC1043','INTC1043 SEN2'),
  @('PCI\VEN_8086&DEV_9A11&SUBSYS_00000000&REV_01','PCI\VEN_8086&DEV_9A11','Base system device')
 )
 $devices=New-Object System.Collections.Generic.List[object]
 for($i=0;$i -lt $rows.Count;$i++){
  $devices.Add([pscustomobject]@{instanceId=($rows[$i][0]+'\TEST'+$i);name=$rows[$i][2];kind='Missing';code=28;category='';hardwareIds=@($rows[$i][0],$rows[$i][1]);compatibleIds=@()})
 }
 if($devices.Count -ne 23){throw ('Aquarius fixture must contain 23 devices, got '+$devices.Count)}
 if(@($devices|Where-Object{$_.code -ne 28}).Count){throw 'Aquarius fixture lost the Code 28 state'}

 $ids=@($rows|ForEach-Object{[string]$_[1]}|Select-Object -Unique)
 $models=for($i=0;$i -lt $ids.Count;$i++){'%D'+$i+'%=Install,'+$ids[$i]}
 $inf=Join-Path $work 'Intel-FORCED-Aquarius.inf'
 $body="[Version]`r`nClass=System`r`nDriverVer=10/01/2026,10.1.18838.8284`r`nCatalogFile=Aquarius.cat`r`n[Manufacturer]`r`n%Intel%=Intel,NTamd64.10.0...17763`r`n[Intel.NTamd64.10.0...17763]`r`n"+($models -join "`r`n")+"`r`n"
 [IO.File]::WriteAllText($inf,$body,[Text.Encoding]::Unicode)
 [IO.File]::WriteAllBytes((Join-Path $work 'Aquarius.cat'),[byte[]](1,2,3))
 $model=Get-GSInfModel -Path $inf -Architecture x64 -Build 19041
 $matched=0
 foreach($device in $devices){
  $selected=Select-GSInfForDevice -Device $device -Models @($model) -PackageName 'Intel-FORCED-Chipset-10x64-drp.zip'
  if($null -eq $selected.Model){throw ('Aquarius ID was rejected: '+$device.hardwareIds[0]+' | '+$selected.Reason)}
  if(-not $selected.SourceMarkedForced){throw 'DriverPack FORCED metadata was not recorded'}
  $matched++
 }
 if($matched -ne 23){throw ('Not all Aquarius devices matched: '+$matched)}
 $wrong=[pscustomobject]@{instanceId='PCI\VEN_9999&DEV_9999\TEST';name='Unrelated';code=28;category='';hardwareIds=@('PCI\VEN_9999&DEV_9999');compatibleIds=@()}
 if($null -ne (Select-GSInfForDevice -Device $wrong -Models @($model) -PackageName 'FORCED.zip').Model){throw 'Unrelated device accepted a DriverPack package'}

 if((Get-GSPackageCacheKey 'https://a.invalid/x/driver.zip') -eq (Get-GSPackageCacheKey 'https://b.invalid/y/driver.zip')){throw 'URL-specific package cache keys collided for different sources'}
 $cacheFile=Join-Path $work 'cache.zip';[IO.File]::WriteAllBytes($cacheFile,[byte[]](1,2,3,4))
 $cacheManifest=Join-Path $work 'package.json';$cacheUrl='https://a.invalid/x/driver.zip'
 $cacheHash=(Get-FileHash -LiteralPath $cacheFile -Algorithm SHA256).Hash.ToLowerInvariant()
 [IO.File]::WriteAllText($cacheManifest,([pscustomobject]@{url=$cacheUrl;bytes=4;sha256=$cacheHash}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 if(!(Test-GSCacheManifest $cacheFile $cacheManifest $cacheUrl)){throw 'A verified package cache entry was rejected'}
 [IO.File]::WriteAllBytes($cacheFile,[byte[]](9,2,3,4))
 if(Test-GSCacheManifest $cacheFile $cacheManifest $cacheUrl){throw 'A modified cached package was reused'}
 $ordered=@(
  [pscustomobject]@{kind='Zip';url='https://dl.driverpack.io/repack/Sound_Intel/Intel/FORCED/SST/x.zip';label='sound'},
  [pscustomobject]@{kind='Zip';url='https://dl.driverpack.io/repack/Chipset/Intel/FORCED/SerialIO/x.zip';label='serial'},
  [pscustomobject]@{kind='Zip';url='https://dl.driverpack.io/repack/Chipset/Intel/FORCED/Chipset/x.zip';label='chipset'}
 )|Sort-Object @{Expression={Get-GSPackagePriority $_}}
 if($ordered[0].label -ne 'chipset' -or $ordered[1].label -ne 'serial' -or $ordered[2].label -ne 'sound'){throw 'Parent-driver dependency order is incorrect'}

 # Regression for the exact field crash seen after the first successful
 # PnPUtil call on Windows PowerShell 5.1 (List[object] through @(...)).
 $generic=New-Object System.Collections.Generic.List[object]
 $generic.Add([pscustomobject]@{instanceId='A'});$generic.Add([pscustomobject]@{instanceId='B'})
 $stable=@(ConvertTo-GSStableArray $generic)
 if($stable.Count -ne 2 -or $stable[1].instanceId -ne 'B'){throw 'Generic install-plan list cannot be enumerated safely'}
 if(@(Get-GSUnresolvedTargets @($stable) @()).Count -ne 0){throw 'Empty selection must produce an empty unresolved target list'}
 if(@(Get-GSUnresolvedTargets @($stable) @('B')).Count -ne 1){throw 'Selected unresolved target filtering is incorrect'}

 $workerSource=Get-Content -LiteralPath (Join-Path $engine 'Worker.ps1') -Raw -Encoding UTF8
 $runStart=$workerSource.IndexOf('function Run-Install')
 $runEnd=$workerSource.IndexOf("`ntry {",$runStart)
 $runSource=$workerSource.Substring($runStart,$runEnd-$runStart)
 $downloadPos=$runSource.IndexOf('$prepared.Add(')
 $unpackPos=$runSource.IndexOf("Write-Status 'Распаковка'")
 $installPos=$runSource.IndexOf("Write-Status 'Установка'")
 if($downloadPos -lt 0 -or $unpackPos -le $downloadPos -or $installPos -le $unpackPos){throw 'Batch flow is not download-all -> unpack-all -> install'}

 $selectedSource=Get-Content -LiteralPath (Join-Path $engine 'Selected.ps1') -Raw -Encoding UTF8
 if($selectedSource -notmatch "'Mode' 'fallback'"){throw 'Fresh Windows Update fallback is not invoked for unresolved DRP devices'}

 if((Get-GSWuaInstallOutcome 4 -2145124330) -ne 'PendingRebootOrBusy'){throw '0x80240016 was not classified'}
 if((Get-GSWuaErrorExplanation -2145124330) -notmatch 'перезагруз'){throw '0x80240016 explanation is not actionable'}

 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $badZip=Join-Path $work 'bad.zip'
 $zip=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
 try{$entry=$zip.CreateEntry('../escape.txt');$stream=$entry.Open();try{$bytes=[Text.Encoding]::UTF8.GetBytes('bad');$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
 $blocked=$false;try{$null=Expand-GSSafeArchive -Archive $badZip -Destination (Join-Path $work 'expanded')}catch{$blocked=$true}
 if(-not $blocked -or (Test-Path -LiteralPath (Join-Path $work 'escape.txt'))){throw 'ZIP traversal was not blocked'}

 Write-Host 'Aquarius NS483 regression passed: 23 Code 28 devices, exact INF matches, PS5 bulk plan, phased batch flow, fresh WU fallback, cache isolation, dependency order, ZIP traversal and 0x80240016.'
}finally{
 $env:GARANT_PO_DATA_ROOT=$oldData
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
