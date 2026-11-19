# Battery telemetry trust (field: T159R reported 4 117 of 4 117 mAh = "100% хорошее").
# Equal raw capacities or a placeholder serial -> "Данные не подтверждены":
# no health %, no wear 0%, no green bar - and no claim that the battery is worn.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.SystemSummary.ps1')
. (Join-Path $project 'GarantStore.System.ps1')
function Assert-Equal($Name,$Expected,$Actual){if([string]$Expected -cne [string]$Actual){throw ($Name+': expected «'+$Expected+'», got «'+$Actual+'»')}}
function B([double]$Design,[double]$Full,[int]$Cycles=0,[bool]$Suspect=$false,[double]$Voltage=11550){[pscustomobject]@{Present=$true;DesignCapacity=$Design;FullChargeCapacity=$Full;CycleCount=$Cycles;ChargePercent=80;DesignVoltage=$Voltage;SerialSuspect=$Suspect;Source='powercfg'}}

# Placeholder serials
foreach($s in @('123456789','00001','0001','0000000000','11111111','FFFF','UNKNOWN','N/A','none','12345678','SN','Default')){if(-not (Test-GSPlaceholderSerial $s)){throw ('placeholder serial not detected: '+$s)}}
foreach($s in @('','A1B2C3D4E5','5B10W13906','1024','30416')){if(Test-GSPlaceholderSerial $s){throw ('real serial flagged: '+$s)}}

# Normal battery (Lenovo IdeaPad S145 field values)
$normal=B 41600 36620 392
$a=Get-GSBatteryAssessment $normal
Assert-Equal 'normal status' 'Confirmed' $a.Status
Assert-Equal 'normal health (floor)' 88 $a.HealthPercent
if((Format-GSPower $normal) -notmatch '^\d[\d ]* из [\d ]+ mAh · состояние 88% \(хорошее\) · циклов заряда: 392$'){throw ('normal text: '+(Format-GSPower $normal))}
Assert-Equal 'normal trust' 'Confirmed' (Get-GSBatteryTrust $normal)

# Absent
Assert-Equal 'absent power' 'Не определяется программно · модель и мощность — на наклейке блока питания' (Format-GSPower ([pscustomobject]@{Present=$false;DesignCapacity=0;FullChargeCapacity=0;CycleCount=0;ChargePercent=-1}))
Assert-Equal 'absent health' -1 (Get-GSBatteryHealth $null)
Assert-Equal 'absent trust' 'Absent' (Get-GSBatteryTrust @())

# Equal raw capacities (T159R photo: 4 117 of 4 117 mAh)
$equal=B 47550 47550 0 $false 11550
$e=Get-GSBatteryAssessment $equal
Assert-Equal 'equal status' 'Unconfirmed' $e.Status
Assert-Equal 'equal health hidden' -1 (Get-GSBatteryHealth $equal)
$text=Format-GSPower $equal
if($text -notmatch '^Данные не подтверждены · ' -or $text -match 'хорошее|100%|износ'){throw ('equal text: '+$text)}
if($text -notmatch 'точно равна паспортной'){throw 'equal reason missing'}

# Equal only after mWh->mAh rounding: raw differs -> still confirmed, not "unconfirmed"
$rounded=B 42001 42000 10 $false 11550
$r=Get-GSBatteryAssessment $rounded
Assert-Equal 'rounded status' 'Confirmed' $r.Status
Assert-Equal 'rounded display equal' $true $r.DisplayEqual
Assert-Equal 'rounded health floor' 99 $r.HealthPercent
if((Format-GSPower $rounded) -notmatch 'значения округлены'){throw 'rounding note missing'}

# Placeholder serial with plausible numbers
$fake=B 41600 39000 5 $true
Assert-Equal 'fake serial status' 'Unconfirmed' (Get-GSBatteryAssessment $fake).Status
if((Format-GSPower $fake) -notmatch 'заглушка'){throw 'serial reason missing'}
if((Format-GSBattery $fake) -match '% ёмкости'){throw 'legacy text shows health for unconfirmed battery'}

