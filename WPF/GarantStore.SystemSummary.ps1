# Garant Store - plain-language hardware summary for "Моя система".
# Pure formatting functions (no WMI) so they are tested on fixtures; the
# collection side lives in Get-GSSummaryRaw at the end of this file.

function ConvertTo-GSCleanText([string]$Text){
 if([string]::IsNullOrWhiteSpace($Text)){return ''}
 $value=$Text -replace '\((R|TM|tm|r)\)','' -replace '®|™','' -replace '\s+',' '
 return $value.Trim()
}

function Test-GSPlaceholderText([string]$Text){
 return ([string]::IsNullOrWhiteSpace($Text) -or $Text -match '(?i)^(to be filled.*|default string|system (product name|manufacturer|version)|unknown|not applicable|none|n/a|o\.e\.m\.?|oem|0x0+|не определено|модель не указана.*|производитель не определён)$')
}

function Format-GSVendorName([string]$Manufacturer){
 $m=ConvertTo-GSCleanText $Manufacturer
 if(Test-GSPlaceholderText $m){return ''}
 $map=[ordered]@{'(?i)^asustek|^asus'='ASUS';'(?i)^hewlett|^hp\b'='HP';'(?i)^lenovo'='Lenovo';'(?i)^dell'='Dell';'(?i)^acer'='Acer';'(?i)^micro-star|^msi\b'='MSI';'(?i)^gigabyte'='Gigabyte';'(?i)^huawei'='Huawei';'(?i)^honor'='Honor';'(?i)^timi|^xiaomi'='Xiaomi';'(?i)^samsung'='Samsung';'(?i)^apple'='Apple';'(?i)^microsoft'='Microsoft';'(?i)^toshiba|^dynabook'='Toshiba';'(?i)^sony'='Sony';'(?i)^fujitsu'='Fujitsu';'(?i)^medion'='Medion';'(?i)^chuwi'='Chuwi';'(?i)^razer'='Razer';'(?i)^machenike'='Machenike';'(?i)^thunderobot'='Thunderobot'}
 foreach($pattern in $map.Keys){if($m -match $pattern){return $map[$pattern]}}
 return ($m -replace '(?i),?\s*(inc\.?|corporation|corp\.?|co\.?,?\s*ltd\.?|ltd\.?|llc\.?|gmbh|computer)\b','').Trim(' ',',','.')
}

function Format-GSModelName([string]$Manufacturer,[string]$Model,[string]$Version='',[string]$Board='',[string]$ComputerName=''){
 # "Vivobook Go E1504FA_E1504FA" -> "ASUS Vivobook Go E1504FA". Lenovo keeps the
 # marketing name in Version ("IdeaPad 3 15IAU7") and a type code in Model.
 $vendor=Format-GSVendorName $Manufacturer
 $name=ConvertTo-GSCleanText $Model
 if($vendor -eq 'Lenovo' -and -not (Test-GSPlaceholderText $Version) -and $Version -match '[A-Za-z]{3,}'){$name=ConvertTo-GSCleanText $Version}
 $name=($name -replace '\s*\([^)]{16,}\)','').Trim()
 if(Test-GSPlaceholderText $name){$name=''}
 if($name -match '^(.+?)_([A-Za-z0-9-]+)$'){$head=$Matches[1];$tail=$Matches[2];if($head.Contains($tail)){$name=$head}}
 if(-not $name){
  $boardText=ConvertTo-GSCleanText $Board
  # Chinese X79/X99 boards put a chipset essay in brackets:
  # "X79 (INTEL Xeon E5/Corei7 DMI2 - C600/C200 Cipset)" -> "X79". Short codes like "(MS-7C95)" stay.
  $boardText=($boardText -replace '\s*\([^)]{16,}\)','').Trim()
  if(-not (Test-GSPlaceholderText $boardText)){$name=$boardText}
 }
 if($name -and $vendor -and $name -notmatch ('^(?i)'+[regex]::Escape($vendor))){$name=$vendor+' '+$name}
 elseif(-not $name -and $vendor){$name=$vendor}
 if(-not $name){$name=if($ComputerName){'Компьютер '+$ComputerName}else{'Компьютер без маркировки модели'}}
 return $name.Trim()
}

function Format-GSCpuName([string]$Name,[int]$Cores=0,[int]$Threads=0){
 $clean=ConvertTo-GSCleanText $Name
 $clean=$clean -replace '(?i)\s+CPU\b','' -replace '(?i)\s*@\s*[\d.]+\s*GHz','' -replace '(?i)\s+\d+-Core Processor','' -replace '(?i)\s+with Radeon( Vega)? Graphics','' -replace '(?i)\s+Processor$',''
 $clean=$clean.Trim()
 $layout=if($Cores -gt 0){' ('+$Cores+' '+(Get-GSRussianPlural $Cores 'ядро' 'ядра' 'ядер')+$(if($Threads -gt 0){' / '+$Threads+' '+(Get-GSRussianPlural $Threads 'поток' 'потока' 'потоков')}else{''})+')'}else{''}
 if($clean -match '(?i)^Genuine Intel\s*0+$|^Intel\s*0+$' -or $clean -match '(?i)^Genuine Intel$'){return 'Intel, инженерный образец'+$layout}
 if(-not $clean){return 'Процессор не определён'}
 return $clean+$layout
}

