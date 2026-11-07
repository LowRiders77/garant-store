[CmdletBinding()]
param([ValidateSet('install','download')][string]$Mode='install')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'UpdateCatalog.ps1')
$script:SelectedTask=[ordered]@{action=('selected-'+$Mode);scanned=$true;running=$true;phase='Подготовка';message='Подготавливаем отмеченные элементы';receivedIds=@();total=0;remaining=0;finished=0;downloaded=0;errors=0;bytes=0;expectedBytes=0;percent=-1;lastError='';needReboot=$false;started=(Get-Date).ToString('o');finishedAt=''}
function Set-SelectedStatus([string]$phase,[string]$message){$script:SelectedTask.phase=$phase;$script:SelectedTask.message=$message;Save-JsonFile $script:StatusFile $script:SelectedTask}
function Write-SelectedLog([string]$message){$line='['+(Get-Date -Format 'HH:mm:ss')+'] [Выбранные элементы] '+$message;Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8;Write-Host $line}
function Invoke-SelectedChild([string]$scriptName,[string]$parameter,[string]$value,[string[]]$ids,[string]$label){
 if(Test-Path -LiteralPath (Join-Path $script:StateDir 'cancel.flag')){throw [System.OperationCanceledException]::new('Операция остановлена пользователем')}
 Save-JsonFile (Join-Path $script:StateDir 'selection.json') $ids
 $child=Join-Path $PSScriptRoot $scriptName
 $stdout=Join-Path $script:StateDir ('selected-'+$script:SelectedTask.finished+'.stdout.txt')
 $stderr=Join-Path $script:StateDir ('selected-'+$script:SelectedTask.finished+'.stderr.txt')
 $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$child+'"'))
 if($parameter){$arguments+=@('-'+$parameter,$value)}
 Set-SelectedStatus 'Выполнение' ($label+': '+$ids.Count+' выбрано')
 $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ($arguments -join ' ') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $childStatus=Load-JsonFile $script:StatusFile ([pscustomobject]@{})
 $errors=[int](Get-GSSelectedChildProperty $childStatus 'errors' 0)
 $childPhase=[string](Get-GSSelectedChildProperty $childStatus 'phase' '')
 $downloaded=[int](Get-GSSelectedChildProperty $childStatus 'downloaded' 0)
 $needReboot=[bool](Get-GSSelectedChildProperty $childStatus 'needReboot' $false)
 $message=[string](Get-GSSelectedChildProperty $childStatus 'message' '')
 $completed=[math]::Max([int](Get-GSSelectedChildProperty $childStatus 'finished' 0),$downloaded)
 $script:SelectedTask.finished += $completed
 $script:SelectedTask.downloaded += $downloaded
 $script:SelectedTask.errors += $errors
 $script:SelectedTask.needReboot=$script:SelectedTask.needReboot -or $needReboot
 if($errors -gt 0){$script:SelectedTask.lastError=$message}
 elseif($scriptName -eq 'Worker.ps1' -and $childPhase -eq 'Завершено с ошибками' -and $message -match '(?i)не найден проверенный пакет'){Write-SelectedLog 'DRP не предоставил пакет для части устройств; результат будет оценён после резервной проверки Windows Update.'}
 elseif($childPhase -in @('Завершено с ошибками','Ошибка')){$script:SelectedTask.errors++;$script:SelectedTask.lastError=$message}
 Write-SelectedLog ($label+' завершено; ошибок '+$errors+'; '+$message)
 if($process.ExitCode -ne 0 -and $errors -eq 0){$script:SelectedTask.errors++;$script:SelectedTask.lastError=($label+' завершилось с кодом '+$process.ExitCode)}
 $script:SelectedTask.remaining=[math]::Max(0,$script:SelectedTask.total-$script:SelectedTask.finished)
 Save-JsonFile $script:StatusFile $script:SelectedTask
}
function Get-GSSelectedChildProperty($Object,[string]$Name,$Default){$p=$Object.PSObject.Properties[$Name];if($null -eq $p -or $null -eq $p.Value){return $Default};return $p.Value}
try{
 [IO.File]::WriteAllText($script:LatestLog,"Garant-PO selected operation | $(Get-Date) | Mode: $Mode`r`n",[Text.UTF8Encoding]::new($false))
 $selection=@(Load-JsonFile (Join-Path $script:StateDir 'selection.json') @()|ForEach-Object{[string]$_})
 $originalInventory=@(Load-JsonFile $script:DeviceFile @())
 $devices=New-Object System.Collections.Generic.List[string];$updates=New-Object System.Collections.Generic.List[string];$libraries=New-Object System.Collections.Generic.List[string]
 foreach($item in $selection){
  if($item -match '^device:(.+)$'){$devices.Add($Matches[1])}
  elseif($item -match '^update:([0-9A-Fa-f-]{36}\|\d+)$'){$updates.Add($Matches[1])}
  elseif($item -match '^library:(vcredist-x64|vcredist-x86|directx-legacy|netfx3|webview2|dotnet-desktop|dotnet-desktop-10|windows-app-runtime|physx|physx-legacy|openal)$'){$libraries.Add($Matches[1])}
 }
 $updateRows=@($originalInventory|Where-Object{[string](Get-GSSelectedChildProperty $_ 'kind' '') -eq 'Update'})
 if($devices.Count -and $updateRows.Count){Write-SelectedLog 'Для отмеченных устройств сначала запускается поиск и установка из DRP. Предложения Windows Update остаются отдельным источником.'}
 $script:SelectedTask.receivedIds=$selection
 $script:SelectedTask.total=$devices.Count+$updates.Count+$libraries.Count;$script:SelectedTask.remaining=$script:SelectedTask.total
 if($script:SelectedTask.total -eq 0){throw 'Не выбраны поддерживаемые элементы для операции.'}
 if($Mode -eq 'install' -and $devices.Count){
  Invoke-SelectedChild 'Worker.ps1' 'Action' 'auto' @($devices.ToArray()) 'Драйверы устройств'
  # DRP is tried first. Only if it leaves selected devices unresolved do we
  # use matching Windows Update offers as a best-effort fallback.
  if(-not $updates.Count -and -not (Test-Path -LiteralPath (Join-Path $script:StateDir 'cancel.flag'))){
   $afterDrp=@(Get-RemainingSelectedProblemDevices (Load-JsonFile $script:DeviceFile @()) $devices.ToArray())
   $wuFallbackIds=@(Get-MatchedWindowsDriverUpdateIds $afterDrp $updateRows)
   if($wuFallbackIds.Count){
    Write-SelectedLog ('DRP оставил без установленного пакета устройств: '+$afterDrp.Count+'; применяю совпадающие предложения Windows Update как резервный источник.')
    Invoke-SelectedChild 'Updates.ps1' 'Mode' 'install' $wuFallbackIds 'Резервные обновления Windows Update'
   }elseif($afterDrp.Count){Write-SelectedLog ('Для оставшихся устройств в результатах сканирования нет совпадающего предложения Windows Update: '+$afterDrp.Count)}
  }
 }
 elseif($Mode -eq 'download' -and $devices.Count){Invoke-SelectedChild 'Worker.ps1' 'Action' 'download' @($devices.ToArray()) 'Пакеты драйверов'}
 if($updates.Count){Invoke-SelectedChild 'Updates.ps1' 'Mode' $Mode @($updates.ToArray()) $(if($Mode -eq 'install'){'Обновления Windows Update'}else{'Загрузка обновлений Windows Update'})}
 if($libraries.Count){Invoke-SelectedChild 'Libraries.ps1' 'Mode' $Mode @($libraries.ToArray()) $(if($Mode -eq 'install'){'Библиотеки Windows'}else{'Загрузка библиотек Windows'})}
 if($Mode -eq 'install' -and -not (Test-Path -LiteralPath (Join-Path $script:StateDir 'cancel.flag'))){
  Save-JsonFile (Join-Path $script:StateDir 'selection.json') @()
  $refreshPath=Join-Path $PSScriptRoot 'Worker.ps1'
  $refreshOut=Join-Path $script:StateDir 'selected-refresh.stdout.txt';$refreshErr=Join-Path $script:StateDir 'selected-refresh.stderr.txt'
  $refreshArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$refreshPath+'"'),'-Action','scan')
  Set-SelectedStatus 'Проверка результата' 'Повторно сканируем систему после выбранных установок.'
  $refresh=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ($refreshArgs -join ' ') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $refreshOut -RedirectStandardError $refreshErr
  $refreshStatus=Load-JsonFile $script:StatusFile ([pscustomobject]@{})
  if($refresh.ExitCode -ne 0 -or [int](Get-GSSelectedChildProperty $refreshStatus 'errors' 0) -gt 0){$script:SelectedTask.errors++;$script:SelectedTask.lastError=[string](Get-GSSelectedChildProperty $refreshStatus 'message' 'Повторное сканирование завершилось с ошибкой')}
  if($libraries.Contains('webview2')){
   $installedRow=@(Load-JsonFile $script:DeviceFile @() | Where-Object { [string]$_.instanceId -eq 'LIBRARY|webview2' } | Select-Object -First 1)
   if($installedRow.Count -ne 1 -or [string]$installedRow[0].libraryStatus -ne 'Установлено' -or [bool]$installedRow[0].canSelect){
    $script:SelectedTask.errors++
    $script:SelectedTask.lastError='После установки и повторного сканирования WebView2 не подтверждён.'
    Write-SelectedLog $script:SelectedTask.lastError
   }else{Write-SelectedLog ('WebView2 подтверждён повторным сканированием: '+[string]$installedRow[0].reason)}
  }
  if($devices.Count){
   $remainingSelected=@(Get-RemainingSelectedProblemDevices (Load-JsonFile $script:DeviceFile @()) $devices.ToArray())
   if($remainingSelected.Count){$script:SelectedTask.errors++;$script:SelectedTask.lastError=('После DRP и доступного резерва осталось устройств без подтверждённой установки: '+$remainingSelected.Count);Write-SelectedLog $script:SelectedTask.lastError}
  }
 }elseif($Mode -eq 'download'){
  Save-JsonFile $script:DeviceFile $originalInventory
 }
 if(Test-Path -LiteralPath (Join-Path $script:StateDir 'cancel.flag')){Set-SelectedStatus 'Остановлено' 'Операция остановлена. Выполненные шаги сохранены.'}
 elseif($script:SelectedTask.errors){Set-SelectedStatus 'Завершено с ошибками' ('Завершено с ошибками: '+$script:SelectedTask.lastError)}
 elseif($Mode -eq 'download'){Set-SelectedStatus 'Готово' 'Отмеченные доступные пакеты скачаны. Установка не выполнялась.'}
 elseif($script:SelectedTask.needReboot){Set-SelectedStatus 'Готово' 'Выбранные компоненты обработаны. Для завершения части обновлений требуется перезагрузка.'}
 else{Set-SelectedStatus 'Готово' 'Выбранные драйверы и библиотеки обработаны.'}
}catch [System.OperationCanceledException]{Set-SelectedStatus 'Остановлено' $_.Exception.Message}
catch{$script:SelectedTask.errors++;$script:SelectedTask.lastError=$_.Exception.Message;Write-SelectedLog ('ОШИБКА: '+$_.Exception.Message);Set-SelectedStatus 'Ошибка' $_.Exception.Message}
finally{$script:SelectedTask.running=$false;$script:SelectedTask.finishedAt=(Get-Date).ToString('o');Save-JsonFile $script:StatusFile $script:SelectedTask}
