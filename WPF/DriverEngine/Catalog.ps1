function Get-DrpLookupKeys($Device) {
  $keys=New-Object System.Collections.Generic.List[string]
  foreach($key in @(Get-NormalIds $Device)) {
    $value=([string]$key).Trim().ToUpperInvariant()
    if($value.Length -lt 5 -or $value.Length -gt 300 -or $value -notmatch '^[A-Z0-9_]+\\[^\\]+$'){continue}
    if(!$keys.Contains($value)){$keys.Add($value)}
  }
  return @($keys.ToArray())
}
function Get-DynamicDrpLinks($dev) {
  $keys=@(Get-DrpLookupKeys $dev)
  if($keys.Count -eq 0){return @()}
  $windows='windows-10'
  try {
    $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if([string]$os.Caption -match 'Windows 11'){$windows='windows-11'}
  } catch {
    if([Environment]::OSVersion.Version.Build -ge 22000){$windows='windows-11'}
  }
  $architecture=if([Environment]::Is64BitOperatingSystem){'x64'}else{'x86'}
  $osTarget=$windows+'-'+$architecture
  $cacheRoot=Join-Path $script:StateDir 'drp-metadata'
  if(!(Test-Path -LiteralPath $cacheRoot)){New-Item -ItemType Directory -Path $cacheRoot -Force|Out-Null}
  $regex='https?:(?:\\?/\\?/|//)dl\.driverpack\.io[^"''<>\s]+?\.zip'
  foreach($key in $keys) {
    $encoded=[uri]::EscapeDataString($key)
    $url="https://driverpack.io/en/hwids/$encoded`?os=$osTarget"
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try{$urlHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($url))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $html=Join-Path $cacheRoot ($urlHash+'.html')
    $cacheInfo=Join-Path $cacheRoot ($urlHash+'.json')
    $useCache=$false
    if((Test-Path -LiteralPath $html) -and (Test-Path -LiteralPath $cacheInfo)){
      try{
        $record=Get-Content -LiteralPath $cacheInfo -Raw -Encoding UTF8|ConvertFrom-Json
        $age=((Get-Date).ToUniversalTime()-[datetime]::Parse([string]$record.fetchedUtc).ToUniversalTime()).TotalMinutes
        $useCache=([string]$record.url -ceq $url -and [int]$record.httpStatus -eq 200 -and [string]$record.contentType -match '(?i)^text/html|application/xhtml\+xml' -and $age -ge 0 -and $age -lt 30 -and (Get-Item -LiteralPath $html).Length -gt 100)
      }catch{$useCache=$false}
    }
    if(!$useCache){
      Remove-Item -LiteralPath $html,$cacheInfo -Force -ErrorAction SilentlyContinue
      $tempHtml=$html+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
      if(!(Curl-Fetch $url $tempHtml $true)) {Remove-Item -LiteralPath $tempHtml -Force -ErrorAction SilentlyContinue;Log "DRP-каталог не вернул проверенную HTML-страницу (URL-specific cache, HTTP 200) для ID $key; проверяю следующий совместимый ID.";continue}
      try{
        $bodyText=[System.IO.File]::ReadAllText($tempHtml)
        if($bodyText.Length -lt 100 -or $bodyText -match '(?is)^\s*(\{|\[).*?(error|blocked|captcha)') {throw 'Ответ каталога пустой или похож на страницу ошибки.'}
        Move-Item -LiteralPath $tempHtml -Destination $html -Force
        Save-JsonFile $cacheInfo ([pscustomobject]@{url=$url;httpStatus=200;contentType='text/html';fetchedUtc=(Get-Date).ToUniversalTime().ToString('o')})
      }catch{Remove-Item -LiteralPath $tempHtml,$html,$cacheInfo -Force -ErrorAction SilentlyContinue;Log ('DRP metadata rejected: '+$_.Exception.Message);continue}
    }
    try{$body=[System.IO.File]::ReadAllText($html)}catch{Log ('Не удалось прочитать страницу DRP: '+$_.Exception.Message);continue}
    $found=New-Object System.Collections.Generic.List[string]
    foreach($m in [regex]::Matches($body,$regex,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
      $candidate=[System.Net.WebUtility]::HtmlDecode($m.Value.Replace('\/','/'))
      try {
        $uri=[uri]$candidate
        if($uri.Scheme -eq 'https' -and $uri.Host -eq 'dl.driverpack.io' -and !$found.Contains($candidate)){$found.Add($candidate)}
      } catch {}
    }
    if($found.Count){Log "DRP нашёл $($found.Count) ZIP-пакет(а) по ID $key";return @($found.ToArray())}
  }
  Log 'В каталоге DRP не найден ZIP ни для одного Hardware ID устройства.'
  return @()
}
function Get-Packages($devices,[switch]$KnownOnly) {
  $catalog = @()
  $db=Join-Path $script:Root 'DRP_Known_Links.csv'
  if (Test-Path $db) {$catalog=@(Import-Csv $db)}
  $res=New-Object System.Collections.Generic.List[object]
  foreach ($d in $devices) {
    $keys = @(Get-NormalIds $d)
    # NVIDIA / AMD: только официальный пакет производителя (с фирменной панелью).
    if ($d.kind -eq 'GPU' -and -not $KnownOnly -and @($keys | Where-Object {$_ -match '^PCI\\VEN_(10DE|1002)&DEV_'}).Count) {
      $fetch = { param($u,$r) Get-GSWebText $u $r }
      $vendorPkg = $null
      try {
        if (@($keys | Where-Object {$_ -match '^PCI\\VEN_10DE&DEV_'}).Count) { $vendorPkg = Resolve-GSNvidiaOfficialDriver -Device $d -Fetch $fetch -IsNotebook (Test-GSNotebook) }
        else { $vendorPkg = Resolve-GSAmdOfficialDriver -Device $d -Fetch $fetch }
      } catch { Log ('Официальный видеодрайвер не определён: ' + $_.Exception.Message) }
      if ($null -ne $vendorPkg) {
        if (!(@($res | Where-Object {$_.url -eq $vendorPkg.url}).Count)) { $res.Add($vendorPkg) }
        continue
      }
      Log 'Официальный пакет не найден — используем Windows Update / DRP'
    }
    # Intel Alder Lake UP3 integrated GPU: official Intel executable, no unrelated OEM subsys driver.
    if ($d.kind -eq 'GPU' -and $keys -contains 'PCI\VEN_8086&DEV_46A8') {
      $url='https://downloadmirror.intel.com/929468/gfx_win_101.7092.exe'
      if (!(@($res | Where-Object {$_.url -eq $url}).Count)) {
        $res.Add([pscustomobject]@{url=$url; kind='IntelGPU'; label='Intel 11–14 Gen Graphics 32.0.101.7092'; sha512='35a863fc2ace37e267a1602eb992e54f909dbce6122b7224ad500301bbdb2389c38741800ffc4e389d91e1444bc96c2e26ee4283c97c4a7c7060064724385b9d'; expectedBytes=780899944; ids=@($keys | Where-Object {$_ -match '^PCI\\VEN_8086&DEV_46A8'})})
      }
      continue
    }
    # Intel Jasper Lake UHD (including Lenovo subsystem 17AA): current WHQL DCH package.
    if ($d.kind -eq 'GPU' -and $keys -contains 'PCI\VEN_8086&DEV_4E55') {
      $url='https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe'
      if (!(@($res | Where-Object {$_.url -eq $url}).Count)) {
        $res.Add([pscustomobject]@{url=$url; kind='IntelGPU'; label='Intel 7th–10th Gen / Jasper Lake Graphics 31.0.101.2145'; sha512='d30369a17f66a787d477fe77787d934a1e74581f27cb19ba1608df22e76c8dce68b589db327456527ae9228d8788663ce005467df84c722c03f59a2e9297c2d5'; expectedBytes=0; ids=@($keys | Where-Object {$_ -match '^PCI\\VEN_8086&DEV_4E55'})})
      }
      continue
    }
    $urls=New-Object System.Collections.Generic.List[string]
    foreach($row in $catalog) {
      if ($keys -contains ([string]$row.HardwareID).ToUpperInvariant()) {
        if (!$urls.Contains($row.ZipURL)) {$urls.Add($row.ZipURL)}
      }
    }
    # Resolve every hardware-ID form through the online DRP catalog when no direct package is indexed locally.
    if ($urls.Count -eq 0 -and -not $KnownOnly) {
      foreach ($link in @(Get-DynamicDrpLinks $d)) {if (!$urls.Contains($link)){$urls.Add($link)}}
    }
    foreach ($url in $urls) {
      $existingPackage=@($res | Where-Object {$_.url -eq $url} | Select-Object -First 1)
      if ($existingPackage.Count -eq 0) {
        $res.Add([pscustomobject]@{url=$url;kind='Zip';label=([uri]$url).Segments[-1];sha512='';expectedBytes=0;ids=@($keys)})
      } else {
        # One DRP archive commonly covers several selected devices. Keep every
        # matched ID so coverage reporting does not claim those devices have no source.
        $existingPackage[0].ids=@(@($existingPackage[0].ids)+@($keys)|Select-Object -Unique)
      }
    }
    if ($urls.Count -eq 0) {Log "DRP не предложил прямой ZIP для $($d.hwid)."}
  }
  return @($res.ToArray())
}
function Get-PackageTargets($Package,$Devices,[string[]]$AllowedInstanceIds=@()) {
  $matched=New-Object System.Collections.Generic.List[object]
  $packageIds=@($Package.ids|ForEach-Object{[string]$_})
  foreach($device in @($Devices)){
    $instanceId=[string]$device.instanceId
    if($AllowedInstanceIds.Count -gt 0 -and $AllowedInstanceIds -notcontains $instanceId){continue}
    $hasMatch=$false
    foreach($id in @(Get-NormalIds $device)){
      if($packageIds -contains [string]$id){$hasMatch=$true;break}
    }
    if($hasMatch){$matched.Add($device)}
  }
  return @($matched.ToArray())
}

function Test-InfMatchesTargets([string]$Path,$Targets) {
  if (!(Test-Path -LiteralPath $Path)) {return $false}
  try {
    $bytes=[System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {$encoding=[System.Text.Encoding]::Unicode}
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {$encoding=[System.Text.Encoding]::BigEndianUnicode}
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {$encoding=[System.Text.Encoding]::UTF8}
    else {$encoding=[System.Text.Encoding]::Default}
    $content=$encoding.GetString($bytes).ToUpperInvariant()
  } catch {return $false}
  foreach ($device in @($Targets)) {
    foreach ($key in @(Get-NormalIds $device)) {
      if ($key.Length -ge 10 -and $content.Contains([string]$key)) {return $true}
    }
  }
  return $false
}