function Get-GSRussianPlural([int]$Number,[string]$One,[string]$Few,[string]$Many){
 $n=[Math]::Abs($Number)%100;$last=$n%10
 if($n -ge 11 -and $n -le 14){return $Many}
 if($last -eq 1){return $One}
 if($last -ge 2 -and $last -le 4){return $Few}
 return $Many
}

function Test-GSIntegratedGpu([string]$Name){
 if($Name -match '(?i)nvidia|geforce|quadro|rtx|gtx'){return $false}
 if($Name -match '(?i)\bArc\s*A\d{3}|\bArc\s*B\d{3}'){return $false}
 if($Name -match '(?i)intel'){return $true}
 if($Name -match '(?i)radeon\s*(\(tm\)\s*)?(graphics|vega|\d{3}M)\b' -and $Name -notmatch '(?i)\bRX\b|radeon pro'){return $true}
 return $false
}

function Format-GSGpuList([object[]]$Adapters){
 $items=New-Object System.Collections.Generic.List[object]
 foreach($adapter in @($Adapters)){
  if($null -eq $adapter){continue}
  $name=ConvertTo-GSCleanText ([string]$adapter.Name)
  if(-not $name -or $name -match '(?i)microsoft basic|remote display|virtual|parsec|dameware|citrix|meta virtual'){continue}
  $integrated=Test-GSIntegratedGpu $name
  $memory=[double]0;if($adapter.PSObject.Properties['MemoryBytes']){$memory=[double]$adapter.MemoryBytes}
  $label=$name
  if(-not $integrated -and $memory -ge 512MB){
   $gb=[Math]::Round($memory/1GB)
   if($gb -ge 1 -and $label -notmatch '(?i)\b\d+\s*GB\b'){$label=$label+' '+$gb+'GB'}
  }
  if($integrated){$label=$label+' (встроенная)'}
  $items.Add([pscustomobject]@{Label=$label;Integrated=$integrated})
 }
 $ordered=@($items|Sort-Object @{Expression={$_.Integrated}},@{Expression={$_.Label}})
 if(-not $ordered.Count){return 'Не определено'}
 return (@($ordered|ForEach-Object{$_.Label}) -join ' + ')
}

function Get-GSMemoryTypeName([int]$SmbiosType,[int]$Speed=0){
 $map=@{18='DDR';19='DDR2';20='DDR2 FB';24='DDR3';26='DDR4';27='LPDDR';28='LPDDR2';29='LPDDR3';30='LPDDR4';34='DDR5';35='LPDDR5'}
 if($map.ContainsKey($SmbiosType)){return $map[$SmbiosType]}
 if($Speed -ge 4800){return 'DDR5'}elseif($Speed -ge 2133){return 'DDR4'}elseif($Speed -ge 800){return 'DDR3'}
 return ''
}

function Get-GSMemoryVendor([string]$Manufacturer,[string]$PartNumber=''){
 $m=([string]$Manufacturer).Trim()
 $jedec=@{'80CE'='Samsung';'CE00'='Samsung';'80AD'='SK Hynix';'AD00'='SK Hynix';'802C'='Micron';'2C00'='Micron';'859B'='Crucial';'9B05'='Crucial';'0198'='Kingston';'9801'='Kingston';'029E'='Corsair';'9E02'='Corsair';'04CD'='G.Skill';'CD04'='G.Skill';'04CB'='ADATA';'CB04'='ADATA';'0B83'='Patriot';'8551'='Qimonda';'0443'='Ramaxel';'4304'='Ramaxel';'051B'='Teamgroup';'1B05'='Teamgroup';'8A45'='CXMT';'1315'='CXMT'}
 $key=($m -replace '^0x','' -replace '\s','').ToUpperInvariant()
 if($key.Length -ge 4 -and $jedec.ContainsKey($key.Substring(0,4))){$vendor=$jedec[$key.Substring(0,4)]}
 elseif(-not (Test-GSPlaceholderText $m) -and $m -notmatch '^(?i)[0-9A-F]{4,}$'){$vendor=ConvertTo-GSCleanText $m}
 else{$vendor=''}
 $part=([string]$PartNumber).Trim()
 $series=''
 if($part -match '(?i)^CMK'){$series='Vengeance LPX'}elseif($part -match '(?i)^CM[WGH]'){$series='Vengeance RGB'}elseif($part -match '(?i)^CMS'){$series='Vengeance SODIMM'}
 elseif($part -match '(?i)^F[45]-.*(TZ|TR)'){$series='Trident Z'}elseif($part -match '(?i)^F[45]-.*(RS|GVK|GIS)'){$series='Ripjaws'}
 elseif($part -match '(?i)^KF[3-6]|^HX[3-6]'){$series='Fury'}elseif($part -match '(?i)^BL[S]?\d'){$series='Ballistix'}
 if(-not $vendor -and $series){$vendor=switch -Regex ($part){'(?i)^CM'{'Corsair'}'(?i)^F[45]-'{'G.Skill'}'(?i)^(KF|HX)'{'Kingston'}'(?i)^BL'{'Crucial'}default{''}}}
 return (@($vendor,$series)|Where-Object{$_}) -join ' '
}

