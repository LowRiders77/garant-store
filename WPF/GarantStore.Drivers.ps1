Set-StrictMode -Version Latest

function Invoke-GSDriverApi {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$Method='GET',$Body=$null,[switch]$NoAuth)
 if(-not $script:driverEndpoint){throw 'Драйверный движок ещё не подключён'}
 $request=[Net.HttpWebRequest]::Create([string]$script:driverEndpoint.url+$Path)
 $request.Method=$Method;$request.Proxy=$null;$request.Timeout=5000;$request.ReadWriteTimeout=5000;$request.KeepAlive=$false
 $request.CachePolicy=[Net.Cache.HttpRequestCachePolicy]::new([Net.Cache.HttpRequestCacheLevel]::NoCacheNoStore)
 if(-not $NoAuth){$request.Headers['X-Garant-Token']=[string]$script:driverEndpoint.token}
 if($null -ne $Body){
  $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 6 -Compress))
  $request.ContentType='application/json; charset=utf-8';$request.ContentLength=$bytes.Length
  $stream=$request.GetRequestStream();try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
 }
 try{$response=$request.GetResponse()}catch [Net.WebException]{
  $response=$_.Exception.Response
  if($null -eq $response){throw}
  try{$reader=New-Object IO.StreamReader($response.GetResponseStream());$message=$reader.ReadToEnd();$reader.Dispose()}finally{$response.Dispose()}
  try{$errorObject=$message|ConvertFrom-Json;if($errorObject.error){throw ([string]$errorObject.error)} }catch{if($_.Exception.Message -notmatch '^HTTP '){throw}}
  throw ('HTTP '+[int]$response.StatusCode)
 }
 try{
  if($response.ContentType -like 'application/json*'){$reader=New-Object IO.StreamReader($response.GetResponseStream(),[Text.Encoding]::UTF8);try{return ($reader.ReadToEnd()|ConvertFrom-Json)}finally{$reader.Dispose()}}
  $memory=New-Object IO.MemoryStream;$response.GetResponseStream().CopyTo($memory);return ,$memory.ToArray()
 }finally{$response.Dispose()}
}

function Start-GSDriverStatusFetch {
 if($script:driverStatusFetch -or -not $script:driverEndpoint){return}
 $runspace=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
 $ps=[System.Management.Automation.PowerShell]::Create()
 try{
  $runspace.Open();$ps.Runspace=$runspace
  $fetch=@'
param([string]$Url,[string]$Token)
try{
 $request=[Net.HttpWebRequest]::Create($Url);$request.Method='GET';$request.Proxy=$null;$request.Timeout=5000;$request.ReadWriteTimeout=5000;$request.KeepAlive=$false
 $request.Headers['X-Garant-Token']=$Token
 $response=$request.GetResponse()
 try{$reader=New-Object IO.StreamReader($response.GetResponseStream(),[Text.Encoding]::UTF8);try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}}
 finally{$response.Dispose()}
 [pscustomobject]@{Success=$true;Text=$text;Error=''}
}catch{[pscustomobject]@{Success=$false;Text='';Error=$_.Exception.Message}}
'@
  $null=$ps.AddScript($fetch).AddArgument([string]($script:driverEndpoint.url+'api/status')).AddArgument([string]$script:driverEndpoint.token)
  $async=$ps.BeginInvoke()
  $script:driverStatusFetch=@{PowerShell=$ps;Runspace=$runspace;Async=$async;Started=[DateTime]::UtcNow}
 }catch{
  try{$ps.Dispose()}catch{};try{$runspace.Dispose()}catch{}
  throw
 }
}

function Complete-GSDriverStatusFetch {
 if(-not $script:driverStatusFetch -or -not $script:driverStatusFetch.Async.IsCompleted){return $false}
 $fetch=$script:driverStatusFetch;$script:driverStatusFetch=$null
 try{
  $items=@($fetch.PowerShell.EndInvoke($fetch.Async))
  if($items.Count -eq 0){throw 'Локальный API не вернул состояние.'}
  $result=$items[-1]
  if(-not [bool]$result.Success){throw [string]$result.Error}
  $snapshot=[string]$result.Text|ConvertFrom-Json -ErrorAction Stop
  Apply-GSDriverSnapshot $snapshot
  $status=Get-GSDriverProperty $snapshot 'status' $null
  $script:driverActionBusy=[bool](Get-GSDriverProperty $status 'running' $false)
  $script:driverLastStatusAt=[DateTime]::UtcNow
 }catch{
  $message=$_.Exception.Message
  $script:driverDetail.Text='Локальный модуль временно не ответил; последний результат сохранён. Повторное подключение…'
  $script:driverState.Text='Переподключение'
  $script:driverProgress.IsIndeterminate=$true
  $script:driverLastStatusErrorAt=[DateTime]::UtcNow
  Write-GSDriverUiLog 'STATUS ERROR' $message
 }finally{try{$fetch.PowerShell.Dispose()}catch{};try{$fetch.Runspace.Dispose()}catch{}}
 return $true
}

