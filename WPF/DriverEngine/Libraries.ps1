[CmdletBinding()]
param([ValidateSet('install','download')][string]$Mode='install')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:LibraryTask=[ordered]@{action='libraries';mode=$Mode;scanned=$true;running=$true;phase='Подготовка';message='Подготовка системных библиотек';total=0;remaining=0;finished=0;downloaded=0;errors=0;bytes=0;expectedBytes=0;percent=-1;lastError='';needReboot=$false;started=(Get-Date).ToString('o');finishedAt=''}
function Set-LibraryStatus([string]$phase,[string]$message){
 $script:LibraryTask.phase=$phase;$script:LibraryTask.message=$message
 Save-JsonFile $script:StatusFile $script:LibraryTask
}
function Write-LibraryLog([string]$message){
 $line='['+(Get-Date -Format 'HH:mm:ss')+'] [Библиотеки] '+$message
 Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8
 Write-Host $line
}
function Get-ValidMicrosoftInstaller([string]$url,[string]$name){
 # Verify and run from the administrators-only engine folder; a file in the
 # user's Downloads could be replaced between the signature check and launch.
 $path=Join-Path $script:EngineLibraryDir $name
 $valid=$false
 if(Test-Path -LiteralPath $path){
  $signature=Get-AuthenticodeSignature -FilePath $path
  $valid=($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid -and $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match '(?i)(^|,\s*)O=Microsoft Corporation(,|$)')
 }
 if(-not $valid){
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  $partial=$path+'.partial.exe'
  Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
  [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $partial -UseBasicParsing -TimeoutSec 240
  if(-not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -lt 10000){throw ('Загружен неполный файл '+$name)}
  $signature=Get-AuthenticodeSignature -FilePath $partial
  if($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)'){
   Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
   throw ('Не удалось подтвердить подпись Microsoft у '+$name)
  }
  Move-Item -LiteralPath $partial -Destination $path -Force
 }
 Write-LibraryLog ('Проверен установщик '+$name+'; SHA-256 '+(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())
 if(Publish-GSUserCopy -Path $path -UserDirectory $script:LibraryDir){Write-LibraryLog ('Копия сохранена в «'+$script:LibraryDir+'»')}
 return $path
}
# Components without a direct Microsoft download link are installed from their
# official WinGet packages (hash-verified by WinGet). IDs are checked in CI.
$script:GSLibraryWingetIds=@{
 'dotnet-desktop'='Microsoft.DotNet.DesktopRuntime.8'
 'dotnet-desktop-10'='Microsoft.DotNet.DesktopRuntime.10'
 'windows-app-runtime'='Microsoft.WindowsAppRuntime.1.8'
 'physx'='Nvidia.PhysX'
 'physx-legacy'='Nvidia.PhysXLegacy'
 'openal'='CreativeTechnology.OpenAL'
}
function Get-GSLibraryWingetPath {
 $command=Get-Command winget.exe -ErrorAction SilentlyContinue
 if($command -and $command.Source){return [string]$command.Source}
 try{
  $package=Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop|Sort-Object Version -Descending|Select-Object -First 1
  if($package){$candidate=Join-Path $package.InstallLocation 'winget.exe';if(Test-Path -LiteralPath $candidate){return $candidate}}
 }catch{}
 throw 'WinGet не найден. Восстановите WinGet в разделе «Восстановить WinGet» и повторите.'
}
function Get-GSVcRedistVerb([string]$Arch){
 # An installed runtime is repaired in place (fixes damaged MSVCP/VCRUNTIME DLLs).
 $row=Get-SystemLibrarySuggestions|Where-Object{$_.instanceId -eq ('LIBRARY|vcredist-'+$Arch)}|Select-Object -First 1
 if($row -and $row.libraryStatus -eq 'Установлено'){Write-LibraryLog ('Visual C++ '+$Arch+' установлен: выполняется восстановление');return '/repair'}
 return '/install'
}
function Install-GSWingetLibrary([string]$Id){
 $packageId=$script:GSLibraryWingetIds[$Id]
 if(-not $packageId){throw ('Для '+$Id+' не настроен пакет WinGet')}
 $winget=Get-GSLibraryWingetPath
 if($Mode -eq 'download'){
  Set-LibraryStatus 'Загрузка библиотек' ('Скачиваем '+$packageId)
  [void][IO.Directory]::CreateDirectory($script:LibraryDir)
  $output=& $winget download --id $packageId --exact --source winget --download-directory $script:LibraryDir --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1|Out-String
  if($LASTEXITCODE -ne 0){throw ('WinGet не скачал '+$packageId+' (код '+$LASTEXITCODE+'). '+$output.Trim())}
  $script:LibraryTask.downloaded++;$script:LibraryTask.finished++
  Write-LibraryLog ('Пакет '+$packageId+' скачан в «'+$script:LibraryDir+'»; установка не запускалась')
  return
 }
 Set-LibraryStatus 'Установка библиотек' ('Устанавливаем '+$packageId)
 Write-LibraryLog ('WinGet: установка '+$packageId)
 $output=& $winget install --id $packageId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1|Out-String
 $code=$LASTEXITCODE
 Write-LibraryLog ('WinGet завершился с кодом '+$code)
 if($code -in @(3010,1641)){$script:LibraryTask.needReboot=$true}
 # The exit code alone is not proof: confirm through the same detection the list uses.
 $row=Get-SystemLibrarySuggestions|Where-Object{$_.instanceId -eq ('LIBRARY|'+$Id)}|Select-Object -First 1
 if(-not $row -or $row.libraryStatus -ne 'Установлено'){
  if($script:LibraryTask.needReboot){Write-LibraryLog ($packageId+' требует перезагрузки для завершения установки');$script:LibraryTask.finished++;return}
  throw ('Windows не подтвердила установку '+$packageId+' (код WinGet '+$code+'). '+(($output -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 3) -join ' '))
 }
 $script:LibraryTask.downloaded++;$script:LibraryTask.finished++
 Write-LibraryLog ('Установлено и подтверждено: '+$packageId)
}
function Install-MicrosoftRuntime([string]$Id,[string]$Url,[string]$File,[string[]]$Arguments){
 if($Id -eq 'webview2'){
  $before=Get-GSWebView2State
  if($before.Installed){Write-LibraryLog ('WebView2 уже установлен: '+$before.Version+'; повторная установка не выполняется');$script:LibraryTask.finished++;return}
  if($before.Unverified -or -not $before.Supported){throw 'Не удалось подтвердить отсутствие WebView2 или совместимость Windows; установка остановлена.'}
 }

 Set-LibraryStatus 'Загрузка библиотек' ('Скачиваем '+$Id+' в папку «Загрузки»')
 Write-LibraryLog ('Загружается '+$Id+' с официального сервера Microsoft')
 $installer=Get-ValidMicrosoftInstaller $Url $File
 $script:LibraryTask.downloaded++
 Set-LibraryStatus 'Установка библиотек' ('Устанавливаем '+$Id)
 $process=Start-Process -FilePath $installer -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
 # 1638: a newer Visual C++ build is already installed - the runtime is present.
 if($process.ExitCode -eq 1638 -and $Id -like 'vcredist-*'){Write-LibraryLog ($Id+': установлена более новая версия; переустановка не требуется')}
 elseif($process.ExitCode -notin @(0,3010,1641)){throw ($Id+' завершился с кодом '+$process.ExitCode)}
 if($process.ExitCode -in @(3010,1641)){$script:LibraryTask.needReboot=$true}
 if($Id -eq 'webview2'){
  # EdgeUpdate may register the new runtime shortly after setup.exe exits.
  $after=$null
  for($attempt=0;$attempt -lt 40;$attempt++){
   $after=Get-GSWebView2State
   if($after.Installed){break}
   Start-Sleep -Milliseconds 750
  }
  if(-not $after.Installed){
   $message=if($script:LibraryTask.needReboot){'Установщик запросил перезагрузку, но версия WebView2 пока не подтверждена. Перезагрузите компьютер и повторите сканирование.'}else{'Установщик завершился, но EdgeUpdate и исполняемый файл WebView2 не подтвердили установку.'}
   throw $message
  }
  Write-LibraryLog ('Подтверждена установленная версия WebView2: '+$after.Version+'; код '+$process.ExitCode)
 }elseif(-not $script:LibraryTask.needReboot){
  $row=Get-SystemLibrarySuggestions|Where-Object{$_.instanceId -eq ('LIBRARY|'+$Id)}|Select-Object -First 1
  if(-not $row -or $row.libraryStatus -ne 'Установлено'){throw ('Windows не подтвердила установку '+$Id)}
 }
 $script:LibraryTask.finished++
 Write-LibraryLog ('Установка '+$Id+' завершилась; код '+$process.ExitCode)
}

try{
 [IO.File]::WriteAllText($script:LatestLog,("Garant-PO libraries | "+(Get-Date)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
 $selection=@(Load-JsonFile (Join-Path $script:StateDir 'selection.json') @()|ForEach-Object{[string]$_})
 $allowed=@('vcredist-x64','vcredist-x86','directx-legacy','netfx3','webview2')+@($script:GSLibraryWingetIds.Keys)
 $selection=@($selection|Where-Object{$allowed -contains $_}|Select-Object -Unique)
 if($selection.Count -eq 0){throw 'Не выбраны системные библиотеки для установки'}
 $script:LibraryTask.total=$selection.Count;$script:LibraryTask.remaining=$selection.Count
 foreach($id in $selection){
  try{
   if($Mode -eq 'download' -and $script:GSLibraryWingetIds.ContainsKey($id)){Install-GSWingetLibrary $id}
   elseif($Mode -eq 'download'){
    switch($id){
     'vcredist-x64'{$null=Get-ValidMicrosoftInstaller 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe'}
     'vcredist-x86'{$null=Get-ValidMicrosoftInstaller 'https://aka.ms/vs/17/release/vc_redist.x86.exe' 'vc_redist.x86.exe'}
     'directx-legacy'{$null=Get-ValidMicrosoftInstaller 'https://download.microsoft.com/download/1/7/1/1718ccc4-6315-4d8e-9543-8e28a4e18c4c/dxwebsetup.exe' 'dxwebsetup.exe'}
     'webview2'{throw 'Для WebView2 доступна онлайн-установка, а не загрузка автономного пакета.'}
     'netfx3'{throw '.NET Framework 3.5 включается компонентом Windows и не скачивается отдельно этой кнопкой.'}
    }
    $script:LibraryTask.downloaded++;$script:LibraryTask.finished++
    Write-LibraryLog ('Файлы '+$id+' скачаны и проверены; установка не запускалась')
   }else{
   switch($id){
    'vcredist-x64'{Install-MicrosoftRuntime $id 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' @((Get-GSVcRedistVerb 'x64'),'/quiet','/norestart')}
    'vcredist-x86'{Install-MicrosoftRuntime $id 'https://aka.ms/vs/17/release/vc_redist.x86.exe' 'vc_redist.x86.exe' @((Get-GSVcRedistVerb 'x86'),'/quiet','/norestart')}
    'directx-legacy'{Install-MicrosoftRuntime $id 'https://download.microsoft.com/download/1/7/1/1718ccc4-6315-4d8e-9543-8e28a4e18c4c/dxwebsetup.exe' 'dxwebsetup.exe' @('/Q')}
    'webview2'{
     Install-MicrosoftRuntime $id 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' 'MicrosoftEdgeWebview2Setup.exe' @('/silent','/install')
    }
    'netfx3'{
     Set-LibraryStatus 'Включение компонента Windows' 'Проверяем .NET Framework 3.5'
     $feature=Get-WindowsOptionalFeature -Online -FeatureName NetFx3
     if($feature.State -eq 'Enabled'){Write-LibraryLog '.NET Framework 3.5 уже включён'}
     else{
      $featureResult=Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop
      if($featureResult.RestartNeeded){$script:LibraryTask.needReboot=$true}
      Write-LibraryLog '.NET Framework 3.5 включён средствами Windows'
     }
     $script:LibraryTask.finished++
    }
    default{Install-GSWingetLibrary $id}
   }
   }
  }catch{$script:LibraryTask.errors++;$script:LibraryTask.lastError=$_.Exception.Message;Write-LibraryLog ('ОШИБКА '+$id+': '+$_.Exception.Message)}
  $script:LibraryTask.remaining=[math]::Max(0,$selection.Count-$script:LibraryTask.finished)
 }
 if($script:LibraryTask.errors){Set-LibraryStatus 'Завершено с ошибками' ('Обработано: '+$script:LibraryTask.finished+' из '+$script:LibraryTask.total+'. '+$script:LibraryTask.lastError)}
 elseif($script:LibraryTask.needReboot){Set-LibraryStatus 'Готово' 'Библиотеки установлены. Для завершения изменений перезагрузите компьютер.'}
 elseif($Mode -eq 'download'){Set-LibraryStatus 'Готово' ('Скачано и проверено установщиков: '+$script:LibraryTask.downloaded+'. Установка не выполнялась.')}
 else{Set-LibraryStatus 'Готово' ('Установлено компонентов: '+$script:LibraryTask.finished)}
}catch{
 $script:LibraryTask.errors++;$script:LibraryTask.lastError=$_.Exception.Message
 Write-LibraryLog ('КРИТИЧЕСКАЯ ОШИБКА: '+$_.Exception.Message)
 Set-LibraryStatus 'Ошибка' $_.Exception.Message
}finally{
 $script:LibraryTask.running=$false;$script:LibraryTask.finishedAt=(Get-Date).ToString('o')
 Save-JsonFile $script:StatusFile $script:LibraryTask
}

