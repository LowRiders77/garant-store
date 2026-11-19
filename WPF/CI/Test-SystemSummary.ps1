# Plain-language "Моя система" summary on fixtures taken from real field reports
# (ASUS Vivobook Go E1504FA and an unbranded NoviSea laptop with an Intel ES CPU).
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.SystemSummary.ps1')
function Assert-Equal($Actual,$Expected,[string]$What){if([string]$Actual -cne [string]$Expected){throw ($What+': expected «'+$Expected+'», got «'+$Actual+'»')}}

# Synthetic EDID: CMN 15E8, 34x19 cm, 1920x1080 with a 138.5 MHz preferred timing, panel text N156HCA-EAB.
$edid=New-Object byte[] 128
$header=@(0,255,255,255,255,255,255,0);for($i=0;$i -lt 8;$i++){$edid[$i]=[byte]$header[$i]}
$edid[8]=0x0D;$edid[9]=0xAE;$edid[10]=0xE8;$edid[11]=0x15;$edid[21]=34;$edid[22]=19
$dtd=@(0x18,0x36,0x80,0xA0,0x70,0x38,0x1F,0x40);for($i=0;$i -lt $dtd.Count;$i++){$edid[54+$i]=[byte]$dtd[$i]}
$edid[72+3]=0xFE;$text=[Text.Encoding]::ASCII.GetBytes("N156HCA-EAB`n  ");for($i=0;$i -lt 13;$i++){$edid[72+5+$i]=$text[$i]}
$panel=ConvertFrom-GSEdid $edid
Assert-Equal $panel.Vendor 'CMN' 'EDID vendor'
Assert-Equal $panel.ProductCode '15E8' 'EDID product code'
Assert-Equal $panel.Width 1920 'EDID width';Assert-Equal $panel.Height 1080 'EDID height';Assert-Equal $panel.Refresh 60 'EDID refresh'
Assert-Equal $panel.PanelText 'N156HCA-EAB' 'EDID panel part number'
Assert-Equal $panel.DiagonalInches 15.3 'EDID diagonal'
if($null -ne (ConvertFrom-GSEdid ([byte[]](1..128)))){throw 'Garbage EDID was parsed'}
# High-refresh desktop monitor (field: LHC N27SH2 shown as "60 Гц" while Windows ran it at 240 Hz).
# Base block: preferred 1920x1080@60 (148.5 MHz); CTA-861 extension: 1920x1080@240 and 1280x720@300.
function New-TestDtd([int]$ClockTenKHz,[int]$W,[int]$H,[int]$HBlank,[int]$VBlank){
 [byte[]]@(($ClockTenKHz -band 255),($ClockTenKHz -shr 8),($W -band 255),($HBlank -band 255),((($W -shr 8) -shl 4) -bor ($HBlank -shr 8)),($H -band 255),($VBlank -band 255),((($H -shr 8) -shl 4) -bor ($VBlank -shr 8)),0,0,0,0,0,0,0,0,0,0)
}
$hr=New-Object byte[] 256
for($i=0;$i -lt 8;$i++){$hr[$i]=[byte]$header[$i]}
$hr[8]=0x31;$hr[9]=0x03;$hr[21]=60;$hr[22]=34;$hr[126]=1
$d=New-TestDtd 14850 1920 1080 280 45;for($i=0;$i -lt 18;$i++){$hr[54+$i]=$d[$i]}
$hr[128]=2;$hr[129]=3;$hr[130]=4
$d=New-TestDtd 56410 1920 1080 160 50;for($i=0;$i -lt 18;$i++){$hr[132+$i]=$d[$i]}
$d=New-TestDtd 33000 1280 720 370 30;for($i=0;$i -lt 18;$i++){$hr[150+$i]=$d[$i]}
$fast=ConvertFrom-GSEdid $hr
Assert-Equal $fast.Width 1920 'High-refresh EDID width'
Assert-Equal $fast.Refresh 240 'Maximum refresh at native resolution from the CTA extension (not the 60 Hz preferred timing, not the 720p mode)'