function Format-GSMemory([object[]]$Modules){
 $list=@($Modules|Where-Object{$null -ne $_ -and [double]$_.Capacity -gt 0})
 if(-not $list.Count){return 'Не определено'}
 $totalGb=[Math]::Round((($list|Measure-Object -Property Capacity -Sum).Sum)/1GB)
 $sizes=@($list|ForEach-Object{[Math]::Round([double]$_.Capacity/1GB)})
 $layout=if(@($sizes|Select-Object -Unique).Count -eq 1){[string]$sizes.Count+'x'+[string]$sizes[0]}else{($sizes -join '+')}
 $speed=@($list|ForEach-Object{[int]$(if([int]$_.ConfiguredClockSpeed -gt 0){$_.ConfiguredClockSpeed}else{$_.Speed})}|Where-Object{$_ -gt 0}|Measure-Object -Minimum).Minimum
 $type=Get-GSMemoryTypeName ([int]$list[0].SMBIOSMemoryType) ([int]$speed)
 $vendors=@($list|ForEach-Object{Get-GSMemoryVendor ([string]$_.Manufacturer) $(if($_.PSObject.Properties['PartNumber']){[string]$_.PartNumber}else{''})}|Where-Object{$_}|Select-Object -Unique)
 $parts=@(([string]$totalGb+'GB'),$type,('('+$layout+')'))
 if($vendors.Count -eq 1){$parts+=$vendors[0]}
 if($speed -gt 0){$parts+=([string]$speed+'MHz')}
 return (@($parts|Where-Object{$_}) -join ' ')
}

function Format-GSDiskSize([double]$Bytes){
 $gb=$Bytes/1e9
 if($gb -ge 999){$tb=[Math]::Round($gb/1000,1);return ($(if($tb -eq [Math]::Floor($tb)){[string][int]$tb}else{$tb.ToString([Globalization.CultureInfo]::InvariantCulture)})+'TB')}
 return ([string][Math]::Round($gb)+'GB')
}

function Format-GSStorage([object[]]$Disks){
 # Internal drives only: a USB enclosure (BusType 7) is not part of the laptop.
 $internal=@($Disks|Where-Object{$null -ne $_ -and [int]$_.BusType -notin @(1,6,7,12,13,14) -and [double]$_.Size -gt 1GB})
 if(-not $internal.Count){return 'Не определено'}
 $ordered=@($internal|Sort-Object @{Expression={-not [bool]$_.IsSystem}},@{Expression={-[double]$_.Size}})
 $labels=foreach($disk in $ordered){
  $model=ConvertTo-GSCleanText ([string]$disk.FriendlyName)
  $model=$model -replace '(?i)^SAMSUNG\b','Samsung' -replace '(?i)^KINGSTON\b','Kingston' -replace '(?i)^WDC\b','WD' -replace '(?i)^TOSHIBA\b','Toshiba' -replace '(?i)\s+NVMe$',''
  $model=$model -replace '-[0-9A-Z]{5,8}$',''
  $model=$model -replace '(?i)\s+\d+(\.\d+)?\s*(GB?|TB?)$',''
  $bus=[int]$disk.BusType;$media=[int]$disk.MediaType
  $kind=if($bus -eq 17){'NVMe SSD'}elseif($media -eq 4){'SATA SSD'}elseif($media -eq 3){'HDD'}elseif($model -match '(?i)ssd|nvme'){'SSD'}else{'накопитель'}
  ($model+' '+(Format-GSDiskSize ([double]$disk.Size))+' '+$kind).Trim()
 }
 return (@($labels) -join ' + ')
}

function Get-GSPanelVendor([string]$Code){
 $map=@{CMN='Innolux';BOE='BOE';AUO='AU Optronics';LGD='LG Display';SHP='Sharp';SDC='Samsung Display';SEC='Samsung';IVO='InfoVision';CSO='CSOT';NCP='Panda';KDB='Kyocera';CMO='Chimei';LEN='Lenovo';APP='Apple';DEL='Dell';ACR='Acer';AUS='ASUS';SAM='Samsung';GSM='LG';HWP='HP';PHL='Philips';AOC='AOC';BNQ='BenQ';MSI='MSI';HKC='HKC';VSC='ViewSonic'}
 if($map.ContainsKey($Code)){return $map[$Code]}
 return $Code
}