function Get-GSDriverProperty($Object,[string]$Name,$Default=$null){
 if($null -eq $Object){return $Default}
 $property=$Object.PSObject.Properties[$Name]
 if($null -eq $property -or $null -eq $property.Value){return $Default}
 return $property.Value
}

function Write-GSDriverUiLog([string]$Event,[string]$Detail){
 if(-not $script:driverEndpoint){return}
 try{$null=Invoke-GSDriverApi -Path '/api/ui-event' -Method 'POST' -Body @{event=$Event;detail=$Detail}}catch{}
}

function Get-GSSelectedDriverRows($ItemsSource){
 if($null -eq $ItemsSource){return @()}
 return @($ItemsSource|Where-Object{[bool](Get-GSDriverProperty $_ 'Selected' $false) -and [string](Get-GSDriverProperty $_ 'kind' '') -ne 'Inventory' -and [bool](Get-GSDriverProperty $_ 'canSelect' $true)})
}

function Get-GSDriverSourceUri($Device){
 $ids=@(Get-GSDriverProperty $Device 'hardwareIds' @())
 $hwid=[string](Get-GSDriverProperty $Device 'hwid' '')
 if($hwid){$ids+=,$hwid}
 $ids=@($ids|ForEach-Object{([string]$_).ToUpperInvariant()})
 $kind=[string](Get-GSDriverProperty $Device 'kind' '')
 if($kind -eq 'GPU'){
  if($ids -contains 'PCI\VEN_8086&DEV_4E55'){return 'https://www.intel.com/content/www/us/en/download/776137/intel-7th-10th-gen-processor-graphics-windows.html'}
  if(@($ids|Where-Object{$_ -match '^PCI\\VEN_10DE&DEV_'}).Count){return 'https://www.nvidia.com/Download/index.aspx?lang=ru-ru'}
  if(@($ids|Where-Object{$_ -match '^PCI\\VEN_1002&DEV_'}).Count){return 'https://www.amd.com/en/support/download/drivers.html'}
  if(@($ids|Where-Object{$_ -match '^PCI\\VEN_8086&DEV_'}).Count){return 'https://www.intel.com/content/www/us/en/support/detect.html'}
 }
 $id=$ids|Where-Object{$_ -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_|USB\\VID_|ACPI\\)'}|Select-Object -First 1
 if(-not $id){return 'https://driverpack.io/en/hwids/'}
 return 'https://driverpack.io/en/hwids/'+[uri]::EscapeDataString($id)
}

function Open-GSDriverSource {
 $selected=@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource)
 $targets=@($selected|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -in @('Missing','Issue','GPU')})
 if($targets.Count -ne 1){[void][Windows.MessageBox]::Show('Отметьте ровно одно устройство, чтобы открыть для него подходящий источник драйвера. Для видеокарты откроется сайт её производителя, для остальных устройств — поиск DriverPack по Hardware ID.','Источник драйвера',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Information);return}
 $url=Get-GSDriverSourceUri $targets[0]
 try{Start-Process -FilePath $url;Write-GSDriverUiLog 'SOURCE OPEN' ([string](Get-GSDriverProperty $targets[0] 'hwid' '')+' | '+$url);$script:driverHint.Text='Источник открыт в браузере. После скачивания ZIP используйте «Установить из папки».'}catch{$script:driverHint.Text='Не удалось открыть источник: '+$_.Exception.Message}
}

