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

Write-Host 'System summary gate passed: model names, CPU incl. engineering samples, GPU VRAM/integrated, RAM kit format, internal storage only, EDID panel, battery health, safe file name.'
