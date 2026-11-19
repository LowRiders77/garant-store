# Официальные видеодрайверы с сайтов производителей.
#
# Зачем: драйвер из Windows Update / DRP ставит только сам драйвер. Фирменная
# панель (пункт «Панель управления NVIDIA» / «AMD Software» в меню рабочего
# стола) приходит с официальным пакетом производителя.
#
# NVIDIA: таблица GPU берётся онлайн из NVIDIA lookupValueSearch (TypeID 2/3),
#   ссылка на актуальный DCH-драйвер — из AjaxDriverService (тот же сервис, что
#   у nvidia.com). Файл качается только с *.nvidia.com и проверяется подписью
#   NVIDIA Corporation. Установка: -s -noreboot -noeula.
# AMD: официальный установщик Auto-Detect («minimalsetup») с amd.com; он сам
#   определяет видеокарту. Установщик AMD интерактивный — запускается окно AMD.
# Все функции разбора — чистые (без сети), сеть передаётся через $Fetch.

$script:GSNotebookChassis = @(8,9,10,11,12,14,18,21,30,31,32)

function ConvertFrom-GSNvidiaLookupXml {
  param([AllowEmptyString()][string]$Xml)
  $result = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($Xml)) { return @() }
  try { [xml]$doc = $Xml } catch { return @() }
  foreach ($node in @($doc.SelectNodes('//LookupValue'))) {
    $name = [string]$node.SelectSingleNode('Name').InnerText
    $value = [string]$node.SelectSingleNode('Value').InnerText
    $parent = [string]$node.GetAttribute('ParentID')
    if ($name -and $value) { [void]$result.Add([pscustomobject]@{ Name = $name; Value = $value; ParentID = $parent }) }
  }
  return @($result.ToArray())
}