function ConvertFrom-GSEdid([byte[]]$Edid){
 # Header, PNP vendor, product code, physical size and the preferred timing.
 if($null -eq $Edid -or $Edid.Length -lt 128){return $null}
 if(-not ($Edid[0] -eq 0 -and $Edid[1] -eq 255 -and $Edid[7] -eq 0)){return $null}
 $vendorBits=([int]$Edid[8] -shl 8) -bor [int]$Edid[9]
 $vendor=-join @([char](64+(($vendorBits -shr 10) -band 31)),[char](64+(($vendorBits -shr 5) -band 31)),[char](64+($vendorBits -band 31)))
 $product='{0:X4}' -f (([int]$Edid[11] -shl 8) -bor [int]$Edid[10])
 $widthCm=[int]$Edid[21];$heightCm=[int]$Edid[22]
 $name='';$text='';$width=0;$height=0;$refresh=0
 for($offset=54;$offset -le 108;$offset+=18){
  $clock=([int]$Edid[$offset+1] -shl 8) -bor [int]$Edid[$offset]
  if($clock -gt 0){
   if($width -eq 0){
    $width=[int]$Edid[$offset+2] -bor (([int]$Edid[$offset+4] -shr 4) -shl 8)
    $hBlank=[int]$Edid[$offset+3] -bor (([int]$Edid[$offset+4] -band 15) -shl 8)
    $height=[int]$Edid[$offset+5] -bor (([int]$Edid[$offset+7] -shr 4) -shl 8)
    $vBlank=[int]$Edid[$offset+6] -bor (([int]$Edid[$offset+7] -band 15) -shl 8)
    $total=($width+$hBlank)*($height+$vBlank)
    if($total -gt 0){$refresh=[Math]::Round(($clock*10000.0)/$total)}
   }
   continue
  }
  $tag=[int]$Edid[$offset+3]
  $raw=[Text.Encoding]::ASCII.GetString($Edid,$offset+5,13)
  $value=($raw -split "`n")[0].Trim()
  if($tag -eq 0xFC -and $value){$name=$value}
  elseif($tag -eq 0xFE -and $value -and -not $text){$text=$value}
 }
 $diagonal=if($widthCm -gt 0 -and $heightCm -gt 0){[Math]::Round([Math]::Sqrt($widthCm*$widthCm+$heightCm*$heightCm)/2.54,1)}else{0}
 return [pscustomobject]@{Vendor=$vendor;ProductCode=$product;Name=$name;PanelText=$text;Width=$width;Height=$height;Refresh=$refresh;DiagonalInches=$diagonal}
}

function Format-GSDisplay([object[]]$Panels){
 $list=@($Panels|Where-Object{$null -ne $_})
 if(-not $list.Count){return 'Не определено'}
 $ordered=@($list|Sort-Object @{Expression={-not [bool]$_.Internal}})
 $labels=foreach($panel in $ordered){
  $parts=@()
  if([double]$panel.DiagonalInches -gt 5){$parts+=(([double]$panel.DiagonalInches).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)+'"')}
  if([int]$panel.Width -gt 0){$parts+=([string]$panel.Width+'×'+[string]$panel.Height)}
  if([int]$panel.Refresh -gt 0){$parts+=([string]$panel.Refresh+' Гц')}
  $maker=Get-GSPanelVendor ([string]$panel.Vendor)
  $model=@($panel.PanelText,$panel.Name)|Where-Object{$_ -and $_ -notmatch '^(?i)(lcd|led|edp|panel)$'}|Select-Object -First 1
  $identity=(@($maker,$model)|Where-Object{$_}) -join ' '
  if(-not $model -and $panel.ProductCode){$identity=$identity+' (код '+$panel.Vendor+$panel.ProductCode+')'}
  $prefix=if([bool]$panel.Internal){''}else{'Монитор: '}
  $spec=($parts -join ' ')
  $prefix+((@($spec,$identity)|Where-Object{$_}) -join ', ')
 }
 return (@($labels) -join ' + ')
}

function Format-GSBoardName([string]$Manufacturer,[string]$Product){
 # "Micro-Star International Co., Ltd." + "B550M PRO-VDH (MS-7C95)" -> "MSI B550M PRO-VDH (MS-7C95)"
 $product=ConvertTo-GSCleanText $Product
 if(Test-GSPlaceholderText $product){return 'Не определено'}
 $vendor=Format-GSVendorName $Manufacturer
 if(-not $vendor){$vendor=ConvertTo-GSCleanText $Manufacturer;if(Test-GSPlaceholderText $vendor){$vendor=''}}
 if($vendor -and $product -notmatch ('^(?i)'+[regex]::Escape($vendor))){return ($vendor+' '+$product)}
 return $product
}

# ---------------------------------------------------------------------------
# Battery telemetry trust. Cheap and Chinese controllers often report
# FullChargeCapacity == DesignCapacity and a placeholder serial number; that is
# not "100% healthy", it is "the controller does not measure". The serial
# itself is only inspected at collection time and never stored or shown.
function Test-GSPlaceholderSerial([string]$Serial){
 $s=([string]$Serial).Trim()
 if(-not $s){return $false}                       # empty: unknown, not evidence of a fake
 $compact=($s -replace '[\s\-_.:]','')
 if($compact -match '(?i)^(unknown|n/?a|na|none|null|default|serial(number)?|sn|0x0+|to ?be ?filled.*|not ?specified|empty)$'){return $true}
 if($compact.Length -lt 3){return $true}
 if($compact -match '^(.)\1+$'){return $true}      # 0000, 1111, FFFF
 if($compact -match '^0+\d{1,2}$'){return $true}   # 00001, 0001
 foreach($seq in @('0123456789','123456789','12345678','1234567','987654321','98765432','abcdef')){
  if($compact.ToLowerInvariant() -eq $seq -or $compact.ToLowerInvariant() -eq $seq.Substring(0,[Math]::Min($seq.Length,$compact.Length)) -and $compact.Length -ge 5){return $true}
 }
 return $false
}

