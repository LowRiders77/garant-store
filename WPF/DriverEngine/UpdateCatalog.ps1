Set-StrictMode -Version Latest

function Get-WindowsDriverUpdateMetadata($Update) {
 $metadata=[ordered]@{manufacturer='';model='';hardwareId='';date='';provider='';class=''}
 try{$metadata.manufacturer=[string]$Update.DriverManufacturer}catch{}
 try{$metadata.model=[string]$Update.DriverModel}catch{}
 try{$metadata.hardwareId=[string]$Update.DriverHardwareID}catch{}
 try{$value=[datetime]$Update.DriverVerDate;if($value -gt [datetime]::MinValue){$metadata.date=$value.ToString('yyyy-MM-dd')}}catch{}
 try{$metadata.provider=[string]$Update.DriverProvider}catch{}
 try{$metadata.class=[string]$Update.DriverClass}catch{}
 return [pscustomobject]$metadata
}

function Get-GSWuaComparableHardwareIds($Values) {
 $ids=New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
 foreach($value in @($Values)) {
  foreach($candidate in ([string]$value -split '[,;\r\n]')) {
   $normalized=$candidate.Trim()
   if(-not $normalized){continue}
   [void]$ids.Add($normalized)
   if(Get-Command Get-NormalIds -ErrorAction SilentlyContinue) {
    $device=[pscustomobject]@{hardwareIds=@($normalized)}
    foreach($expanded in @(Get-NormalIds $device)){if($expanded){[void]$ids.Add([string]$expanded)}}
   }
  }
 }
 return ,$ids
}

function Get-GSWuaInstallOutcome([int]$ResultCode,[int]$HResult){
 # 2/3 = succeeded (with errors). 0x80070103 means Windows kept an equal or
 # better driver that is already installed: nothing to do, not a failure.
 if($ResultCode -in @(2,3)){return 'Installed'}
 if($HResult -eq -2147024637){return 'NotNeeded'}
 return 'Failed'
}
function Format-GSHResult([int]$HResult){return ('0x'+([uint32]([int64]$HResult -band 0xFFFFFFFF)).ToString('X8'))}

function Get-MatchedWindowsDriverUpdateIds($Devices,$Updates) {
 $matched=New-Object System.Collections.Generic.List[string]
 foreach($device in @($Devices)){
  $deviceIds=@()
  $hardwareProperty=$device.PSObject.Properties['hardwareIds'];$hwidProperty=$device.PSObject.Properties['hwid']
  if($hardwareProperty){$deviceIds+=@($hardwareProperty.Value)}
  if($hwidProperty){$deviceIds+=@($hwidProperty.Value)}
  $hardware=Get-GSWuaComparableHardwareIds $deviceIds
  if($hardware.Count -eq 0){continue}
  foreach($update in @($Updates)){
   $updateHardwareProperty=$update.PSObject.Properties['driverHardwareId']
   $candidateId=if($updateHardwareProperty){[string]$updateHardwareProperty.Value}else{''}
   if(-not $candidateId){continue}
   $updateHardware=Get-GSWuaComparableHardwareIds @($candidateId)
   $isMatched=$false
   foreach($id in $updateHardware){if($hardware.Contains($id)){$isMatched=$true;break}}
   $instanceProperty=$update.PSObject.Properties['instanceId']
   $instanceId=if($instanceProperty){[string]$instanceProperty.Value}else{''}
   if($isMatched -and $instanceId -and -not $matched.Contains($instanceId)){$matched.Add($instanceId)}
  }
 }
 return @($matched.ToArray())
}


function Export-GSWuaUpdateContent($Update,[string]$Destination) {
 if(-not [bool]$Update.IsDownloaded){throw 'Windows Update не подтвердил завершение загрузки пакета.'}
 New-Item -ItemType Directory -Path $Destination -Force|Out-Null
 $Update.CopyFromCache($Destination,$false)
 $files=@(Get-ChildItem -LiteralPath $Destination -File -Recurse -ErrorAction Stop)
 if($files.Count -eq 0){throw 'Windows Update не экспортировал файлы пакета в папку драйверов.'}
 return $files
}

function Invoke-GSWuaDriverSearch($Searcher) {
 try{return $Searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")}catch{
  $hresult=('{0:X8}' -f ([long]$_.Exception.HResult -band 0xFFFFFFFFL))
  throw ('Windows Update не выполнил поиск драйверов (HRESULT 0x'+$hresult+'): '+$_.Exception.Message)
 }
}

function Get-WindowsDriverUpdates {
 param([scriptblock]$StatusCallback=$null,[scriptblock]$LogCallback=$null)
 if($StatusCallback){& $StatusCallback 'Поиск обновлений' 'Проверяем применимые обновления драйверов через Windows Update.'}
 if($LogCallback){& $LogCallback 'Запущен поиск применимых обновлений типа Driver.'}
 try{
  $wuService=Get-CimInstance -ClassName Win32_Service -Filter "Name='wuauserv'" -ErrorAction Stop
  if($wuService.StartMode -eq 'Disabled'){throw 'Служба Windows Update (wuauserv) отключена. Включите её в службах Windows или используйте источник производителя/DriverPack.'}
 }catch{
  if($_.Exception.Message -like '*wuauserv*'){throw}
  if($LogCallback){& $LogCallback ('Не удалось проверить состояние службы Windows Update: '+$_.Exception.Message)}
 }
 $session=New-Object -ComObject Microsoft.Update.Session
 $session.ClientApplicationID='Garant Store'
 $searcher=$session.CreateUpdateSearcher()
 try{$result=Invoke-GSWuaDriverSearch $searcher}catch{if($LogCallback){& $LogCallback $_.Exception.Message};throw}
 $items=New-Object System.Collections.ArrayList
 for($i=0;$i -lt $result.Updates.Count;$i++){
  [void]$items.Add((ConvertTo-GSWuaDriverRow $result.Updates.Item($i)))
 }
 return @($items.ToArray())
}

function ConvertTo-GSWuaDriverRow($Update) {
 $identity=$update.Identity
  $id=[string]$identity.UpdateID+'|'+[string]$identity.RevisionNumber
  $title=[string]$update.Title
  $metadata=Get-WindowsDriverUpdateMetadata $update
  $manufacturer=$metadata.manufacturer;$model=$metadata.model;$hardware=$metadata.hardwareId;$date=$metadata.date
  $eulaAccepted=$false
  try{$eulaAccepted=[bool]$update.EulaAccepted}catch{}
  $selectable=($eulaAccepted -and -not [string]::IsNullOrWhiteSpace($hardware) -and $metadata.class -notmatch '(?i)firmware' -and $title -notmatch '(?i)\b(BIOS|UEFI|Firmware)\b')
  $detail=@($manufacturer,$model,$(if($date){'Дата драйвера '+$date}),$(if($hardware){'Hardware ID '+$hardware}))|Where-Object{![string]::IsNullOrWhiteSpace([string]$_)}
  return [pscustomobject]@{instanceId=$id;name=$title;hwid=($detail -join ' · ');kind='Update';reason=$(if($selectable){'Применимое предложение Windows Update; установка после подтверждения.'}elseif(-not $eulaAccepted){'Сначала примите условия этого обновления в Центре обновления Windows.'}else{'Автоматическая установка заблокирована: прошивка или недостаточно сведений об оборудовании.'});driverDate=$date;driverManufacturer=$manufacturer;driverModel=$model;driverHardwareId=$hardware;driverProvider=$metadata.provider;driverClass=$metadata.class;eulaAccepted=$eulaAccepted;source='Windows Update';canSelect=$selectable;Selected=$false}
}
