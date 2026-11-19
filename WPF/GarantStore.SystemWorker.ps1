param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
try {
 . (Join-Path $PSScriptRoot 'DriverEngine\SystemProfile.ps1')
 . (Join-Path $PSScriptRoot 'GarantStore.SystemSummary.ps1')
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $profile=Get-GSComputerProfile
 $profile|Add-Member -NotePropertyName details -NotePropertyValue (Get-GSSystemDetail)
 # AdapterRAM is a 32-bit WMI field (max 4 GB); attach the real size from the driver key.
 try{
  $gpuClassMemory=Get-GSGpuClassMemory
  foreach($row in @($profile.details.graphics|Where-Object{$null -ne $_})){
   $vram=Get-GSGpuMemoryInfo -Name ([string]$row.Name) -PnpDeviceId ([string]$row.PNPDeviceID) -AdapterRam $row.AdapterRAM -ClassMemory $gpuClassMemory
   $row|Add-Member -NotePropertyName VideoMemoryBytes -NotePropertyValue $vram.Bytes -Force
   $row|Add-Member -NotePropertyName VideoMemoryAtLeast -NotePropertyValue $vram.AtLeast -Force
   $row|Add-Member -NotePropertyName VideoMemorySource -NotePropertyValue $vram.Source -Force
  }
 }catch{}
 $services=@(foreach($name in @('wuauserv','BITS','AppXSvc','ClipSVC','InstallService')){try{$s=Get-Service $name -ErrorAction Stop;[pscustomobject]@{name=$name;status=[string]$s.Status}}catch{[pscustomobject]@{name=$name;status='Не определено'}}})
 $problemCount=try{@(Get-CimInstance Win32_PnPEntity -OperationTimeoutSec 10 -ErrorAction Stop|Where-Object{$_.ConfigManagerErrorCode -ne 0}).Count}catch{$null}
 $driverCount=try{@(Get-CimInstance Win32_PnPSignedDriver -OperationTimeoutSec 10 -ErrorAction Stop).Count}catch{$null}
 $profile|Add-Member -NotePropertyName services -NotePropertyValue ($services)
 $profile|Add-Member -NotePropertyName installedDriverCount -NotePropertyValue $driverCount
 $profile|Add-Member -NotePropertyName problemDeviceCount -NotePropertyValue $problemCount
 # Current engine data root first; the per-user location is read for history written by older builds.
 $history=@()
 foreach($historyRoot in @((Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GarantStoreEngine'),(Join-Path $env:LOCALAPPDATA 'Garant Store\Drivers'))){
  # Stable ID first; the pre-migration ID keeps older per-user history readable.
  foreach($historyId in @($profile.localId,$profile.legacyLocalId)|Where-Object{$_}){
   $historyPath=Join-Path $historyRoot ('Devices\'+$historyId+'\sessions.json')
   if(Test-Path -LiteralPath $historyPath){try{$history=@(Get-Content -LiteralPath $historyPath -Raw -Encoding UTF8|ConvertFrom-Json|ForEach-Object{$_})}catch{}}
   if($history.Count){break}
  }
  if($history.Count){break}
 }
 $profile|Add-Member -NotePropertyName history -NotePropertyValue ($history)
 # Plain-language first page: model, CPU, GPU, RAM, storage, panel, battery.
 try{$profile|Add-Member -NotePropertyName summary -NotePropertyValue (New-GSSystemSummary (Get-GSSummaryRaw))}catch{$profile|Add-Member -NotePropertyName summaryError -NotePropertyValue ($_.Exception.Message+' ['+[IO.Path]::GetFileName([string]$_.InvocationInfo.ScriptName)+':'+$_.InvocationInfo.ScriptLineNumber+']')}
 $profile|Add-Member -NotePropertyName collectionMs -NotePropertyValue ($watch.ElapsedMilliseconds)
 $json=$profile|ConvertTo-Json -Depth 9
 [IO.File]::WriteAllText($OutputPath,$json,[Text.UTF8Encoding]::new($false))
} catch {
 [IO.File]::WriteAllText($OutputPath,(@{error=$_.Exception.Message}|ConvertTo-Json),[Text.UTF8Encoding]::new($false));exit 1
}