function Get-GSBatteryAssessment($Battery){
 # Status: Absent | Invalid | Unconfirmed | Confirmed. Reasons are client-facing.
 $result=[ordered]@{Status='Absent';Reasons=@();HealthPercent=-1;Full=0.0;Design=0.0;Voltage=0.0;Cycles=0;DisplayEqual=$false;Unit='';FullShown='';DesignShown=''}
 if($null -eq $Battery -or -not [bool]$Battery.Present){return [pscustomobject]$result}
 $design=[double]$Battery.DesignCapacity;$full=[double]$Battery.FullChargeCapacity
 $voltage=0.0;if($Battery.PSObject.Properties['DesignVoltage']){$voltage=[double]$Battery.DesignVoltage}
 $result.Full=$full;$result.Design=$design;$result.Voltage=$voltage;$result.Cycles=[int]$Battery.CycleCount
 $inv=[Globalization.CultureInfo]::InvariantCulture
 if($design -gt 0 -and $full -gt 0){
  if($voltage -ge 3000 -and $voltage -le 30000){
   $result.Unit='mAh';$result.FullShown=([Math]::Round($full*1000/$voltage)).ToString('#,0',$inv).Replace(',',' ');$result.DesignShown=([Math]::Round($design*1000/$voltage)).ToString('#,0',$inv).Replace(',',' ')
  }else{
   $result.Unit='Вт·ч';$result.FullShown=($full/1000).ToString('0.#',$inv);$result.DesignShown=($design/1000).ToString('0.#',$inv)
  }
  # Equal after mWh->mAh conversion and rounding is NOT the same as equal raw values.
  $result.DisplayEqual=($result.FullShown -eq $result.DesignShown)
 }
 $serialSuspect=($Battery.PSObject.Properties['SerialSuspect'] -and [bool]$Battery.SerialSuspect)
 if($design -le 0 -or $full -le 0){
  $result.Status='Invalid';$result.Reasons=@('контроллер не сообщает ёмкость')
 }elseif($design -lt 5000 -or $design -gt 250000 -or $full -gt $design*1.25 -or $full -lt $design*0.05){
  $result.Status='Invalid';$result.Reasons=@('значения ёмкости неправдоподобны')
 }else{
  $reasons=@()
  if($full -eq $design){$reasons+='полная ёмкость точно равна паспортной'}
  if($full -gt $design*1.05){$reasons+='полная ёмкость больше паспортной'}
  if($serialSuspect){$reasons+='серийный номер аккумулятора — заглушка'}
  if($reasons.Count){$result.Status='Unconfirmed';$result.Reasons=$reasons}
  else{
   $result.Status='Confirmed'
   # Floor: rounding must never turn 99.7% into a "perfect" 100%.
   $result.HealthPercent=[int][Math]::Min(100,[Math]::Floor($full*100/$design))
  }
 }
 return [pscustomobject]$result
}

function Get-GSBatteryList($Battery){
 return @(@($Battery)|Where-Object{$null -ne $_ -and $_.PSObject.Properties['Present'] -and [bool]$_.Present})
}

function Get-GSBatteryVerdict([int]$Health){
 if($Health -ge 85){'хорошее'}elseif($Health -ge 70){'нормальное'}elseif($Health -ge 50){'заметный износ'}else{'требует замены'}
}

function Format-GSBatteryOne($Battery,[switch]$Legacy){
 $a=Get-GSBatteryAssessment $Battery
 $parts=@()
 switch($a.Status){
  'Confirmed'{
   if($Legacy){
    $inv=[Globalization.CultureInfo]::InvariantCulture
    $parts+=([string]$a.HealthPercent+'% ёмкости ('+(Get-GSBatteryVerdict $a.HealthPercent)+'), износ '+[string](100-$a.HealthPercent)+'%')
    $parts+=($a.Full.ToString('#,0',$inv).Replace(',',' ')+' из '+$a.Design.ToString('#,0',$inv).Replace(',',' ')+' мВт·ч')
   }else{
    $parts+=($a.FullShown+' из '+$a.DesignShown+' '+$a.Unit)
    $parts+=('состояние '+[string]$a.HealthPercent+'% ('+(Get-GSBatteryVerdict $a.HealthPercent)+')')
    if($a.DisplayEqual){$parts+='значения округлены при пересчёте в '+$a.Unit}
   }
  }
  'Unconfirmed'{
   $parts+='Данные не подтверждены'
   $parts+=('контроллер сообщает '+$a.FullShown+' из '+$a.DesignShown+' '+$a.Unit+' (отчёт Windows)')
   $parts+=('причина: '+($a.Reasons -join '; '))
  }
  default{
   $parts+='Данные не подтверждены'
   $parts+=('причина: '+($a.Reasons -join '; '))
  }
 }
 if($a.Cycles -gt 0){$parts+=$(if($Legacy){'циклов: '}else{'циклов заряда: '})+[string]$a.Cycles}
 if($Legacy -and $Battery.PSObject.Properties['ChargePercent'] -and [int]$Battery.ChargePercent -ge 0){$parts+=('заряд '+[string]$Battery.ChargePercent+'%')}
 return ($parts -join $(if($Legacy){', '}else{' · '}))
}

function Format-GSBattery($Battery){
 $list=@(Get-GSBatteryList $Battery)
 if(-not $list.Count){return 'Нет (настольный ПК или аккумулятор не обнаружен)'}
 if($list.Count -eq 1){return (Format-GSBatteryOne $list[0] -Legacy)}
 $i=0;return (@($list|ForEach-Object{$i++;'АКБ '+$i+': '+(Format-GSBatteryOne $_ -Legacy)}) -join ' + ')
}