$asus=[pscustomobject]@{
 Manufacturer='ASUSTeK COMPUTER INC.';Model='Vivobook Go E1504FA_E1504FA';Version='1.0';Board='ASUSTeK COMPUTER INC. E1504FA';ComputerName='GARANT-PC';PcSystemType=2
 CpuName='AMD Ryzen 5 7520U with Radeon Graphics         ';Cores=4;Threads=8
 Gpus=@([pscustomobject]@{Name='AMD Radeon(TM) Graphics';MemoryBytes=536870912})
 MemoryModules=@([pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=35;ConfiguredClockSpeed=5500;Speed=5500;Manufacturer='Unknown';PartNumber=''},[pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=35;ConfiguredClockSpeed=5500;Speed=5500;Manufacturer='Unknown';PartNumber=''})
 Disks=@([pscustomobject]@{FriendlyName='Realtek RTL9210 NVME';Size=512110190592;BusType=7;MediaType=4;IsSystem=$false},[pscustomobject]@{FriendlyName='SAMSUNG MZVMA512HCLV-00BTW';Size=512110190592;BusType=17;MediaType=4;IsSystem=$true})
 Panels=@([pscustomobject]@{Vendor='CMN';ProductCode='15E8';Name='';PanelText='N156HCA-EAB';Width=1920;Height=1080;Refresh=60;DiagonalInches=15.6;Internal=$true})
 Battery=[pscustomobject]@{Present=$true;DesignCapacity=42000;FullChargeCapacity=38640;CycleCount=12;ChargePercent=80}
}
$s=New-GSSystemSummary $asus
Assert-Equal $s.Kind 'Ноутбук' 'Asus kind'
Assert-Equal $s.Model 'ASUS Vivobook Go E1504FA' 'Asus model'
Assert-Equal $s.Processor 'AMD Ryzen 5 7520U (4 ядра / 8 потоков)' 'Asus CPU'
Assert-Equal $s.Graphics 'AMD Radeon Graphics (встроенная)' 'Asus GPU'
Assert-Equal $s.Memory '16GB LPDDR5 (2x8) 5500MHz' 'Asus RAM'
Assert-Equal $s.Storage 'Samsung MZVMA512HCLV 512GB NVMe SSD' 'Asus storage (USB enclosure excluded)'
Assert-Equal $s.Display '15.6" 1920×1080 60 Гц, Innolux N156HCA-EAB' 'Asus display'
Assert-Equal $s.Battery '92% ёмкости (хорошее), износ 8%, 38 640 из 42 000 мВт·ч, циклов: 12, заряд 80%' 'Asus battery'

$novisea=[pscustomobject]@{
 Manufacturer='Default string';Model='Default string';Version='Default string';Board='';ComputerName='GARANT-PC';PcSystemType=2
 CpuName='Genuine Intel(R) 0000';Cores=6;Threads=8
 Gpus=@([pscustomobject]@{Name='Intel(R) Iris(R) Xe Graphics';MemoryBytes=134217728},[pscustomobject]@{Name='Microsoft Basic Display Adapter';MemoryBytes=0})
 MemoryModules=@([pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=26;ConfiguredClockSpeed=2667;Speed=2667;Manufacturer='0x0000';PartNumber=''})
 Disks=@([pscustomobject]@{FriendlyName='Realtek RTL9210 NVME';Size=512110190592;BusType=7;MediaType=4;IsSystem=$false},[pscustomobject]@{FriendlyName='Kingsand P600 256G';Size=256060514304;BusType=11;MediaType=4;IsSystem=$true})
 Panels=@([pscustomobject]@{Vendor='BOE';ProductCode='0A1B';Name='';PanelText='';Width=1920;Height=1080;Refresh=60;DiagonalInches=15.6;Internal=$true})
 Battery=[pscustomobject]@{Present=$true;DesignCapacity=0;FullChargeCapacity=0;CycleCount=0;ChargePercent=55}
}
$n=New-GSSystemSummary $novisea
Assert-Equal $n.Model 'Компьютер GARANT-PC' 'Unbranded model fallback'
Assert-Equal $n.Processor 'Intel, инженерный образец (6 ядер / 8 потоков)' 'Intel ES CPU'
Assert-Equal $n.Graphics 'Intel Iris Xe Graphics (встроенная)' 'Intel GPU, basic adapter hidden'
Assert-Equal $n.Memory '8GB DDR4 (1x8) 2667MHz' 'Single DDR4 module'
Assert-Equal $n.Storage 'Kingsand P600 256GB SATA SSD' 'SATA SSD'
Assert-Equal $n.Display '15.6" 1920×1080 60 Гц, BOE (код BOE0A1B)' 'Panel without part number'
Assert-Equal $n.Battery 'Данные не подтверждены, причина: контроллер не сообщает ёмкость, заряд 55%' 'Battery without capacity data'

