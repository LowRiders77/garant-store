# Безопасность установки драйверов и честные итоги.
#  - Состояние источников: после HTTP 401/403/429/451 источник приостанавливается,
#    вместо десятков повторных запросов по каждому Hardware ID (поле: DriverPack 403).
#  - Разбор INF по секциям [Manufacturer]/моделей с учётом архитектуры и сборки
#    Windows; точное совпадение Hardware ID конкретного устройства; FORCED-пакеты
#    DRP и INF другого класса устройств не устанавливаются.
#  - Снимок для отката до установки и проверка звука после неё.
#  - Итог различает: источник недоступен / сеть / пакет не найден / несовместим / установлено.

# ---------------------------------------------------------------- источники
function Get-GSSourceHost([string]$Url){try{return ([uri]$Url).Host.ToLowerInvariant()}catch{return ''}}

function Get-GSSourceHealth([string]$Path){
  # PS 5.1 emits a JSON array as one object: ForEach-Object unrolls it so every host is mapped.
  $map=@{}
  if($Path -and (Test-Path -LiteralPath $Path)){
    try{foreach($e in @(Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json|ForEach-Object{$_})){if($e -and $e.host){$map[[string]$e.host]=$e}}}catch{}
  }
  return $map
}

function Save-GSSourceHealth([string]$Path,[hashtable]$Map){
  if(-not $Path){return}
  $list=@($Map.Keys|ForEach-Object{$Map[$_]})
  [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $list -Depth 4),[Text.UTF8Encoding]::new($false))
}

function Get-GSFetchClassification([string]$HttpCode,[int]$CurlCode){
  if($HttpCode -in @('200','206')){return 'Ok'}
  if($HttpCode -in @('401','403','451')){return 'Blocked'}
  if($HttpCode -eq '429'){return 'RateLimited'}
  if($HttpCode -in @('404','410')){return 'NotFound'}
  if($CurlCode -in @(5,6,7,28,35,52,55,56) -or $HttpCode -in @('000','unknown','502','503','504')){return 'NetworkError'}
  return 'Failed'
}

function Register-GSSourceResult{
  # Returns the classification; persists a pause for blocked/unreachable hosts.
  param([string]$Path,[string]$Url,[string]$HttpCode,[int]$CurlCode,[datetime]$Now=(Get-Date))
  $class=Get-GSFetchClassification $HttpCode $CurlCode
  $sourceHost=Get-GSSourceHost $Url
  if(-not $sourceHost){return $class}
  $map=Get-GSSourceHealth $Path
  $entry=if($map.ContainsKey($sourceHost)){$map[$sourceHost]}else{[pscustomobject]@{host=$sourceHost;failures=0;blockedUntil='';reason='';lastCode=''}}
  $entry.lastCode=$HttpCode
  switch($class){
    'Ok'{$entry.failures=0;$entry.blockedUntil='';$entry.reason=''}
    'Blocked'{$entry.blockedUntil=$Now.AddMinutes(30).ToString('o');$entry.reason=('HTTP '+$HttpCode)}
    'RateLimited'{$entry.blockedUntil=$Now.AddMinutes(10).ToString('o');$entry.reason='HTTP 429'}
    'NetworkError'{$entry.failures=[int]$entry.failures+1;if([int]$entry.failures -ge 3){$entry.blockedUntil=$Now.AddMinutes(10).ToString('o');$entry.reason='нет связи'}}
  }
  $map[$sourceHost]=$entry
  Save-GSSourceHealth $Path $map
  return $class
}

function Test-GSSourceBlocked{
  # $null when usable; otherwise the reason ("HTTP 403", "нет связи").
  param([string]$Path,[string]$Url,[datetime]$Now=(Get-Date))
  $sourceHost=Get-GSSourceHost $Url
  $map=Get-GSSourceHealth $Path
  if(-not $sourceHost -or -not $map.ContainsKey($sourceHost)){return $null}
  $e=$map[$sourceHost]
  if(-not $e.blockedUntil){return $null}
  try{if([datetime]::Parse([string]$e.blockedUntil,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind) -gt $Now){return [string]$e.reason}}catch{}
  return $null
}

# ---------------------------------------------------------------- INF
function Read-GSInfText([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE){return [Text.Encoding]::Unicode.GetString($bytes,2,$bytes.Length-2)}
  if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF){return [Text.Encoding]::BigEndianUnicode.GetString($bytes,2,$bytes.Length-2)}
  if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){return [Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)}
  return [Text.Encoding]::Default.GetString($bytes)
}

