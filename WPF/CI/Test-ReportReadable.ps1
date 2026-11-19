# Report readability: WMI codes become client-facing characteristics in HTML/TXT and
# the WPF details view, implausible virtual-adapter speeds are never shown, JSON keeps raw values.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.SystemSummary.ps1')
. (Join-Path $project 'GarantStore.System.ps1')
function Assert-Equal($Name,$Expected,$Actual){if([string]$Expected -cne [string]$Actual){throw ($Name+': expected «'+$Expected+'», got «'+$Actual+'»')}}

$mem=@(Get-GSReadableDetailRows 'memoryModules' @([pscustomobject]@{DeviceLocator='DIMM 0';Capacity=8589934592;ConfiguredClockSpeed=2666;Speed=3200;SMBIOSMemoryType=26;FormFactor=12;Manufacturer='Samsung'}))
Assert-Equal 'memory size' '8 ГБ' $mem[0].'Объём'
Assert-Equal 'memory type' 'DDR4' $mem[0].'Тип'
Assert-Equal 'memory form' 'SO-DIMM (ноутбучный)' $mem[0].'Форм-фактор'
Assert-Equal 'memory speed' '2666 МТ/с (модуль до 3200 МТ/с)' $mem[0].'Частота'
$unknownMem=@(Get-GSReadableDetailRows 'memoryModules' @([pscustomobject]@{DeviceLocator='A';Capacity=0;ConfiguredClockSpeed=0;Speed=0;SMBIOSMemoryType=0;FormFactor=0;Manufacturer=''}))
if($null -ne $unknownMem[0].'Тип' -or $null -ne $unknownMem[0].'Частота' -or $null -ne $unknownMem[0].'Объём'){throw 'Unknown memory codes must not be shown as values'}

$disk=@(Get-GSReadableDetailRows 'physicalDisks' @([pscustomobject]@{FriendlyName='WD SN530';Manufacturer='';Size=256060514304;MediaType=4;BusType=17;HealthStatus=0}))
Assert-Equal 'disk size' '238,5 ГБ' $disk[0].'Объём'
Assert-Equal 'disk media' 'SSD' $disk[0].'Тип'
Assert-Equal 'disk bus' 'NVMe' $disk[0].'Интерфейс'
Assert-Equal 'disk health' 'исправен' $disk[0].'Состояние'
$diskText=@(Get-GSReadableDetailRows 'physicalDisks' @([pscustomobject]@{FriendlyName='X';Manufacturer='';Size=2000398934016;MediaType='Unspecified';BusType='USB';HealthStatus='Healthy'}))
Assert-Equal 'disk bus as text' 'USB' $diskText[0].'Интерфейс'
Assert-Equal 'disk TB' '1,82 ТБ' $diskText[0].'Объём'

$vol=@(Get-GSReadableDetailRows 'volumes' @([pscustomobject]@{DeviceID='C:';FileSystem='NTFS';Size=255061700608;FreeSpace=63765425152}))
Assert-Equal 'volume used' '75 %' $vol[0].'Заполнено'

$cpu=@(Get-GSReadableDetailRows 'processors' @([pscustomobject]@{Name='Intel(R) Core(TM) i5-1035G1 CPU @ 1.00GHz  ';Manufacturer='GenuineIntel';Architecture=9;SocketDesignation='U3E1';NumberOfCores=4;NumberOfLogicalProcessors=8;CurrentClockSpeed=1190;MaxClockSpeed=1190;L2CacheSize=2048;L3CacheSize=6144;LoadPercentage=12}))
Assert-Equal 'cpu arch' 'x64' $cpu[0].'Архитектура'
Assert-Equal 'cpu L3' '6 МБ' $cpu[0].'Кэш L3'
Assert-Equal 'cpu clock' '1,19 ГГц' $cpu[0].'Базовая частота'