$desktop=[pscustomobject]@{
 Manufacturer='Micro-Star International Co., Ltd.';Model='MS-7C02';Version='';Board='';ComputerName='GAMER';PcSystemType=1
 CpuName='AMD Ryzen 5 5600X 6-Core Processor             ';Cores=6;Threads=12
 Gpus=@([pscustomobject]@{Name='NVIDIA GeForce GTX 1060 6GB';MemoryBytes=6442450944},[pscustomobject]@{Name='NVIDIA GeForce RTX 5060';MemoryBytes=8589934592})
 MemoryModules=@([pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=26;ConfiguredClockSpeed=2333;Speed=3200;Manufacturer='Corsair';PartNumber='CMK16GX4M2B3200C16'},[pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=26;ConfiguredClockSpeed=2333;Speed=3200;Manufacturer='Corsair';PartNumber='CMK16GX4M2B3200C16'})
 Disks=@([pscustomobject]@{FriendlyName='WDC WD10EZEX-08WN4A0';Size=1000204886016;BusType=11;MediaType=3;IsSystem=$false},[pscustomobject]@{FriendlyName='Samsung SSD 970 EVO Plus 1TB';Size=1000204886016;BusType=17;MediaType=4;IsSystem=$true})
 Panels=@([pscustomobject]@{Vendor='GSM';ProductCode='5B7F';Name='LG ULTRAGEAR';PanelText='';Width=2560;Height=1440;Refresh=165;DiagonalInches=27;Internal=$false})
 Battery=[pscustomobject]@{Present=$false;DesignCapacity=0;FullChargeCapacity=0;CycleCount=0;ChargePercent=-1}
}
$d=New-GSSystemSummary $desktop
Assert-Equal $d.Kind 'Компьютер' 'Desktop kind'
Assert-Equal $d.Model 'MSI MS-7C02' 'Desktop model'
Assert-Equal $d.Processor 'AMD Ryzen 5 5600X (6 ядер / 12 потоков)' 'Desktop CPU'
Assert-Equal $d.Graphics 'NVIDIA GeForce GTX 1060 6GB + NVIDIA GeForce RTX 5060 8GB' 'Discrete GPUs with VRAM'
Assert-Equal $d.Memory '16GB DDR4 (2x8) Corsair Vengeance LPX 2333MHz' 'Corsair kit like the user example'
Assert-Equal $d.Storage 'Samsung SSD 970 EVO Plus 1TB NVMe SSD + WD WD10EZEX 1TB HDD' 'System disk first'
Assert-Equal $d.Display 'Монитор: 27.0" 2560×1440 165 Гц, LG LG ULTRAGEAR' 'External monitor'
Assert-Equal $d.Battery 'Нет (настольный ПК или аккумулятор не обнаружен)' 'Desktop battery'
Assert-Equal (ConvertTo-GSSafeFileName 'ASUS Vivobook Go: E1504FA/2') 'ASUS Vivobook Go E1504FA 2' 'Safe file name'

# New first-page parts: motherboard and power.
Assert-Equal (Format-GSBoardName 'Micro-Star International Co., Ltd.' 'B550M PRO-VDH (MS-7C95)') 'MSI B550M PRO-VDH (MS-7C95)' 'Board name'
Assert-Equal (Format-GSBoardName 'ASUSTeK COMPUTER INC.' 'ASUS TUF GAMING B550-PLUS') 'ASUS TUF GAMING B550-PLUS' 'Board name without duplicate vendor'
Assert-Equal (Format-GSBoardName 'Default string' 'Default string') 'Не определено' 'Placeholder board'
Assert-Equal (Format-GSPower ([pscustomobject]@{Present=$true;DesignCapacity=42000;FullChargeCapacity=38640;CycleCount=12;ChargePercent=80;DesignVoltage=11550})) '3 345 из 3 636 mAh · состояние 92% (хорошее) · циклов заряда: 12' 'Battery in mAh'
Assert-Equal (Format-GSPower ([pscustomobject]@{Present=$true;DesignCapacity=42000;FullChargeCapacity=38640;CycleCount=0;ChargePercent=80})) '38.6 из 42 Вт·ч · состояние 92% (хорошее)' 'Battery without voltage'
if((Format-GSPower $desktop.Battery) -notmatch 'блока питания'){throw 'Desktop PSU text missing'}
Assert-Equal $d.BatteryHealth -1 'Desktop has no battery health'