function Test-GSInfDecoration{
  # NTamd64 / NTamd64.10.0...17763 (= NT<arch>.<major>.<minor>.<product>.<suite>.<build>) / NTx86 / NTarm64.
  param([string]$Decoration,[string]$Architecture,[int]$Build)
  $d=$Decoration.Trim().ToUpperInvariant()
  if(-not $d){return $true}
  $parts=$d.Split('.')
  if($parts[0] -notmatch '^NT(AMD64|X86|ARM64|ARM|IA64)?$'){return $false}
  $arch=$Matches[1]
  $want=switch($Architecture){'x86'{'X86'}'arm64'{'ARM64'}default{'AMD64'}}
  if($arch -and $arch -ne $want){return $false}
  if($parts.Count -ge 2 -and $parts[1] -match '^\d+$' -and [int]$parts[1] -gt 10){return $false}
  if($parts.Count -ge 6 -and $parts[5] -match '^\d+$' -and $Build -gt 0 -and [int]$parts[5] -gt $Build){return $false}
  return $true
}

function Get-GSInfModel{
  # IDs from the model sections that apply to this architecture/build, the INF
  # Class and provider. Comments and strings in other sections are ignored, so
  # an ID mentioned in a comment can no longer select a package.
  param([Parameter(Mandatory=$true)][string]$Path,[string]$Architecture='x64',[int]$Build=19041)
  $text=Read-GSInfText $Path
  $sections=@{};$current=''
  foreach($rawLine in ($text -split "`r?`n")){
    $line=$rawLine
    $q=$false;$cut=-1
    for($i=0;$i -lt $line.Length;$i++){$ch=$line[$i];if($ch -eq '"'){$q=-not $q}elseif($ch -eq ';' -and -not $q){$cut=$i;break}}
    if($cut -ge 0){$line=$line.Substring(0,$cut)}
    $line=$line.Trim()
    if(-not $line){continue}
    if($line -match '^\[(.+)\]$'){$current=$Matches[1].Trim().ToUpperInvariant();if(-not $sections.ContainsKey($current)){$sections[$current]=New-Object System.Collections.Generic.List[string]};continue}
    if($current){$sections[$current].Add($line)}
  }
  $class='';$provider=''
  if($sections.ContainsKey('VERSION')){foreach($l in $sections['VERSION']){if($l -match '^(?i)Class\s*=\s*"?([^"]+)"?$'){$class=$Matches[1].Trim()};if($l -match '^(?i)Provider\s*=\s*(.+)$'){$provider=$Matches[1].Trim()}}}
  $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  if($sections.ContainsKey('MANUFACTURER')){
    foreach($l in $sections['MANUFACTURER']){
      if($l -notmatch '='){continue}
      $parts=@(($l.Split('=',2)[1]).Split(',')|ForEach-Object{$_.Trim()})
      $base=$parts[0].ToUpperInvariant()
      $decorations=@($parts|Select-Object -Skip 1)
      $names=@()
      if(-not $decorations.Count){$names=@($base)}
      else{foreach($dec in $decorations){if(Test-GSInfDecoration -Decoration $dec -Architecture $Architecture -Build $Build){$names+=($base+'.'+$dec.ToUpperInvariant())}}}
      foreach($n in $names){
        if(-not $sections.ContainsKey($n)){continue}
        foreach($model in $sections[$n]){
          if($model -notmatch '='){continue}
          $fields=@(($model.Split('=',2)[1]).Split(',')|ForEach-Object{$_.Trim().Trim('"')})
          foreach($id in @($fields|Select-Object -Skip 1)){if($id){[void]$ids.Add($id.ToUpperInvariant())}}
        }
      }
    }
  }
  return [pscustomobject]@{Path=$Path;Class=$class;Provider=$provider;Ids=$ids}
}

function Test-GSForcedPackage([string]$Name){return ([string]$Name -match '(?i)(^|[-_\\/ ])FORCED([-_\\/ ]|$)')}

function Get-GSDeviceIdTier([string]$Id){
  if($Id -match '(?i)SUBSYS_'){return 1}
  if($Id -match '(?i)&REV_'){return 2}
  return 3
}

