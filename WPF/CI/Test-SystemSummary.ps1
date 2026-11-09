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
Assert-Equal $n.Battery 'ёмкость не определена, заряд 55%' 'Battery without capacity data'

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
Write-Host 'System summary gate passed: model names, CPU incl. engineering samples, GPU VRAM/integrated, RAM kit format, internal storage only, EDID panel, battery health, safe file name.'
