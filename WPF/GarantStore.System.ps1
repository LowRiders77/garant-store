$script:gsSystemCache=@{Profile=$null}
function Get-GSSystemValue($Object,[string]$Name) {
 if($null -eq $Object){return 'Не определено'}
 $p=$Object.PSObject.Properties[$Name]
 if(-not $p -or $null -eq $p.Value -or [string]::IsNullOrWhiteSpace([string]$p.Value)){return 'Не определено'}
 return $p.Value
}
function Get-GSSystemCards($Profile,[scriptblock]$GetValue) {
 $cards=New-Object System.Collections.Generic.List[object]
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
 foreach($field in @('capturedUtc','manufacturer','model','machineType','boardManufacturer','boardModel','biosVersion','processor','processorManufacturer','cores','logicalProcessors','memoryBytes','windows','edition','displayVersion','build','osArchitecture','powerShell','windowsUpdateService','installedDriverCount','problemDeviceCount','services','collectionMs','details')){
  $property=$State.Profile.PSObject.Properties[$field]
  if($property){$snapshot[$field]=$property.Value}
 }
 if($FullReport){$snapshot.computerName=[Environment]::MachineName}
 $sections=[ordered]@{
  'Сводка'=@([pscustomobject]@{Производитель=$snapshot.manufacturer;Модель=$snapshot.model;Процессор=$snapshot.processor;ОЗУ_байт=$snapshot.memoryBytes;Windows=$snapshot.edition;Сборка=$snapshot.build})
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
   $date=[Net.WebUtility]::HtmlEncode([string]$snapshot.capturedUtc)
   $document=@"
<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Garant Store · Системный отчёт</title>
<style>
:root{color-scheme:dark;--bg:#101413;--panel:#1a221e;--text:#eef5ef;--muted:#b7c5bc;--accent:#70e2aa;--line:#3b5145}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,sans-serif}
main{max-width:1060px;margin:auto;padding:clamp(16px,4vw,48px)}header{border-bottom:2px solid var(--accent);margin-bottom:20px;padding-bottom:16px}
h1,h2{margin:.25em 0}p{color:var(--muted)}nav{display:flex;flex-wrap:wrap;gap:8px;margin:20px 0}
a{color:var(--accent);border:1px solid var(--line);border-radius:8px;padding:5px 10px}section{margin:18px 0;padding:16px;background:var(--panel);border:1px solid var(--line);border-radius:12px}
table{width:100%;table-layout:fixed;border-collapse:collapse;margin:12px 0}th,td{text-align:left;vertical-align:top;padding:6px 8px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{width:40%;color:var(--muted)}
@page{size:A4;margin:14mm}@media print{:root{color-scheme:light;--bg:white;--panel:white;--text:#111;--muted:#333;--accent:#13603e;--line:#ccc}main{padding:0}nav{display:none}section{padding:0;border:0}h2{break-after:avoid}tr{break-inside:avoid}}
</style><main><header><h1>Garant Store</h1><p>Системный отчёт · $date</p></header><nav aria-label="Оглавление">$nav</nav>$content</main></html>
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
 $state.Refresh.Add_Click({& $refreshProfile $state}.GetNewClosure())
 $state.Copy.Add_Click({try{[Windows.Clipboard]::SetText($state.Text);$state.Status.Text='Характеристики скопированы'}catch{$state.Status.Text=$_.Exception.Message}}.GetNewClosure())
 $state.Export.Add_Click({try{$d=[Microsoft.Win32.SaveFileDialog]::new();$d.Title='Garant Store: экспорт отчёта';$d.Filter='HTML|*.html|Текст|*.txt|JSON|*.json';$d.FileName='Garant-System.html';if($d.ShowDialog($state.Window)){& $exportProfile $state $d.FileName ([bool]$state.Full.IsChecked);$state.Status.Text='Отчёт сохранён'}}catch{$state.Status.Text=$_.Exception.Message}}.GetNewClosure())
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
