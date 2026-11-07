$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:DataRoot = if ([string]::IsNullOrWhiteSpace($env:GARANT_PO_DATA_ROOT)) { $script:Root } else { [System.IO.Path]::GetFullPath($env:GARANT_PO_DATA_ROOT) }
$script:StateDir = Join-Path $script:DataRoot 'State'
$script:LogDir = Join-Path $script:DataRoot 'Logs'
$script:DownloadDir = if ([string]::IsNullOrWhiteSpace($env:GARANT_PO_DOWNLOAD_DIR)) { Join-Path $script:DataRoot 'Downloads' } else { [System.IO.Path]::GetFullPath($env:GARANT_PO_DOWNLOAD_DIR) }
$script:CacheDir = Join-Path $script:DataRoot 'Cache'
$script:DriverDir = if ([string]::IsNullOrWhiteSpace($env:GARANT_PO_DRIVER_DIR)) { Join-Path $script:DataRoot 'Drivers' } else { [System.IO.Path]::GetFullPath($env:GARANT_PO_DRIVER_DIR) }
$script:LibraryDir = if ([string]::IsNullOrWhiteSpace($env:GARANT_PO_LIBRARY_DIR)) { Join-Path $script:DataRoot 'Libraries' } else { [System.IO.Path]::GetFullPath($env:GARANT_PO_LIBRARY_DIR) }
# Files that the elevated worker installs or executes live only under DataRoot,
# which the WPF client starts as an administrators-only folder. DownloadDir,
# DriverDir and LibraryDir point at the user's Downloads and receive copies.
$script:EngineDownloadDir = Join-Path $script:DataRoot 'Downloads'
$script:EngineLibraryDir = Join-Path $script:DataRoot 'Libraries'
$script:StagingDir = Join-Path $script:DataRoot 'Staging'
foreach ($d in @($script:StateDir,$script:LogDir,$script:DownloadDir,$script:CacheDir,$script:DriverDir,$script:LibraryDir,$script:EngineDownloadDir,$script:EngineLibraryDir,$script:StagingDir)) { if (!(Test-Path $d)) {New-Item -ItemType Directory -Path $d -Force | Out-Null} }
. (Join-Path $script:Root 'SecureRoot.ps1')
$script:StatusFile = Join-Path $script:StateDir 'status.json'
$script:DeviceFile = Join-Path $script:StateDir 'devices.json'
$script:LatestLog = Join-Path $script:LogDir 'Garant-PO-Latest.log'
function Save-JsonFile([string]$path, $value) {
  $json = ConvertTo-Json -InputObject $value -Depth 9 -Compress
  $tmp = $path + '.' + $PID + '.tmp'
  [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Load-JsonFile([string]$path, $fallback) {
  if (!(Test-Path $path)) {return $fallback}
  try {return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)} catch {return $fallback}
}
function Get-RemainingSelectedProblemDevices($Inventory,[string[]]$InstanceIds) {
  # Inventory rows document a working installed driver; only actionable PnP
  # problem states count as unresolved after an install/rescan.
  $problemKinds=@('Missing','Issue','GPU')
  return @($Inventory|Where-Object{
    $id=[string]$_.instanceId
    $kind=[string]$_.kind
    $InstanceIds -contains $id -and $problemKinds -contains $kind
  })
}
function Test-GSDownloadResponse([int]$ExitCode,[string]$HttpStatus,[string]$ContentType,[long]$Bytes,[bool]$IsHtml,[long]$ExpectedBytes=0,[long]$ExistingBytes=0,[string]$ContentRange='') {
  if($ExitCode -ne 0 -or $Bytes -lt 100){return $false}
  if($IsHtml){return ($HttpStatus -eq '200' -and $ContentType -match '(?i)^(text/html|application/xhtml\+xml)')}
  if($HttpStatus -notin @('200','206') -or $ContentType -match '(?i)^(text/html|application/xhtml\+xml|application/json)'){return $false}
  if($HttpStatus -eq '206' -and ($ExistingBytes -le 0 -or $ContentRange -notmatch ('(?i)^bytes\s+'+$ExistingBytes+'-\d+/\d+'))){return $false}
  if($ExpectedBytes -gt 0 -and $Bytes -ne $ExpectedBytes){return $false}
  return $true
}
. (Join-Path $PSScriptRoot 'SystemProfile.ps1')
function Save-GSDeviceSession($Profile,[int]$ProblemCount,[int]$InventoryCount,[int]$UpdateCount,[int]$LibraryCount) {
  $record=[pscustomobject]@{capturedUtc=$Profile.capturedUtc;localId=$Profile.localId;windows=$Profile.windows;build=$Profile.build;problemCount=$ProblemCount;installedDriverCount=$InventoryCount;confirmedUpdateCount=$UpdateCount;libraryCount=$LibraryCount;rebootRequired=$false}
  $deviceRoot=Join-Path (Join-Path $script:DataRoot 'Devices') ([string]$Profile.localId)
  if(!(Test-Path -LiteralPath $deviceRoot)){New-Item -ItemType Directory -Path $deviceRoot -Force|Out-Null}
  $deviceHistoryPath=Join-Path $deviceRoot 'sessions.json'
  $deviceHistory=@(Load-JsonFile $deviceHistoryPath @())
  $deviceHistory=@($record)+@($deviceHistory|Select-Object -First 49)
  Save-JsonFile $deviceHistoryPath $deviceHistory
  $historyPath=Join-Path $script:StateDir 'device-history.json'
  $history=@(Load-JsonFile $historyPath @())
  $history=@($record)+@($history|Select-Object -First 49)
  Save-JsonFile $historyPath $history
  Save-JsonFile (Join-Path $script:StateDir 'system-profile.json') $Profile
  Save-JsonFile (Join-Path $script:StateDir 'device-session.json') $record
  return $record
}
function Get-TargetDevices {
  $items = New-Object System.Collections.Generic.List[object]
  try { $all = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop) } catch {throw "Device scan failed: $($_.Exception.Message)"}
  foreach ($d in $all) {
    $code = [int]$d.ConfigManagerErrorCode
    $isGpu = ($d.Name -match '(?i)Microsoft Basic Display|Базовый видеоадаптер|Стандартный VGA|Standard VGA Graphics|Video Controller \(VGA Compatible\)')
    if ($code -eq 0 -and !$isGpu) {continue}
    if ([string]::IsNullOrWhiteSpace($d.PNPDeviceID)) {continue}
    $ids = @($d.HardwareID | Where-Object {![string]::IsNullOrWhiteSpace([string]$_)} | ForEach-Object {[string]$_})
    if ($ids.Count -eq 0) {
      try { $pn = Get-PnpDeviceProperty -InstanceId $d.PNPDeviceID -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop; $ids = @($pn.Data) } catch {}
    }
    $key = if ($ids.Count) { [string]$ids[0] } else { [string]$d.PNPDeviceID }
    $kind = if ($isGpu) {'GPU'} elseif ($code -eq 28) {'Missing'} else {'Issue'}
    $description = if ([string]::IsNullOrWhiteSpace($d.Name)) {'Неизвестное устройство'} else {[string]$d.Name}
    $items.Add([pscustomobject]@{instanceId=[string]$d.PNPDeviceID;name=$description; kind=$kind; code=$code; reason=$(if($code -eq 28){'Драйвер не установлен'}elseif($isGpu){'Используется базовый видеодрайвер'}else{'Код состояния устройства: '+$code}); hardwareIds=@($ids); hwid=$key; category=[string]$d.PNPClass; vendor=$(if($key -match 'VEN_([0-9A-Fa-f]{4})'){$Matches[1].ToUpper()}else{''})})
  }
  return @($items.ToArray() | Sort-Object @{Expression={if($_.kind -eq 'GPU'){0}else{1}}},name)
}
function Get-InstalledDriverInventory($ProblemDevices=@()) {
  $excluded=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach($device in @($ProblemDevices)){if($device.instanceId){[void]$excluded.Add([string]$device.instanceId)}}
  $pnpById=@{}
  foreach($pnp in @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)){
    if($pnp.PNPDeviceID){$pnpById[[string]$pnp.PNPDeviceID]=$pnp}
  }
  $signedById=@{}
  try{
    foreach($driver in @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop)){
      if($driver.DeviceID -and -not $signedById.ContainsKey([string]$driver.DeviceID)){$signedById[[string]$driver.DeviceID]=$driver}
    }
  }catch{}
  $rows=New-Object System.Collections.Generic.List[object]
  foreach($deviceId in @($signedById.Keys)){
    if($excluded.Contains([string]$deviceId)){continue}
    $driver=$signedById[$deviceId]
    $pnp=if($pnpById.ContainsKey([string]$deviceId)){$pnpById[[string]$deviceId]}else{$null}
    $hardware=@()
    if($null -ne $pnp){$hardware=@($pnp.HardwareID|Where-Object{![string]::IsNullOrWhiteSpace([string]$_)}|ForEach-Object{[string]$_})}
    if($hardware.Count -eq 0){$hardware=@([string]$deviceId)}
    $compatible=@()
    if(Get-Command Get-PnpDeviceProperty -ErrorAction SilentlyContinue){
      try{$property=Get-PnpDeviceProperty -InstanceId ([string]$deviceId) -KeyName 'DEVPKEY_Device_CompatibleIds' -ErrorAction Stop;$compatible=@($property.Data|Where-Object{![string]::IsNullOrWhiteSpace([string]$_)}|ForEach-Object{[string]$_})}catch{}
    }
    $deviceName=if($pnp -and $pnp.Name){[string]$pnp.Name}else{[string]$driver.DeviceName}
    if([string]::IsNullOrWhiteSpace($deviceName)){$deviceName=[string]$deviceId}
    $date='';try{$parsed=[datetime]$driver.DriverDate;if($parsed -gt [datetime]::MinValue){$date=$parsed.ToString('yyyy-MM-dd')}}catch{}
    $ids=@($hardware)+@($compatible)
    $rows.Add([pscustomobject]@{
      instanceId=[string]$deviceId;name=$deviceName;kind='Inventory';code=0
      reason=('Версия '+[string]$driver.DriverVersion+' · '+[string]$driver.DriverProviderName+$(if($date){' · '+$date})+' · актуальность не подтверждена независимым источником')
      hardwareIds=@($hardware);compatibleIds=@($compatible);hwid=$(if($hardware.Count){[string]$hardware[0]}else{[string]$deviceId})
      category=$(if($pnp){[string]$pnp.PNPClass}else{''});vendor='';currentDriverVersion=[string]$driver.DriverVersion
      driverDate=$date;driverProvider=[string]$driver.DriverProviderName;driverManufacturer=[string]$driver.Manufacturer
      infName=[string]$driver.InfName;isSigned=[bool]$driver.IsSigned;actuality='Unknown';canSelect=$false
    })
  }
  return @($rows.ToArray()|Sort-Object name)
}
function Get-GSWebView2State {
  $clientId='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
  $registries=@('HKLM:\SOFTWARE\WOW6432Node','HKLM:\SOFTWARE','HKCU:\SOFTWARE')
  $folders=@([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),[Environment]::GetFolderPath('ProgramFiles'),[Environment]::GetFolderPath('LocalApplicationData'))|Where-Object{$_}
  $paths=@($folders|ForEach-Object{Join-Path $_ 'Microsoft\EdgeWebView\Application'}|Select-Object -Unique)
  $versions=New-Object System.Collections.Generic.List[version]
  $registered=$false;$binary=$false
  foreach($path in $paths){
    if(Test-Path -LiteralPath $path){
      foreach($dir in @(Get-ChildItem -LiteralPath $path -Directory -ErrorAction SilentlyContinue)){
        if(Test-Path -LiteralPath (Join-Path $dir.FullName 'msedgewebview2.exe') -PathType Leaf){$binary=$true;break}
      }
    }
  }
  foreach($root in $registries){
    $reg=Get-ItemProperty -LiteralPath "$root\Microsoft\EdgeUpdate\Clients\$clientId" -ErrorAction SilentlyContinue
    if(-not $reg){continue}
    $registered=$true;$v=[string]$reg.pv
    if($v -notmatch '^\d+\.\d+\.\d+\.\d+$'){continue}
    if([version]$v -le [version]'0.0.0.0'){continue}
    foreach($path in $paths){
      if(Test-Path -LiteralPath (Join-Path $path ($v+'\msedgewebview2.exe')) -PathType Leaf){$versions.Add([version]$v);break}
    }
  }
  $v=''
  if($versions.Count){$v=($versions|Sort-Object -Descending|Select-Object -First 1).ToString()}
  $compatible=([Environment]::OSVersion.Version.Major -ge 10 -and [Environment]::OSVersion.Version.Build -ge 17763)
  return [pscustomobject]@{Installed=([bool]$v);Version=$v;Supported=$compatible;Unverified=((-not $v) -and ($registered -or $binary));RegistrationSeen=$registered;BinarySeen=$binary}
}
function Get-GSInstalledUninstallEntry([string]$Pattern) {
  foreach($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){
    try{if(@(Get-ItemProperty -Path $hive -ErrorAction Stop|Where-Object{$displayName=$_.PSObject.Properties['DisplayName'];$displayName -and [string]$displayName.Value -match $Pattern}).Count){return $true}}catch{}
  }
  return $false
}
function Get-GSDesktopRuntimeVersions {
  # Returns "8.0.11 x64"-style entries of installed .NET Desktop Runtimes.
  $result=@(foreach($arch in @('x64','x86','arm64')){
    foreach($root in @('HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node')){
      $key="$root\dotnet\Setup\InstalledVersions\$arch\sharedfx\Microsoft.WindowsDesktop.App"
      $registry=Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
      if($registry){foreach($version in $registry.GetValueNames()){if($version -match '^\d+\.\d+\.\d+$'){"$version $arch"}}}
    }
  }) | Select-Object -Unique
  return @($result|Where-Object{$_})
}
function Get-SystemLibrarySuggestions {
  # Every row that can be selected has a verified installer in Libraries.ps1.
  # Visual C++ and DirectX stay selectable when present: reinstalling them is the
  # standard repair for "MSVCP140.dll / d3dx9_43.dll not found" errors.
  $optional='Можно установить дополнительно'
  $items=New-Object System.Collections.Generic.List[object]
  foreach($arch in @('x64','x86')){
    $key=if($arch -eq 'x64'){'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'}else{'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'}
    $runtime=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    $installed=($null -ne $runtime -and $null -ne $runtime.PSObject.Properties['Installed'] -and [int]$runtime.Installed -eq 1)
    $id='vcredist-'+$arch
    $items.Add([pscustomobject]@{instanceId=('LIBRARY|'+$id);name=('Microsoft Visual C++ 2015–2022, '+$arch);kind='Library';libraryId=$id;libraryStatus=$(if($installed){'Установлено'}else{$optional});hwid='Microsoft · официальный распространяемый пакет';reason=$(if($installed){'Пакет установлен. Отметьте, чтобы восстановить его при ошибках MSVCP140.dll / VCRUNTIME140.dll.'}else{'Не обнаружен. Нужен большинству программ и игр.'});downloadable=$true;canSelect=$true;selected=$false})
  }
  $directXFiles=@((Join-Path $env:WINDIR 'System32\d3dx9_43.dll'),(Join-Path $env:WINDIR 'SysWOW64\d3dx9_43.dll'),(Join-Path $env:WINDIR 'System32\xinput1_3.dll'),(Join-Path $env:WINDIR 'SysWOW64\xinput1_3.dll'))
  $dxMissing=@($directXFiles|Where-Object{-not (Test-Path -LiteralPath $_)})
  $items.Add([pscustomobject]@{instanceId='LIBRARY|directx-legacy';name='DirectX Legacy Runtime';kind='Library';libraryId='directx-legacy';libraryStatus=$(if($dxMissing.Count){$optional}else{'Установлено'});hwid='Microsoft · DirectX End-User Runtime';reason=$(if($dxMissing.Count){'Некоторые legacy-файлы не найдены; нужны старым играм и программам.'}else{'Файлы найдены. Отметьте, чтобы переустановить при ошибках d3dx9 / xinput.'});downloadable=$true;canSelect=$true;selected=$false})
  $netFx=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue
  $netFxInstalled=($null -ne $netFx -and $null -ne $netFx.PSObject.Properties['Install'] -and [int]$netFx.Install -eq 1)
  $items.Add([pscustomobject]@{instanceId='LIBRARY|netfx3';name='.NET Framework 3.5';kind='Library';libraryId=$(if(-not $netFxInstalled){'netfx3'}else{''});libraryStatus=$(if($netFxInstalled){'Установлено'}else{$optional});hwid='Компонент Windows';reason=$(if($netFxInstalled){'Функция Windows включена.'}else{'Компонент Windows для старых программ; включается средствами Windows.'});downloadable=$false;canSelect=(-not $netFxInstalled);selected=$false})
  $webView=Get-GSWebView2State
  $available=(-not $webView.Installed -and -not $webView.Unverified -and $webView.Supported)
  $status=if($webView.Installed){'Установлено'}elseif($webView.Unverified){'Невозможно определить'}elseif($webView.Supported){$optional}else{'Не поддерживается этой системой'}
  $reason=if($webView.Installed){'Подтверждена версия '+$webView.Version+' (реестр и исполняемый файл). Повторная установка не требуется.'}elseif($webView.Unverified){'Найдены неполные следы WebView2; установка отключена до уточнения состояния.'}elseif($webView.Supported){'WebView2 отсутствует; установка добровольная, требуется интернет.'}else{'Эта Windows не поддерживается.'}
  $items.Add([pscustomobject]@{instanceId='LIBRARY|webview2';name='Microsoft Edge WebView2 Runtime';kind='Library';libraryId=$(if($available){'webview2'}else{''});libraryStatus=$status;hwid='Microsoft · Evergreen Runtime';reason=$reason;downloadable=$false;canSelect=$available;selected=$false})
  $desktopRuntimes=@(Get-GSDesktopRuntimeVersions)
  $nativeArch=if([Environment]::Is64BitOperatingSystem){'x64'}else{'x86'}
  foreach($major in @(@{id='dotnet-desktop';version='8';label='.NET Desktop Runtime 8 (LTS)'},@{id='dotnet-desktop-10';version='10';label='.NET Desktop Runtime 10 (LTS)'})){
    $found=@($desktopRuntimes|Where-Object{$_ -match ('^'+$major.version+'\.\d+\.\d+ '+$nativeArch+'$')})
    $isInstalled=($found.Count -gt 0)
    $items.Add([pscustomobject]@{instanceId=('LIBRARY|'+$major.id);name=$major.label;kind='Library';libraryId=$(if($isInstalled){''}else{$major.id});libraryStatus=$(if($isInstalled){'Установлено'}else{$optional});hwid=('Microsoft · '+$nativeArch);reason=$(if($isInstalled){'Обнаружены версии: '+($found -join ', ')}else{'Не обнаружен. Нужен программам на .NET '+$major.version+' (WPF / WinForms).'});downloadable=$true;canSelect=(-not $isInstalled);selected=$false})
  }
  foreach($runtime in @(@{name='NVIDIA PhysX';pattern='(?i)^NVIDIA PhysX(?! Legacy)';id='physx';hint='Нужен играм с физикой NVIDIA PhysX.'},@{name='NVIDIA PhysX Legacy';pattern='(?i)^NVIDIA PhysX Legacy';id='physx-legacy';hint='Нужен старым играм (примерно до 2010 года) с PhysX.'},@{name='OpenAL';pattern='(?i)^OpenAL';id='openal';hint='Звуковая библиотека для старых игр.'})){
    $found=Get-GSInstalledUninstallEntry $runtime.pattern
    $items.Add([pscustomobject]@{instanceId=('LIBRARY|'+$runtime.id);name=$runtime.name;kind='Library';libraryId=$(if($found){''}else{$runtime.id});libraryStatus=$(if($found){'Установлено'}else{$optional});hwid='Официальный пакет WinGet';reason=$(if($found){'Компонент найден в списке установленных программ.'}else{$runtime.hint+' Устанавливается добровольно.'});downloadable=$true;canSelect=(-not $found);selected=$false})
  }
  $appRuntimeCount=0
  if(Get-Command Get-AppxPackage -ErrorAction SilentlyContinue){try{$appRuntimeCount=@(Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsAppRuntime.1.8*' -ErrorAction Stop).Count}catch{}}
  $items.Add([pscustomobject]@{instanceId='LIBRARY|windows-app-runtime';name='Microsoft Windows App Runtime 1.8';kind='Library';libraryId=$(if($appRuntimeCount){''}else{'windows-app-runtime'});libraryStatus=$(if($appRuntimeCount){'Установлено'}else{$optional});hwid='Microsoft · AppX framework packages';reason=$(if($appRuntimeCount){'Найдены framework packages: '+$appRuntimeCount}else{'Нужен современным приложениям на WinUI 3. Устанавливается добровольно.'});downloadable=$false;canSelect=($appRuntimeCount -eq 0);selected=$false})
  return @($items.ToArray())
}
function Get-NormalIds($dev) {
  $keys = New-Object System.Collections.Generic.List[string]
  foreach ($id in @($dev.hardwareIds)) {
    if (!$id) {continue}
    $id = ([string]$id).ToUpperInvariant()
    $keys.Add($id)
    if ($id -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') {$keys.Add($Matches[1])}
    if ($id -match '^(USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') {$keys.Add($Matches[1])}
    if ($id -match '^ACPI\\(?:VEN_([^&]+)&DEV_([^&]+)|([A-Z0-9]{3,4})([0-9A-F]{4}))') {
      if ($Matches[1]) {$keys.Add("ACPI\$($Matches[1])$($Matches[2])");$keys.Add("ACPI\VEN_$($Matches[1])&DEV_$($Matches[2])")}
      elseif ($Matches[3]) {$keys.Add("ACPI\$($Matches[3])$($Matches[4])");$keys.Add("ACPI\VEN_$($Matches[3])&DEV_$($Matches[4])")}
    }
  }
  return @($keys | Select-Object -Unique)
}
function Get-GSDriverSourceUrl($Device) {
  $ids=@(Get-NormalIds $Device)
  if([string]$Device.kind -eq 'GPU'){
    if($ids -contains 'PCI\VEN_8086&DEV_4E55'){return 'https://www.intel.com/content/www/us/en/download/776137/intel-7th-10th-gen-processor-graphics-windows.html'}
    if($ids | Where-Object {$_ -match '^PCI\\VEN_10DE&DEV_'}){return 'https://www.nvidia.com/Download/index.aspx?lang=ru-ru'}
    if($ids | Where-Object {$_ -match '^PCI\\VEN_1002&DEV_'}){return 'https://www.amd.com/en/support/download/drivers.html'}
    if($ids | Where-Object {$_ -match '^PCI\\VEN_8086&DEV_'}){return 'https://www.intel.com/content/www/us/en/support/detect.html'}
  }
  $id=$ids | Where-Object {$_ -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_|USB\\VID_|ACPI\\)'} | Select-Object -First 1
  if(-not $id){return 'https://driverpack.io/en/hwids/'}
  return 'https://driverpack.io/en/hwids/'+[uri]::EscapeDataString($id)
}
function Get-ProxyUrl {
  $p = Join-Path $script:Root 'Proxy.txt'
  if (Test-Path $p) {
    $one = Get-Content $p | Where-Object {$_ -match '^\s*(https?://|socks5h?://)'} | Select-Object -First 1
    if ($one) {return ([string]$one).Trim()}
  }
  foreach ($v in @('HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy')) {
    $one = [Environment]::GetEnvironmentVariable($v)
    if ($one -match '^https?://|^socks5h?://') {return $one.Trim()}
  }
  try {
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($reg.ProxyEnable -eq 1 -and $reg.ProxyServer) {
      $x=[string]$reg.ProxyServer
      if ($x -match 'https=([^;]+)') {$x=$Matches[1]} elseif ($x -match 'http=([^;]+)') {$x=$Matches[1]}
      if ($x -match '^\w+://') {return $x}
      if ($x -match '^[\w.-]+:\d+$') {return 'http://'+$x}
    }
  } catch {}
  return ''
}


