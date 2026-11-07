[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,UIAutomationClient,UIAutomationTypes,System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GSDriverUiInput {
 [DllImport("user32.dll",SetLastError=true)] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll",SetLastError=true)] public static extern void mouse_event(UInt32 flags,UInt32 dx,UInt32 dy,UInt32 data,UIntPtr extraInfo);
}
'@
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Drivers.ps1')
. (Join-Path $project 'DriverEngine\UpdateCatalog.ps1')
[xml]$xml=Get-Content -LiteralPath (Join-Path $project 'DriverWindow.xaml') -Raw -Encoding UTF8
$reader=New-Object System.Xml.XmlNodeReader($xml)
$window=[Windows.Markup.XamlReader]::Load($reader);$reader.Close()
$pairs=@(@('DriverState','driverState'),@('DriverDetail','driverDetail'),@('DriverProgress','driverProgress'),@('DriverDeviceCount','driverDeviceCount'),@('DriverDevices','driverDevices'),@('DriverLog','driverLog'),@('DriverHint','driverHint'),@('DriverScan','driverScan'),@('DriverSelectionActions','driverSelectionActions'),@('DriverInstall','driverInstall'),@('DriverDownload','driverDownload'),@('DriverSource','driverSource'),@('DriverNetwork','driverNetwork'),@('DriverLocal','driverLocal'),@('DriverRestore','driverRestore'),@('DriverWuRepair','driverWuRepair'),@('DriverCancel','driverCancel'),@('DriverSelectAll','driverSelectAll'),@('DriverOpenFolder','driverOpenFolder'),@('DriverDiagnostics','driverDiagnostics'),@('DriverClose','driverClose'),@('DriverViewAll','driverViewAll'),@('DriverViewComponents','driverViewComponents'),@('DriverToggleLog','driverToggleLog'),@('DriverLogPanel','driverLogPanel'),@('DriverLogColumn','driverLogColumn'),@('DriverLogSpacer','driverLogSpacer'),@('DriverEmptyMessage','driverEmptyMessage'))
foreach($pair in $pairs){Set-Variable -Scope Script -Name $pair[1] -Value $window.FindName($pair[0])}
$script:driverActionBusy=$false
$script:driverSelectionActions.Visibility=[Windows.Visibility]::Collapsed
$script:driverViewMode='attention';$script:driverLastSnapshot=$null
$script:driverDevices.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,[System.Windows.RoutedEventHandler]{Update-GSDriverActionVisibility $true $script:driverActionBusy},$true)
$script:driverSelectAll.Add_Click({Toggle-GSDriverSelection})
$script:driverViewAll.Add_Click({if($script:driverViewMode -eq 'inventory'){Set-GSDriverViewMode 'attention'}else{Set-GSDriverViewMode 'inventory'}})
$script:driverViewComponents.Add_Click({if($script:driverViewMode -eq 'components'){Set-GSDriverViewMode 'attention'}else{Set-GSDriverViewMode 'components'}})
$script:driverToggleLog.Add_Click({Toggle-GSDriverLogPanel})
$rows=@(
 [pscustomobject]@{instanceId='TEST\MISSING';name='Mock missing driver';kind='Missing';hwid='PCI\VEN_1234&DEV_0001';canSelect=$true;Selected=$false;reason='Driver missing'},
 (ConvertTo-GSWuaDriverRow ([pscustomobject]@{Identity=[pscustomobject]@{UpdateID='test-update';RevisionNumber=1};Title='Mock confirmed update';DriverHardwareID='PCI\VEN_1234&DEV_0002';DriverClass='OtherHardware';EulaAccepted=$true})),
 [pscustomobject]@{instanceId='TEST\INVENTORY';name='Mock installed driver';kind='Inventory';hwid='PCI\VEN_1234&DEV_0003';canSelect=$false;Selected=$false;reason='Actuality unknown'},
 [pscustomobject]@{instanceId='LIBRARY|unknown';name='Mock optional library';kind='Library';libraryId='';canSelect=$false;Selected=$false;libraryStatus='Невозможно определить';reason='No proven dependency'}
)
$snapshot=[pscustomobject]@{
 status=[pscustomobject]@{running=$false;phase='Готово';message='Изолированная проверка отображения';percent=100}
 scanned=$true;devices=$rows;logs=@()
}
$rows[1].PSObject.Properties.Remove('canSelect') # Legacy candidate-140 payload: no selection capability field.
Apply-GSDriverSnapshot $snapshot
$window.Title='Driver selection UI test'
$window.Width=950;$window.Height=700;$window.ShowInTaskbar=$false
$window.Show();$window.UpdateLayout()
function Find-DriverWindow {
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'Driver selection UI test')
 [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)
}
function Pump-UI {
 [System.Windows.Forms.Application]::DoEvents()
 $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
}
function Get-Checkboxes {
 $root=Find-DriverWindow
 if(-not $root){throw 'Driver window was not exposed to UI Automation.'}
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::CheckBox)
 return ,@($root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition))
}
function Click-Checkbox([System.Windows.Automation.AutomationElement]$Element) {
 if(-not $Element.Current.IsEnabled){throw 'Expected an eligible driver checkbox to be enabled.'}
 $point=$Element.GetClickablePoint()
 [void][GSDriverUiInput]::SetCursorPos([int]$point.X,[int]$point.Y)
 Start-Sleep -Milliseconds 80
 [GSDriverUiInput]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 80
 [GSDriverUiInput]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
 Pump-UI
}
function Get-EnabledCheckboxes {
 $checks=Get-Checkboxes;$enabled=[System.Collections.Generic.List[System.Windows.Automation.AutomationElement]]::new()
 foreach($check in $checks){if($check.Current.IsEnabled){$enabled.Add($check)}}
 return ,$enabled.ToArray()
}
try{
 Pump-UI
 $checks=Get-Checkboxes
 if($checks.Count -ne 2){throw ('Attention view should render only the missing-driver and confirmed-update rows; UI Automation exposed '+$checks.Count)}
 $enabled=Get-EnabledCheckboxes
 if($enabled.Count -ne 2){throw ('Expected exactly 2 selectable repair/update rows; found '+$enabled.Count)}
 $disabled=0;foreach($check in $checks){if(-not $check.Current.IsEnabled){$disabled++}}
 if($disabled -ne 0){throw 'Informational inventory/library rows leaked into the default attention view.'}

 Click-Checkbox $enabled[0]
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 1){throw 'A pointer click did not update the bound Selected property.'}
 if($script:driverSelectionActions.Visibility -ne [Windows.Visibility]::Visible){throw 'Install/download actions did not appear after selecting one eligible row.'}
 Apply-GSDriverSnapshot $snapshot;Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 1){throw 'Selection was lost when refreshed scan data was rebound.'}

 $selectButton=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverSelectAvailable'))
 if(-not $selectButton -or -not $selectButton.Current.IsEnabled){throw 'Select available button is not enabled when eligible rows exist.'}
 $selectButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 2){throw 'Select available did not select every eligible row.'}
 foreach($row in @($script:driverDevices.ItemsSource)){
  if([string]$row.kind -in @('Inventory','Library') -and [bool]$row.Selected){throw ('Select available selected informational row '+$row.instanceId)}
 }
 if([string]$script:driverSelectAll.Content -ne 'Снять выбор'){throw 'Select available did not switch to the clear-selection action.'}
 $selectButton=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverSelectAvailable'))
 $selectButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 0){throw 'Second select-button click did not clear the selection.'}

 $root=Find-DriverWindow
 $installedToggle=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverViewInstalledToggle'))
 $installedToggle.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 $inventoryChecks=Get-Checkboxes
 if($inventoryChecks.Count -ne 1 -or $inventoryChecks[0].Current.IsEnabled){$inventoryEnabled=if($inventoryChecks.Count -gt 0){[string]$inventoryChecks[0].Current.IsEnabled}else{'n/a'};$rowKinds=(@($script:driverDevices.ItemsSource|ForEach-Object{[string]$_.kind}) -join ',');throw ('Installed-driver reference view mismatch: checkboxes='+$inventoryChecks.Count+'; firstEnabled='+$inventoryEnabled+'; mode='+$script:driverViewMode+'; rows='+$rowKinds)}
 $root=Find-DriverWindow
 $componentToggle=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverViewComponentsToggle'))
 $componentToggle.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 $libraryChecks=Get-Checkboxes
 if($libraryChecks.Count -ne 1 -or $libraryChecks[0].Current.IsEnabled){throw 'System component recommendations are not isolated from driver entries.'}
 Set-GSDriverViewMode 'attention';Pump-UI
 $root=Find-DriverWindow
 $logToggle=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverLogToggle'))
 $logToggle.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 if($script:driverLogPanel.Visibility -ne [Windows.Visibility]::Visible -or $script:driverLogColumn.Width.Value -le 0){throw 'The operation journal did not expand on demand.'}
 $root=Find-DriverWindow
 $logToggle=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'DriverLogToggle'))
 $logToggle.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Pump-UI
 if($script:driverLogPanel.Visibility -ne [Windows.Visibility]::Collapsed -or $script:driverLogColumn.Width.Value -ne 0){throw 'The operation journal did not collapse after use.'}

 $keyboardCheck=(Get-EnabledCheckboxes)[1]
 $keyboardCheck.SetFocus();[System.Windows.Forms.SendKeys]::SendWait(' ');Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 1){throw 'Space key did not toggle a focused driver checkbox.'}
 if($script:driverSelectionActions.Visibility -ne [Windows.Visibility]::Visible){throw 'Keyboard selection did not make install/download actions available.'}

 Set-GSDriverViewMode 'components';Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 0){throw 'A driver selection leaked into component actions.'}
 Set-GSDriverViewMode 'attention';Pump-UI
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -ne 1){throw 'Driver selection was lost across categories.'}
 Toggle-GSDriverSelection
 if(@(Get-GSSelectedDriverRows $script:driverDevices.ItemsSource).Count -gt 0){Toggle-GSDriverSelection}
 Pump-UI

 $emptyRows=@($rows|ForEach-Object{$_.Selected=$false;$_})
 $emptySnapshot=[pscustomobject]@{status=[pscustomobject]@{running=$false;phase='Готово';message='Нет доступных обновлений';percent=100};scanned=$true;devices=$emptyRows;logs=@()}
 foreach($row in $emptyRows){$row.canSelect=$false}
 Apply-GSDriverSnapshot $emptySnapshot;Pump-UI
 if($script:driverSelectAll.IsEnabled){throw 'Select available remained enabled with no eligible rows.'}
 if([string]$script:driverSelectAll.Content -ne 'В разделе нет доступных элементов'){throw 'Empty selection state is not explained by the button label.'}
 if($script:driverSelectionActions.Visibility -ne [Windows.Visibility]::Collapsed){throw 'Install/download actions remained visible with no selected eligible row.'}

 $xamlText=Get-Content -LiteralPath (Join-Path $project 'DriverWindow.xaml') -Raw -Encoding UTF8
 if($xamlText -notmatch 'Text="\{Binding name\}" Foreground="#EEF2EE"' -or $xamlText -notmatch 'Text="\{Binding hwid\}"[^>]*Foreground="#B0BBB2"' -or $xamlText -notmatch 'Text="\{Binding reason\}" Foreground="#AAB5AC"' -or $xamlText -notmatch 'HorizontalScrollBarVisibility="Disabled"'){throw 'Driver card text does not explicitly define readable light-theme foreground colors.'}
 Write-Host 'Driver window UI Automation passed: mouse click, keyboard toggle, eligible-only select/clear, action visibility, attention-only default view, separate installed-driver and Windows-component views, disabled horizontal scrolling, empty-state message, category grouping and explicit text colors.'
}catch{Write-Host ('Driver UI automation failure at line '+$_.InvocationInfo.ScriptLineNumber+': '+$_.Exception.Message);Write-Host $_.ScriptStackTrace;throw}finally{try{$window.Close()}catch{}}