function Repair-GSWindowsUpdate {
 $answer=[Windows.MessageBox]::Show('Если служба Windows Update или BITS отключена, Garant Store изменит её тип запуска на «Вручную» и запустит службу. Политики обновлений и другие параметры не меняются. После восстановления нужно выполнить сканирование ещё раз. Продолжить?','Восстановление Windows Update',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
 if($answer -ne [Windows.MessageBoxResult]::Yes){return}
 Invoke-GSDriverAction 'windows-update-repair'
}

function Start-GSDriverEngine {
 $runtimeRoot=Join-Path $env:LOCALAPPDATA 'Garant Store\DriverRuntime'
 # The elevated engine keeps everything it installs in an administrators-only
 # folder; the user's Downloads only receives copies of downloaded packages.
 $dataRoot=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GarantStoreEngine'
 $engineRoot=Join-Path $root 'DriverEngine'
 $server=Join-Path $engineRoot 'Server.ps1'
 if(-not (Test-Path -LiteralPath $server)){throw 'Не найден сервер Garant-ПО 6.0'}
 # Only the runtime folder is created here. The data root must be created by the
 # elevated server with its protected ACL; a user-created folder would be refused.
 New-Item -ItemType Directory -Force -Path $runtimeRoot|Out-Null
 $bootstrap=Join-Path $runtimeRoot ('connection-'+[guid]::NewGuid().ToString('N')+'.json')
 $script:driverBootstrap=$bootstrap
 $hostProcess=Join-Path $PSHOME 'powershell.exe'
 # The client generates the session token and hands it to the elevated server on
 # its command line, which standard-user processes cannot read. The bootstrap file
 # therefore carries only the address.
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$tokenBytes=New-Object byte[] 32;$rng.GetBytes($tokenBytes)}finally{$rng.Dispose()}
 $sessionToken=-join ($tokenBytes|ForEach-Object{$_.ToString('x2')})
 $args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$server+'"'),'-DataRoot',('"'+$dataRoot+'"'),'-SecureDataRoot','-Embedded','-BootstrapFile',('"'+$bootstrap+'"'),'-Token',$sessionToken)
 $script:driverProcess=Start-Process -FilePath $hostProcess -ArgumentList ($args -join ' ') -Verb RunAs -WindowStyle Hidden -PassThru
 $limit=(Get-Date).AddSeconds(35)
 while((Get-Date)-lt $limit){
  if(Test-Path -LiteralPath $bootstrap){
   $raw=[IO.File]::ReadAllText($bootstrap,[Text.Encoding]::UTF8)
   $info=$raw|ConvertFrom-Json
   if($info.PSObject.Properties['ok'] -and -not [bool]$info.ok){throw ('Драйверный модуль не запущен: '+[string]$info.error)}
   if($info.ok -and $info.version -eq '6.0' -and $info.url -match '^http://127\.0\.0\.1:\d+/$'){$script:driverEndpoint=[pscustomobject]@{ok=$true;version=[string]$info.version;url=[string]$info.url;pid=$info.pid;token=$sessionToken};break}
  }
  if($script:driverProcess.HasExited){throw 'Сервер Garant-ПО завершился при запуске. Проверьте журналы в папке Drivers.'}
  Start-Sleep -Milliseconds 250
 }
 if(-not $script:driverEndpoint){throw 'Сервер Garant-ПО не запустился вовремя'}
 $health=Invoke-GSDriverApi -Path '/api/health' -NoAuth
 if(-not $health.ok -or $health.version -ne '6.0'){throw 'Сервер Garant-ПО не прошёл проверку готовности'}
}

function Set-GSDriverState([string]$Title,[string]$Detail,[bool]$Busy=$false){
 $script:driverState.Text=$Title;$script:driverDetail.Text=$Detail
 $script:driverProgress.IsIndeterminate=$Busy
 if(-not $Busy){$script:driverProgress.Value=0}
 $script:driverScan.IsEnabled=-not $Busy
 $script:driverNetwork.IsEnabled=-not $Busy;$script:driverLocal.IsEnabled=-not $Busy
 $script:driverRestore.IsEnabled=-not $Busy
 $script:driverWuRepair.IsEnabled=-not $Busy
 $script:driverCancel.IsEnabled=$Busy
}

function Save-GSDriverSelection {
 if(-not (Get-Variable driverSelectedIds -Scope Script -ErrorAction SilentlyContinue)){$script:driverSelectedIds=@{}}
 foreach($row in @($script:driverDevices.ItemsSource)){
  $id=[string](Get-GSDriverProperty $row 'instanceId' '')
  if(-not $id){continue}
  if([bool](Get-GSDriverProperty $row 'Selected' $false) -and [bool](Get-GSDriverProperty $row 'canSelect' $false)){$script:driverSelectedIds[$id]=$true}else{$script:driverSelectedIds.Remove($id)}
 }
}
function Update-GSDriverActionVisibility([bool]$Scanned,[bool]$Busy){
 Save-GSDriverSelection
 $selected=@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource)
 $eligible=@($script:driverDevices.ItemsSource|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -in @('Missing','Issue','GPU','Update','Library') -and [bool](Get-GSDriverProperty $_ 'canSelect' $false)})
 $allSelected=($eligible.Count -gt 0 -and @($eligible|Where-Object{-not [bool](Get-GSDriverProperty $_ 'Selected' $false)}).Count -eq 0)
 $show=($Scanned -and $selected.Count -gt 0 -and -not $Busy)
 $script:driverSelectionActions.Visibility=if($show){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
 $script:driverSelectAll.IsEnabled=($Scanned -and -not $Busy -and $eligible.Count -gt 0)
 $script:driverSelectAll.Content=if($eligible.Count -eq 0){'В разделе нет доступных элементов'}elseif($allSelected){'Снять выбор'}else{'Выбрать доступные'}
 $script:driverSource.IsEnabled=($Scanned -and -not $Busy -and $selected.Count -eq 1 -and [string](Get-GSDriverProperty $selected[0] 'kind' '') -in @('Missing','Issue','GPU'))
}

