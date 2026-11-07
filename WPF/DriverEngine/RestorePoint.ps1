[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$status=[ordered]@{action='restore-point';scanned=(Test-Path -LiteralPath (Join-Path $script:StateDir 'scan.flag'));running=$true;phase='Подготовка';message='Проверяем защиту системы';total=1;remaining=1;finished=0;downloaded=0;errors=0;percent=-1;started=(Get-Date).ToString('o');finishedAt='';lastError=''}
function Write-RestoreStatus([string]$phase,[string]$message){$status.phase=$phase;$status.message=$message;$status.updatedAt=(Get-Date).ToString('HH:mm:ss');Save-JsonFile $script:StatusFile $status}
function Write-RestoreLog([string]$message){$line='['+(Get-Date -Format 'HH:mm:ss')+'] [Точка восстановления] '+$message;Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8;Write-Host $line}
function Convert-GSRestorePointTime($Point){
 try{$raw=[string]$Point.CreationTime;if($raw.Length -lt 14){return $null};$value=[datetime]::MinValue;if([datetime]::TryParseExact($raw.Substring(0,14),'yyyyMMddHHmmss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeLocal,[ref]$value)){return $value}}catch{}
 return $null
}
function Get-GSRestorePointFrequencyMinutes{
 $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
 try{$value=Get-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -ErrorAction Stop;return [Math]::Max(0,[int]$value.SystemRestorePointCreationFrequency)}catch{return 1440}
}
try{
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal($identity)
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Для создания точки восстановления нужны права администратора.'}
 $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
 $drive=[string]$os.SystemDrive
 if($drive -notmatch '^[A-Z]:$'){throw ('Не удалось определить системный диск Windows: '+$drive)}
 $volume=$drive+'\'
 Write-RestoreLog ('Системный том: '+$volume)
 $policy=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
 if($null -ne $policy -and (($null -ne $policy.PSObject.Properties['DisableSR'] -and [int]$policy.DisableSR -eq 1) -or ($null -ne $policy.PSObject.Properties['DisableConfig'] -and [int]$policy.DisableConfig -eq 1))){throw 'Создание точки восстановления заблокировано политикой Windows System Restore. Изменять эту политику без администратора организации нельзя.'}
 $restoreClass=Get-WmiObject -Namespace 'root\default' -List -Class 'SystemRestore' -ErrorAction Stop
 $before=@(Get-WmiObject -Namespace 'root\default' -Class 'SystemRestore' -ErrorAction Stop)
 $latestBefore=$null
 foreach($point in $before){$time=Convert-GSRestorePointTime $point;if($time -and ($null -eq $latestBefore -or $time -gt $latestBefore.Time)){$latestBefore=[pscustomobject]@{Time=$time;Point=$point}}}
 $frequency=Get-GSRestorePointFrequencyMinutes
 if($frequency -gt 0 -and $latestBefore -and $latestBefore.Time -ge (Get-Date).AddMinutes(-$frequency)){
  $description=[string]$latestBefore.Point.Description
  $message=('Новая точка не создавалась: Windows ограничивает частоту до одной точки за '+$frequency+' минут. Последняя точка создана '+$latestBefore.Time.ToString('dd.MM.yyyy HH:mm')+$(if($description){' («'+$description+'»)'}else{''})+'.')
  $status.finished=1;$status.remaining=0;$status.percent=100
  Write-RestoreLog $message
  Write-RestoreStatus 'Готово' $message
  return
 }
 Write-RestoreStatus 'Подготовка' ('Проверяем/включаем защиту системного тома '+$volume)
 $enable=$restoreClass.Enable($volume)
 if([int]$enable.ReturnValue -ne 0){throw ('Windows не включила защиту системы. Код WMI: '+[int]$enable.ReturnValue)}
 Write-RestoreLog ('Вызов Enable для защиты '+$volume+' завершился кодом '+[int]$enable.ReturnValue+'.')
 $description='Garant Store — перед установкой драйверов '+(Get-Date -Format 'yyyy-MM-dd HH:mm')
 Write-RestoreStatus 'Создание точки' 'Windows создаёт точку восстановления. Это может занять несколько минут.'
 $startedAt=Get-Date
 $created=$restoreClass.CreateRestorePoint($description,10,100)
 if([int]$created.ReturnValue -ne 0){throw ('Windows не создала точку восстановления. Код WMI: '+[int]$created.ReturnValue)}
 $after=@();$newPoint=@()
 for($verifyAttempt=1;$verifyAttempt -le 3;$verifyAttempt++){
  $after=@(Get-WmiObject -Namespace 'root\default' -Class 'SystemRestore' -ErrorAction Stop)
  $newPoint=@($after|Where-Object{
   $createdAt=Convert-GSRestorePointTime $_
   $createdAt -and [string]$_.Description -eq $description -and $createdAt -ge $startedAt.AddMinutes(-1)
  })
  if($newPoint.Count -gt 0){break}
  if($verifyAttempt -lt 3){Start-Sleep -Seconds 1}
 }
 if($newPoint.Count -eq 0){
  $latestAfter=$null
  foreach($point in $after){$time=Convert-GSRestorePointTime $point;if($time -and ($null -eq $latestAfter -or $time -gt $latestAfter.Time)){$latestAfter=[pscustomobject]@{Time=$time;Point=$point}}}
  if($frequency -gt 0 -and $latestAfter -and $latestAfter.Time -ge $startedAt.AddMinutes(-$frequency)){
   $message=('Windows пропустила создание новой точки из-за ограничения частоты. Подтверждённая последняя точка: '+$latestAfter.Time.ToString('dd.MM.yyyy HH:mm')+' («'+[string]$latestAfter.Point.Description+'»).')
   $status.finished=1;$status.remaining=0;$status.percent=100
   Write-RestoreLog $message;Write-RestoreStatus 'Готово' $message
   return
  }
  $recentEvents=@()
  try{$recentEvents=@(Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$startedAt.AddMinutes(-15)} -ErrorAction Stop|Where-Object{$_.ProviderName -match '^(VSS|VolSnap|Microsoft-Windows-.*VSS)'}|Select-Object -First 3)}catch{}
  $eventDetail=if($recentEvents.Count){' Недавнее событие VSS: '+([string]$recentEvents[0].Message -replace '\s+',' ').Trim()}else{' В журнале Application не найдено недавних событий VSS.'}
  throw ('WMI вернула код успеха, но новой точки не обнаружено. Предыдущая точка не объясняет пропуск по частоте (интервал '+$frequency+' мин.). Проверьте состояние защиты системного диска, свободное место и VSS.'+$eventDetail)
 }
 $status.finished=1;$status.remaining=0;$status.percent=100
 Write-RestoreLog ('Создана и проверена точка «'+$description+'»; номер '+[string]$newPoint[-1].SequenceNumber)
 Write-RestoreStatus 'Готово' 'Точка восстановления создана и найдена в списке Windows.'
}catch{
 $status.errors=1;$status.lastError=$_.Exception.Message
 Write-RestoreLog ('Ошибка: '+$_.Exception.Message)
 Write-RestoreStatus 'Завершено с ошибкой' $_.Exception.Message
}finally{
 $status.running=$false;$status.finishedAt=(Get-Date).ToString('o');Save-JsonFile $script:StatusFile $status
}