# Collector on mocked Windows sources: the MSI B550M / RTX 5060 desktop from the
# field report. This path broke on every PC with a monitor ([uint32]0x80000000).
function Get-CimInstance {
 [CmdletBinding()]param([string]$ClassName,[string]$Namespace,[int]$OperationTimeoutSec,[string]$Filter)
 switch($ClassName){
  'Win32_ComputerSystem'{[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Model='MS-7C95';PCSystemType=1}}
  'Win32_ComputerSystemProduct'{[pscustomobject]@{Version='1.0'}}
  'Win32_BaseBoard'{[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Product='B550M PRO-VDH (MS-7C95)'}}
  'Win32_Processor'{[pscustomobject]@{Name='AMD Ryzen 5 5600X 6-Core Processor             ';NumberOfCores=6;NumberOfLogicalProcessors=12}}
  'Win32_VideoController'{[pscustomobject]@{Name='NVIDIA GeForce RTX 5060';AdapterRAM=4293918720}}
  'Win32_PhysicalMemory'{1..2|ForEach-Object{[pscustomobject]@{Capacity=8589934592;SMBIOSMemoryType=26;ConfiguredClockSpeed=3200;Speed=3200;Manufacturer='Unknown';PartNumber=''}}}
  'MSFT_PhysicalDisk'{[pscustomobject]@{FriendlyName='Realtek RTL9210 NVME';Size=512110190592;BusType='USB';MediaType='SSD';DeviceId='1'};[pscustomobject]@{FriendlyName='BIWIN NV7400 1TB';Size=1024209543168;BusType='NVMe';MediaType='SSD';DeviceId='0'}}
  'WmiMonitorConnectionParams'{[pscustomobject]@{InstanceName='DISPLAY\LHC0001\5&1_0';VideoOutputTechnology=[uint32]10}}
  'WmiMonitorID'{[pscustomobject]@{InstanceName='DISPLAY\LHC0001\5&1_0';ManufacturerName=[uint16[]][char[]]'LHC';ProductCodeID=[uint16[]][char[]]'0001';UserFriendlyName=[uint16[]][char[]]'N27SH2'}}
  'Win32_Battery'{}
  default{}
 }
}
function Get-ItemProperty { [CmdletBinding()]param([string]$LiteralPath) if($LiteralPath -like '*CentralProcessor*'){return [pscustomobject]@{ProcessorNameString='AMD Ryzen 5 5600X 6-Core Processor             '}}; throw 'not found' }
function Get-ChildItem { [CmdletBinding()]param([string]$LiteralPath) @() }
function Get-Partition { [CmdletBinding()]param([string]$DriveLetter) [pscustomobject]@{DiskNumber=0} }
if(-not $env:SystemDrive){$env:SystemDrive='C:'}
$raw=Get-GSSummaryRaw
$m=New-GSSystemSummary $raw
Assert-Equal $m.Processor 'AMD Ryzen 5 5600X (6 ядер / 12 потоков)' 'Collected CPU'
Assert-Equal $m.Motherboard 'MSI B550M PRO-VDH (MS-7C95)' 'Collected board'
Assert-Equal $m.Storage 'BIWIN NV7400 1TB NVMe SSD' 'USB enclosure excluded'
if($m.Graphics -notmatch 'RTX 5060'){throw ('Collected GPU: '+$m.Graphics)}
if($m.Memory -notmatch '^16GB DDR4 \(2x8\)'){throw ('Collected RAM: '+$m.Memory)}
if($m.Display -match 'Не определено'){throw ('Monitor lost: '+$m.Display)}
# --- Video memory (field: RTX 5060 8 GB reported as "4GB") ---------------------------
# AdapterRAM is uint32: 4293918720 for every card with >= 4 GB. It must never become the size.
$rtxPnp='PCI\VEN_10DE&DEV_2D05&SUBSYS_00001462&REV_A1\4&2B1A7F3C&0&0019'
$script:fakeRegistry=@{}
function Read-GSRegistryValue([string]$SubKey,[string]$Name){ $k=$SubKey+'|'+$Name; if($script:fakeRegistry.ContainsKey($k)){return $script:fakeRegistry[$k]}; return $null }
function Get-GSRegistrySubKeyNames([string]$SubKey){ @($script:fakeRegistry.Keys|Where-Object{$_ -like ($SubKey+'\*')}|ForEach-Object{($_.Substring($SubKey.Length+1) -split '[\\|]')[0]}|Sort-Object -Unique) }
$script:smiCalls=0;$script:fakeSmi=@{}
function Invoke-GSNvidiaSmi { $script:smiCalls++; return $script:fakeSmi }
function Get-CimInstance {
 [CmdletBinding()]param([string]$ClassName,[string]$Namespace,[int]$OperationTimeoutSec,[string]$Filter)
 switch($ClassName){
  'Win32_ComputerSystem'{[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Model='MS-7C95';PCSystemType=1}}
  'Win32_BaseBoard'{[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Product='B550M PRO-VDH (MS-7C95)'}}
  'Win32_Processor'{[pscustomobject]@{Name='AMD Ryzen 5 5600X 6-Core Processor';NumberOfCores=6;NumberOfLogicalProcessors=12}}
  'Win32_VideoController'{[pscustomobject]@{Name='NVIDIA GeForce RTX 5060';AdapterRAM=[uint32]4293918720;PNPDeviceID=$rtxPnp;CurrentHorizontalResolution=1920;CurrentVerticalResolution=1080;CurrentRefreshRate=240}}
  'WmiMonitorConnectionParams'{[pscustomobject]@{InstanceName='DISPLAY\LHC0001\5&1_0';VideoOutputTechnology=[uint32]10}}
  'WmiMonitorID'{[pscustomobject]@{InstanceName='DISPLAY\LHC0001\5&1_0';ManufacturerName=[uint16[]][char[]]'LHC';ProductCodeID=[uint16[]][char[]]'0001';UserFriendlyName=[uint16[]][char[]]'N27SH2'}}
  default{}
 }
}
$classRoot='SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
function Invoke-VramCase([hashtable]$Registry,[hashtable]$Smi){
 $script:fakeRegistry=$Registry;$script:fakeSmi=$Smi;$script:GSSmiCache=$null;$script:smiCalls=0
 return (New-GSSystemSummary (Get-GSSummaryRaw)).Graphics
}
# 1. Exact driver key of this adapter (Enum\<PNPDeviceID>\Driver -> Class\...\0001), REG_QWORD.
$g=Invoke-VramCase @{("SYSTEM\CurrentControlSet\Enum\$rtxPnp|Driver")='{4d36e968-e325-11ce-bfc1-08002be10318}\0001';($classRoot+'\0001|HardwareInformation.qwMemorySize')=[int64]8589934592} @{}
Assert-Equal $g 'NVIDIA GeForce RTX 5060 8GB' 'VRAM from the exact driver key'
# EDID with a 60 Hz preferred timing only; Windows runs the panel at 1920x1080@240.
$script:baseEdid=$edid
function Get-ItemProperty { [CmdletBinding()]param([string]$LiteralPath) if($LiteralPath -like '*LHC0001*'){$e=[byte[]]$script:baseEdid.Clone();$e[8]=0x31;$e[9]=0x03;return [pscustomobject]@{EDID=$e}}; if($LiteralPath -like '*CentralProcessor*'){return [pscustomobject]@{ProcessorNameString='AMD Ryzen 5 5600X 6-Core Processor'}}; throw 'not found' }
$d240=New-GSSystemSummary (Get-GSSummaryRaw)
if($d240.Display -notmatch '1920×1080 240 Гц'){throw ('Active 240 Hz mode lost: '+$d240.Display)}
if($script:smiCalls -ne 0){throw 'nvidia-smi must not run when the registry answered'}
# 2. Enum key unreadable, class key found by DriverDesc; an unreadable sibling does not abort the scan.
$g=Invoke-VramCase @{($classRoot+'\0000|DriverDesc')='AMD Radeon RX 6600';($classRoot+'\0000|HardwareInformation.qwMemorySize')=[int64]8589934592;($classRoot+'\0001|DriverDesc')='NVIDIA GeForce RTX 5060';($classRoot+'\0001|HardwareInformation.qwMemorySize')=[int64]8589934592;($classRoot+'\Properties|Security')=$null} @{}
Assert-Equal $g 'NVIDIA GeForce RTX 5060 8GB' 'VRAM from the class key by name'
# 3. No registry value at all: nvidia-smi (MiB).
$g=Invoke-VramCase @{} @{'NVIDIA GeForce RTX 5060'=[double]8151}
Assert-Equal $g 'NVIDIA GeForce RTX 5060 8GB' 'VRAM from nvidia-smi'
# 4. Only the capped WMI value: a lower bound, never "4GB".
$g=Invoke-VramCase @{} @{}
Assert-Equal $g 'NVIDIA GeForce RTX 5060 (видеопамять не менее 4GB)' 'Capped AdapterRAM is shown as a lower bound'
# 5. A capped 32-bit registry DWORD is not trusted either.
$g=Invoke-VramCase @{("SYSTEM\CurrentControlSet\Enum\$rtxPnp|Driver")='{4d36e968-e325-11ce-bfc1-08002be10318}\0001';($classRoot+'\0001|HardwareInformation.MemorySize')=[byte[]](0x00,0x00,0xF0,0xFF)} @{}
Assert-Equal $g 'NVIDIA GeForce RTX 5060 (видеопамять не менее 4GB)' 'Capped registry DWORD is a lower bound'
# Unit cases: 12 GB QWORD, 2 GB DWORD (below the cap is exact), integrated 128 MB from WMI.
$v=Get-GSGpuMemoryInfo -Name 'NVIDIA GeForce RTX 3060' -PnpDeviceId 'PCI\X' -AdapterRam ([uint32]4293918720) -ClassMemory @{'NVIDIA GeForce RTX 3060'=[pscustomobject]@{Bytes=[double]12884901888;Source='registry-qw'}} -SmiMemory @{}
Assert-Equal (Format-GSVideoMemory $v) '12 ГБ' '12 GB QWORD'
$v=Get-GSGpuMemoryInfo -Name 'NVIDIA GeForce GT 1030' -PnpDeviceId '' -AdapterRam $null -ClassMemory @{'NVIDIA GeForce GT 1030'=[pscustomobject]@{Bytes=[double]2147483648;Source='registry-dword'}} -SmiMemory @{}
Assert-Equal (Format-GSVideoMemory $v) '2 ГБ' '2 GB DWORD below cap'
$v=Get-GSGpuMemoryInfo -Name 'Intel(R) UHD Graphics 630' -PnpDeviceId '' -AdapterRam ([uint32]1073741824) -ClassMemory @{} -SmiMemory @{}
Assert-Equal (Format-GSVideoMemory $v) '1 ГБ' 'Small AdapterRAM is exact'
Assert-Equal (Format-GSVideoMemory ([pscustomobject]@{Bytes=[double]4GB;AtLeast=$true})) 'не менее 4 ГБ (точный объём Windows не сообщила)' 'Lower-bound wording'
Assert-Equal (ConvertTo-GSRegistryBytes ([int]-1048576)) '4293918720' 'Signed DWORD from the registry is read as unsigned'
# Laptop panel reported as internal (0x80000000) must not throw either.
function Get-CimInstance {
 [CmdletBinding()]param([string]$ClassName,[string]$Namespace,[int]$OperationTimeoutSec,[string]$Filter)
 switch($ClassName){
  'WmiMonitorConnectionParams'{[pscustomobject]@{InstanceName='DISPLAY\CMN15E8\4&1_0';VideoOutputTechnology=[uint32]2147483648}}
  'WmiMonitorID'{[pscustomobject]@{InstanceName='DISPLAY\CMN15E8\4&1_0';ManufacturerName=[uint16[]][char[]]'CMN';ProductCodeID=[uint16[]][char[]]'15E8';UserFriendlyName=$null}}
  default{}
 }
}
$laptopRaw=Get-GSSummaryRaw
Assert-Equal @($laptopRaw.Panels).Count 1 'Internal panel collected'
Assert-Equal $laptopRaw.Panels[0].Internal $true 'Internal panel flagged'

Assert-Equal (ConvertTo-GSStorageCode 'NVMe' 'Bus') 17 'Bus name mapped'
Assert-Equal (ConvertTo-GSStorageCode 'SATA' 'Bus') 11 'SATA mapped'
Assert-Equal (ConvertTo-GSStorageCode ([uint16]7) 'Bus') 7 'Numeric bus kept'
Assert-Equal (ConvertTo-GSStorageCode 'HDD' 'Media') 3 'Media name mapped'
Assert-Equal (Format-GSModelName 'QIYIDA' 'X79 (INTEL Xeon E5/Corei7 DMI2 - C600/C200 Cipset)' '' '' 'GARANT-PC') 'QIYIDA X79' 'Chinese board essay dropped'
Assert-Equal (ConvertTo-GSSafeFileName 'QIYIDA X79 (INTEL Xeon E5 Corei7 DMI2 - C600 C200 Cipset') 'QIYIDA X79' 'Unbalanced bracket dropped'
Write-Host 'System summary gate passed: model names, CPU incl. engineering samples, GPU VRAM/integrated, VRAM above the 32-bit WMI cap (driver key, class key, nvidia-smi, lower bound), RAM kit format, internal storage only, EDID panel, battery health, safe file name.'