function Toggle-GSDriverSelection {
 $eligible=@($script:driverDevices.ItemsSource|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -in @('Missing','Issue','GPU','Update','Library') -and [bool](Get-GSDriverProperty $_ 'canSelect' $false)})
 $clear=($eligible.Count -gt 0 -and @($eligible|Where-Object{-not [bool](Get-GSDriverProperty $_ 'Selected' $false)}).Count -eq 0)
 foreach($device in $eligible){if($null -eq $device.PSObject.Properties['Selected']){$device|Add-Member -NotePropertyName Selected -NotePropertyValue (-not $clear)}else{$device.Selected=(-not $clear)}}
 $script:driverDevices.Items.Refresh()
 Update-GSDriverActionVisibility $true $script:driverActionBusy
}

function Set-GSDriverViewMode([string]$Mode){
 if($Mode -notin @('attention','inventory','components')){return}
 $script:driverViewMode=$Mode
 $script:driverViewAll.Content=if($Mode -eq 'inventory'){'Проблемы и обновления'}else{'Все установленные драйверы'}
 $script:driverViewComponents.Content=if($Mode -eq 'components'){'Проблемы и обновления'}else{'Компоненты Windows'}
 if($script:driverLastSnapshot){Apply-GSDriverSnapshot $script:driverLastSnapshot}
}
function Toggle-GSDriverLogPanel {
 $show=($script:driverLogPanel.Visibility -ne [Windows.Visibility]::Visible)
 $script:driverLogPanel.Visibility=if($show){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
 $script:driverLogColumn.Width=if($show){[Windows.GridLength]::new(0.8,[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::new(0)}
 $script:driverLogSpacer.Width=if($show){[Windows.GridLength]::new(12)}else{[Windows.GridLength]::new(0)}
 $script:driverToggleLog.Content=if($show){'Скрыть журнал'}else{'Показать журнал'}
}
function Apply-GSDriverSnapshot($Snapshot){
 if($null -eq $Snapshot){return}
 $script:driverLastSnapshot=$Snapshot
 $s=Get-GSDriverProperty $Snapshot 'status' ([pscustomobject]@{})
 $busy=[bool](Get-GSDriverProperty $s 'running' $false)
 $phase=[string](Get-GSDriverProperty $s 'phase' 'Ожидание')
 $message=[string](Get-GSDriverProperty $s 'message' 'Нажмите «Сканировать», чтобы проверить устройства.')
 $percent=Get-GSDriverProperty $s 'percent' -1
 $scanned=[bool](Get-GSDriverProperty $Snapshot 'scanned' $false)
 $devices=@(Get-GSDriverProperty $Snapshot 'devices' @())
 $logs=@(Get-GSDriverProperty $Snapshot 'logs' @())
 Set-GSDriverState -Title $phase -Detail $message -Busy $busy
 $profile=Get-GSDriverProperty $s 'systemProfile' $null
 if($profile){
  $machine=[string](Get-GSDriverProperty $profile 'manufacturer' 'Производитель не определён')
  $model=[string](Get-GSDriverProperty $profile 'model' 'Модель не указана в SMBIOS')
  $osName=[string](Get-GSDriverProperty $profile 'windows' 'Windows');$osBuild=[string](Get-GSDriverProperty $profile 'build' '')
  $script:driverDeviceProfile.Text=('Это устройство: '+$machine+' '+$model+'  •  '+$osName+$(if($osBuild){' build '+$osBuild}else{''}))
 }
 if([double]$percent -ge 0 -and [double]$percent -le 100){$script:driverProgress.IsIndeterminate=$false;$script:driverProgress.Value=[double]$percent}
 $libraryRows=@()
 $inventoryCount=0
 if($scanned){
  $problemRows=@($devices|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -in @('Missing','Issue','GPU')})
  $updateRows=@($devices|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -eq 'Update'})
  $libraryRows=@($devices|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -eq 'Library'})
  $inventoryCount=@($devices|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -eq 'Inventory'}).Count
  $eligibleCount=@($devices|Where-Object{[string](Get-GSDriverProperty $_ 'kind' '') -in @('Missing','Issue','GPU','Update','Library') -and [bool](Get-GSDriverProperty $_ 'canSelect' $false)}).Count
  $script:driverDeviceCount.Text=('Требуют внимания: '+($problemRows.Count+$updateRows.Count)+'  •  установленные драйверы: '+$inventoryCount+'  •  компоненты: '+$libraryRows.Count)
  $script:driverViewAll.IsEnabled=($inventoryCount -gt 0)
  $script:driverViewComponents.IsEnabled=($libraryRows.Count -gt 0)
  if(($problemRows.Count+$updateRows.Count) -eq 0 -and -not $busy){$script:driverHint.Text='Все обнаруженные устройства работают исправно. Подтверждённых обновлений нет.'}
  elseif($devices.Count -eq 0 -and -not $busy){$script:driverHint.Text='Драйверы актуальны; обновлений и недостающих библиотек не найдено.'}
  elseif(-not $busy -and $eligibleCount -eq 0){$script:driverHint.Text='Нет доступных обновлений для выбора. Установленные драйверы показаны для справки; неизвестная актуальность не означает, что их нужно заменять.'}
  elseif(-not $busy){$script:driverHint.Text='Выберите подходящие элементы в нужной категории. Установленные драйверы без подтверждённого обновления остаются только для справки.'}
 }else{$script:driverDeviceCount.Text='Результаты сканирования';if(-not $busy){$script:driverHint.Text='Сначала выполните сканирование системы.'}}
 if($busy){$script:driverHint.Text='Идёт операция. Закрытие раздела заблокировано до её остановки.'}
 Save-GSDriverSelection
 $selectedIds=@($script:driverSelectedIds.Keys)
 $rows=New-Object System.Collections.ArrayList
 foreach($device in $devices){
  $instanceId=[string](Get-GSDriverProperty $device 'instanceId' '')
  if($null -eq $device -or -not $instanceId){continue}
  $isSelected=$selectedIds -contains $instanceId
  if($null -eq $device.PSObject.Properties['Selected']){$device|Add-Member -NotePropertyName Selected -NotePropertyValue $isSelected}else{$device.Selected=$isSelected}
  $kind=[string](Get-GSDriverProperty $device 'kind' '')
  $kindText=switch($kind){'Update'{'Обновление Windows Update'}'Library'{[string](Get-GSDriverProperty $device 'libraryStatus' 'Компонент Windows')}'Inventory'{'Актуальность не проверена'}'GPU'{'Базовый видеодрайвер'}'Issue'{'Ошибка устройства, код '+[string](Get-GSDriverProperty $device 'code' '?')}default{'Драйвер не установлен'}}
  if($null -eq $device.PSObject.Properties['KindText']){$device|Add-Member -NotePropertyName KindText -NotePropertyValue $kindText}else{$device.KindText=$kindText}
  $category=if($kind -eq 'Inventory'){'Установленные драйверы'}elseif($kind -eq 'Library'){'Системные компоненты'}else{'Требуют внимания'}
  $order=if($kind -eq 'Inventory'){1}elseif($kind -eq 'Library'){2}else{0}
  if($null -eq $device.PSObject.Properties['DisplayCategory']){$device|Add-Member -NotePropertyName DisplayCategory -NotePropertyValue $category}else{$device.DisplayCategory=$category}
  if($null -eq $device.PSObject.Properties['DisplayOrder']){$device|Add-Member -NotePropertyName DisplayOrder -NotePropertyValue $order}else{$device.DisplayOrder=$order}
  if($kind -eq 'Inventory'){$device.Selected=$false;if($null -eq $device.PSObject.Properties['canSelect']){$device|Add-Member -NotePropertyName canSelect -NotePropertyValue $false}else{$device.canSelect=$false}}
  elseif($null -eq $device.PSObject.Properties['canSelect']){$device|Add-Member -NotePropertyName canSelect -NotePropertyValue ($kind -in @('Missing','Issue','GPU') -or ($kind -eq 'Update' -and [bool](Get-GSDriverProperty $device 'eulaAccepted' $false) -and -not [string]::IsNullOrWhiteSpace([string](Get-GSDriverProperty $device 'driverHardwareId' '')) -and [string](Get-GSDriverProperty $device 'driverClass' '') -notmatch '(?i)firmware' -and [string](Get-GSDriverProperty $device 'name' '') -notmatch '(?i)\b(BIOS|UEFI|Firmware)\b'))}
  [void]$rows.Add($device)
 }
 $view=[System.Windows.Data.CollectionViewSource]::GetDefaultView($rows)
 $view.GroupDescriptions.Clear()
 $view.GroupDescriptions.Add([System.Windows.Data.PropertyGroupDescription]::new('DisplayCategory'))
 $view.SortDescriptions.Clear()
 $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('DisplayOrder',[System.ComponentModel.ListSortDirection]::Ascending))
 $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('name',[System.ComponentModel.ListSortDirection]::Ascending))
 $mode=$script:driverViewMode
 $visibleRows=@($rows|Where-Object{
  $rowKind=[string](Get-GSDriverProperty $_ 'kind' '')
  if($mode -eq 'inventory'){$rowKind -eq 'Inventory'}
  elseif($mode -eq 'components'){$rowKind -eq 'Library'}
  else{$rowKind -in @('Missing','Issue','GPU','Update')}
 })
 $displayView=[System.Windows.Data.CollectionViewSource]::GetDefaultView($visibleRows)
 $displayView.GroupDescriptions.Clear()
 $displayView.GroupDescriptions.Add([System.Windows.Data.PropertyGroupDescription]::new('DisplayCategory'))
 $displayView.SortDescriptions.Clear()
 $displayView.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('DisplayOrder',[System.ComponentModel.ListSortDirection]::Ascending))
 $displayView.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('name',[System.ComponentModel.ListSortDirection]::Ascending))
 $script:driverDevices.ItemsSource=$displayView
 if($scanned -and -not $busy -and $mode -eq 'components'){$script:driverDeviceCount.Text=('Компоненты Windows: '+$libraryRows.Count+' • выбор и установка в этом разделе');$script:driverHint.Text='Установленные компоненты повторно не устанавливаются. Дополнительные библиотеки устанавливаются только по вашему выбору.'}
 elseif($scanned -and -not $busy -and $mode -eq 'inventory'){$script:driverDeviceCount.Text=('Установленные драйверы: '+$inventoryCount+' • справочный перечень');$script:driverHint.Text='Для установки откройте «Проблемы и обновления». Выбор в других разделах сохранён.'}
 $script:driverEmptyMessage.Text=if($visibleRows.Count -eq 0){if($mode -eq 'inventory'){'Установленные драйверы не найдены.'}elseif($mode -eq 'components'){'Компоненты для отображения не обнаружены.'}else{'Нет доступных обновлений для выбора.'}}else{''}
 $script:driverLog.Text=($logs|Where-Object{$_}|Select-Object -Last 80)-join [Environment]::NewLine
 $script:driverLog.ScrollToEnd()
 Update-GSDriverActionVisibility $scanned $busy
}

