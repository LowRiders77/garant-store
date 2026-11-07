[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$status=[ordered]@{action='windows-update-repair';scanned=(Test-Path -LiteralPath (Join-Path $script:StateDir 'scan.flag'));running=$true;phase='Подготовка';message='Проверяем службы Windows Update';total=2;remaining=2;finished=0;downloaded=0;errors=0;percent=-1;started=(Get-Date).ToString('o');finishedAt='';lastError=''}
function Write-RepairStatus([string]$phase,[string]$message){$status.phase=$phase;$status.message=$message;$status.updatedAt=(Get-Date).ToString('HH:mm:ss');Save-JsonFile $script:StatusFile $status}
function Write-RepairLog([string]$message){$line='['+(Get-Date -Format 'HH:mm:ss')+'] [Windows Update] '+$message;Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8;Write-Host $line}
try{
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal($identity)
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Для восстановления Windows Update нужны права администратора.'}
 $wuPolicy=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
 if($null -ne $wuPolicy -and $null -ne $wuPolicy.PSObject.Properties['DisableWindowsUpdateAccess'] -and [int]$wuPolicy.DisableWindowsUpdateAccess -eq 1){
  throw 'Windows Update заблокирован административной политикой DisableWindowsUpdateAccess=1. Garant-ПО не менял политику и не будет включать службу в обход этого ограничения. Разрешение может выдать только администратор, управляющий политикой.'
 }
 foreach($name in @('wuauserv','BITS')){
  Write-RepairStatus 'Проверка служб' ('Проверяем '+$name)
  $service=Get-CimInstance -ClassName Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction Stop
  if($null -eq $service){throw ('Служба '+$name+' отсутствует. Windows может быть изменена или повреждена.')}
  if([string]$service.StartMode -eq 'Disabled'){
   Write-RepairLog ($name+' отключена; выставляем тип запуска Manual.')
   Set-Service -Name $name -StartupType Manual -ErrorAction Stop
  }
  $current=Get-Service -Name $name -ErrorAction Stop
  if($current.Status -ne 'Running'){
   Write-RepairStatus 'Запуск служб' ('Запускаем '+$name)
   Start-Service -Name $name -ErrorAction Stop
   (Get-Service -Name $name -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(20))
  }
  $status.finished++
  Write-RepairLog ($name+' доступна и запущена.')
 }
 Write-RepairStatus 'Готово' 'Windows Update и BITS запущены. Теперь выполните сканирование драйверов ещё раз.'
}catch{
 $status.errors=1;$status.lastError=$_.Exception.Message
 $message=$_.Exception.Message
 if($message -match 'Access is denied|Отказано в доступе|denied|policy|политик'){$message+=' Возможно, запуск блокирует групповая политика или корпоративная защита Windows.'}
 Write-RepairLog ('Ошибка: '+$message)
 Write-RepairStatus 'Завершено с ошибкой' $message
}finally{
 $status.running=$false;$status.finishedAt=(Get-Date).ToString('o');Save-JsonFile $script:StatusFile $status
}