function Get-GSBatteryHealth($Battery){
 # Only confirmed telemetry yields a health figure; any doubt -> -1 (no bar, no verdict).
 $list=@(Get-GSBatteryList $Battery)
 if(-not $list.Count){return -1}
 $values=@()
 foreach($b in $list){$a=Get-GSBatteryAssessment $b;if($a.Status -ne 'Confirmed'){return -1};$values+=$a.HealthPercent}
 return [int](($values|Measure-Object -Minimum).Minimum)
}

function Get-GSBatteryTrust($Battery){
 $list=@(Get-GSBatteryList $Battery)
 if(-not $list.Count){return 'Absent'}
 $states=@($list|ForEach-Object{(Get-GSBatteryAssessment $_).Status})
 if($states -contains 'Invalid'){return 'Invalid'}
 if($states -contains 'Unconfirmed'){return 'Unconfirmed'}
 return 'Confirmed'
}

function Format-GSPower($Battery){
 # Laptop: capacity in mAh (Windows reports mWh; mAh needs the design voltage),
 # health and charge cycles. Desktop: Windows has no data about the PSU.
 $list=@(Get-GSBatteryList $Battery)
 if(-not $list.Count){return 'Не определяется программно · модель и мощность — на наклейке блока питания'}
 if($list.Count -eq 1){return (Format-GSBatteryOne $list[0])}
 $i=0;return (@($list|ForEach-Object{$i++;'АКБ '+$i+': '+(Format-GSBatteryOne $_)}) -join ' + ')
}

function Invoke-GSSummaryPart([scriptblock]$Block){
 # One broken source must not empty the whole first page.
 try{$value=& $Block;if($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)){return 'Не определено'};return $value}catch{return 'Не определено'}
}

function New-GSSystemSummary($Raw){
 # Builds the ordered first-page summary from Get-GSSummaryRaw output.
 $batteries=if($Raw.PSObject.Properties['Batteries'] -and @($Raw.Batteries).Count){@($Raw.Batteries)}else{@($Raw.Battery)}
 $kind=if(@(Get-GSBatteryList $batteries).Count -or [int]$Raw.PcSystemType -eq 2){'Ноутбук'}else{'Компьютер'}
 $model=Format-GSModelName ([string]$Raw.Manufacturer) ([string]$Raw.Model) ([string]$Raw.Version) ([string]$Raw.Board) ([string]$Raw.ComputerName)
 return [pscustomobject][ordered]@{
  Kind=$kind
  Model=$model
  Processor=Invoke-GSSummaryPart {Format-GSCpuName ([string]$Raw.CpuName) ([int]$Raw.Cores) ([int]$Raw.Threads)}
  Graphics=Invoke-GSSummaryPart {Format-GSGpuList @($Raw.Gpus)}
  Motherboard=Invoke-GSSummaryPart {if($Raw.PSObject.Properties['BoardProduct']){Format-GSBoardName ([string]$Raw.BoardManufacturer) ([string]$Raw.BoardProduct)}else{''}}
  Memory=Invoke-GSSummaryPart {Format-GSMemory @($Raw.MemoryModules)}
  Storage=Invoke-GSSummaryPart {Format-GSStorage @($Raw.Disks)}
  Display=Invoke-GSSummaryPart {Format-GSDisplay @($Raw.Panels)}
  Battery=Invoke-GSSummaryPart {Format-GSBattery $batteries}
  Power=Invoke-GSSummaryPart {Format-GSPower $batteries}
  BatteryHealth=$(try{Get-GSBatteryHealth $batteries}catch{-1})
  BatteryTrust=$(try{Get-GSBatteryTrust $batteries}catch{'Invalid'})
 }
}

function ConvertTo-GSSafeFileName([string]$Name){
 $clean=($Name -replace '\s*\([^)]{16,}\)','' -replace '[\\/:*?"<>|]',' ' -replace '\s+',' ').Trim(' ','.')
 if($clean.Length -gt 60){$clean=$clean.Substring(0,60);$cut=$clean.LastIndexOf(' ');if($cut -gt 20){$clean=$clean.Substring(0,$cut)}}
 $clean=($clean -replace '\s*\([^)]*$','').Trim(' ','.','-')
 if(-not $clean){$clean='Компьютер'}
 return $clean
}

function Get-GSCimRawValue($Object,[string]$Name){
 # Raw CIM value: once the Storage module is loaded (Get-Partition), Windows
 # PowerShell shows MSFT_PhysicalDisk.BusType as "NVMe" and MediaType as "SSD"
 # instead of numbers, and [int] on those strings broke the whole summary.
 if($null -eq $Object){return $null}
 try{$cim=$Object.CimInstanceProperties;if($null -ne $cim -and $null -ne $cim[$Name]){return $cim[$Name].Value}}catch{}
 $property=$Object.PSObject.Properties[$Name]
 if($null -eq $property){return $null}
 return $property.Value
}