function Invoke-GSDriverAction([string]$Action){
 try{
  if($script:driverActionBusy){return}
  $apiAction=$Action;$ids=@()
  if($Action -in @('install','download')){
   $selected=@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource)
   if($selected.Count -eq 0){[void][Windows.MessageBox]::Show('Сначала отметьте строки после сканирования.','Garant Store',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Information);return}
   $skipped=@()
   foreach($row in $selected){
    $kind=[string](Get-GSDriverProperty $row 'kind' '')
    $instanceId=[string](Get-GSDriverProperty $row 'instanceId' '')
    if($kind -eq 'Library'){
     $libraryId=[string](Get-GSDriverProperty $row 'libraryId' '')
     if($Action -eq 'download' -and -not [bool](Get-GSDriverProperty $row 'downloadable' $false)){$skipped+=([string](Get-GSDriverProperty $row 'name' 'Компонент'));continue}
     if($libraryId){$ids+=('library:'+ $libraryId)}
    }elseif($kind -eq 'Update'){$ids+=('update:'+ $instanceId)}
    else{$ids+=('device:'+ $instanceId)}
   }
   $ids=@($ids|Where-Object{![string]::IsNullOrWhiteSpace($_)})
   if($skipped.Count){[void][Windows.MessageBox]::Show(("Только скачать не может получить компонент «"+($skipped -join ', ')+"» отдельно: его загружает и включает сама Windows. Остальные отмеченные пункты будут обработаны."),'Garant Store',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Information)}
   if($ids.Count -eq 0){return}
   if($Action -eq 'install'){
    $names=($selected|ForEach-Object{[string](Get-GSDriverProperty $_ 'name' 'Компонент')})-join [Environment]::NewLine
    $answer=[Windows.MessageBox]::Show(('Установить или обновить только отмеченные пункты? Обновления Windows загружаются средствами Центра обновления Windows.'+[Environment]::NewLine+[Environment]::NewLine+$names),'Подтверждение установки',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
    if($answer -ne [Windows.MessageBoxResult]::Yes){return}
    $apiAction='selected-install'
   }else{$apiAction='selected-download'}
  }elseif($Action -eq 'restore-point'){
   $answer=[Windows.MessageBox]::Show('Будет создана точка восстановления перед работой с драйверами. Если защита системного диска выключена, Garant Store включит её. Windows ограничивает создание точек одной за 24 часа. Продолжить?','Точка восстановления',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
   if($answer -ne [Windows.MessageBoxResult]::Yes){return}
  }elseif($Action -eq 'windows-update-repair'){
   $apiAction='windows-update-repair'
  }elseif($Action -eq 'network'){
   $answer=[Windows.MessageBox]::Show('Будет очищен DNS-кэш и сброшен каталог Winsock. IP-адреса, DNS-серверы и прокси будут сохранены. Возможна необходимость переподключить VPN. Для применения потребуется перезагрузка Windows. Продолжить?','Восстановление сети',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
   if($answer -ne [Windows.MessageBoxResult]::Yes){return}
  }
  $null=Invoke-GSDriverApi -Path '/api/action' -Method 'POST' -Body @{action=$apiAction;ids=$ids}
  $script:driverActionBusy=$true
  Set-GSDriverState -Title 'Операция запущена' -Detail 'Получаем состояние от движка Garant-ПО…' -Busy $true
  Write-GSDriverUiLog 'ACTION' ($apiAction+' | selected='+$ids.Count)
 }catch{$message=$_.Exception.Message;$script:driverDetail.Text=$message;$script:driverState.Text='Операция не запущена';Write-GSDriverUiLog 'ACTION ERROR' ($Action+' | '+$message)}
}

function Save-GSDriverDiagnostics {
 try{
  $dialog=New-Object Microsoft.Win32.SaveFileDialog;$dialog.Filter='ZIP архив (*.zip)|*.zip';$dialog.FileName='Garant-PO-Diagnostics.zip'
  if($dialog.ShowDialog() -ne $true){return}
  $bytes=Invoke-GSDriverApi -Path '/api/diagnostics'
  [IO.File]::WriteAllBytes($dialog.FileName,[byte[]]$bytes)
  $script:driverHint.Text='Диагностика сохранена: '+$dialog.FileName
 }catch{$script:driverHint.Text='Не удалось сохранить диагностику: '+$_.Exception.Message}
}

function Show-DriverModule {
 param([ValidateSet('attention','components')][string]$InitialMode='attention')
 $path=Join-Path $root 'DriverWindow.xaml'
 if(-not (Test-Path -LiteralPath $path)){$Status.Text='Окно драйверов не найдено';return}
 try{
  [xml]$xml=Get-Content -LiteralPath $path -Raw -Encoding UTF8
  $reader=New-Object System.Xml.XmlNodeReader($xml);$driver=[Windows.Markup.XamlReader]::Load($reader);$reader.Close()
  $driver.Owner=$win
  if(Test-Path -LiteralPath (Join-Path $root 'Assets\GarantStoreMark.ico')){$driver.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new((Join-Path $root 'Assets\GarantStoreMark.ico')))}
  foreach($pair in @(@('DriverState','driverState'),@('DriverDetail','driverDetail'),@('DriverDeviceProfile','driverDeviceProfile'),@('DriverProgress','driverProgress'),@('DriverDeviceCount','driverDeviceCount'),@('DriverDevices','driverDevices'),@('DriverLog','driverLog'),@('DriverHint','driverHint'),@('DriverScan','driverScan'),@('DriverSelectionActions','driverSelectionActions'),@('DriverInstall','driverInstall'),@('DriverDownload','driverDownload'),@('DriverSource','driverSource'),@('DriverNetwork','driverNetwork'),@('DriverLocal','driverLocal'),@('DriverRestore','driverRestore'),@('DriverWuRepair','driverWuRepair'),@('DriverCancel','driverCancel'),@('DriverSelectAll','driverSelectAll'),@('DriverOpenFolder','driverOpenFolder'),@('DriverDiagnostics','driverDiagnostics'),@('DriverClose','driverClose'),@('DriverViewAll','driverViewAll'),@('DriverViewComponents','driverViewComponents'),@('DriverToggleLog','driverToggleLog'),@('DriverLogPanel','driverLogPanel'),@('DriverLogColumn','driverLogColumn'),@('DriverLogSpacer','driverLogSpacer'),@('DriverEmptyMessage','driverEmptyMessage'))){Set-Variable -Scope Script -Name $pair[1] -Value $driver.FindName($pair[0])}
  $script:driverWindow=$driver
  $script:driverViewMode=$InitialMode;$script:driverLastSnapshot=$null;$script:driverSelectedIds=@{}
 if($InitialMode -eq 'components'){$driver.Title='Компоненты Windows — Garant Store';$driver.FindName('DriverHeading').Text='Компоненты Windows'}
  $script:driverEndpoint=$null;$script:driverProcess=$null;$script:driverActionBusy=$false;$script:driverPollBusy=$false;$script:driverStatusFetch=$null;$script:driverLastStatusAt=$null;$script:driverLastStatusErrorAt=$null
  Set-GSDriverState -Title 'Запуск Garant-ПО 6.0' -Detail 'Windows запросит подтверждение для модуля драйверов' -Busy $true
  $script:driverState.Text='Запуск Garant-ПО 6.0'
  $script:driverPoll=New-Object Windows.Threading.DispatcherTimer;$script:driverPoll.Interval=[TimeSpan]::FromMilliseconds(400)
  $script:driverPoll.Add_Tick({
   if(-not $script:driverEndpoint){return}
   if($script:driverStatusFetch){[void](Complete-GSDriverStatusFetch)}
   if(-not $script:driverStatusFetch){try{Start-GSDriverStatusFetch}catch{$script:driverDetail.Text='Не удалось опросить локальный модуль: '+$_.Exception.Message}}
  })
  $script:driverScan.Add_Click({Invoke-GSDriverAction 'scan'})
  $script:driverInstall.Add_Click({Invoke-GSDriverAction 'install'})
  $script:driverDownload.Add_Click({Invoke-GSDriverAction 'download'})
  $script:driverNetwork.Add_Click({Invoke-GSDriverAction 'network'})
  $script:driverRestore.Add_Click({Invoke-GSDriverAction 'restore-point'})
  $script:driverWuRepair.Add_Click({Repair-GSWindowsUpdate})
  $script:driverSource.Add_Click({Open-GSDriverSource})
  $script:driverLocal.Add_Click({Invoke-GSDriverAction 'local'})
  $script:driverCancel.Add_Click({try{$null=Invoke-GSDriverApi -Path '/api/cancel' -Method 'POST' -Body @{};$script:driverHint.Text='Остановка запрошена'}catch{$script:driverHint.Text=$_.Exception.Message}})
  $script:driverDevices.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,[System.Windows.RoutedEventHandler]{Update-GSDriverActionVisibility $true $script:driverActionBusy},$true)
  $script:driverSelectAll.Add_Click({Toggle-GSDriverSelection})
  $script:driverViewAll.Add_Click({if($script:driverViewMode -eq 'inventory'){Set-GSDriverViewMode 'attention'}else{Set-GSDriverViewMode 'inventory'}})
  $script:driverViewComponents.Add_Click({if($script:driverViewMode -eq 'components'){Set-GSDriverViewMode 'attention'}else{Set-GSDriverViewMode 'components'}})
  $script:driverToggleLog.Add_Click({Toggle-GSDriverLogPanel})
  $script:driverOpenFolder.Add_Click({try{$null=Invoke-GSDriverApi -Path '/api/open-drivers' -Method 'POST' -Body @{} }catch{$script:driverHint.Text=$_.Exception.Message}})
  $script:driverDiagnostics.Add_Click({Save-GSDriverDiagnostics})
  $script:driverClose.Add_Click({$driver.Close()})
  $driver.Add_Closing({
   if($script:driverPoll){$script:driverPoll.Stop()}
   if($script:driverStatusFetch){try{$script:driverStatusFetch.PowerShell.Stop()}catch{};try{$script:driverStatusFetch.PowerShell.Dispose()}catch{};try{$script:driverStatusFetch.Runspace.Dispose()}catch{};$script:driverStatusFetch=$null}
   if($script:driverEndpoint){
    try{$state=Invoke-GSDriverApi -Path '/api/status';$stateStatus=Get-GSDriverProperty $state 'status' $null;if([bool](Get-GSDriverProperty $stateStatus 'running' $false)){$_.Cancel=$true;$script:driverHint.Text='Сначала остановите текущую операцию. Закрытие не прервёт Worker незаметно.';if($script:driverPoll){$script:driverPoll.Start()};return}}catch{if($script:driverProcess -and -not $script:driverProcess.HasExited){$_.Cancel=$true;$script:driverHint.Text='Не удалось проверить движок; окно оставлено открытым для безопасного завершения.';if($script:driverPoll){$script:driverPoll.Start()};return}}
    try{$null=Invoke-GSDriverApi -Path '/api/exit' -Method 'POST' -Body @{};if($script:driverProcess){[void]$script:driverProcess.WaitForExit(5000)}}catch{}
   }
   if($script:driverBootstrap -and (Test-Path -LiteralPath $script:driverBootstrap)){Remove-Item -LiteralPath $script:driverBootstrap -Force -ErrorAction SilentlyContinue}
  })
  $driver.Add_ContentRendered({
   try{Start-GSDriverEngine;$script:driverPoll.Start();Start-GSDriverStatusFetch}
   catch{$message=$_.Exception.Message;$script:driverState.Text='Модуль не запущен';$script:driverDetail.Text=$message;$script:driverProgress.IsIndeterminate=$false;Write-GSDriverUiLog 'START ERROR' $message}
  })
  [void]$driver.ShowDialog()
 }catch{$Status.Text='Не удалось открыть раздел «Драйверы»: '+$_.Exception.Message}
}