function Select-GSInfForDevice{
  # Best INF for ONE device. The match must be one of this device's own
  # Hardware IDs (most specific first), listed in an applicable model section.
  # Returns $null with a reason when nothing is safe to install.
  param([Parameter(Mandatory=$true)]$Device,[object[]]$Models,[string]$PackageName='')
  if(Test-GSForcedPackage $PackageName){return [pscustomobject]@{Model=$null;MatchedId='';Tier=0;Reason='Пакет DRP помечен FORCED (принудительная установка) — автоматически не ставится'}}
  $deviceIds=@(@($Device.hardwareIds)|Where-Object{$_}|ForEach-Object{([string]$_).ToUpperInvariant()})
  $deviceClass=if($Device.PSObject.Properties['category']){[string]$Device.category}else{''}
  $best=$null;$bestIndex=[int]::MaxValue;$classRejected=$false;$forcedRejected=$false
  foreach($m in @($Models)){
    if($null -eq $m){continue}
    if(Test-GSForcedPackage ([string]$m.Path)){
      foreach($id in $deviceIds){if($m.Ids.Contains($id)){$forcedRejected=$true;break}}
      continue
    }
    if($deviceClass -and $m.Class -and $deviceClass -ne $m.Class){
      foreach($id in $deviceIds){if($m.Ids.Contains($id)){$classRejected=$true;break}}
      continue
    }
    for($i=0;$i -lt $deviceIds.Count -and $i -lt $bestIndex;$i++){
      if($m.Ids.Contains($deviceIds[$i])){$best=$m;$bestIndex=$i;break}
    }
  }
  if($null -eq $best){
    $reason=if($forcedRejected){'Подходит только FORCED-пакет DRP (принудительная установка) — автоматически не ставится'}elseif($classRejected){'INF относится к другому классу устройств — не устанавливается'}else{'Ни один INF не содержит Hardware ID этого устройства'}
    return [pscustomobject]@{Model=$null;MatchedId='';Tier=0;Reason=$reason}
  }
  $matched=$deviceIds[$bestIndex]
  $tier=Get-GSDeviceIdTier $matched
  $quality=switch($tier){1{'точное совпадение с OEM-подсистемой'}2{'совпадение по ревизии устройства'}default{'общий драйвер производителя чипа (без OEM-подсистемы)'}}
  return [pscustomobject]@{Model=$best;MatchedId=$matched;Tier=$tier;Reason=$quality}
}

# ---------------------------------------------------------------- звук
function Test-GSAudioDevice($Device){
  $ids=(@($Device.hardwareIds)+@([string]$Device.instanceId)) -join ' '
  $category=if($Device.PSObject.Properties['category']){[string]$Device.category}else{''}
  return (($ids -match '(?i)(INTELAUDIO|HDAUDIO)\\') -or ($category -in @('MEDIA','AudioEndpoint')))
}

function Get-GSAudioHealth{
  # Snapshot of audio-related PnP devices and playback endpoints (Windows).
  $devices=@();$endpoints=@()
  try{$devices=@(Get-PnpDevice -PresentOnly -ErrorAction Stop|Where-Object{[string]$_.InstanceId -match '(?i)^(INTELAUDIO|HDAUDIO)\\' -or [string]$_.Class -eq 'MEDIA'})}catch{}
  try{$endpoints=@(Get-PnpDevice -PresentOnly -Class AudioEndpoint -ErrorAction Stop)}catch{}
  return [pscustomobject]@{
    Devices=@($devices|ForEach-Object{[pscustomobject]@{InstanceId=[string]$_.InstanceId;Name=[string]$_.FriendlyName;Status=[string]$_.Status;Problem=[string]$_.Problem}})
    Endpoints=@($endpoints|ForEach-Object{[pscustomobject]@{Name=[string]$_.FriendlyName;Status=[string]$_.Status}})
  }
}

function Compare-GSAudioHealth{
  # Pure: decides what can be claimed after an audio driver install.
  param($Before,$After)
  $badAfter=@(@($After.Devices)|Where-Object{$_.Status -ne 'OK'})
  $badBeforeIds=@(@($Before.Devices)|Where-Object{$_.Status -ne 'OK'}|ForEach-Object{$_.InstanceId})
  $newProblems=@($badAfter|Where-Object{$badBeforeIds -notcontains $_.InstanceId})
  $okEndpoints=@(@($After.Endpoints)|Where-Object{$_.Status -eq 'OK'})
  $state=if($newProblems.Count){'Regression'}elseif($badAfter.Count){'StillFailing'}elseif(-not $okEndpoints.Count){'NoEndpoint'}else{'DriverOk'}
  $text=switch($state){
    'Regression'{'После установки появились новые ошибки аудиоустройств: '+(@($newProblems|ForEach-Object{$_.Name}) -join ', ')+'. Используйте откат драйвера.'}
    'StillFailing'{'Аудиоустройства всё ещё с ошибкой: '+(@($badAfter|ForEach-Object{$_.Name}) -join ', ')}
    'NoEndpoint'{'Драйверы установлены, но устройство воспроизведения не появилось — динамики работать не будут'}
    default{'Аудиоустройства без ошибок, устройств воспроизведения: '+$okEndpoints.Count+'. Работу динамиков проверьте кнопкой «Проверить звук».'}
  }
  return [pscustomobject]@{State=$state;NewProblems=@($newProblems);Failing=@($badAfter);Endpoints=$okEndpoints.Count;Text=$text}
}