# Invalid values
Assert-Equal 'zero design' 'Invalid' (Get-GSBatteryAssessment (B 0 30000)).Status
Assert-Equal 'implausible design' 'Invalid' (Get-GSBatteryAssessment (B 999999 500000)).Status
Assert-Equal 'full far above design' 'Invalid' (Get-GSBatteryAssessment (B 40000 60000)).Status
Assert-Equal 'slightly above design is unconfirmed' 'Unconfirmed' (Get-GSBatteryAssessment (B 40000 43000)).Status
Assert-Equal 'invalid health hidden' -1 (Get-GSBatteryHealth (B 0 30000))

# Several batteries: health only when every pack is confirmed
$two=@((B 23000 20000 100),(B 23000 18000 200))
Assert-Equal 'two health = worst' 78 (Get-GSBatteryHealth $two)
if((Format-GSPower $two) -notmatch '^АКБ 1: .* \+ АКБ 2: '){throw ('two text: '+(Format-GSPower $two))}
$mixed=@((B 23000 20000 100),(B 23000 23000 0))
Assert-Equal 'mixed health hidden' -1 (Get-GSBatteryHealth $mixed)
Assert-Equal 'mixed trust' 'Unconfirmed' (Get-GSBatteryTrust $mixed)

# Summary + every output (HTML tiles, WPF/TXT rows, JSON) agree
$raw=[pscustomobject]@{Manufacturer='T159R';Model='T159R';Version='';BoardManufacturer='';BoardProduct='EM_APX938_V2.0';Board='';ComputerName='X';PcSystemType=2;CpuName='AMD Ryzen 9 6900HX with Radeon Graphics';Cores=8;Threads=16;Gpus=@();MemoryModules=@();Disks=@();Panels=@();Battery=$equal;Batteries=@($equal)}
$summary=New-GSSystemSummary $raw
Assert-Equal 'summary health' -1 $summary.BatteryHealth
Assert-Equal 'summary trust' 'Unconfirmed' $summary.BatteryTrust
$profile=[pscustomobject]@{summary=$summary;manufacturer='T159R';model='T159R';boardManufacturer='';boardModel='';processor='';memoryBytes=0}
$rows=Get-GSSystemSummaryRows $profile
if([string]$rows.'Аккумулятор' -notmatch '^Данные не подтверждены'){throw 'WPF/TXT row shows unconfirmed battery as fact'}
$html=New-GSSummaryHtml $rows $profile
if($html -match 'class="bar"' -or $html -match '100%|хорошее'){throw 'HTML shows a health bar or verdict for unconfirmed telemetry'}
if($html -notmatch 'Данные не подтверждены'){throw 'HTML lacks the unconfirmed notice'}
$json=ConvertTo-Json -InputObject $summary -Depth 6
if($json -match '(?i)serial'){throw 'JSON summary mentions a serial number'}
$okSummary=New-GSSystemSummary ([pscustomobject]@{Manufacturer='LENOVO';Model='81W8';Version='IdeaPad S145-15IIL';BoardManufacturer='';BoardProduct='';Board='';ComputerName='X';PcSystemType=2;CpuName='';Cores=0;Threads=0;Gpus=@();MemoryModules=@();Disks=@();Panels=@();Battery=$normal;Batteries=@($normal)})
$okHtml=New-GSSummaryHtml (Get-GSSystemSummaryRows ([pscustomobject]@{summary=$okSummary;manufacturer='';model='';boardManufacturer='';boardModel='';processor='';memoryBytes=0})) ([pscustomobject]@{summary=$okSummary})
if($okHtml -notmatch 'class="bar"'){throw 'confirmed battery lost its health bar'}
Write-Host 'Battery trust gate passed: normal, absent, equal raw vs rounded, placeholder serial, invalid, multiple packs, HTML/rows/JSON consistency.'