$os=@(Get-GSReadableDetailRows 'operatingSystem' @([pscustomobject]@{Caption='Windows 11 Pro';Version='10.0.26100';BuildNumber='26100';OSArchitecture='64-bit';InstallDate='/Date(1735689600000)/';LastBootUpTime='2026-11-19T08:00:00Z';TotalVisibleMemorySize=8213020;FreePhysicalMemory=3145728}))
Assert-Equal 'os memory' '7,8 ГБ доступно Windows' $os[0].'Оперативная память'
Assert-Equal 'os build' '26100' $os[0].'Сборка'
if([string]$os[0].'Установлена' -notmatch '^\d\d\.\d\d\.20(24|25)$'){throw ('os install date: '+$os[0].'Установлена')}

$net=@(Get-GSReadableDetailRows 'network' @(
 [pscustomobject]@{Name='WAN Miniport (IP)';Manufacturer='Microsoft';AdapterType='';NetConnectionStatus=$null;Speed=9223372036854775807;PhysicalAdapter=$false},
 [pscustomobject]@{Name='Hyper-V Virtual Ethernet';Manufacturer='Microsoft';AdapterType='Ethernet 802.3';NetConnectionStatus=2;Speed=10000000000000;PhysicalAdapter='False'},
 [pscustomobject]@{Name='Intel Wi-Fi 6 AX201';Manufacturer='Intel';AdapterType='Ethernet 802.3';NetConnectionStatus=2;Speed=1201000000;PhysicalAdapter=$true},
 [pscustomobject]@{Name='Realtek PCIe GbE';Manufacturer='Realtek';AdapterType='Ethernet 802.3';NetConnectionStatus=7;Speed=9223372036854775807;PhysicalAdapter=$true},
 [pscustomobject]@{Name='USB LAN';Manufacturer='ASIX';AdapterType='Ethernet 802.3';NetConnectionStatus=2;Speed=9223372036854775807;PhysicalAdapter=$true}))
Assert-Equal 'net rows' 4 $net.Count
Assert-Equal 'wifi speed' '1,2 Гбит/с' $net[0].'Скорость подключения'
Assert-Equal 'disconnected' 'кабель не подключён' $net[1].'Состояние'
Assert-Equal 'disconnected speed' 'нет подключения' $net[1].'Скорость подключения'
Assert-Equal 'implausible speed' 'не сообщается адаптером' $net[2].'Скорость подключения'
if([string]$net[3].'Виртуальные адаптеры' -notmatch '^2 скрыто'){throw 'Virtual adapters must be summarised, not listed'}

$gfx=@(Get-GSReadableDetailRows 'graphics' @(
 [pscustomobject]@{Name='NVIDIA GeForce RTX 5060';AdapterCompatibility='NVIDIA';DriverVersion='32.0.16.1742';DriverDate='20260930000000.000000-000';CurrentHorizontalResolution=1920;CurrentVerticalResolution=1080;CurrentRefreshRate=240;PNPDeviceID='PCI\VEN_10DE';AdapterRAM=4293918720;VideoMemoryBytes=8589934592;VideoMemoryAtLeast=$false;VideoMemorySource='registry-qw'},
 [pscustomobject]@{Name='NVIDIA GeForce RTX 5060';AdapterCompatibility='NVIDIA';DriverVersion='1';DriverDate='';CurrentHorizontalResolution=$null;CurrentVerticalResolution=$null;CurrentRefreshRate=$null;PNPDeviceID='';AdapterRAM=4293918720;VideoMemoryBytes=4294967296;VideoMemoryAtLeast=$true;VideoMemorySource='wmi-capped'},
 [pscustomobject]@{Name='Old profile';AdapterCompatibility='NVIDIA';DriverVersion='1';DriverDate='';CurrentHorizontalResolution=$null;CurrentVerticalResolution=$null;CurrentRefreshRate=$null}))
