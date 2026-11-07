[CmdletBinding()]
param([ValidateSet('scan','install','download')][string]$Mode='scan')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'UpdateCatalog.ps1')

$script:UpdateTask=[ordered]@{action=$(if($Mode -eq 'scan'){'update-scan'}elseif($Mode -eq 'download'){'update-download'}else{'update-install'});scanned=$false;running=$true;phase='Подготовка';message='Подготовка поиска обновлений Windows';percent=-1;total=0;remaining=0;finished=0;downloaded=0;errors=0;needReboot=$false;started=(Get-Date).ToString('o');finishedAt='';lastError=''}
function Update-Status([string]$Phase,[string]$Message){
 $script:UpdateTask.phase=$Phase;$script:UpdateTask.message=$Message
 Save-JsonFile $script:StatusFile $script:UpdateTask
}
function Update-Log([string]$Message){
 $line='['+(Get-Date -Format 'HH:mm:ss')+'] [Windows Update] '+$Message
 Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8
 Write-Host $line
}
function Test-UpdateCancelled {
 if(Test-Path -LiteralPath (Join-Path $script:StateDir 'cancel.flag')){throw [System.OperationCanceledException]::new('Операция остановлена пользователем')}
}
try{
 [IO.File]::WriteAllText($script:LatestLog,"Garant-PO Windows Update | $(Get-Date) | Mode: $Mode`r`n",[Text.UTF8Encoding]::new($false))
 Test-UpdateCancelled
 if($Mode -eq 'scan'){
  $updates=@(Get-WindowsDriverUpdates -StatusCallback {param($p,$m) Update-Status $p $m} -LogCallback {param($m) Update-Log $m})
  Save-JsonFile $script:DeviceFile $updates
  $script:UpdateTask.scanned=$true;$script:UpdateTask.total=$updates.Count;$script:UpdateTask.remaining=$updates.Count;$script:UpdateTask.percent=100
  if($updates.Count){Update-Status 'Готово' ('Windows Update предлагает обновления драйверов: '+$updates.Count)}
  else{Update-Status 'Готово' 'Windows Update не предлагает обновлений драйверов для этого устройства.'}
  Update-Log ('Найдено предложений Windows Update: '+$updates.Count)
 }else{
  $selection=@(Load-JsonFile (Join-Path $script:StateDir 'selection.json') @()|ForEach-Object{[string]$_})
  if($selection.Count -eq 0){throw 'Не выбраны обновления для установки'}
  Test-UpdateCancelled
  $session=New-Object -ComObject Microsoft.Update.Session;$session.ClientApplicationID='Garant Store'
  $searcher=$session.CreateUpdateSearcher();$available=(Invoke-GSWuaDriverSearch $searcher).Updates
  $collection=New-Object -ComObject Microsoft.Update.UpdateColl
  $chosen=New-Object System.Collections.ArrayList
  for($i=0;$i -lt $available.Count;$i++){
   $update=$available.Item($i);$id=[string]$update.Identity.UpdateID+'|'+[string]$update.Identity.RevisionNumber
   if($selection -contains $id){
    if(-not [bool]$update.EulaAccepted){throw ('Для обновления требуется принять лицензионные условия Windows Update: '+[string]$update.Title+'. Откройте Параметры Windows → Центр обновления Windows и проверьте предложение там.')}
    [void]$collection.Add($update);[void]$chosen.Add($update)
   }
  }
  if($collection.Count -eq 0){throw 'Выбранные обновления больше не предлагаются Windows Update. Выполните поиск заново.'}
  Test-UpdateCancelled
  $script:UpdateTask.total=$collection.Count;$script:UpdateTask.remaining=$collection.Count
  Update-Status 'Скачивание обновлений' ('Загружаем выбранные обновления: '+$collection.Count)
  Update-Log ('Выбрано обновлений: '+$collection.Count)
  $downloader=$session.CreateUpdateDownloader();$downloader.Updates=$collection;$downloadResult=$downloader.Download()
  if([int]$downloadResult.ResultCode -notin @(2,3)){throw ('Windows Update не смог скачать выбранные драйверы. Код результата: '+[int]$downloadResult.ResultCode)}
  if($Mode -eq 'download'){
   $exported=0;$exportFailures=New-Object System.Collections.Generic.List[string]
   foreach($update in $chosen){
    Test-UpdateCancelled
    $identity=[string]$update.Identity.UpdateID
    $title=[string]$update.Title
    $safeTitle=($title -replace '[<>:"/\\|?*]','_' -replace '\s+',' ').Trim()
    if($safeTitle.Length -gt 72){$safeTitle=$safeTitle.Substring(0,72).Trim()}
    $folder=Join-Path $script:DriverDir ($safeTitle+'-'+$identity.Substring(0,8))
    try{
     $files=@(Export-GSWuaUpdateContent $update $folder)
     $exported += $files.Count
     Update-Log ('Пакет Windows Update экспортирован в «'+$folder+'»; файлов: '+$files.Count)
    }catch{
     $script:UpdateTask.errors++
     $exportFailures.Add($title+': '+$_.Exception.Message)
     Update-Log ('Не удалось скопировать пакет Windows Update в папку драйверов. Пакет остаётся в кэше Windows Update. '+$title+' | '+$_.Exception.Message)
    }
   }
   $script:UpdateTask.downloaded=$chosen.Count;$script:UpdateTask.finished=$chosen.Count;$script:UpdateTask.remaining=0;$script:UpdateTask.percent=100
   if($exportFailures.Count){
    $script:UpdateTask.lastError=$exportFailures -join '; '
    Update-Status 'Завершено с ошибками' ('Windows Update скачал '+$chosen.Count+' пакет(а), но не все удалось скопировать в «Загрузки\Garant Store\Drivers». Смотрите журнал; пакеты остаются в кэше Windows Update.')
   }else{
    Update-Status 'Готово' ('Скачано обновлений Windows Update: '+$chosen.Count+'; файлы скопированы в «Загрузки\Garant Store\Drivers». Установка не выполнялась.')
   }
   Update-Log ('Скачано обновлений Windows Update без установки: '+$chosen.Count+'; экспортировано файлов: '+$exported)
  }else{
  Test-UpdateCancelled
  $installCollection=New-Object -ComObject Microsoft.Update.UpdateColl
  for($i=0;$i -lt $chosen.Count;$i++){
   $update=$chosen[$i]
   if([bool]$update.IsDownloaded){[void]$installCollection.Add($update)}
   else{$script:UpdateTask.errors++;Update-Log ('Не удалось скачать: '+[string]$update.Title)}
  }
  if($installCollection.Count -eq 0){throw 'Windows Update не завершил скачивание ни одного выбранного драйвера'}
  Update-Status 'Установка обновлений' ('Устанавливаем драйверы: '+$installCollection.Count)
  $installer=$session.CreateUpdateInstaller();$installer.Updates=$installCollection;$installResult=$installer.Install()
  $script:UpdateTask.needReboot=[bool]$installResult.RebootRequired
  if([int]$installResult.ResultCode -notin @(2,3)){throw ('Windows Update завершил установку с ошибкой. Код результата: '+[int]$installResult.ResultCode)}
  $script:UpdateTask.downloaded=$installCollection.Count;$script:UpdateTask.finished=$installCollection.Count
  if($script:UpdateTask.needReboot){Update-Log 'Для завершения установки требуется перезагрузка.'}
  for($i=0;$i -lt $installCollection.Count;$i++){
   $one=$installResult.GetUpdateResult($i)
   if([int]$one.ResultCode -notin @(2,3)){$script:UpdateTask.errors++;Update-Log ('Ошибка обновления '+[string]$installCollection.Item($i).Title+'; код '+[int]$one.ResultCode)}
   else{Update-Log ('Установлено: '+[string]$installCollection.Item($i).Title)}
  }
  $remaining=@(Get-WindowsDriverUpdates -StatusCallback {param($p,$m) Update-Status $p $m} -LogCallback {param($m) Update-Log $m})
  Save-JsonFile $script:DeviceFile $remaining
  $script:UpdateTask.scanned=$true;$script:UpdateTask.remaining=$remaining.Count;$script:UpdateTask.percent=100
  if($remaining.Count -eq 0){Update-Status 'Готово' 'Выбранные обновления установлены. Windows Update больше не предлагает обновлений драйверов.'}
  else{Update-Status 'Готово' ('Установка завершена. Осталось предложений Windows Update: '+$remaining.Count)}
  }
 }
}catch [System.OperationCanceledException]{
 $script:UpdateTask.scanned=$true;Update-Log 'Пользователь запросил остановку операции.';Update-Status 'Остановлено' $_.Exception.Message
}catch{
 $script:UpdateTask.errors++;$script:UpdateTask.lastError=$_.Exception.Message;Update-Log ('ОШИБКА: '+$_.Exception.Message);Update-Status 'Ошибка' $_.Exception.Message
}finally{
 $script:UpdateTask.running=$false;$script:UpdateTask.finishedAt=(Get-Date).ToString('o');Save-JsonFile $script:StatusFile $script:UpdateTask
}
