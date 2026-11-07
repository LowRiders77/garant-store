param([ValidateSet('scan','auto','download','gpu','local','network')][string]$Action='scan')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'UpdateCatalog.ps1')
. (Join-Path $PSScriptRoot 'Catalog.ps1')
$script:Task = [ordered]@{scanned=$false;running=$true; action=$Action; phase='Подготовка'; message='Запуск'; total=0; remaining=0; finished=0; downloaded=0; errors=0; bytes=0; expectedBytes=0; speedBps=0; etaSec=-1; percent=-1; currentIndex=0; packagesTotal=0; resumedBytes=0; current=''; actionTargetIds=@(); stageTimings=@{};systemProfile=$null;started=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); updatedAt=(Get-Date).ToString('HH:mm:ss'); finishedAt=''; lastError=''; needReboot=$false}
function Write-Status([string]$phase,[string]$message) {
  $script:Task.phase=$phase; $script:Task.message=$message; $script:Task.updatedAt=(Get-Date).ToString('HH:mm:ss')
  Save-JsonFile $script:StatusFile $script:Task
}
function Log([string]$msg) {
  $line='['+(Get-Date -Format 'HH:mm:ss')+'] '+$msg
  Add-Content -LiteralPath $script:LatestLog -Value $line -Encoding UTF8
  Write-Host $line
}
function Get-CurrentTargets {
  $watch=[System.Diagnostics.Stopwatch]::StartNew()
  $all = @(Get-TargetDevices)
  $watch.Stop()
  if($script:Task.scanned){$prior=[long]0;if($script:Task.stageTimings.ContainsKey('postInstallVerificationMs')){$prior=[long]$script:Task.stageTimings.postInstallVerificationMs};$script:Task.stageTimings.postInstallVerificationMs=$prior+$watch.ElapsedMilliseconds}
  Save-JsonFile $script:DeviceFile $all
  return $all
}
function Test-Archive([string]$path) {
  if (!(Test-Path $path)) {return $false}
  if ((Get-Item $path).Length -lt 500) {return $false}
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[System.IO.Compression.ZipFile]::OpenRead($path)
    try { return $zip.Entries.Count -gt 0 } finally {$zip.Dispose()}
  } catch { return $false }
}
# Track the actual response headers as the file grows; no separate HEAD request needed.
function Get-ExpectedDownloadLength([string]$headerPath,[long]$originalSize) {
  if (!(Test-Path -LiteralPath $headerPath)) {return [long]0}
  try {
    $raw = [System.IO.File]::ReadAllText($headerPath)
    $blocks = [regex]::Split($raw,'\r?\n\r?\n')
    for($j=$blocks.Count-1; $j -ge 0; $j--) {
      $block=$blocks[$j]
      if ($block -notmatch '(?mi)^HTTP/\S+\s+(200|206)\b') {continue}
      if ($block -match '(?mi)^Content-Range:\s*bytes\s+\d+-\d+/(\d+)') {return [long]$Matches[1]}
      if ($block -match '(?mi)^Content-Length:\s*(\d+)') {
        $bytes=[long]$Matches[1]
        if ($block -match '(?mi)^HTTP/\S+\s+206\b') {return ($bytes+$originalSize)}
        return $bytes
      }
    }
  } catch {}
  return [long]0
}
function Curl-Fetch([string]$url,[string]$destination,[bool]$isHtml=$false,[long]$knownSize=0) {
  $curl=Join-Path $env:WINDIR 'System32\curl.exe'
  if (!(Test-Path $curl)) {$curl='curl.exe'}
  $stderr=Join-Path $script:StateDir 'curl_stderr.txt'
  $stdout=Join-Path $script:StateDir 'curl_stdout.txt'
  $headers=Join-Path $script:StateDir 'curl_headers.txt'
  $diagnostics=Join-Path $script:StateDir 'curl_diagnostics.log'
  $proxy=Get-ProxyUrl
  $resumeDisabled=$false
  $maxAttempts=if($isHtml){2}else{3}
  $curlRetries=if($isHtml){'0'}else{'1'}
  for ($attempt=1; $attempt -le $maxAttempts; $attempt++) {
    if (Test-Path (Join-Path $script:StateDir 'cancel.flag')) {throw [System.OperationCanceledException]::new('Операция отменена пользователем')}
    $existing=[long]0
    if (!$isHtml -and (Test-Path -LiteralPath $destination)) {$existing=[long](Get-Item -LiteralPath $destination).Length}
    if($isHtml -and (Test-Path -LiteralPath $destination)){Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue}
    $script:Task.resumedBytes=$existing
    $script:Task.bytes=$existing
    $script:Task.expectedBytes=$knownSize
    $script:Task.percent=if($knownSize -gt 0){[math]::Min(100,[math]::Round(100*$existing/$knownSize,1))}else{-1}
    $script:Task.speedBps=0
    $script:Task.etaSec=-1
    Write-Status 'Загрузка' "Попытка $attempt/$maxAttempts — $($script:Task.current)"
    Log "Загрузка: попытка $attempt/$maxAttempts; на диске $existing байт"
    foreach ($p in @($stderr,$stdout,$headers)) {Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
    $args=@('--location','--fail','--silent','--show-error','--retry',$curlRetries,'--retry-delay','2','--connect-timeout',$(if($isHtml){'8'}else{'20'}),'--max-time',$(if($isHtml){'15'}else{'7200'}),'--speed-limit','1024','--speed-time','120','--user-agent','"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"','--header','"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"','--header','"Accept-Language: en-US,en;q=0.9,ru;q=0.8"','--referer','https://driverpack.io/','--dump-header',('"'+$headers+'"'),'--write-out','HTTP_CODE=%{http_code};CONTENT_TYPE=%{content_type};SIZE=%{size_download}','--output',('"'+$destination+'"'))
    if($isHtml){$args+=@('--header','"Sec-Fetch-Dest: document"','--header','"Sec-Fetch-Mode: navigate"','--header','"Sec-Fetch-Site: none"')}
    if ($proxy) {$args+=@('--proxy',('"'+$proxy+'"'))}
    # HTML catalog pages are metadata, never resumable files. Reusing an old
    # body with Range can make curl report exit 0 after an HTTP 416 response.
    if (!$isHtml -and $existing -gt 0 -and !$resumeDisabled) {$args+=@('--continue-at','-')}
    $args+=('"'+$url+'"')
    $transferTimer=[System.Diagnostics.Stopwatch]::StartNew()
    try {
      $p=Start-Process -FilePath $curl -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
      $lastSize=$existing
      $lastAt=[DateTime]::UtcNow
      $speed=0.0
      while ($true) {
        Start-Sleep -Milliseconds 750
        $p.Refresh()
        $now=[DateTime]::UtcNow
        $size=[long]0
        if (Test-Path -LiteralPath $destination) {$size=[long](Get-Item -LiteralPath $destination).Length}
        $seconds=[math]::Max(0.1,($now-$lastAt).TotalSeconds)
        $instant=[math]::Max(0,($size-$lastSize)/$seconds)
        $speed=if($speed -le 0){$instant}else{($speed*0.5+$instant*0.5)}
        $lastAt=$now; $lastSize=$size
        $script:Task.bytes=$size
        $script:Task.speedBps=[long]$speed
        $length=Get-ExpectedDownloadLength $headers $existing
        if ($length -gt 0) {$script:Task.expectedBytes=$length}
        if ($script:Task.expectedBytes -gt 0) {
          $script:Task.percent=[math]::Min(100,[math]::Round(100*$size/$script:Task.expectedBytes,1))
          $script:Task.etaSec=if($speed -gt 1024){[math]::Ceiling([math]::Max(0,$script:Task.expectedBytes-$size)/$speed)}else{-1}
        } else {$script:Task.percent=-1;$script:Task.etaSec=-1}
        $script:Task.updatedAt=(Get-Date).ToString('HH:mm:ss')
        Save-JsonFile $script:StatusFile $script:Task
        if (Test-Path (Join-Path $script:StateDir 'cancel.flag')) {
          if (!$p.HasExited) {$p.Kill()}
          throw [System.OperationCanceledException]::new('Операция отменена пользователем')
        }
        if ($p.HasExited) {break}
      }
      $p.Refresh()
      $code=[int]$p.ExitCode
    } catch [System.OperationCanceledException] {throw}
      catch { Log "Ошибка запуска curl: $($_.Exception.Message)";return $false }
    $transferTimer.Stop()
    $downloadPrior=[long]0;if($script:Task.stageTimings.ContainsKey('downloadMs')){$downloadPrior=[long]$script:Task.stageTimings.downloadMs}
    $script:Task.stageTimings.downloadMs=$downloadPrior+$transferTimer.ElapsedMilliseconds
    $err=''
    if (Test-Path -LiteralPath $stderr) {
      try {
        $raw=Get-Content -LiteralPath $stderr -Raw -ErrorAction Stop
        if ($null -ne $raw) {$err=([string]$raw).Trim()}
      } catch {$err='Не удалось прочитать stderr: '+$_.Exception.Message}
    }
    $received=[long]0
    if (Test-Path -LiteralPath $destination) {$received=[long](Get-Item -LiteralPath $destination).Length}
    $meta='';$httpCode='unknown'
    try {if (Test-Path $stdout) {$rawMeta=Get-Content -LiteralPath $stdout -Raw -ErrorAction Stop; if($null -ne $rawMeta){$meta=([string]$rawMeta).Trim()}}}catch{}
    if ($meta -match 'HTTP_CODE=(\d{3})') {$httpCode=$Matches[1]}
    $headerSummary=''
    try {if (Test-Path $headers) {$headerSummary=([string](Get-Content -LiteralPath $headers -Tail 15 -ErrorAction Stop)) -replace '\s+',' '}}catch{}
    Add-Content -LiteralPath $diagnostics -Value ('['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+ $url +' | curl='+$code+' | '+$meta+' | bytes='+$received+' | stderr='+$err+' | headers='+$headerSummary) -Encoding UTF8
    $contentType=''
    if($meta -match '(?i)CONTENT_TYPE=([^;\s]+)'){$contentType=[string]$Matches[1]}
    $contentRange=''
    if(Test-Path -LiteralPath $headers){try{$headerText=[System.IO.File]::ReadAllText($headers);$ranges=[regex]::Matches($headerText,'(?im)^Content-Range:\s*(.+)$');if($ranges.Count){$contentRange=[string]$ranges[$ranges.Count-1].Groups[1].Value.Trim()}}catch{}}
    if (Test-GSDownloadResponse $code $httpCode $contentType $received $isHtml $knownSize $existing $contentRange) {
      if ($knownSize -gt 0 -and $received -ne $knownSize) {Log "Размер не совпадает: $received / $knownSize байт; продолжим загрузку"}
      else {
        $script:Task.bytes=$received
        $script:Task.percent=100
        $script:Task.speedBps=0
        $script:Task.etaSec=0
        Save-JsonFile $script:StatusFile $script:Task
        return $true
      }
    } elseif ($httpCode -eq '416' -and !$isHtml -and $existing -gt 0 -and !$resumeDisabled) {
      Log 'HTTP 416: сервер не принял смещение докачки. Удаляю частичный архив и ограниченно повторяю загрузку с нуля.'
      Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
      $resumeDisabled=$true
    } elseif ($code -eq 0) {Log ('Ответ не прошёл проверку: curl='+$code+'; HTTP '+$httpCode+'; content-type/size='+$meta+'/'+$received)}
    else {Log "curl: код $code; HTTP $httpCode; $err; сохранено $received байт"}
    if ($meta -match '(?i)CONTENT_TYPE=(text/html|application/xhtml\+xml|application/json)' -and !$isHtml) {
      Log ('DRP вернул не архив, а HTML/JSON; HTTP '+$httpCode+'. Содержимое не устанавливается.')
      return $false
    }
    if ($httpCode -in @('401','403','404','410','451')) {
      Log "Источник драйверов отклонил автоматическую загрузку (HTTP $httpCode). Этот источник пропускается; проверьте другие результаты поиска или укажите ZIP вручную в папке драйверов."
      return $false
    }
    if ($code -eq 33 -and $existing -gt 0 -and !$resumeDisabled) {
      Log 'Сервер не поддерживает докачку (curl 33). Повторная загрузка с нуля.'
      Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
      $resumeDisabled=$true
    }
    if ($attempt -lt $maxAttempts) {Start-Sleep -Seconds 2}
  }
  return $false
}
function Install-MatchingInf([string]$folder,$targets) {
  $infs=@(Get-ChildItem -Path $folder -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue)
  $matchList=New-Object System.Collections.Generic.List[string]
  foreach ($inf in $infs) {
    if (Test-InfMatchesTargets $inf.FullName $targets) {$matchList.Add($inf.FullName)}
  }
  Log "Найдено INF: $($infs.Count), совпали по Hardware ID: $($matchList.Count)"
  foreach ($inf in $matchList) {
    Write-Status 'Установка' (Split-Path $inf -Leaf)
    Log "Установка INF: $(Split-Path $inf -Leaf)"
    $out=Join-Path $script:StateDir 'pnputil_out.txt'
    $err=Join-Path $script:StateDir 'pnputil_err.txt'
    $installTimer=[System.Diagnostics.Stopwatch]::StartNew()
    $proc=Start-Process -FilePath "$env:WINDIR\System32\pnputil.exe" -ArgumentList @('/add-driver',('"'+$inf+'"'),'/install') -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    $installTimer.Stop();$installPrior=[long]0;if($script:Task.stageTimings.ContainsKey('installMs')){$installPrior=[long]$script:Task.stageTimings.installMs};$script:Task.stageTimings.installMs=$installPrior+$installTimer.ElapsedMilliseconds
    Log ('Время pnputil: '+$installTimer.ElapsedMilliseconds+' мс; INF '+(Split-Path $inf -Leaf))
    $code=$proc.ExitCode
    $content=Get-Content $out -Raw -ErrorAction SilentlyContinue
    if ($content) {Log (($content -split '\r?\n' | Where-Object {$_ -match 'installed on device|Установлен.*устройств|Driver package added|успешно|reboot|перезагруз'} | Select-Object -First 8) -join ' | ')}
    if ($code -eq 3010) {$script:Task.needReboot=$true}
    if ($code -notin @(0,259,3010)) {$script:Task.errors++;Log "PnPUtil завершился с кодом $code"}
    $newTargets=@(Get-CurrentTargets)
    $script:Task.remaining=$newTargets.Count
    Save-JsonFile $script:StatusFile $script:Task
  }
}
function Run-Install($packages,$install,$original) {
  $i=0
  foreach ($pkg in $packages) {
    if (Test-Path (Join-Path $script:StateDir 'cancel.flag')) {throw [System.OperationCanceledException]::new('Операция отменена пользователем')}
    $i++
    $filename=[System.IO.Path]::GetFileName(([uri]$pkg.url).AbsolutePath)
    # Download and verify inside the trusted engine folder; the user gets a copy.
    $path=Join-Path $script:EngineDownloadDir $filename
    $script:Task.current=$filename
    $script:Task.currentIndex=$i
    $script:Task.packagesTotal=@($packages).Count
    $script:Task.bytes=0
    $script:Task.expectedBytes=0
    $script:Task.speedBps=0
    $script:Task.percent=-1
    Write-Status 'Загрузка' "Пакет $i из $($packages.Count): $filename"
    Log "Пакет $i/$($packages.Count): $filename"
    $isValid=$false
    if (Test-Path $path) {
      if ($pkg.kind -eq 'Zip') {$isValid=Test-Archive $path}
      else {
        if ((Get-Item $path).Length -gt 100MB) {$sha=(Get-FileHash $path -Algorithm SHA512).Hash.ToLowerInvariant();$isValid=($sha -eq $pkg.sha512)}
      }
    }
    if (!$isValid) {
      $partial=$path+'.partial'
      # Keep .partial on interruption and resume from the previous byte on the next run.
      if (!(Curl-Fetch $pkg.url $partial $false ([long]$pkg.expectedBytes))) {$script:Task.errors++;continue}
      if ($pkg.kind -eq 'Zip' -and !(Test-Archive $partial)) { Log 'Ответ не является ZIP-архивом';$script:Task.errors++;Remove-Item $partial -Force;continue }
      if ($pkg.kind -eq 'IntelGPU') {
        $sha=(Get-FileHash $partial -Algorithm SHA512).Hash.ToLowerInvariant()
        if ($sha -ne $pkg.sha512) {Log 'ОШИБКА: контрольная сумма Intel Graphics не совпала';$script:Task.errors++;Remove-Item $partial -Force;continue}
        $signature=Get-AuthenticodeSignature -LiteralPath $partial
        if($signature.Status -ne 'Valid' -or [string]$signature.SignerCertificate.Subject -notmatch '(?i)Intel') {Log ('ОШИБКА: подпись Intel Graphics не подтверждена: '+[string]$signature.Status);$script:Task.errors++;Remove-Item $partial -Force;continue}
      }
      Move-Item $partial $path -Force
      Log 'Файл скачан и проверен'
    } else {Log 'Найден в кэше, повторная загрузка не нужна'}
    if (Publish-GSUserCopy -Path $path -UserDirectory $script:DownloadDir) {Log ('Копия сохранена в папке пользователя: '+$script:DownloadDir)}
    $script:Task.downloaded++
    $script:Task.bytes=[long](Get-Item $path).Length
    $script:Task.speedBps=0
    $script:Task.etaSec=0
    $script:Task.percent=100
    Save-JsonFile $script:StatusFile $script:Task
    if (!$install) {continue}
    $newTargets=@(Get-CurrentTargets)
    if ($pkg.kind -eq 'IntelGPU') {
      $matchingGpu=@($newTargets | Where-Object {$_.kind -eq 'GPU' -and @(@(Get-NormalIds $_) | Where-Object {$pkg.ids -contains $_}).Count -gt 0})
      if ($matchingGpu.Count -eq 0) {continue}
      Write-Status 'Установка' ('Intel Graphics — официальный пакет '+$pkg.label)
      Log 'Запуск официального установщика Intel Graphics в тихом режиме (-s)'
      $exe=Start-Process -FilePath $path -ArgumentList @('-s') -Wait -PassThru -WindowStyle Hidden
      Log "Intel Graphics installer exit code: $($exe.ExitCode)"
      $gpuAfter=@(Get-CurrentTargets | Where-Object {$_.kind -eq 'GPU' -and @(@(Get-NormalIds $_) | Where-Object {$pkg.ids -contains $_}).Count -gt 0})
      if ($gpuAfter.Count -eq 0) {Log 'GPU: базовый драйвер больше не используется, подтверждено повторным сканированием'}
      else {Log 'GPU: по-прежнему базовый драйвер; проверь IntelGfx.log и версию Windows';$script:Task.errors++}
      if ($exe.ExitCode -in @(2,14,3010)) {$script:Task.needReboot=$true}
      elseif($exe.ExitCode -ne 0){$script:Task.errors++;Log 'Intel Graphics installer returned a failure code'}
    } else {
      $packageTargets=@(Get-PackageTargets $pkg $newTargets $script:actionTargetIds)
      if($packageTargets.Count -eq 0){Log ('Архив не относится к выбранным устройствам: '+$pkg.label);continue}
      $folder=Join-Path $script:CacheDir ([System.IO.Path]::GetFileNameWithoutExtension($filename))
      if (!(Test-Path $folder)) {New-Item -ItemType Directory $folder -Force | Out-Null}
      $infs=@(Get-ChildItem $folder -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
      if (!$infs.Count) {
        Write-Status 'Распаковка' $filename
        try {Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory($path,$folder)} catch {Log "Ошибка распаковки: $($_.Exception.Message)";$script:Task.errors++;continue}
      }
      Install-MatchingInf $folder $packageTargets
    }
    $newTargets=@(Get-CurrentTargets)
    $script:Task.remaining=$newTargets.Count
    $script:Task.finished=($script:Task.total-$newTargets.Count)
    Save-JsonFile $script:StatusFile $script:Task
    if ($newTargets.Count -eq 0) {Log 'Все целевые устройства получили драйверы';break}
  }
}
try {
  $noPackageCount=0
  [System.IO.File]::WriteAllText($script:LatestLog,"Garant-PO 6.0 | $(Get-Date) | Action: $Action`r`n",[System.Text.UTF8Encoding]::new($false))
  Write-Status 'Сканирование' 'Получаем список устройств'
  $localScanTimer=[System.Diagnostics.Stopwatch]::StartNew()
  $all=@(Get-CurrentTargets)
  $localScanTimer.Stop();$script:Task.stageTimings.localScanMs=$localScanTimer.ElapsedMilliseconds
  $script:Task.scanned=$true
  [System.IO.File]::WriteAllText((Join-Path $script:StateDir 'scan.flag'),'scanned',[System.Text.Encoding]::ASCII)
  Save-JsonFile $script:StatusFile $script:Task
  $script:Task.total=$all.Count
  $script:Task.remaining=$all.Count
  Log "Найдено проблемных устройств и базовых GPU: $($all.Count)"
  if ($Action -eq 'scan') {
    # Reveal local PnP problems immediately, before the slower inventory and
    # any online catalog/source checks complete.
    Save-JsonFile $script:DeviceFile $all
    Write-Status 'Локальное сканирование завершено' ("Проблемных устройств: $($all.Count). Собираю сведения об установленных драйверах.")
    $inventoryTimer=[System.Diagnostics.Stopwatch]::StartNew()
    $driverInventory=@()
    try{$driverInventory=@(Get-InstalledDriverInventory -ProblemDevices $all);Log ('Инвентаризация установленных PnP-драйверов: '+$driverInventory.Count+'; актуальность без источника обновлений не объявляется подтверждённой.')}catch{Log ('Не удалось получить полный список установленных PnP-драйверов: '+$_.Exception.Message)}
    $inventoryTimer.Stop();$script:Task.stageTimings.driverInventoryMs=$inventoryTimer.ElapsedMilliseconds
    $librarySuggestions=@(Get-SystemLibrarySuggestions)
    try{$script:Task.systemProfile=Get-GSComputerProfile;Save-JsonFile (Join-Path $script:StateDir 'system-profile.json') $script:Task.systemProfile;Log ('Профиль устройства сохранён локально; ID '+$script:Task.systemProfile.localId.Substring(0,12)+'. Серийные номера не собираются.')}catch{Log ('Не удалось сохранить локальный профиль устройства: '+$_.Exception.Message)}
    # Publish a usable local snapshot before any network source is queried.
    # The UI can show device problems immediately while DRP/WU continue.
    $visible=@($all)+@($driverInventory)+@($librarySuggestions)
    Save-JsonFile $script:DeviceFile $visible
    $script:Task.total=$visible.Count;$script:Task.remaining=$visible.Count
    Write-Status 'Локальная проверка завершена' ("Найдено проблемных устройств: $($all.Count). Проверяю источники обновлений в фоне.")
    if($all.Count){
      $drpTimer=[System.Diagnostics.Stopwatch]::StartNew()
      try{
        Write-Status 'Поиск DriverPack' ("Проверяю DriverPack для $($all.Count) проблемных устройств до резервных источников.")
        $drpCandidates=@(Get-Packages $all)
        Log ('DRP: проверено проблемных устройств '+$all.Count+'; подтверждённых каталожных ссылок на пакеты '+$drpCandidates.Count+'. Совместимость INF будет проверена перед установкой.')
      }catch{Log ('Ошибка поиска в DriverPack; будет проверен резервный источник: '+$_.Exception.Message)}
      $drpTimer.Stop();$script:Task.stageTimings.driverPackSearchMs=$drpTimer.ElapsedMilliseconds;Log ('Время поиска DriverPack: '+$drpTimer.ElapsedMilliseconds+' мс.')
    }
    $windowsUpdates=@();$windowsUpdateWarning=''
    $wuTimer=[System.Diagnostics.Stopwatch]::StartNew()
    try{
      Write-Status 'Резервная проверка Windows Update' 'DriverPack проверен; запрашиваю доступные резервные предложения Windows Update.'
      $windowsUpdates=@(Get-WindowsDriverUpdates -StatusCallback {param($p,$m) Write-Status $p $m} -LogCallback {param($m) Log ('[Windows Update] '+$m)})
      Log "Предложений драйверов через Windows Update: $($windowsUpdates.Count)"
    }catch{
      $windowsUpdateWarning=$_.Exception.Message
      Log "Windows Update недоступен: $windowsUpdateWarning"
    }
    $wuTimer.Stop();$script:Task.stageTimings.windowsUpdateSearchMs=$wuTimer.ElapsedMilliseconds;Log ('Время поиска Windows Update: '+$wuTimer.ElapsedMilliseconds+' мс.')
    $visible=@($all)+@($driverInventory)+@($windowsUpdates)+@($librarySuggestions)
    if($script:Task.systemProfile){$null=Save-GSDeviceSession $script:Task.systemProfile $all.Count $driverInventory.Count $windowsUpdates.Count $librarySuggestions.Count}
    Save-JsonFile $script:DeviceFile $visible
    $script:Task.total=$visible.Count;$script:Task.remaining=$visible.Count
    if($visible.Count -eq 0 -and -not $windowsUpdateWarning){Write-Status 'Готово' 'Проблемных устройств и доступных обновлений драйверов не найдено.'}
    elseif($windowsUpdateWarning){Write-Status 'Завершено с предупреждением' ("Проверка устройств завершена. Windows Update: "+$windowsUpdateWarning)}
    else{Write-Status 'Готово' ("Проблемные устройства: $($all.Count); инвентаризированных драйверов: $($driverInventory.Count); подтверждённых обновлений: $($windowsUpdates.Count); рекомендации компонентов: $($librarySuggestions.Count)")}
  }
  elseif ($Action -eq 'network') {
    $proxy=Get-ProxyUrl
    if ($proxy) {Log "Прокси: $proxy"} else {Log 'Прокси не задан; запрос пойдёт через системную маршрутизацию/VPN'}
    $url='https://dl.driverpack.io/driverpacks/repack/Chipset/Intel/FORCED/HID/10x64/2.2.2.17/Intel-FORCED-HID-10x64-2.2.2.17-drp.zip'
    $curl=Join-Path $env:WINDIR 'System32\curl.exe'
    $args=@('--location','--silent','--show-error','--range','0-127','--max-time','40','--fail','--output','NUL',('"'+$url+'"'))
    if ($proxy) {$args=@('--proxy',('"'+$proxy+'"'))+$args}
    $proc=Start-Process -FilePath $curl -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $script:StateDir 'netout.txt') -RedirectStandardError (Join-Path $script:StateDir 'neterr.txt')
    if ($proc.ExitCode -eq 0) {Log 'Тест загрузки с DRP завершился успешно (curl 0)'} else {Log "Тест DRP: curl $($proc.ExitCode); см. State\neterr.txt";$script:Task.errors++}
  } elseif ($Action -eq 'local') {
    # The user's folders are writable without administrator rights. Take a
    # snapshot into a fresh administrators-only staging folder and install only
    # from that snapshot, so nothing can be swapped between check and pnputil.
    $staging=Join-Path $script:StagingDir ('local-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
      $userDirs=@($script:DriverDir,$script:DownloadDir) | Where-Object {$_} | Select-Object -Unique
      $index=0
      foreach ($dir in $userDirs) {
        $index++
        Write-Status 'Подготовка' ('Копирование пакетов из «'+$dir+'»')
        $copy=Copy-GSUntrustedTree -Source $dir -Destination (Join-Path $staging ('source'+$index)) -MaxBytes 8GB
        Log ('Скопировано из папки пользователя: файлов '+$copy.Files+', байт '+$copy.Bytes+'; пропущено '+$copy.Skipped+$(if($copy.Truncated){' (превышен лимит 8 ГБ)'}else{''}))
      }
      $archives=@(Get-ChildItem $staging -File -Filter '*.zip' -Recurse -ErrorAction SilentlyContinue)
      foreach ($zip in $archives) {
        if (!(Test-Archive $zip.FullName)) {continue}
        $target=Join-Path $zip.DirectoryName ([System.IO.Path]::GetFileNameWithoutExtension($zip.Name)+'.extracted')
        try {Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName,$target)}catch{Log "Ошибка ZIP: $($zip.Name)"}
      }
      Install-MatchingInf $staging @(Get-CurrentTargets)
      Install-MatchingInf $script:CacheDir @(Get-CurrentTargets)
    } finally {
      Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
  } else {
    $selection=Load-JsonFile (Join-Path $script:StateDir 'selection.json') @()
    $selected=@($all)
    if (@($selection).Count) { $selected=@($all|Where-Object {$selection -contains $_.instanceId}) }
    if ($Action -eq 'gpu') {$selected=@($selected|Where-Object {$_.kind -eq 'GPU'})}
    Log "Выбрано для обработки: $($selected.Count)"
    $script:Task.total=$selected.Count
    if ($Action -ne 'download') {
      # Only the trusted cache is used automatically. Packages the user placed in
      # Downloads are installed through the explicit «Установить из папки» action.
      Log 'Проверяю ранее распакованные INF из защищённого кэша...'
      Install-MatchingInf $script:CacheDir $selected
      $selected=@(Get-CurrentTargets | Where-Object {$selected.instanceId -contains $_.instanceId})
      Log "После проверки локальных INF требуется драйверов: $($selected.Count)"
    }
    $script:actionTargetIds=@($selected|ForEach-Object{[string]$_.instanceId})
    $packages=@(Get-Packages $selected)
    Log "Найдено подходящих источников: $($packages.Count)"
    $coveredIds=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach($pkg in $packages){foreach($id in @($pkg.ids)){foreach($device in $selected){if(@(Get-NormalIds $device) -contains [string]$id){[void]$coveredIds.Add([string]$device.instanceId)}}}}
    $noPackageCount=@($selected|Where-Object{-not $coveredIds.Contains([string]$_.instanceId)}).Count
    if($packages.Count -eq 0 -and $selected.Count){
      Write-Status 'Пакет не найден' 'Для выбранных устройств DRP не вернул совместимый ZIP. Проверьте сетевой доступ к DRP или добавьте официальный пакет производителя в папку «Загрузки\Garant Store\Drivers».'
    }
    $install=($Action -ne 'download')
    Run-Install $packages $install $all
    if ($install) {
      # New child devices may appear after installing parent chipset/Serial IO.
      $before=@($selected|ForEach-Object {$_.instanceId})
      $later=@(Get-CurrentTargets | Where-Object {$before -notcontains $_.instanceId})
      if ($later.Count) {
        Log "Обнаружены дополнительные устройства после установки: $($later.Count)"
        $script:actionTargetIds=@(@($script:actionTargetIds)+@($later|ForEach-Object{[string]$_.instanceId})|Select-Object -Unique)
        $script:Task.total+=$later.Count
        $more=@(Get-Packages $later)
        Run-Install $more $true $all
      }
    }
  }
  $end=@(Get-CurrentTargets)
  if($Action -eq 'scan'){
    $display=@($end)+@($driverInventory)+@($windowsUpdates)+@($librarySuggestions)
    Save-JsonFile $script:DeviceFile $display
    $script:Task.remaining=@($end).Count+@($windowsUpdates).Count+@($librarySuggestions).Count
  }
  $remainingTargets=@($end)
  if($Action -ne 'scan' -and $Action -ne 'download' -and $script:actionTargetIds.Count){
    $remainingTargets=@($end|Where-Object{$script:actionTargetIds -contains [string]$_.instanceId})
  }
  if($Action -eq 'scan'){$script:Task.remaining=@($end).Count+@($windowsUpdates).Count+@($librarySuggestions).Count}
  else{$script:Task.remaining=$remainingTargets.Count}
  $script:Task.finished=[math]::Max(0,$script:Task.total-$remainingTargets.Count)
  Log "ИТОГ: изначально $($script:Task.total), сейчас требуют драйвер $($end.Count); успешно загруженных пакетов $($script:Task.downloaded)."
  $linkFile=Join-Path $script:LogDir 'Missing-DRP-Links.txt'
  $links=New-Object System.Collections.Generic.List[string]
  foreach($dev in $end){
    $ids=@(Get-NormalIds $dev)
    $id=$ids | Where-Object {$_ -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_|ACPI\\)'} | Select-Object -First 1
    if ($id){ $links.Add($dev.name+' | '+$id+' | '+'https://driverpack.io/en/hwids/'+[uri]::EscapeDataString($id)) }
  }
  [System.IO.File]::WriteAllLines($linkFile,$links.ToArray(),[System.Text.UTF8Encoding]::new($true))
  $csv=Join-Path $script:LogDir 'Remaining.csv'
  if ($end.Count) {$end | Select-Object name,kind,code,hwid,instanceId | Export-Csv -Path $csv -Encoding UTF8 -NoTypeInformation}
  else {[System.IO.File]::WriteAllText($csv,'name,kind,code,hwid,instanceId'+[Environment]::NewLine,[System.Text.UTF8Encoding]::new($true))}
  if ($script:Task.errors -gt 0) {
    if($script:actionTargetIds.Count){Write-Status 'Завершено с ошибками' ("Ошибок загрузки/установки: $($script:Task.errors); скачано пакетов: $($script:Task.downloaded); не найден проверенный источник для устройств: $noPackageCount; из выбранных устройств требуют внимания: $($remainingTargets.Count). Смотрите журнал загрузки, распаковки и PnPUtil.")}
    else{Write-Status 'Завершено с ошибками' 'Некоторые пакеты не загружены или не установлены — см. журнал'}
  }
  elseif($noPackageCount -gt 0){Write-Status 'Завершено с ошибками' ("Для $noPackageCount из $($script:actionTargetIds.Count) выбранных устройств не найден проверенный пакет. Скачано пакетов: $($script:Task.downloaded); осталось проблемных устройств: $($remainingTargets.Count). Проверьте сетевое подключение к CDN DriverPack или выберите пакет производителя.")}
  elseif($Action -in @('auto','gpu','local') -and $remainingTargets.Count -gt 0 -and -not $script:Task.needReboot){$script:Task.errors++;Write-Status 'Завершено с ошибками' ("Установка завершилась, но после повторного сканирования $($remainingTargets.Count) выбранных устройств всё ещё требуют драйвер. Проверьте журнал INF/PnPUtil и при необходимости перезагрузите Windows.")}
  elseif($Action -eq 'scan' -and $windowsUpdateWarning){Write-Status 'Готово' ("Проверка завершена. Проблемных устройств: $($end.Count). Windows Update сейчас не ответил: $windowsUpdateWarning. Поиск через DRP доступен отдельно.")}
  elseif($Action -eq 'scan' -and $end.Count -eq 0 -and $windowsUpdates.Count -eq 0 -and $librarySuggestions.Count -eq 0){Write-Status 'Готово' 'Драйверы актуальны, обновлений Windows Update и недостающих библиотек не найдено.'}
  elseif($Action -eq 'scan'){Write-Status 'Готово' ("Устройства: $($end.Count); обновления Windows Update: $($windowsUpdates.Count); рекомендуемые библиотеки: $($librarySuggestions.Count).")}
  elseif($remainingTargets.Count -eq 0){Write-Status 'Готово' 'Все выбранные драйверы установлены. Проблемных выбранных устройств не осталось.'}
  else{Write-Status 'Готово' "Проверка завершена. Среди выбранных устройств осталось: $($remainingTargets.Count)"}
} catch [System.OperationCanceledException] {
  Log 'Операция отменена пользователем. Недокачанные файлы сохранены.'
  Write-Status 'Отменено' 'Частично скачанные файлы сохранены для возобновления'
} catch {
  $script:Task.lastError=$_.Exception.Message
  $script:Task.errors++
  Log "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message) $($_.ScriptStackTrace)"
  Write-Status 'Ошибка' $_.Exception.Message
} finally {
  $script:Task.running=$false
  $script:Task.finishedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Save-JsonFile $script:StatusFile $script:Task
}