Assert-Equal 'vram real' '8 ГБ' $gfx[0].'Видеопамять'
Assert-Equal 'vram lower bound' 'не менее 4 ГБ (точный объём Windows не сообщила)' $gfx[1].'Видеопамять'
if($null -ne $gfx[2].'Видеопамять'){throw 'Without a measured size the report must not invent one'}
if(@($gfx[0].PSObject.Properties.Name) -contains 'AdapterRAM'){throw 'Capped AdapterRAM must not reach the readable report'}
$dimm=@(Get-GSReadableDetailRows 'memoryModules' @(
 [pscustomobject]@{DeviceLocator='DIMM 1';BankLabel='P0 CHANNEL A';Capacity=8589934592;ConfiguredClockSpeed=3200;Speed=3200;SMBIOSMemoryType=26;FormFactor=8;Manufacturer='Unknown';PartNumber=''},
 [pscustomobject]@{DeviceLocator='DIMM 1';BankLabel='P0 CHANNEL B';Capacity=8589934592;ConfiguredClockSpeed=3200;Speed=3200;SMBIOSMemoryType=26;FormFactor=8;Manufacturer='Kingston';PartNumber='KF432C16BB/8 '}))
Assert-Equal 'slot A' 'DIMM 1 · канал A' $dimm[0].'Слот'
Assert-Equal 'slot B' 'DIMM 1 · канал B' $dimm[1].'Слот'
if($null -ne $dimm[0].'Производитель'){throw 'Placeholder "Unknown" must not be shown as a manufacturer'}
Assert-Equal 'part number' 'KF432C16BB/8' $dimm[1].'Маркировка'
$svc=@(Get-GSReadableServiceRows @([pscustomobject]@{name='wuauserv';status='Stopped'},[pscustomobject]@{name='AppXSvc';status='Running'}))
Assert-Equal 'service stopped' 'не запущена (запускается по требованию)' $svc[0].'Центр обновления Windows'
Assert-Equal 'service running' 'работает' $svc[0].'Развёртывание приложений (AppX)'
# Full export: HTML and TXT readable, JSON raw.
$details=[pscustomobject]@{operatingSystem=@();processors=@();motherboard=@();firmware=@();memoryModules=@([pscustomobject]@{DeviceLocator='DIMM 0';Capacity=8589934592;ConfiguredClockSpeed=2666;Speed=2666;SMBIOSMemoryType=26;FormFactor=12;Manufacturer='Samsung'});physicalDisks=@();volumes=@();graphics=@();monitors=@();network=@([pscustomobject]@{Name='WAN Miniport (IP)';Manufacturer='Microsoft';AdapterType='';NetConnectionStatus=$null;Speed=9223372036854775807;PhysicalAdapter=$false});audio=@();peripheral=@()}
$profile=[pscustomobject]@{capturedUtc='2026-11-20T10:00:00Z';services=@([pscustomobject]@{name='wuauserv';status='Stopped'});manufacturer='LENOVO';model='81W8';boardManufacturer='LENOVO';boardModel='LNVNB161216';processor='Intel Core i5-1035G1';memoryBytes=8589934592;summaryError='';edition='Windows 11 Pro';displayVersion='24H2';build='26100';installedDriverCount=120;problemDeviceCount=1;details=$details;summary=$null}
$state=[pscustomobject]@{Profile=$profile}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('gs-report-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp|Out-Null
try{
 foreach($ext in 'html','txt'){
  $path=Join-Path $tmp ('r.'+$ext)
  Export-GSSystemProfile $state $path $false
  $text=[IO.File]::ReadAllText($path)
  if($text -match '9223372036854775807|SMBIOSMemoryType|PhysicalAdapter|(?m)^status: |>status<'){throw ($ext+' report still shows raw WMI values')}
  if($text -notmatch 'DDR4' -or $text -notmatch 'SO-DIMM'){throw ($ext+' report misses readable memory type')}
  if($ext -eq 'txt' -and $text -notmatch '(?m)^Сборка: \d+'){throw 'TXT report must show the Windows build in Russian'}
 }
 $json=Join-Path $tmp 'r.json'
 Export-GSSystemProfile $state $json $false
 if([IO.File]::ReadAllText($json) -notmatch '"SMBIOSMemoryType":\s*26'){throw 'JSON export must keep raw WMI values'}
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'Report readability gate passed: video memory (no 32-bit cap), memory slots/channels, services, memory, disks, volumes, CPU, OS, network (virtual hidden, implausible speed suppressed), HTML/TXT readable, JSON raw.'