function ConvertTo-GSNvidiaLookupName {
  # "NVIDIA GeForce RTX 3060 Ti (LHR)" / "GeForce GTX 1060 6GB" -> "geforce rtx 3060 ti" / "geforce gtx 1060"
  param([AllowEmptyString()][string]$Name)
  $n = ([string]$Name) -replace '(?i)\bNVIDIA\b', ''
  $n = ($n -split '/')[0]
  $n = $n -replace '\s*\([A-Za-z]+\)\s*$', '' -replace '(?i)\s+\d+\s*GB\b.*$', ''
  return (($n -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

function Get-GSNvidiaProductMap {
  param([object[]]$Series, [object[]]$Products)
  $notebookSeries = @{}
  foreach ($s in @($Series)) { if ([string]$s.Name -match '(?i)\(Notebook|Quadro Blade') { $notebookSeries[[string]$s.Value] = $true } }
  $map = @{ desktop = @{}; notebook = @{} }
  foreach ($p in @($Products)) {
    $kind = if ($notebookSeries.ContainsKey([string]$p.ParentID)) { 'notebook' } else { 'desktop' }
    $key = ConvertTo-GSNvidiaLookupName ([string]$p.Name)
    if ($key -and -not $map[$kind].ContainsKey($key)) { $map[$kind][$key] = [string]$p.Value }
  }
  return $map
}

function Get-GSNvidiaNameFromPciIds {
  # pci.ids: vendor line "10de  NVIDIA Corporation", device lines "\t2d05  GB206 [GeForce RTX 5060]".
  param([AllowEmptyString()][string]$PciIds, [Parameter(Mandatory=$true)][string]$DeviceId)
  if ([string]::IsNullOrWhiteSpace($PciIds)) { return '' }
  $inVendor = $false
  $dev = $DeviceId.ToLowerInvariant()
  foreach ($line in ($PciIds -split "`n")) {
    if ($line -match '^10de\s') { $inVendor = $true; continue }
    if ($inVendor -and $line -match '^[0-9a-f]{4}\s') { break }
    if ($inVendor -and $line -match ('^\t' + $dev + '\s+(.+?)\s*$')) {
      $text = $Matches[1]
      if ($text -match '\[(.+)\]') { return $Matches[1] }
      return $text
    }
  }
  return ''
}

function Find-GSNvidiaPfid {
  param([Parameter(Mandatory=$true)][hashtable]$Map, [Parameter(Mandatory=$true)][string]$GpuName, [bool]$IsNotebook)
  $base = ConvertTo-GSNvidiaLookupName $GpuName
  if (-not $base) { return '' }
  $variants = New-Object System.Collections.Generic.List[string]
  [void]$variants.Add($base)
  # pci.ids says "Mobile" / "Max-Q", NVIDIA says "Laptop GPU" (RTX 30+) or just the name.
  $plain = (($base -replace '\b(mobile|max-q|with max-q design)\b', '') -replace '\s+', ' ').Trim()
  foreach ($v in @($plain, ($plain + ' laptop gpu'))) { if ($v -and -not $variants.Contains($v)) { [void]$variants.Add($v) } }
  $order = if ($IsNotebook) { @('notebook','desktop') } else { @('desktop','notebook') }
  foreach ($kind in $order) {
    foreach ($v in $variants) { if ($Map[$kind].ContainsKey($v)) { return [string]$Map[$kind][$v] } }
  }
  return ''
}

function Get-GSNvidiaDownloadInfo {
  param([AllowEmptyString()][string]$Json)
  if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
  try { $payload = $Json | ConvertFrom-Json } catch { return $null }
  if ($null -eq $payload -or [string]$payload.Success -ne '1') { return $null }
  $first = @($payload.IDS)[0]
  if ($null -eq $first -or $null -eq $first.downloadInfo) { return $null }
  $info = $first.downloadInfo
  $url = [System.Net.WebUtility]::UrlDecode([string]$info.DownloadURL)
  try { $uri = [uri]$url } catch { return $null }
  if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)nvidia\.com$' -or $uri.AbsolutePath -notmatch '(?i)\.exe$') { return $null }
  return [pscustomobject]@{ Url = $url; Version = [string]$info.Version; Name = [System.Net.WebUtility]::UrlDecode([string]$info.Name) }
}

function Find-GSAmdInstallerUrl {
  param([AllowEmptyString()][string]$Html)
  if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
  $m = [regex]::Match($Html, 'https://drivers\.amd\.com/drivers/installer/[^"''\s<>]+?minimalsetup[^"''\s<>]*?\.exe', 'IgnoreCase')
  if ($m.Success) { return $m.Value }
  return ''
}

function Test-GSNotebook {
  try { if (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0) { return $true } } catch {}
  try {
    foreach ($e in @(Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop)) {
      foreach ($t in @($e.ChassisTypes)) { if ([int]$t -in $script:GSNotebookChassis) { return $true } }
    }
  } catch {}
  return $false
}

function Resolve-GSNvidiaOfficialDriver {
  # $Fetch: scriptblock (url, referer) -> text or $null.
  param([Parameter(Mandatory=$true)]$Device, [Parameter(Mandatory=$true)][scriptblock]$Fetch, [bool]$IsNotebook = $false)
  $ids = @(Get-NormalIds $Device)
  $pci = @($ids | Where-Object { $_ -match '^PCI\\VEN_10DE&DEV_([0-9A-F]{4})' } | Select-Object -First 1)
  if (-not $pci.Count) { return $null }
  $devId = ([regex]::Match([string]$pci[0], 'DEV_([0-9A-F]{4})')).Groups[1].Value
  $name = [string]$Device.name
  if (-not $name -or $name -notmatch '(?i)GeForce|RTX|GTX|Quadro|NVIDIA') {
    $pciIds = & $Fetch 'https://raw.githubusercontent.com/pciutils/pciids/master/pci.ids' ''
    $name = Get-GSNvidiaNameFromPciIds $pciIds $devId
  }
  if (-not $name) { Log ('NVIDIA: модель видеокарты не определена (DEV_' + $devId + ')'); return $null }
  $series = @(ConvertFrom-GSNvidiaLookupXml (& $Fetch 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=2' 'https://www.nvidia.com/'))
  $products = @(ConvertFrom-GSNvidiaLookupXml (& $Fetch 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3' 'https://www.nvidia.com/'))
  if (-not $products.Count) { Log 'NVIDIA: справочник видеокарт nvidia.com недоступен'; return $null }
  $map = Get-GSNvidiaProductMap -Series $series -Products $products
  $pfid = Find-GSNvidiaPfid -Map $map -GpuName $name -IsNotebook $IsNotebook
  if (-not $pfid) { Log ('NVIDIA: «' + $name + '» не найдена в справочнике nvidia.com'); return $null }
  # osID 57 = Windows 10/11 64-bit (NVIDIA uses the same package), dch=1.
  $json = & $Fetch ('https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&pfid=' + $pfid + '&osID=57&dch=1&numberOfResults=1') 'https://www.nvidia.com/'
  $info = Get-GSNvidiaDownloadInfo $json
  if ($null -eq $info) { Log ('NVIDIA: сервис драйверов не вернул ссылку для «' + $name + '»'); return $null }
  Log ('NVIDIA: ' + $name + ' → официальный драйвер ' + $info.Version)
  return [pscustomobject]@{ url = $info.Url; kind = 'NvidiaGPU'; label = ('NVIDIA ' + $name + ' — драйвер ' + $info.Version); version = $info.Version; sha512 = ''; expectedBytes = 0; referer = 'https://www.nvidia.com/'; ids = @($ids | Where-Object { $_ -match '^PCI\\VEN_10DE&DEV_' }) }
}

function Resolve-GSAmdOfficialDriver {
  param([Parameter(Mandatory=$true)]$Device, [Parameter(Mandatory=$true)][scriptblock]$Fetch)
  $ids = @(Get-NormalIds $Device)
  $html = & $Fetch 'https://www.amd.com/en/support/download/drivers.html' 'https://www.amd.com/'
  $url = Find-GSAmdInstallerUrl $html
  if (-not $url) { Log 'AMD: ссылка на официальный установщик не найдена на amd.com'; return $null }
  Log ('AMD: официальный установщик Auto-Detect: ' + $url)
  return [pscustomobject]@{ url = $url; kind = 'AmdGPU'; label = 'AMD Software: Adrenalin Edition (Auto-Detect)'; version = ''; sha512 = ''; expectedBytes = 0; referer = 'https://www.amd.com/'; ids = @($ids | Where-Object { $_ -match '^PCI\\VEN_1002&DEV_' }) }
}

function Get-GSVendorPanelState {
  # Фирменная панель видеокарты: есть ли она у текущего пользователя.
  param([Parameter(Mandatory=$true)][ValidateSet('10DE','1002')][string]$Vendor)
  $paths = if (-not $env:ProgramFiles) { @() } elseif ($Vendor -eq '10DE') { @(
      (Join-Path $env:ProgramFiles 'NVIDIA Corporation\Control Panel Client\nvcplui.exe')) } else { @(
      (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe')) }
  foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } }
  $appx = if ($Vendor -eq '10DE') { 'NVIDIACorp.NVIDIAControlPanel' } else { 'AdvancedMicroDevicesInc-RSXCM' }
  try { if (@(Get-AppxPackage -Name $appx -ErrorAction Stop).Count -gt 0) { return $true } } catch {}
  return $false
}