function ConvertTo-GSStorageCode($Value,[ValidateSet('Bus','Media')][string]$Kind){
 if($null -eq $Value){return 0}
 $text=([string]$Value).Trim()
 $number=0
 if([int]::TryParse($text,[ref]$number)){return $number}
 $map=if($Kind -eq 'Bus'){@{'SCSI'=1;'ATAPI'=2;'ATA'=3;'1394'=4;'SSA'=5;'Fibre Channel'=6;'USB'=7;'RAID'=8;'iSCSI'=9;'SAS'=10;'SATA'=11;'SD'=12;'MMC'=13;'Virtual'=14;'File Backed Virtual'=15;'Storage Spaces'=16;'NVMe'=17;'SCM'=18;'UFS'=19}}else{@{'Unspecified'=0;'HDD'=3;'SSD'=4;'SCM'=5}}
 foreach($key in $map.Keys){if([string]::Equals($key,$text,[StringComparison]::OrdinalIgnoreCase)){return [int]$map[$key]}}
 return 0
}

# ---------------------------------------------------------------------------
# Collection (Windows only). Every source is optional; failures leave gaps
# that the formatters render as "Не определено" instead of breaking the report.
function Get-GSSummaryRaw {
 function Get-GSCimSafe([string]$Class,[string]$Namespace='root/cimv2',[string]$Filter=''){
  try{$q=@{ClassName=$Class;Namespace=$Namespace;OperationTimeoutSec=8;ErrorAction='Stop'};if($Filter){$q.Filter=$Filter};return @(Get-CimInstance @q)}catch{return @()}
 }
 $computer=@(Get-GSCimSafe Win32_ComputerSystem)|Select-Object -First 1
 $product=@(Get-GSCimSafe Win32_ComputerSystemProduct)|Select-Object -First 1
 $board=@(Get-GSCimSafe Win32_BaseBoard)|Select-Object -First 1
 $cpu=@(Get-GSCimSafe Win32_Processor)|Select-Object -First 1
 $cpuName=''
 try{$cpuName=[string](Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop).ProcessorNameString}catch{}
 if(-not $cpuName -and $cpu){$cpuName=[string]$cpu.Name}

 $gpus=New-Object System.Collections.Generic.List[object]
 $classKey='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
 $registryMemory=@{}
 try{
  foreach($key in @(Get-ChildItem -LiteralPath $classKey -ErrorAction Stop|Where-Object{$_.PSChildName -match '^\d{4}$'})){
   $props=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
   if(-not $props){continue}
   $desc=[string]$props.DriverDesc
   $bytes=[double]0
   if($props.PSObject.Properties['HardwareInformation.qwMemorySize']){$bytes=[double]$props.'HardwareInformation.qwMemorySize'}
   elseif($props.PSObject.Properties['HardwareInformation.MemorySize']){$raw=$props.'HardwareInformation.MemorySize';if($raw -is [byte[]]){$bytes=[double][BitConverter]::ToUInt32($raw,0)}else{$bytes=[double]$raw}}
   if($desc -and $bytes -gt $registryMemory[$desc]){$registryMemory[$desc]=$bytes}
  }
 }catch{}
 foreach($adapter in @(Get-GSCimSafe Win32_VideoController)){
  if($null -eq $adapter){continue}
  $name=[string]$adapter.Name
  $memory=if($registryMemory.ContainsKey($name)){$registryMemory[$name]}else{try{[double]$adapter.AdapterRAM}catch{0}}
  $gpus.Add([pscustomobject]@{Name=$name;MemoryBytes=$memory})
 }

 $memoryModules=@(Get-GSCimSafe Win32_PhysicalMemory|ForEach-Object{[pscustomobject]@{Capacity=[double]$_.Capacity;SMBIOSMemoryType=[int]$_.SMBIOSMemoryType;ConfiguredClockSpeed=[int]$_.ConfiguredClockSpeed;Speed=[int]$_.Speed;Manufacturer=[string]$_.Manufacturer;PartNumber=[string]$_.PartNumber}})

 $systemDiskNumber=-1
 try{$systemDiskNumber=[int](Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop).DiskNumber}catch{}
 $disks=@()
 try{$disks=@(Get-GSCimSafe MSFT_PhysicalDisk 'root/Microsoft/Windows/Storage'|ForEach-Object{[pscustomobject]@{FriendlyName=[string]$_.FriendlyName;Size=[double](Get-GSCimRawValue $_ 'Size');BusType=(ConvertTo-GSStorageCode (Get-GSCimRawValue $_ 'BusType') 'Bus');MediaType=(ConvertTo-GSStorageCode (Get-GSCimRawValue $_ 'MediaType') 'Media');IsSystem=([string](Get-GSCimRawValue $_ 'DeviceId') -eq [string]$systemDiskNumber)}})}catch{}

 $panels=New-Object System.Collections.Generic.List[object]
 $connections=@{}
 foreach($connection in @(Get-GSCimSafe WmiMonitorConnectionParams 'root/wmi')){try{$connections[[string]$connection.InstanceName]=[int64]$connection.VideoOutputTechnology}catch{}}
 foreach($monitor in @(Get-GSCimSafe WmiMonitorID 'root/wmi' 'Active=TRUE')){
  try{
  $instance=[string]$monitor.InstanceName
  # int64 on purpose: in Windows PowerShell 0x80000000 is a negative int32 and
  # [uint32]0x80000000 throws - that broke the whole summary on every PC.
  $technology=if($connections.ContainsKey($instance)){[int64]$connections[$instance]}else{[int64]-1}
  $internal=($technology -in @([int64]6,[int64]11,[int64]13,[int64]2147483648))
  $edid=$null
  try{
   $path='HKLM:\SYSTEM\CurrentControlSet\Enum\'+($instance -replace '_\d+$','')+'\Device Parameters'
   $edid=[byte[]](Get-ItemProperty -LiteralPath $path -ErrorAction Stop).EDID
  }catch{}
  $parsed=ConvertFrom-GSEdid $edid
  if($null -eq $parsed){
   $parsed=[pscustomobject]@{Vendor=(-join ($monitor.ManufacturerName|Where-Object{$_}|ForEach-Object{[char]$_}));ProductCode=(-join ($monitor.ProductCodeID|Where-Object{$_}|ForEach-Object{[char]$_}));Name=(-join ($monitor.UserFriendlyName|Where-Object{$_}|ForEach-Object{[char]$_}));PanelText='';Width=0;Height=0;Refresh=0;DiagonalInches=0}
  }
  $parsed|Add-Member -NotePropertyName Internal -NotePropertyValue $internal -Force
  $panels.Add($parsed)
  }catch{}
 }

 # Every battery (some laptops have two). The serial number is read only to
 # judge whether it is a placeholder; it is never stored, returned or shown.
 $batteries=New-Object System.Collections.Generic.List[object]
 $wmiBatteries=@(Get-GSCimSafe Win32_Battery)
 if($wmiBatteries.Count){
  $reportNodes=@()
  $report=Join-Path ([IO.Path]::GetTempPath()) ('gs-battery-'+[guid]::NewGuid().ToString('N')+'.xml')
  try{
   $null=& (Join-Path $env:WINDIR 'System32\powercfg.exe') /batteryreport /xml /output $report 2>&1
   if(Test-Path -LiteralPath $report){[xml]$xml=Get-Content -LiteralPath $report -Raw -Encoding UTF8;$reportNodes=@($xml.GetElementsByTagName('Battery'))}
  }catch{}finally{Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue}
  $staticNodes=@();$fullNodes=@()
  if(-not $reportNodes.Count){$staticNodes=@(Get-GSCimSafe BatteryStaticData 'root/wmi');$fullNodes=@(Get-GSCimSafe BatteryFullChargedCapacity 'root/wmi')}
  $count=[Math]::Max($wmiBatteries.Count,[Math]::Max($reportNodes.Count,$staticNodes.Count))
  for($i=0;$i -lt $count;$i++){
   $b=[pscustomobject]@{Present=$true;DesignCapacity=0.0;FullChargeCapacity=0.0;CycleCount=0;ChargePercent=-1;DesignVoltage=0.0;SerialSuspect=$false;Source=''}
   if($i -lt $wmiBatteries.Count){try{$b.ChargePercent=[int]$wmiBatteries[$i].EstimatedChargeRemaining;$b.DesignVoltage=[double]$wmiBatteries[$i].DesignVoltage}catch{}}
   elseif($wmiBatteries.Count){try{$b.DesignVoltage=[double]$wmiBatteries[0].DesignVoltage}catch{}}
   $serial=''
   if($i -lt $reportNodes.Count){
    $node=$reportNodes[$i]
    try{$b.DesignCapacity=[double]$node.DesignCapacity;$b.FullChargeCapacity=[double]$node.FullChargeCapacity;if($node.CycleCount){$b.CycleCount=[int]$node.CycleCount};$serial=[string]$node.SerialNumber;$b.Source='powercfg'}catch{}
   }elseif($i -lt $staticNodes.Count){
    try{$b.DesignCapacity=[double]$staticNodes[$i].DesignedCapacity;$serial=[string]$staticNodes[$i].SerialNumber;$b.Source='wmi'}catch{}
    if($i -lt $fullNodes.Count){try{$b.FullChargeCapacity=[double]$fullNodes[$i].FullChargedCapacity}catch{}}
   }
   $b.SerialSuspect=(Test-GSPlaceholderSerial $serial)
   $serial=$null
   $batteries.Add($b)
  }
 }
 $battery=if($batteries.Count){$batteries[0]}else{[pscustomobject]@{Present=$false;DesignCapacity=0;FullChargeCapacity=0;CycleCount=0;ChargePercent=-1}}

 return [pscustomobject]@{
  Manufacturer=[string]$(if($computer){$computer.Manufacturer}else{''})
  Model=[string]$(if($computer){$computer.Model}else{''})
  Version=[string]$(if($product){$product.Version}else{''})
  BoardManufacturer=[string]$(if($board){$board.Manufacturer}else{''})
  BoardProduct=[string]$(if($board){$board.Product}else{''})
  Board=[string]$(if($board){(@($board.Manufacturer,$board.Product)|Where-Object{$_ -and -not (Test-GSPlaceholderText ([string]$_))}) -join ' '}else{''})
  ComputerName=[Environment]::MachineName
  PcSystemType=[int]$(if($computer){$computer.PCSystemType}else{0})
  CpuName=$cpuName;Cores=[int]$(if($cpu){$cpu.NumberOfCores}else{0});Threads=[int]$(if($cpu){$cpu.NumberOfLogicalProcessors}else{0})
  Gpus=@($gpus.ToArray());MemoryModules=$memoryModules;Disks=$disks;Panels=@($panels.ToArray());Battery=$battery;Batteries=@($batteries.ToArray())
 }
}
