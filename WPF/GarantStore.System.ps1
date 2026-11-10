$script:gsSystemCache=@{Profile=$null}
. (Join-Path $PSScriptRoot 'GarantStore.SystemSummary.ps1')
function Get-GSSystemSummaryRows($Profile){
 # First page of the report and the first card: what an ordinary user recognises.
 $summary=$null;if($Profile -and $Profile.PSObject.Properties['summary']){$summary=$Profile.summary}
 $part={param([string]$Name,$Default='Не определено')if($summary -and $summary.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string]$summary.$Name)){[string]$summary.$Name}else{$Default}}
 $boardFallback=Format-GSBoardName ([string]$Profile.boardManufacturer) ([string]$Profile.boardModel)
 if($null -eq $summary){
  $model=Format-GSModelName ([string]$Profile.manufacturer) ([string]$Profile.model) '' ([string]$Profile.boardModel) ([Environment]::MachineName)
  $rows=[ordered]@{
   'Тип и модель'=$model
   'Процессор (CPU)'=(Format-GSCpuName ([string]$Profile.processor) 0 0)
   'Материнская плата'=$boardFallback
   'Оперативная память (RAM)'=$(if([double]$Profile.memoryBytes -gt 0){[string][math]::Round([double]$Profile.memoryBytes/1GB)+'GB'}else{'Не определено'})
  }
  if($Profile.PSObject.Properties['summaryError'] -and $Profile.summaryError){$rows['Примечание']='Подробная сводка не собрана: '+[string]$Profile.summaryError}
  return [pscustomobject]$rows
 }
 $isLaptop=([string]$summary.Kind -eq 'Ноутбук')
 $power=& $part 'Power' $(if($isLaptop){& $part 'Battery'}else{'Не определяется программно · модель и мощность — на наклейке блока питания'})
 return [pscustomobject][ordered]@{
  'Тип и модель'=([string]$summary.Kind+' '+[string]$summary.Model)
  'Процессор (CPU)'=(& $part 'Processor')
  'Видеокарта (GPU)'=(& $part 'Graphics')
  'Материнская плата'=(& $part 'Motherboard' $boardFallback)
  'Оперативная память (RAM)'=(& $part 'Memory')
  'Накопитель (SSD / HDD)'=(& $part 'Storage')
  $(if($isLaptop){'Аккумулятор'}else{'Блок питания (PSU)'})=$power
  $(if($isLaptop){'Матрица'}else{'Монитор'})=(& $part 'Display')
 }
}
function Get-GSSummaryIcon([string]$Label,[string]$Value){
 $paths=switch -Regex ($Label){
  '^Процессор'{'<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx=".8"/><path d="M9 2.5v3M12 2.5v3M15 2.5v3M9 18.5v3M12 18.5v3M15 18.5v3M2.5 9h3M2.5 12h3M2.5 15h3M18.5 9h3M18.5 12h3M18.5 15h3"/>'}
  '^Видеокарта'{'<rect x="2.5" y="6.5" width="17" height="10" rx="1.6"/><circle cx="8.5" cy="11.5" r="3"/><circle cx="8.5" cy="11.5" r=".7"/><path d="M13.5 9.5h3.5M13.5 11.5h3.5M13.5 13.5h3.5M19.5 9h2v5h-2M5.5 16.5V19M8.5 16.5V19M11.5 16.5V19"/>'}
  '^Материнская'{'<rect x="3" y="3" width="18" height="18" rx="2"/><rect x="6" y="6" width="6" height="6" rx="1"/><path d="M15 6v6M17.5 6v6M6 15.5h12M6 18h7"/><circle cx="17" cy="17.8" r="1"/>'}
  '^Оперативная'{'<rect x="2.5" y="7" width="19" height="8" rx="1.2"/><path d="M5.5 9.5h2.5v3H5.5zM10.75 9.5h2.5v3h-2.5zM16 9.5h2.5v3H16zM4.5 15v2.5M7.5 15v2.5M10.5 15v2.5M13.5 15v2.5M16.5 15v2.5M19.5 15v2.5"/>'}
  '^Накопитель'{if($Value -match 'HDD' -and $Value -notmatch 'SSD'){'<rect x="4" y="2.5" width="16" height="19" rx="2"/><circle cx="12" cy="10" r="4.5"/><circle cx="12" cy="10" r=".9"/><path d="M12 10l3.2 6M7 18.5h3"/>'}else{'<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 9h7M7 12h4.5"/><circle cx="16.5" cy="14.5" r="1.2"/><path d="M6 19v1.5M9 19v1.5M12 19v1.5"/>'}}
  '^Аккумулятор'{'<rect x="2.5" y="7" width="17" height="10" rx="2"/><path d="M21.5 10.5v3"/><path d="M11.5 9l-2.5 3.2h3L9.5 15"/>'}
  '^Блок питания'{'<rect x="2.5" y="5" width="19" height="14" rx="1.8"/><circle cx="9" cy="12" r="4"/><path d="M9 8.5v7M5.5 12h7M6.6 9.6l4.8 4.8M11.4 9.6l-4.8 4.8M15.5 9h3M15.5 12h3M15.5 15h3"/>'}
  '^(Матрица|Монитор)'{'<rect x="2.5" y="4" width="19" height="12.5" rx="1.6"/><path d="M8.5 20.5h7M12 16.5v4"/>'}
  default{'<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>'}
 }
 return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+$paths+'</svg>'
}
function New-GSSummaryHtml($Rows,$Profile){
 # Vector-minimal first page: one tile per component with a line icon.
 $enc={param([string]$t)[Net.WebUtility]::HtmlEncode($t)}
 $health=-1
 if($Profile -and $Profile.PSObject.Properties['summary'] -and $Profile.summary -and $Profile.summary.PSObject.Properties['BatteryHealth']){$health=[int]$Profile.summary.BatteryHealth}
 $b=[Text.StringBuilder]::new()
 [void]$b.AppendLine('<div class="tiles">')
 foreach($row in $Rows.PSObject.Properties){
  $label=[string]$row.Name;$value=[string]$row.Value
  if($label -in @('Тип и модель','Матрица','Монитор')){continue}
  if([string]::IsNullOrWhiteSpace($value)){$value='Не определено'}
  $main=$value;$subs=@()
  if($label -match '^Процессор' -and $value -match '^(.*?)\s*\((.+)\)$'){$main=$Matches[1];$subs=@($Matches[2])}
  elseif($value -match ' \+ '){$parts=@($value -split ' \+ ');$main=$parts[0];$subs=@($parts|Select-Object -Skip 1)}
  elseif($value -match ' · '){$parts=@($value -split ' · ');$main=$parts[0];$subs=@($parts|Select-Object -Skip 1)}
  $class=if($label -eq 'Примечание'){'tile note'}else{'tile'}
  [void]$b.Append('<div class="'+$class+'"><div class="ico">'+(Get-GSSummaryIcon $label $value)+'</div><div class="txt"><div class="k">'+(& $enc $label)+'</div><div class="v">'+(& $enc $main)+'</div>')
  foreach($sub in $subs){[void]$b.Append('<div class="s">'+(& $enc ([string]$sub))+'</div>')}
  if($label -eq 'Аккумулятор' -and $health -ge 0){[void]$b.Append('<div class="bar" title="Состояние '+$health+'%"><i style="width:'+$health+'%"></i></div>')}
  [void]$b.AppendLine('</div></div>')
 }
 [void]$b.AppendLine('</div>')
 return $b.ToString()
}
function Get-GSSystemDisplayName($Profile){
 if($Profile -and $Profile.PSObject.Properties['summary'] -and $Profile.summary){return [string]$Profile.summary.Model}
 return Format-GSModelName ([string]$Profile.manufacturer) ([string]$Profile.model) '' ([string]$Profile.boardModel) ([Environment]::MachineName)
}
function Get-GSSystemValue($Object,[string]$Name) {
 if($null -eq $Object){return 'Не определено'}
 $p=$Object.PSObject.Properties[$Name]
 if(-not $p -or $null -eq $p.Value -or [string]::IsNullOrWhiteSpace([string]$p.Value)){return 'Не определено'}
 return $p.Value
}
function Get-GSSystemCards($Profile,[scriptblock]$GetValue) {
 $cards=New-Object System.Collections.Generic.List[object]
 $summaryRows=Get-GSSystemSummaryRows $Profile
 $cards.Add([pscustomobject]@{Title='Сводка';Text=(@($summaryRows.PSObject.Properties|ForEach-Object{$_.Name+': '+[string]$_.Value}) -join "`n")})
 $cards.Add([pscustomobject]@{Title='Компьютер';Text=((& $GetValue $Profile 'manufacturer'),(& $GetValue $Profile 'model'),('Плата: '+(& $GetValue $Profile 'boardModel')),('BIOS/UEFI: '+(& $GetValue $Profile 'biosVersion'))) -join "`n"})
 $cards.Add([pscustomobject]@{Title='Процессор и память';Text=((& $GetValue $Profile 'processor'),('Ядра: '+(& $GetValue $Profile 'cores')+' • потоки: '+(& $GetValue $Profile 'logicalProcessors')),('RAM: '+$(if($Profile.memoryBytes -gt 0){[math]::Round($Profile.memoryBytes/1GB,1).ToString()+' ГБ'}else{'Не определено'}))) -join "`n"})
 $cards.Add([pscustomobject]@{Title='Windows';Text=((& $GetValue $Profile 'edition'),('Build '+(& $GetValue $Profile 'build')+' • '+(& $GetValue $Profile 'osArchitecture')),('PowerShell '+(& $GetValue $Profile 'powerShell'))) -join "`n"})
 foreach($gpu in @($Profile.gpu)){$cards.Add([pscustomobject]@{Title='Видеосистема';Text=([string]$gpu.name+"`nДрайвер: "+[string]$gpu.driverVersion+"`nДата: "+[string]$gpu.driverDate)})}
 foreach($disk in @($Profile.disks)){$cards.Add([pscustomobject]@{Title='Накопитель';Text=([string]$disk.model+"`n"+[math]::Round($disk.sizeBytes/1GB,1)+' ГБ • интерфейс: '+[string]$disk.interface+"`nТип SSD/HDD: не определён")})}
 $cards.Add([pscustomobject]@{Title='Драйверы';Text=('Установленных: '+(& $GetValue $Profile 'installedDriverCount')+"`nПроблемных устройств: "+(& $GetValue $Profile 'problemDeviceCount'))})
 $services=& $GetValue $Profile 'services'
 $cards.Add([pscustomobject]@{Title='Службы';Text=(@($services|ForEach-Object{if($_ -is [string]){$_}else{[string]$_.name+': '+[string]$_.status}}) -join "`n")})
 $history=& $GetValue $Profile 'history'
 $cards.Add([pscustomobject]@{Title='История диагностики';Text=(@($history|Select-Object -First 5|ForEach-Object{if($_ -is [string]){$_}else{[string]$_.capturedUtc+' • проблем: '+[string]$_.problemCount}}) -join "`n")})
 return $cards.ToArray()
}
function Set-GSSystemProfile($State,$Profile,[scriptblock]$FormatCards,[scriptblock]$GetValue) {
 $State.Profile=$Profile
 $State.Cache.Profile=$Profile
 $detailLabels=[ordered]@{operatingSystem='Windows';processors='Процессоры';motherboard='Материнская плата';firmware='BIOS / UEFI';memoryModules='Модули памяти';physicalDisks='Физические накопители';volumes='Разделы';graphics='Видеокарты';monitors='Мониторы';network='Сеть';audio='Аудио';peripheral='Периферия'}
 $detailLines=foreach($key in $detailLabels.Keys){
  $detailLabels[$key]
  $entries=@($Profile.details.$key|Where-Object{$null -ne $_})
  if(-not $entries.Count){'  Не определено'}
  foreach($entry in $entries){
   foreach($property in $entry.PSObject.Properties){
    $value=if($null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)){'Не определено'}else{[string]$property.Value}
    '  '+$property.Name+': '+$value
   }
   ''
  }
  ''
 }
 $State.Detail.Text=$detailLines -join [Environment]::NewLine
 $State.Cards.ItemsSource=@(& $FormatCards $Profile $GetValue)
 $State.Text=(@($State.Cards.ItemsSource|ForEach-Object{$_.Title+"`r`n"+$_.Text}) -join "`r`n`r`n")
 $State.Status.Text='Сведения получены: '+[string]$Profile.capturedUtc
 $State.Copy.IsEnabled=$true;$State.Export.IsEnabled=$true
}
function Export-GSSystemProfile($State,[string]$Path,[bool]$FullReport) {
 if(-not $State.Profile){throw 'Сведения ещё не получены.'}
 $snapshot=[ordered]@{schemaVersion=1}
 foreach($field in @('capturedUtc','manufacturer','model','machineType','boardManufacturer','boardModel','biosVersion','processor','processorManufacturer','cores','logicalProcessors','memoryBytes','windows','edition','displayVersion','build','osArchitecture','powerShell','windowsUpdateService','installedDriverCount','problemDeviceCount','services','collectionMs','summary','details')){
  $property=$State.Profile.PSObject.Properties[$field]
  if($property){$snapshot[$field]=$property.Value}
 }
 if($FullReport){$snapshot.computerName=[Environment]::MachineName}
 $sections=[ordered]@{
  'Сводка'=@(Get-GSSystemSummaryRows $State.Profile)
  'Windows'=@([pscustomobject][ordered]@{'Система'=$snapshot.edition;'Версия'=$snapshot.displayVersion;'Сборка'=$snapshot.build})
  'Драйверы'=@([pscustomobject]@{Установлено=$snapshot.installedDriverCount;Проблемных=$snapshot.problemDeviceCount})
  'Системные службы'=@($snapshot.services)
 }
 $labels=[ordered]@{operatingSystem='Операционная система';processors='Процессоры';motherboard='Материнская плата';firmware='BIOS / UEFI';memoryModules='Модули памяти';physicalDisks='Физические накопители';volumes='Разделы';graphics='Видеокарты';monitors='Мониторы';network='Сетевые адаптеры';audio='Аудио';peripheral='Периферия'}
 foreach($key in $labels.Keys){$sections[$labels[$key]]=@($snapshot.details.$key)}
 if($FullReport){$sections['Идентификация']=@([pscustomobject]@{Имя_ПК=$snapshot.computerName})}
 $extension=[IO.Path]::GetExtension($Path).ToLowerInvariant()
 if($extension -eq '.json'){
  $document=ConvertTo-Json -InputObject $snapshot -Depth 12
 }else{
  $content=[Text.StringBuilder]::new()
  $nav=[Text.StringBuilder]::new()
  $number=0
  $html=$extension -eq '.html'
  [void]$content.AppendLine($(if($html){''}else{"Garant Store — $($snapshot.capturedUtc)"}))
  foreach($title in $sections.Keys){
   $number++
   $rows=@($sections[$title]|Where-Object{$null -ne $_})
   if($html){
    $heading=[Net.WebUtility]::HtmlEncode($title)
    [void]$nav.AppendLine("<a href='#section-$number'>$heading</a>")
    [void]$content.AppendLine("<section id='section-$number'><h2>$heading</h2>")
   }else{[void]$content.AppendLine("\r\n$title")}
   if($html -and $title -eq 'Сводка'){[void]$content.AppendLine((New-GSSummaryHtml $rows[0] $State.Profile));[void]$content.AppendLine('</section>');continue}
   if(-not $rows.Count){[void]$content.AppendLine('Не определено')}
   foreach($row in $rows){
    if($html){[void]$content.AppendLine('<table><tbody>')}
    foreach($field in $row.PSObject.Properties){
     $value=if($null -eq $field.Value -or [string]::IsNullOrWhiteSpace([string]$field.Value)){'Не определено'}else{[string]$field.Value}
     if($html){
      $label=[Net.WebUtility]::HtmlEncode($field.Name)
      $escaped=[Net.WebUtility]::HtmlEncode($value)
      [void]$content.AppendLine("<tr><th scope='row'>$label</th><td>$escaped</td></tr>")
     }else{[void]$content.AppendLine("$($field.Name): $value")}
    }
    if($html){[void]$content.AppendLine('</tbody></table>')}else{[void]$content.AppendLine()}
   }
   if($html){[void]$content.AppendLine('</section>')}
  }
  if($html){
   $date=[Net.WebUtility]::HtmlEncode(([datetime]$snapshot.capturedUtc).ToLocalTime().ToString('dd.MM.yyyy HH:mm'))
   $systemName=[Net.WebUtility]::HtmlEncode((Get-GSSystemDisplayName $State.Profile))
   $summaryRows=Get-GSSystemSummaryRows $State.Profile
   $kindText=if([string]$summaryRows.'Тип и модель' -match '^Ноутбук'){'Ноутбук'}else{'Компьютер'}
   $screenProperty=@($summaryRows.PSObject.Properties|Where-Object{$_.Name -in @('Матрица','Монитор')})|Select-Object -First 1
   $screenLine=if($screenProperty -and [string]$screenProperty.Value -and [string]$screenProperty.Value -ne 'Не определено'){'<span class="chip">'+(Get-GSSummaryIcon 'Монитор' '')+[Net.WebUtility]::HtmlEncode(([string]$screenProperty.Value -replace '^(Матрица|Монитор):\s*',''))+'</span>'}else{''}
   $document=@"
<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$systemName · Garant Store</title>
<style>
:root{color-scheme:dark;--bg:#0e1211;--panel:#151c18;--tile:#18201c;--text:#eef5ef;--muted:#a9b8ae;--accent:#70e2aa;--line:#2c3b33;--ring:#2f6b4a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 "Segoe UI",system-ui,sans-serif}
main{max-width:1080px;margin:auto;padding:clamp(16px,4vw,44px)}
header{padding-bottom:18px;margin-bottom:18px;border-bottom:1px solid var(--line)}
.brand{font:600 12px/1 Bahnschrift,"Segoe UI",sans-serif;letter-spacing:.18em;text-transform:uppercase;color:var(--accent)}
h1{font:700 clamp(26px,4vw,38px)/1.15 Oswald,Bahnschrift,"Segoe UI",sans-serif;margin:.35em 0 .3em;letter-spacing:.01em}
h2{font:600 18px/1.2 Oswald,Bahnschrift,"Segoe UI",sans-serif;letter-spacing:.06em;text-transform:uppercase;margin:0 0 12px;color:var(--text)}
.meta{display:flex;flex-wrap:wrap;gap:8px;align-items:center;color:var(--muted);font-size:13px}
.chip{display:inline-flex;gap:6px;align-items:center;border:1px solid var(--line);border-radius:999px;padding:4px 11px;color:var(--text)}.chip svg{width:15px;height:15px;color:var(--accent)}
.chip.k1{border-color:var(--ring);color:var(--accent)}
p{color:var(--muted)}nav{display:flex;flex-wrap:wrap;gap:6px;margin:18px 0}
nav a{color:var(--muted);text-decoration:none;border:1px solid var(--line);border-radius:8px;padding:4px 10px;font-size:13px}nav a:hover{color:var(--accent);border-color:var(--ring)}
section{margin:16px 0;padding:18px;background:var(--panel);border:1px solid var(--line);border-radius:14px}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:12px}
.tile{display:flex;gap:14px;align-items:flex-start;padding:16px;background:var(--tile);border:1px solid var(--line);border-radius:14px;break-inside:avoid}
.tile.note{grid-column:1/-1;border-style:dashed}
.ico{flex:none;width:46px;height:46px;border-radius:12px;display:grid;place-items:center;color:var(--accent);border:1px solid var(--ring);background:rgba(112,226,170,.06)}.ico svg{width:26px;height:26px}
.txt{min-width:0}.k{font:600 11px/1.3 Bahnschrift,"Segoe UI",sans-serif;letter-spacing:.09em;text-transform:uppercase;color:var(--muted)}
.v{font-size:17px;font-weight:600;margin-top:4px;overflow-wrap:anywhere}.s{color:var(--muted);font-size:13px;margin-top:2px;overflow-wrap:anywhere}
.bar{height:4px;border-radius:2px;background:var(--line);margin-top:9px;max-width:220px}.bar i{display:block;height:100%;border-radius:2px;background:var(--accent)}
table{width:100%;table-layout:fixed;border-collapse:collapse;margin:10px 0}th,td{text-align:left;vertical-align:top;padding:6px 8px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{width:40%;color:var(--muted);font-weight:500}
@page{size:A4;margin:12mm}@media print{:root{color-scheme:light;--bg:#fff;--panel:#fff;--tile:#fff;--text:#111;--muted:#444;--accent:#13603e;--line:#d5ddd8;--ring:#13603e}main{padding:0}nav{display:none}section{padding:0;border:0}#section-1{break-after:page}h2{break-after:avoid}tr{break-inside:avoid}.ico{background:none}}
</style><main><header><div class="brand">Garant Store · системный отчёт</div><h1>$systemName</h1><div class="meta"><span class="chip k1">$kindText</span>$screenLine<span>$date</span></div></header><nav aria-label="Оглавление">$nav</nav>$content</main></html>
"@
  }else{$document=$content.ToString()}
 }
 [IO.File]::WriteAllText($Path,$document,[Text.UTF8Encoding]::new($true))
}
function Start-GSSystemRefresh($State) {
 if($State.Process){return}
 $State.Refresh.IsEnabled=$false;$State.Status.Text='Определяем конфигурацию компьютера…'
 $State.File=Join-Path ([IO.Path]::GetTempPath()) ('gs-system-'+[guid]::NewGuid().ToString('N')+'.json')
 $args='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $State.Root 'GarantStore.SystemWorker.ps1')+'" -OutputPath "'+$State.File+'"'
 try{$State.Process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -PassThru;$State.Started=[datetime]::UtcNow;$State.Timer.Start()}
 catch{$State.Status.Text=$_.Exception.Message;$State.Refresh.IsEnabled=$true}
}
function New-GSSystemPage([string]$ProjectRoot) {
 [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Моя система — Garant Store" AutomationProperties.AutomationId="GarantStoreSystemWindow" Width="960" Height="650" MinWidth="620" MinHeight="420" Background="#101613" Foreground="#EDF4EF" WindowStartupLocation="CenterScreen">
<Window.Resources><Style TargetType="Button"><Setter Property="Padding" Value="14,8"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Background" Value="#26392D"/><Setter Property="Foreground" Value="#EDF4EF"/></Style></Window.Resources>
<Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<StackPanel><TextBlock Text="Моя система" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="Оборудование, Windows и последние диагностики" Foreground="#A5B8AC" Margin="0,6,0,16"/></StackPanel>
<WrapPanel Grid.Row="1"><CheckBox x:Name="FullSystemReport" Content="Включить имя ПК в отчёт" Foreground="#EDF4EF" Margin="0,9,12,0"/><Button x:Name="RefreshSystem" Content="Обновить"/><Button x:Name="CopySystem" Content="Копировать характеристики" IsEnabled="False"/><Button x:Name="ExportSystem" Content="Экспорт отчёта" IsEnabled="False"/></WrapPanel>
<TabControl Grid.Row="2" Background="#101613"><TabItem Header="Обзор"><ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><ItemsControl x:Name="SystemCards"><ItemsControl.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ItemsControl.ItemsPanel><ItemsControl.ItemTemplate><DataTemplate><Border Width="265" MinHeight="130" Padding="16" Margin="0,0,12,12" Background="#1A241E" BorderBrush="#34483B" BorderThickness="1" CornerRadius="10"><StackPanel><TextBlock Text="{Binding Title}" Foreground="#91D5A5" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/><TextBlock Text="{Binding Text}" Foreground="#EDF4EF" TextWrapping="Wrap" FontSize="13"/></StackPanel></Border></DataTemplate></ItemsControl.ItemTemplate></ItemsControl></ScrollViewer></TabItem><TabItem Header="Подробно"><TextBox x:Name="SystemDetail" IsReadOnly="True" Background="#1A241E" Foreground="#EDF4EF" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></TabItem></TabControl>
<TextBlock x:Name="SystemStatus" Grid.Row="3" Text="Нажмите «Обновить»" Foreground="#A5B8AC" TextWrapping="Wrap" Margin="0,8,0,0"/>
</Grid></Window>
'@
 $reader=[Xml.XmlNodeReader]::new($x);try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
 $state=@{Cache=$script:gsSystemCache;Detail=$window.FindName('SystemDetail');Full=$window.FindName('FullSystemReport');Window=$window;Root=$ProjectRoot;Profile=$null;Text='';Process=$null;File='';Started=[datetime]::MinValue;Timer=[Windows.Threading.DispatcherTimer]::new();Cards=$window.FindName('SystemCards');Status=$window.FindName('SystemStatus');Copy=$window.FindName('CopySystem');Export=$window.FindName('ExportSystem');Refresh=$window.FindName('RefreshSystem')}
 if($state.Cache.Profile){Set-GSSystemProfile $state $state.Cache.Profile ${function:Get-GSSystemCards} ${function:Get-GSSystemValue}}
 $window.Tag=$state;$state.Timer.Interval=[TimeSpan]::FromMilliseconds(250)
 $refreshProfile=${function:Start-GSSystemRefresh}
 $applyProfile=${function:Set-GSSystemProfile}
 $formatCards=${function:Get-GSSystemCards}
 $getValue=${function:Get-GSSystemValue}
 $exportProfile=${function:Export-GSSystemProfile}
 $displayName=${function:Get-GSSystemDisplayName}
 $safeFileName=${function:ConvertTo-GSSafeFileName}
 $state.Refresh.Add_Click({& $refreshProfile $state}.GetNewClosure())
 $state.Copy.Add_Click({try{[Windows.Clipboard]::SetText($state.Text);$state.Status.Text='Характеристики скопированы'}catch{$state.Status.Text=$_.Exception.Message}}.GetNewClosure())
 $state.Export.Add_Click({try{$d=[Microsoft.Win32.SaveFileDialog]::new();$d.Title='Garant Store: экспорт отчёта';$d.Filter='HTML|*.html|Текст|*.txt|JSON|*.json';$d.FileName=('Garant-System - '+(& $safeFileName (& $displayName $state.Profile))+'.html');if($d.ShowDialog($state.Window)){& $exportProfile $state $d.FileName ([bool]$state.Full.IsChecked);$state.Status.Text='Отчёт сохранён'}}catch{$state.Status.Text=$_.Exception.Message}}.GetNewClosure())
 $state.Timer.Add_Tick({
  if(-not $state.Process){return}
  try{
   if(-not $state.Process.HasExited){if(([datetime]::UtcNow-$state.Started).TotalSeconds -lt 40){return};$state.Process.Kill();throw 'Сбор сведений превысил 40 секунд. Предыдущий результат сохранён.'}
   $state.Timer.Stop();$data=Get-Content -LiteralPath $state.File -Raw -Encoding UTF8|ConvertFrom-Json
   if($data.PSObject.Properties['error']){throw [string]$data.error}
   & $applyProfile $state $data $formatCards $getValue
  }catch{$state.Status.Text=$_.Exception.Message}
  finally{if($state.Process -and $state.Process.HasExited){$state.Timer.Stop();$state.Process.Dispose();$state.Process=$null;$state.Refresh.IsEnabled=$true;Remove-Item -LiteralPath $state.File -Force -ErrorAction SilentlyContinue}}
 }.GetNewClosure())
 $window.Add_Closed({$state.Timer.Stop();if($state.Process){if(-not $state.Process.HasExited){$state.Process.Kill()};$state.Process.Dispose()};if($state.File){Remove-Item -LiteralPath $state.File -Force -ErrorAction SilentlyContinue}}.GetNewClosure())
 return $window
}
function Show-GSSystemPage {
 try{
  $existing=$win.OwnedWindows|Where-Object{$_.Tag -is [hashtable] -and $_.Tag.ContainsKey('Cards')}|Select-Object -First 1
  if($existing){[void]$existing.Activate();return}
  $page=New-GSSystemPage $root;$page.Owner=$win;$page.Show();if(-not $page.Tag.Profile){Start-GSSystemRefresh $page.Tag}
 }catch{$Status.Text='Не удалось открыть сведения: '+$_.Exception.Message}
}