function Save-GSRollbackSnapshot{
  # Before changing drivers: which driver each target device uses now, plus the
  # list of third-party driver packages, so the change can be rolled back.
  param([object[]]$Targets,[string]$Directory)
  if(-not $Directory){return ''}
  if(!(Test-Path -LiteralPath $Directory)){New-Item -ItemType Directory -Path $Directory -Force|Out-Null}
  $signed=@();try{$signed=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)}catch{}
  $rows=foreach($t in @($Targets)){
    $d=@($signed|Where-Object{[string]$_.DeviceID -eq [string]$t.instanceId})|Select-Object -First 1
    [pscustomobject]@{instanceId=[string]$t.instanceId;name=[string]$t.name;inf=$(if($d){[string]$d.InfName}else{''});version=$(if($d){[string]$d.DriverVersion}else{''});provider=$(if($d){[string]$d.DriverProviderName}else{''});date=$(if($d){[string]$d.DriverDate}else{''})}
  }
  $oem='';try{$oem=(& (Join-Path $env:WINDIR 'System32\pnputil.exe') /enum-drivers 2>&1|Out-String)}catch{}
  $path=Join-Path $Directory ('rollback-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
  [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject ([pscustomobject]@{created=(Get-Date).ToString('o');devices=@($rows);driverStore=$oem}) -Depth 5),[Text.UTF8Encoding]::new($false))
  return $path
}

# ---------------------------------------------------------------- итоги
function Get-GSVendorSupportUrl([string]$Manufacturer,[string]$Model){
  $m=([string]$Manufacturer).ToUpperInvariant()
  $q=[uri]::EscapeDataString(([string]$Model).Trim())
  if($m -match 'LENOVO'){return 'https://pcsupport.lenovo.com/search?query='+$q}
  if($m -match '^HP|HEWLETT'){return 'https://support.hp.com/drivers'}
  if($m -match 'ASUS'){return 'https://www.asus.com/support/'}
  if($m -match 'ACER'){return 'https://www.acer.com/support'}
  if($m -match 'DELL'){return 'https://www.dell.com/support/home'}
  if($m -match 'MICRO-STAR|MSI'){return 'https://www.msi.com/support'}
  if($m -match 'HUAWEI'){return 'https://consumer.huawei.com/support/'}
  return ''
}

function Format-GSOutcomeSummary{
  # Never says "driver not found" when the source could not be asked.
  param([hashtable]$Outcomes,[string[]]$RemainingIds,[string]$WindowsUpdateState='',[string]$VendorUrl='')
  $counts=@{}
  foreach($id in @($RemainingIds)){$o=if($Outcomes.ContainsKey($id)){[string]$Outcomes[$id]}else{'NotFound'};$counts[$o]=1+[int]$counts[$o]}
  $parts=@()
  if($counts['SourceUnavailable']){$parts+=('источник DriverPack сейчас недоступен (отказ сервера) — не проверено устройств: '+$counts['SourceUnavailable'])}
  if($counts['NetworkError']){$parts+=('нет связи с источником — не проверено устройств: '+$counts['NetworkError'])}
  if($counts['Incompatible']){$parts+=('найден пакет, но он не подходит устройству — не установлен: '+$counts['Incompatible'])}
  if($counts['Failed']){$parts+=('установка не удалась: '+$counts['Failed'])}
  if($counts['NotFound']){$parts+=('не найден проверенный пакет: '+$counts['NotFound'])}
  if($WindowsUpdateState -eq 'Disabled'){$parts+='служба Windows Update отключена — резервный источник не использован (Garant Store её не включает автоматически)'}
  if($VendorUrl -and ($counts['SourceUnavailable'] -or $counts['NetworkError'] -or $counts['NotFound'])){$parts+=('официальный сайт производителя: '+$VendorUrl)}
  return ($parts -join '; ')
}
