[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$task=[ordered]@{action='network';scanned=$true;running=$true;phase='Проверка сети';message='Собираем состояние адаптеров, шлюза и прокси';total=2;remaining=2;finished=0;errors=0;percent=-1;needReboot=$false;lastError='';started=(Get-Date).ToString('o');finishedAt=''}
function Set-NetworkStatus([string]$phase,[string]$message){$task.phase=$phase;$task.message=$message;Save-JsonFile $script:StatusFile $task}
function Write-NetworkLog([string]$message){$line='['+(Get-Date -Format 'HH:mm:ss')+'] [Сеть] '+$message;Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8;Write-Host $line}
try{
 [IO.File]::WriteAllText($script:LatestLog,"Garant-PO network repair | $(Get-Date)`r`n",[Text.UTF8Encoding]::new($false))
 $adapters=@()
 try{$adapters=@(Get-NetAdapter -Physical -ErrorAction Stop|Where-Object{$_.Status -eq 'Up'})}catch{
  try{$adapters=@(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop|Where-Object{$_.NetEnabled -eq $true})}catch{}
 }
 Write-NetworkLog ('Активных физических адаптеров: '+$adapters.Count)
 foreach($adapter in $adapters){Write-NetworkLog ('Адаптер: '+[string]$adapter.Name+' | '+[string]$adapter.Status)}
 $configuredProxy=@(@($env:HTTPS_PROXY,$env:HTTP_PROXY,$env:ALL_PROXY)|Where-Object{![string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
 if($configuredProxy.Count){Write-NetworkLog ('Сохранён настроенный прокси: '+($configuredProxy -join ', '))}else{Write-NetworkLog 'Переменные прокси не заданы; системные настройки прокси не изменяются.'}
 Set-NetworkStatus 'Очистка DNS' 'Очищаем локальный кэш DNS.'
 $ipconfig=Join-Path $env:WINDIR 'System32\ipconfig.exe'
 $dnsOutput=@(& $ipconfig '/flushdns' 2>&1);$dnsExit=$LASTEXITCODE
 foreach($line in $dnsOutput){Write-NetworkLog ([string]$line)}
 if($dnsExit -ne 0){throw ('Очистка кэша DNS завершилась с кодом '+$dnsExit)}
 $task.finished=1;$task.remaining=1;Save-JsonFile $script:StatusFile $task
 Set-NetworkStatus 'Восстановление сетевого каталога' 'Сбрасываем Winsock, не меняя IP-адреса, DNS-серверы и прокси.'
 $netsh=Join-Path $env:WINDIR 'System32\netsh.exe'
 $winsockOutput=@(& $netsh winsock reset 2>&1);$winsockExit=$LASTEXITCODE
 foreach($line in $winsockOutput){Write-NetworkLog ([string]$line)}
 if($winsockExit -ne 0){throw ('Сброс Winsock завершился с кодом '+$winsockExit)}
 $task.finished=2;$task.remaining=0;$task.needReboot=$true
 Write-NetworkLog 'Настройки IP и системного прокси не менялись. Для применения сброса Winsock перезагрузите Windows.'
 if($adapters.Count){Set-NetworkStatus 'Готово' 'DNS-кэш очищен, Winsock восстановлен. Перезагрузите Windows; параметры IP и прокси сохранены.'}
 else{Set-NetworkStatus 'Готово с замечанием' 'DNS-кэш и Winsock сброшены, но активный сетевой адаптер не найден. Включите Wi-Fi/Ethernet или проверьте драйвер; затем перезагрузите Windows.'}
}catch{
 $task.errors++;$task.lastError=$_.Exception.Message
 Write-NetworkLog ('ОШИБКА: '+$_.Exception.Message)
 Set-NetworkStatus 'Ошибка восстановления сети' $_.Exception.Message
}finally{
 $task.running=$false;$task.finishedAt=(Get-Date).ToString('o');Save-JsonFile $script:StatusFile $task
}
