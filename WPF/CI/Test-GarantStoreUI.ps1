[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('search-winget','search-msstore','search-aggregate','consent-accept','consent-decline','consent-cancel','network-error','lifecycle','webview2-install','webview2-installed')][string]$Scenario,
 [string]$InstallRoot=(Join-Path $env:ProgramFiles 'Garant Store Next')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GSCIInput {
 [DllImport("user32.dll", SetLastError=true)]
 public static extern bool SetForegroundWindow(IntPtr hWnd);
 [DllImport("user32.dll", SetLastError=true)]
 public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll", SetLastError=true)]
 public static extern IntPtr GetLastActivePopup(IntPtr hWnd);
 [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
 [DllImport("user32.dll", SetLastError=true)]
 public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll", SetLastError=true)]
 public static extern void mouse_event(UInt32 flags, UInt32 dx, UInt32 dy, UInt32 data, UIntPtr extraInfo);
}
'@
$evidence=Join-Path $PSScriptRoot '..\CI-output\ui'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$metrics=[System.Collections.Generic.List[object]]::new()
$started=[DateTime]::UtcNow
$launcher=Join-Path $InstallRoot 'GarantStore.Launcher.vbs'
if(-not (Test-Path -LiteralPath $launcher)){throw 'Installed WPF launcher not found.'}
if($Scenario -match '^consent-' -or $Scenario -eq 'network-error' -or $Scenario -eq 'search-msstore' -or $Scenario -eq 'search-aggregate'){
 # Reset only this disposable CI runner so the first-use agreement flow is reproducible.
 $reset=@(& winget.exe source reset --force 2>&1);$resetCode=$LASTEXITCODE
 if($resetCode -ne 0){throw ('Isolated source reset failed ('+$resetCode+'): '+($reset -join ' '))}
}
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
$launcherArgs='//B '+[char]34+$launcher+[char]34
function Start-TrackedLauncher {
 $env:GS_WPF_TRACK_LAUNCH='1'
 $env:GS_WPF_STARTUP_TRACE=Join-Path $evidence 'startup-stages.log'
 try{return Start-Process -FilePath $wscript -ArgumentList $launcherArgs -WorkingDirectory $InstallRoot -PassThru}
 finally{Remove-Item Env:GS_WPF_TRACK_LAUNCH,Env:GS_WPF_STARTUP_TRACE -ErrorAction SilentlyContinue}
}
$launchProcess=Start-TrackedLauncher

function Find-ByAutomationId([System.Windows.Automation.AutomationElement]$Root,[string]$Id) {
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)
 return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
}
function Find-Button([System.Windows.Automation.AutomationElement]$Root,[string]$Name) {
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
 $buttons=$Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
 foreach($button in $buttons) {
  if($button.Current.Name -eq $Name) {
   return $button
  }
 }
 return $null
}

function Get-MainWindow {
 $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 foreach($candidate in $windows){
  try{if($candidate.Current.AutomationId -eq 'GarantStoreMainWindow'){return $candidate}}
  catch [System.Windows.Automation.ElementNotAvailableException]{continue}
 }
 return $null
}
function Wait-MainWindow([int]$Seconds=45) {
 $until=[DateTime]::UtcNow.AddSeconds($Seconds)
 $hardDeadline=$until.AddSeconds(45)
 $trace=Join-Path $evidence 'startup-stages.log'
 $lastStage=''
 $windowDeadline=$null
 do{
  $main=Get-MainWindow
  if($main){return $main}
  if($launchProcess.HasExited){break}
  $childIds=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($launchProcess.Id)" -ErrorAction SilentlyContinue|ForEach-Object{$_.ProcessId})
  if(Test-Path -LiteralPath $trace){
   $latest=Get-Content -LiteralPath $trace -Tail 12 -ErrorAction SilentlyContinue|Where-Object{($_ -split ' ')[1] -in $childIds}|Select-Object -Last 1
   if($latest -and $latest -ne $lastStage){
    $lastStage=$latest
    $until=[DateTime]::UtcNow.AddSeconds(25)
    if($latest -match ' main-window-rendered$'){$windowDeadline=[DateTime]::UtcNow.AddSeconds(10)}
   }
  }
  if($windowDeadline -and [DateTime]::UtcNow -ge $windowDeadline){break}
  Start-Sleep -Milliseconds 250
 }while([DateTime]::UtcNow -lt $until -and [DateTime]::UtcNow -lt $hardDeadline)
 $windows=@([System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)|ForEach-Object{
  try{[pscustomobject]@{Title=$_.Current.Name;Id=$_.Current.AutomationId;ProcessId=$_.Current.ProcessId}}catch [System.Windows.Automation.ElementNotAvailableException]{}
 })
 $exitCode=if($launchProcess.HasExited){$launchProcess.ExitCode}else{$null}
 $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($launchProcess.Id)" -ErrorAction SilentlyContinue|Select-Object Name,ProcessId,SessionId)
 $details=[pscustomobject]@{LauncherId=$launchProcess.Id;ExitCode=$exitCode;SessionId=([Diagnostics.Process]::GetCurrentProcess().SessionId);Children=$children;Windows=$windows}
 $details|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence 'startup.json') -Encoding UTF8
 throw ('WPF main window did not appear in UI Automation. '+($details|ConvertTo-Json -Depth 5 -Compress))
}
function Get-Dialog([int]$Seconds=5) {
 $until=[DateTime]::UtcNow.AddSeconds($Seconds)
 $windowCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)
 do {
  $main=Get-MainWindow
  $mainId=''
  $windows=[System.Collections.Generic.List[System.Windows.Automation.AutomationElement]]::new()
  if($main -ne $null) {
   $mainId=($main.GetRuntimeId() -join '.')
   $owned=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants,$windowCondition)
   foreach($candidate in $owned){$windows.Add($candidate)}
  }
  $desktop=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,$windowCondition)
  foreach($candidate in $desktop){$windows.Add($candidate)}
  foreach($candidate in $windows) {
   try{
    $candidateId=($candidate.GetRuntimeId() -join '.')
    $title=$candidate.Current.Name
    $isConsent=($title -match 'Microsoft Store|source agreement')
    $isConfirmation=(($title -eq 'Garant Store') -and ($candidateId -ne $mainId))
    if($isConsent -or $isConfirmation) { return $candidate }
   }catch{}
  }
  Start-Sleep -Milliseconds 200
 } while([DateTime]::UtcNow -lt $until)
 return $null
}

function Invoke-Element([System.Windows.Automation.AutomationElement]$Element) {
 if(-not $Element){throw 'UI Automation target element was not found.'}
 $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Press-Button([System.Windows.Automation.AutomationElement]$Element) {
 if(-not $Element){throw 'UI Automation button was not found.'}
 if(-not $Element.Current.IsEnabled){throw ('Package action button is disabled before click: '+$Element.Current.Name)}
 $mainWindow=Get-MainWindow
 if($mainWindow){[void][GSCIInput]::SetForegroundWindow([IntPtr]$mainWindow.Current.NativeWindowHandle)}
 $point=$Element.GetClickablePoint()
 [void][GSCIInput]::SetCursorPos([int]$point.X,[int]$point.Y)
 Start-Sleep -Milliseconds 150
 [GSCIInput]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 80
 [GSCIInput]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
 $modal=Get-Dialog 8
 if($null -ne $modal){Write-Host ('Opened package confirmation by pointer click: '+$modal.Current.Name);return}
 $fresh=Get-MainWindow
 $button=if($fresh){Find-ByAutomationId $fresh 'InstallSelected'}else{$null}
 $status=if($fresh){Find-ByAutomationId $fresh 'OperationStatus'}else{$null}
 $detail=if($fresh){Find-ByAutomationId $fresh 'OperationDetail'}else{$null}
 if($button -and -not $button.Current.IsEnabled){
  Write-Host ('Package action button became disabled after pointer click; delegating to confirmation waiter. Button='+$button.Current.Name)
  return
 }
 throw ('Package confirmation did not open after pointer click. Button='+$(if($button){$button.Current.Name}else{'<none>'})+'; enabled='+$(if($button){$button.Current.IsEnabled}else{'<none>'})+'; status='+$(if($status){$status.Current.Name}else{'<none>'})+'; detail='+$(if($detail){$detail.Current.Name}else{'<none>'}))
}
function Set-Text([System.Windows.Automation.AutomationElement]$Element,[string]$Value) {
 if(-not $Element){throw 'UI Automation text field was not found.'}
 $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Value)
}
function Set-Source([System.Windows.Automation.AutomationElement]$Main,[string]$Source) {
 $combo=Find-ByAutomationId $Main 'SearchSource'
 if(-not $combo){throw 'Search source ComboBox not found.'}
 $combo.SetFocus()
 [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
 if($Source -eq 'msstore'){[System.Windows.Forms.SendKeys]::SendWait('{DOWN}')}
 if($Source -eq 'winget'){[System.Windows.Forms.SendKeys]::SendWait('{DOWN 2}')}
 [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
 Start-Sleep -Milliseconds 150
}
function Start-Search([System.Windows.Automation.AutomationElement]$Main,[string]$Query,[string]$Source) {
 Set-Source $Main $Source
 Set-Text (Find-ByAutomationId $Main 'SearchQuery') $Query
 Invoke-Element (Find-ByAutomationId $Main 'SearchButton')
}
function Get-SearchEvidence([System.Windows.Automation.AutomationElement]$Main) {
 $count=Find-ByAutomationId $Main 'SearchResultCount'
 $list=Find-ByAutomationId $Main 'SearchResults'
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
 $items=$list.FindAll([System.Windows.Automation.TreeScope]::Children,$condition)
 $names=@();foreach($item in $items){if($item.Current.Name){$names+=$item.Current.Name}}
 return [pscustomobject]@{CountText=$count.Current.Name;Rows=$items.Count;Names=$names}
}
function Find-PackageListItem([System.Windows.Automation.AutomationElement]$List,[string]$PackageId) {
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
 $items=$List.FindAll([System.Windows.Automation.TreeScope]::Children,$condition)
 $observed=[System.Collections.Generic.List[string]]::new()
 foreach($item in $items) {
  $parts=[System.Collections.Generic.List[string]]::new()
  try{if($item.Current.Name){$parts.Add([string]$item.Current.Name)}}catch{}
  try{
   $texts=$item.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))
   foreach($text in $texts){if($text.Current.Name){$parts.Add([string]$text.Current.Name)}}
  }catch{}
  $summary=($parts -join ' | ')
  $observed.Add($summary)
  if($summary -match ('(?i)(?<![A-Za-z0-9._-])'+[regex]::Escape($PackageId)+'(?![A-Za-z0-9._-])')) {
   return [pscustomobject]@{Item=$item;Observed=@($observed.ToArray());Count=$items.Count}
  }
 }
 throw ('Package list item with ID '+$PackageId+' was not exposed by UI Automation. Rows='+($observed -join ' || '))
}

function Select-PackageItem([string]$PackageId) {
 if([string]::IsNullOrWhiteSpace($PackageId)){throw 'Package ID is missing.'}
 $until=[DateTime]::UtcNow.AddSeconds(24)
 $attempts=@('uia-pattern','pointer','keyboard')
 foreach($attempt in $attempts){
  $main=Get-MainWindow
  if(-not $main){throw 'Main window disappeared before selecting package row.'}
  [void][GSCIInput]::SetForegroundWindow([IntPtr]$main.Current.NativeWindowHandle)
  $list=Find-ByAutomationId $main 'SearchResults'
  if(-not $list){throw 'Package results list disappeared before selecting package row.'}
  $match=Find-PackageListItem $list $PackageId
  $item=$match.Item
  try {
   if($attempt -eq 'uia-pattern'){
    $item.SetFocus()
    $pattern=$item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $pattern.Select()
   } elseif($attempt -eq 'pointer'){
    $point=$item.GetClickablePoint()
    [void][GSCIInput]::SetCursorPos([int]$point.X,[int]$point.Y)
    Start-Sleep -Milliseconds 120
    [GSCIInput]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [GSCIInput]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
   } else {
    $item.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait(' ')
   }
  } catch {
   Write-Host ('Selection attempt '+$attempt+' failed: '+$_.Exception.Message)
   continue
  }
  $stageUntil=[DateTime]::UtcNow.AddSeconds(5)
  if($stageUntil -gt $until){$stageUntil=$until}
  do {
   $fresh=Get-MainWindow
   $summary=if($fresh){Find-ByAutomationId $fresh 'SelectionSummary'}else{$null}
   $button=if($fresh){Find-ByAutomationId $fresh 'InstallSelected'}else{$null}
   if($summary -and $button -and $button.Current.IsEnabled -and $summary.Current.Name -ne ([regex]::Unescape('\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435'))) {
    return [pscustomobject]@{Window=$fresh;Summary=$summary.Current.Name;Action=$button.Current.Name;SelectionMethod=$attempt}
   }
   Start-Sleep -Milliseconds 150
  } while([DateTime]::UtcNow -lt $stageUntil)
  if([DateTime]::UtcNow -ge $until){break}
 }
 $fresh=Get-MainWindow
 $summary=if($fresh){Find-ByAutomationId $fresh 'SelectionSummary'}else{$null}
 $button=if($fresh){Find-ByAutomationId $fresh 'InstallSelected'}else{$null}
 throw ('Package row '+$PackageId+' did not become actionable after fresh UIA, pointer and keyboard selection; summary='+[string]$summary.Current.Name+'; action='+[string]$button.Current.Name+'; enabled='+[string]$button.Current.IsEnabled)
}

function Wait-Results([int]$Seconds=180) {
 $until=[DateTime]::UtcNow.AddSeconds($Seconds)
 do{
  $fresh=Get-MainWindow;if(-not $fresh){throw 'Garant Store main window closed during search.'}
  $e=Get-SearchEvidence $fresh
  if($e.Rows -gt 0){return [pscustomobject]@{Window=$fresh;Evidence=$e}}
  $status=Find-ByAutomationId $fresh 'OperationStatus'
  $stop=Find-ByAutomationId $fresh 'StopOperation'
  if($status -and $status.Current.Name -match '^\u041e\u0448\u0438\u0431\u043a\u0430$' -and $stop -and -not $stop.Current.IsEnabled){
   throw ('Search failed: '+(Find-ByAutomationId $fresh 'OperationDetail').Current.Name)
  }
  Start-Sleep -Milliseconds 250
 }while([DateTime]::UtcNow -lt $until)
 $fresh=Get-MainWindow
 $status=if($fresh){Find-ByAutomationId $fresh 'OperationStatus'}else{$null}
 $detail=if($fresh){Find-ByAutomationId $fresh 'OperationDetail'}else{$null}
 throw ('UI displayed no package rows. Status='+$(if($status){$status.Current.Name}else{'<closed>'})+'; Detail='+$(if($detail){$detail.Current.Name}else{'<none>'}))
}
function Wait-Idle([int]$Seconds=180) {
 $until=[DateTime]::UtcNow.AddSeconds($Seconds)
 do{
  $fresh=Get-MainWindow;if(-not $fresh){throw 'Garant Store main window closed during operation.'}
  $stop=Find-ByAutomationId $fresh 'StopOperation'
  if($stop -and -not $stop.Current.IsEnabled){return $fresh}
  Start-Sleep -Milliseconds 200
 }while([DateTime]::UtcNow -lt $until)
 throw 'WPF operation did not finish before timeout.'
}
function Handle-Consent([ValidateSet('accept','decline','cancel')][string]$Action,[bool]$Required=$false) {
 $dialog=Get-Dialog 12
 if($dialog -eq $null) {
  if($Required) {
   $top= [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
   $names=@();foreach($window in $top){try{$names+=([string]$window.Current.ControlType.ProgrammaticName+': '+[string]$window.Current.Name)}catch{}}
   $main=Get-MainWindow
   $status=if($main){Find-ByAutomationId $main 'OperationStatus'}else{$null}
   $detail=if($main){Find-ByAutomationId $main 'OperationDetail'}else{$null}
   try{$screen=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object System.Drawing.Bitmap($screen.Width,$screen.Height);$graphics=[System.Drawing.Graphics]::FromImage($bmp);try{$graphics.CopyFromScreen($screen.Left,$screen.Top,0,0,$screen.Size);$bmp.Save((Join-Path $evidence ($Scenario+'-consent-debug.png')),[System.Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bmp.Dispose()}}catch{Write-Host ('Consent screenshot capture failed: '+$_.Exception.Message)}
   throw ('Expected first-use source consent dialog did not appear. DesktopWindows='+($names -join ' | ')+'; status='+$(if($status){$status.Current.Name}else{'<closed>'})+'; detail='+$(if($detail){$detail.Current.Name}else{'<none>'}))
  }
  return $false
 }
 $isConsent=($dialog.Current.Name -match 'Microsoft Store|source agreement')
 if(-not $isConsent) {
  if($Required) { throw ('Expected source agreement prompt, found dialog: '+$dialog.Current.Name) }
  return $false
 }
 if($Action -eq 'accept') { $buttonName='Yes' }
 elseif($Action -eq 'decline') { $buttonName='No' }
 else { $buttonName='Cancel' }
 $button=Find-Button $dialog $buttonName
 if($button -eq $null) {
  if($buttonName -eq 'Yes') { $button=Find-Button $dialog ([regex]::Unescape('\u0414\u0430')) }
  elseif($buttonName -eq 'No') { $button=Find-Button $dialog ([regex]::Unescape('\u041d\u0435\u0442')) }
  else { $button=Find-Button $dialog ([regex]::Unescape('\u041e\u0442\u043c\u0435\u043d\u0430')) }
 }
 if($button -eq $null) { throw 'Consent dialog action button was not found.' }
 Invoke-Element $button
 return $true
}

function Click-Confirmation {
 $until=[DateTime]::UtcNow.AddSeconds(12)
 do {
  $dialog=Get-Dialog 1
  if($dialog -ne $null) {
   $yes=Find-Button $dialog 'Yes'
   if($yes -eq $null) { $yes=Find-Button $dialog ([regex]::Unescape('\u0414\u0430')) }
   if($yes -ne $null) { Invoke-Element $yes; return }
  }
  Start-Sleep -Milliseconds 150
 } while([DateTime]::UtcNow -lt $until)
 $foreground=[GSCIInput]::GetForegroundWindow()
 $mainWindow=Get-MainWindow
 $mainHandle=if($mainWindow){[IntPtr]$mainWindow.Current.NativeWindowHandle}else{[IntPtr]::Zero}
 $popup=if($mainHandle -ne [IntPtr]::Zero){[GSCIInput]::GetLastActivePopup($mainHandle)}else{[IntPtr]::Zero}
 $caption=New-Object System.Text.StringBuilder 256
 [void][GSCIInput]::GetWindowText($foreground,$caption,$caption.Capacity)
 $popupCaption=New-Object System.Text.StringBuilder 256
 [void][GSCIInput]::GetWindowText($popup,$popupCaption,$popupCaption.Capacity)
 $isOwnedModal=($popup -ne [IntPtr]::Zero -and $popup -ne $mainHandle -and $popupCaption.ToString() -eq 'Garant Store')
 $isForegroundModal=($foreground -ne [IntPtr]::Zero -and $foreground -ne $mainHandle -and $caption.ToString() -eq 'Garant Store')
 if($isOwnedModal -or $isForegroundModal) {
  # WPF's owner is disabled while its native MessageBox is open. In this isolated
  # lifecycle test, Enter is the explicit user confirmation for the install/update.
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 250
  Write-Host ('Confirmed Garant Store modal using keyboard input. OwnedPopup='+$popupCaption.ToString())
  return
 }
 $status=if($mainWindow){Find-ByAutomationId $mainWindow 'OperationStatus'}else{$null}
 $detail=if($mainWindow){Find-ByAutomationId $mainWindow 'OperationDetail'}else{$null}
 $stop=if($mainWindow){Find-ByAutomationId $mainWindow 'StopOperation'}else{$null}
 throw ('Garant Store confirmation dialog did not appear; foreground='+$caption.ToString()+'; foregroundHwnd='+$foreground+'; ownedPopup='+$popupCaption.ToString()+'; popupHwnd='+$popup+'; mainHwnd='+$mainHandle+'; status='+$(if($status){$status.Current.Name}else{'<none>'})+'; detail='+$(if($detail){$detail.Current.Name}else{'<none>'})+'; stopEnabled='+$(if($stop){$stop.Current.IsEnabled}else{'<none>'}))
}

function Run-WinGet([string[]]$Arguments) {
 $exe=(Get-Command winget.exe -ErrorAction Stop).Source
 $output=@(& $exe @Arguments 2>&1);$code=$LASTEXITCODE
 if($code -ne 0){throw ('winget '+($Arguments -join ' ')+' failed ('+$code+'): '+($output -join ' '))}
 return [pscustomobject]@{Code=$code;Output=($output -join [Environment]::NewLine)}
}
try {
 $main=Wait-MainWindow
 switch -Regex ($Scenario) {
  '^webview2-(install|installed)$' {
   # Must run on a disposable, genuinely WebView2-free Windows instance.
   # Preinstalled/uncertain runtime is a gate failure, never a pass or skip.
   $oldDataRoot=$env:GARANT_PO_DATA_ROOT
   $env:GARANT_PO_DATA_ROOT=Join-Path ([IO.Path]::GetTempPath()) ('gs-webview2-ui-'+[guid]::NewGuid().ToString('N'))
   try {
    . (Join-Path $InstallRoot 'DriverEngine\Core.ps1')
    $before=Get-GSWebView2State
   } finally {$env:GARANT_PO_DATA_ROOT=$oldDataRoot}
   $installedCheck=($Scenario -eq 'webview2-installed')
   if($before.Unverified){throw ('WebView2 registration/binary state is inconclusive: '+($before|ConvertTo-Json -Compress))}
   if($installedCheck -and -not $before.Installed){throw 'Existing-installation test requires a genuinely installed WebView2.'}
   if(-not $installedCheck -and $before.Installed){
    $record=[pscustomobject]@{Scenario=$Scenario;Result='unavailable';Reason='PreinstalledWebView2';InstalledVersion=$before.Version;Error='The runner already has WebView2; no clean installation was attempted.'}
    $record|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence ($Scenario+'.json')) -Encoding UTF8
    Write-Host ($record|ConvertTo-Json -Compress)
    return
   }
   if(-not $before.Supported){throw 'Windows runner is incompatible with WebView2.'}
   $metrics.Add([pscustomobject]@{Check=$(if($installedCheck){'real-installed-baseline'}else{'real-absence'});Installed=$before.Installed;Version=$before.Version})
   function Get-ComponentsWindow {
    $rootUi=[System.Windows.Automation.AutomationElement]::RootElement
    $windowCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)
    $windows=[System.Collections.Generic.List[System.Windows.Automation.AutomationElement]]::new()
    $top=$rootUi.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
    foreach($candidate in $top){$windows.Add($candidate)}
    $mainWindow=Get-MainWindow
    if($mainWindow){
     $owned=$mainWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants,$windowCondition)
     foreach($candidate in $owned){$windows.Add($candidate)}
    }
    foreach($candidate in $windows){
     try{
      $name=$candidate.Current.Name
      if($name -eq 'Компоненты Windows — Garant Store' -or ($name -match 'Garant Store' -and (Find-ByAutomationId $candidate 'DriverScan'))){return $candidate}
     }catch{}
    }
    return $null
   }
   function Find-WebViewRow([System.Windows.Automation.AutomationElement]$Window) {
    $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
    $rows=$Window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
    foreach($row in $rows) {
     $texts=$row.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))
     $labels=@(foreach($item in $texts){try{[string]$item.Current.Name}catch{}})
     if(($labels -join ' | ') -match 'Microsoft Edge WebView2 Runtime'){
      return [pscustomobject]@{Row=$row;Checkbox=(Find-ByAutomationId $row 'DriverRowCheckbox');Text=($labels -join ' | ')}
     }
    }
    return $null
   }
   function Click-Component([System.Windows.Automation.AutomationElement]$Element,[System.Windows.Automation.AutomationElement]$Window) {
    if(-not $Element -or -not $Element.Current.IsEnabled){throw 'Required WPF element is missing or disabled.'}
    [void][GSCIInput]::SetForegroundWindow([IntPtr]$Window.Current.NativeWindowHandle)
    $point=$Element.GetClickablePoint();[void][GSCIInput]::SetCursorPos([int]$point.X,[int]$point.Y)
    Start-Sleep -Milliseconds 140
    [GSCIInput]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [GSCIInput]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
   }
   $nav=Find-Button $main 'Компоненты Windows'
   Click-Component $nav $main
   $components=$null
   foreach($attempt in @(1,2)){
    $until=[DateTime]::UtcNow.AddSeconds(55)
    do{$components=Get-ComponentsWindow;if($components){break};Start-Sleep -Milliseconds 350}while([DateTime]::UtcNow -lt $until)
    if($components){break}
    if($attempt -eq 1){
     $main=Get-MainWindow
     if(-not $main){throw 'Main WPF window exited while navigating to Windows components.'}
     $nav=Find-Button $main 'Компоненты Windows'
     $nav.SetFocus()
     [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    }
   }
   if(-not $components){
    $top=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
    $names=@(foreach($candidate in $top){try{([string]$candidate.Current.Name)+' ['+[string]$candidate.Current.AutomationId+']'}catch{}})
    throw ('Real WPF components window did not open after pointer and keyboard navigation. DesktopWindows='+($names -join ' | '))
   }
   $scan=Find-ByAutomationId $components 'DriverScan'
   $until=[DateTime]::UtcNow.AddSeconds(110)
   while(((-not $scan) -or (-not $scan.Current.IsEnabled)) -and [DateTime]::UtcNow -lt $until){Start-Sleep -Milliseconds 250;$scan=Find-ByAutomationId $components 'DriverScan'}
   if(-not $scan -or -not $scan.Current.IsEnabled){throw ('Driver backend failed to initialize: '+(Find-ByAutomationId $components 'DriverDetail').Current.Name)}
   Invoke-Element $scan
   $until=[DateTime]::UtcNow.AddSeconds(300);$webRow=$null
   do{
    $webRow=Find-WebViewRow $components;$scan=Find-ByAutomationId $components 'DriverScan'
    if($webRow -and $webRow.Checkbox -and $scan.Current.IsEnabled){break}
    Start-Sleep -Milliseconds 500
   }while([DateTime]::UtcNow -lt $until)
   if($installedCheck){
    # The row can be read a moment before WPF has applied every binding of a
    # refreshed snapshot. Re-read for up to 10 s; a state that stays wrong still fails.
    $settleUntil=[DateTime]::UtcNow.AddSeconds(10)
    while((-not $webRow -or -not $webRow.Checkbox -or $webRow.Checkbox.Current.IsEnabled -or $webRow.Text -notmatch 'Установлено') -and [DateTime]::UtcNow -lt $settleUntil){
     Start-Sleep -Milliseconds 500
     $webRow=Find-WebViewRow $components
    }
    if(-not $webRow -or -not $webRow.Checkbox -or $webRow.Checkbox.Current.IsEnabled -or $webRow.Text -notmatch 'Установлено'){
     $rowText=if($webRow){[string]$webRow.Text}else{'<row not found>'}
     $checkboxState=if($webRow -and $webRow.Checkbox){'enabled='+[string]$webRow.Checkbox.Current.IsEnabled}else{'<no checkbox>'}
     $engineRow='<devices.json not readable>'
     foreach($stateRoot in @((Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GarantStoreEngine\State'),(Join-Path $env:LOCALAPPDATA 'Garant Store\Drivers\State'))){
      $devicesFile=Join-Path $stateRoot 'devices.json'
      if(Test-Path -LiteralPath $devicesFile){try{$engineRow=$devicesFile+' => '+(@(Get-Content -LiteralPath $devicesFile -Raw -Encoding UTF8|ConvertFrom-Json)|Where-Object{$_.instanceId -eq 'LIBRARY|webview2'}|ConvertTo-Json -Compress -Depth 4)}catch{$engineRow=$devicesFile+' => '+$_.Exception.Message};break}
     }
     throw ('Installed WebView2 was not shown as installed/nonselectable by WPF: '+(Find-ByAutomationId $components 'DriverDetail').Current.Name+' | row='+$rowText+' | checkbox '+$checkboxState+' | engine='+$engineRow+' | test-side state='+(ConvertTo-Json -InputObject $before -Compress))
    }
    $metrics.Add([pscustomobject]@{Check='existing-webview2-is-nonselectable';Version=$before.Version;Text=$webRow.Text;Selectable=$false})
    $close=Find-ByAutomationId $components 'DriverClose'
    if($close){Click-Component $close $components}
    break
   }
   if(-not $webRow -or -not $webRow.Checkbox -or -not $webRow.Checkbox.Current.IsEnabled){throw ('Missing WebView2 could not be selected after scan: '+(Find-ByAutomationId $components 'DriverDetail').Current.Name)}
   if($webRow.Text -notmatch 'добровольная|дополнительно'){throw ('WebView2 is not advertised as optional: '+$webRow.Text)}
   $metrics.Add([pscustomobject]@{Check='real-ui-discovery-and-selection';Text=$webRow.Text})
   $webRow.Checkbox.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
   $install=Find-ByAutomationId $components 'DriverInstall';$until=[DateTime]::UtcNow.AddSeconds(10)
   while(((-not $install) -or (-not $install.Current.IsEnabled)) -and [DateTime]::UtcNow -lt $until){Start-Sleep -Milliseconds 150;$install=Find-ByAutomationId $components 'DriverInstall'}
   if(-not $install -or -not $install.Current.IsEnabled){throw 'Selecting WebView2 did not enable real WPF install action.'}
   Click-Component $install $components
   $confirmation=$null;$until=[DateTime]::UtcNow.AddSeconds(15)
   do{
    $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
    foreach($candidate in $windows){try{if($candidate.Current.Name -eq 'Подтверждение установки'){$confirmation=$candidate;break}}catch{}}
    if($confirmation){break}
    Start-Sleep -Milliseconds 150
   }while([DateTime]::UtcNow -lt $until)
   if(-not $confirmation){throw 'WPF installation confirmation did not appear.'}
   $yes=Find-Button $confirmation 'Да';if(-not $yes){$yes=Find-Button $confirmation 'Yes'}
   if(-not $yes){throw 'Installation confirmation has no explicit Yes button.'}
   Click-Component $yes $confirmation
   $metrics.Add([pscustomobject]@{Check='actual-user-install-operation';Confirmed=$true})
   $until=[DateTime]::UtcNow.AddMinutes(12);$after=$null
   do{
    $after=Get-GSWebView2State
    $phase=(Find-ByAutomationId $components 'DriverState').Current.Name
    $detail=(Find-ByAutomationId $components 'DriverDetail').Current.Name
    if($phase -match 'Ошибка|ошибками|Остановлено'){throw ('WebView2 installation failed in UI: '+$phase+' '+$detail)}
    $webRow=Find-WebViewRow $components
    if($after.Installed -and $webRow -and $webRow.Checkbox -and -not $webRow.Checkbox.Current.IsEnabled -and $webRow.Text -match 'Установлено' -and $phase -eq 'Готово'){break}
    Start-Sleep -Milliseconds 700
   }while([DateTime]::UtcNow -lt $until)
   if(-not $after.Installed -or -not $webRow -or -not $webRow.Checkbox -or $webRow.Checkbox.Current.IsEnabled -or $webRow.Text -notmatch 'Установлено' -or $phase -ne 'Готово'){
    throw ('Actual installed runtime not proven in UI and registry: '+($after|ConvertTo-Json -Compress)+'; phase='+$phase+'; detail='+$detail)
   }
   $setupPath=Join-Path $env:USERPROFILE 'Downloads\Garant Store\Libraries\MicrosoftEdgeWebview2Setup.exe'
   if(-not (Test-Path -LiteralPath $setupPath -PathType Leaf)){throw ('Actual downloaded setup was not found: '+$setupPath)}
   $sig=Get-AuthenticodeSignature -LiteralPath $setupPath
   if($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)'){throw 'Downloaded runtime lacks valid Microsoft signature.'}
   $sha=(Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
   if((Get-Item -LiteralPath $setupPath).Length -lt 10000){throw 'Downloaded setup was incomplete.'}
   $metrics.Add([pscustomobject]@{Check='official-binary-and-success';Sha256=$sha;Signature='Valid';Version=$after.Version;UI=$webRow.Text})
   # Explicit second scan proves the installed state does not offer reinstallation.
   Invoke-Element (Find-ByAutomationId $components 'DriverScan')
   $until=[DateTime]::UtcNow.AddMinutes(5);$rowAgain=$null
   do{
    $rowAgain=Find-WebViewRow $components;$scan=Find-ByAutomationId $components 'DriverScan'
    if($rowAgain -and $rowAgain.Checkbox -and $scan.Current.IsEnabled -and $rowAgain.Text -match 'Установлено'){break}
    Start-Sleep -Milliseconds 450
   }while([DateTime]::UtcNow -lt $until)
   if(-not $rowAgain -or -not $rowAgain.Checkbox -or $rowAgain.Checkbox.Current.IsEnabled -or $rowAgain.Text -notmatch 'Установлено'){throw 'Installed WebView2 is incorrectly offered for reinstallation.'}
   $metrics.Add([pscustomobject]@{Check='idempotent-second-scan';Version=(Get-GSWebView2State).Version;Selectable=$false})
   $close=Find-ByAutomationId $components 'DriverClose'
   if($close){Click-Component $close $components}
  }
  '^search-(winget|msstore|aggregate)$' {
   $source=switch($Matches[1]){'winget'{'winget'}'msstore'{'msstore'}default{''}}
   $watch=[Diagnostics.Stopwatch]::StartNew()
   Start-Search $main 'WhatsApp' $source
   $accepted=Handle-Consent 'accept'
   if($accepted){$metrics.Add([pscustomobject]@{Check='source-consent';Action='explicit Yes in isolated UI test'})}
   $result=Wait-Results
   $main=Wait-Idle
   $watch.Stop();$e=Get-SearchEvidence $main
   $metrics.Add([pscustomobject]@{Check='live-ui-search';Source=$(if($source){$source}else{'aggregate'});Rows=$e.Rows;CountText=$e.CountText;ElapsedMs=$watch.ElapsedMilliseconds})
  }
  '^consent-(accept|decline|cancel)$' {
   Start-Search $main 'WhatsApp' 'msstore';$action=$Matches[1]
   [void](Handle-Consent $action $true)
   if($action -eq 'accept'){
    $null=Wait-Results
    $main=Wait-Idle
    $e=Get-SearchEvidence $main
    $log=Find-ByAutomationId $main 'OperationLog'
    $logText=[string]$log.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    if($logText -notmatch 'AgreementConsent=True') { throw 'UI retry did not carry explicit agreement consent into Core.' }
    $metrics.Add([pscustomobject]@{Check='consent-accept-retry';Rows=$e.Rows;CountText=$e.CountText;ConsentPassedToCore=$true})
    $main.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    if(-not $launchProcess.WaitForExit(15000)){throw 'First WPF process did not exit after closing its main window.'}
    if($launchProcess.ExitCode -ne 0){throw ('First WPF process exited with code '+$launchProcess.ExitCode)}
    $launchProcess=Start-TrackedLauncher
    $main=Wait-MainWindow
    Start-Search $main 'WhatsApp' 'msstore'
    if((Get-Dialog 4) -ne $null) { throw 'The accepted source agreement was requested again after app restart.' }
    $null=Wait-Results
    $main=Wait-Idle
    $e=Get-SearchEvidence $main
    $metrics.Add([pscustomobject]@{Check='consent-persists-after-restart';Rows=$e.Rows;CountText=$e.CountText;RePrompted=$false})
   }else{
    Start-Sleep -Milliseconds 800;$main=Get-MainWindow
    if(-not $main){throw 'Main window closed after refusing/canceling consent.'}
    $status=Find-ByAutomationId $main 'OperationStatus';$detail=Find-ByAutomationId $main 'OperationDetail'
    if($status.Current.Name -match '^\u041e\u0448\u0438\u0431\u043a\u0430$'){throw ('UI error after '+$action+': '+$detail.Current.Name)}
    if($detail.Current.Name -notmatch '\u0441\u043e\u0433\u043b\u0430\u0441\u0438\u0435|\u043e\u0442\u043c\u0435\u043d\u0451\u043d|\u043d\u0435 \u043f\u0440\u0438\u043d\u044f\u0442\u043e'){throw ('Missing refusal explanation: '+$detail.Current.Name)}
    $metrics.Add([pscustomobject]@{Check='consent-'+$action;WindowOpen=$true;Status=$status.Current.Name;Detail=$detail.Current.Name})
   }
  }
  '^network-error$' {
   $rule='GarantStore-CI-BlockNetwork-'+[Guid]::NewGuid().ToString('N')
   New-NetFirewallRule -DisplayName $rule -Direction Outbound -RemoteAddress Any -Action Block -Profile Any | Out-Null
   try{
    Start-Search $main 'WhatsApp' 'msstore'
    $null=Handle-Consent 'accept'
    $latency=[Diagnostics.Stopwatch]::StartNew()
    $nav=Find-Button $main ([regex]::Unescape('\u0416\u0443\u0440\u043d\u0430\u043b \u043e\u043f\u0435\u0440\u0430\u0446\u0438\u0439'));if($nav){Invoke-Element $nav}
    $latency.Stop()
    if($latency.ElapsedMilliseconds -gt 2000){throw ('UI blocked for '+$latency.ElapsedMilliseconds+' ms during network failure')}
    $main=Wait-Idle 180;$status=Find-ByAutomationId $main 'OperationStatus'
    if($status.Current.Name -notmatch '^\u041e\u0448\u0438\u0431\u043a\u0430$'){throw ('Expected network error, got UI status: '+$status.Current.Name+'; detail='+(Find-ByAutomationId $main 'OperationDetail').Current.Name)}
    $metrics.Add([pscustomobject]@{Check='network-error-ui-responsive';NavigationLatencyMs=$latency.ElapsedMilliseconds;LimitMs=2000;Status=$status.Current.Name;WindowOpen=$true})
   }finally{Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue}
  }
  '^lifecycle$' {
   $existing=@(& winget.exe list --id 7zip.7zip --exact --source winget --disable-interactivity 2>&1)
   if(($existing -join [Environment]::NewLine) -match '7zip[.]7zip'){
    $null=Run-WinGet @('uninstall','--id','7zip.7zip','--exact','--source','winget','--accept-source-agreements','--silent','--disable-interactivity')
   }
   $versions=@(& winget.exe show --id 7zip.7zip --exact --source winget --versions --accept-source-agreements --disable-interactivity 2>&1)
   if($LASTEXITCODE -ne 0){throw ('Could not query safe test package versions: '+($versions -join ' '))}
   $versionValues=@()
   foreach($versionLine in $versions){
    $versionMatches=[regex]::Matches([string]$versionLine,'(?<!\d)(\d+\.\d+(?:\.\d+)?)(?!\d)')
    foreach($versionMatch in $versionMatches){
     try{$null=[version]$versionMatch.Groups[1].Value;$versionValues+= $versionMatch.Groups[1].Value}catch{}
    }
   }
   $available=@($versionValues|Sort-Object { [version]$_ } -Unique)
   Write-Host ('7-Zip versions returned by source: '+($available -join ', '))
   if($available.Count -lt 2){throw 'WinGet source must expose at least two 7-Zip versions for a real update test.'}
   $oldVersion=[string]$available[$available.Count-2]
   $fixtureWatch=[Diagnostics.Stopwatch]::StartNew()
   $null=Run-WinGet @('install','--id','7zip.7zip','--exact','--source','winget','--version',$oldVersion,'--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity')
   $fixtureWatch.Stop()
   $metrics.Add([pscustomobject]@{Check='test-fixture';Version=$oldVersion;ElapsedMs=$fixtureWatch.ElapsedMilliseconds})
   Start-Search $main '7-Zip' 'winget';$null=Handle-Consent 'accept'
   $result=Wait-Results;$main=$result.Window;$main=Wait-Idle
   $list=Find-ByAutomationId $main 'SearchResults'
   $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
   $packageItem=Find-PackageListItem $list '7zip.7zip'
   $selection=Select-PackageItem '7zip.7zip'; $main=$selection.Window
   $button=Find-ByAutomationId $main 'InstallSelected';$summary=Find-ByAutomationId $main 'SelectionSummary'
   $expectedUpdateAction=[regex]::Unescape('\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c')
   if($button.Current.Name -ne $expectedUpdateAction){
    $directList=@(& winget.exe list --id 7zip.7zip --exact --source winget --disable-interactivity 2>&1)
    $directListText=[string]::Join(' ',[string[]]$directList)
    throw ('Outdated package was not detected as updateable: '+$summary.Current.Name+'; action='+$button.Current.Name+'; direct winget list='+$directListText)
   }
   Press-Button $button;Click-Confirmation
   $latency=[Diagnostics.Stopwatch]::StartNew();$nav=Find-Button $main ([regex]::Unescape('\u0416\u0443\u0440\u043d\u0430\u043b \u043e\u043f\u0435\u0440\u0430\u0446\u0438\u0439'));if($nav){Invoke-Element $nav};$latency.Stop()
   if($latency.ElapsedMilliseconds -gt 2000){throw ('UI blocked during a real package update for '+$latency.ElapsedMilliseconds+' ms')}
   $main=Wait-Idle 900
   $status=Find-ByAutomationId $main 'OperationStatus'
   $detail=Find-ByAutomationId $main 'OperationDetail'
   $direct=@(& winget.exe list --id 7zip.7zip --exact --source winget --disable-interactivity 2>&1)
   $directExit=$LASTEXITCODE
   $detailText=if($detail){$detail.Current.Name}else{''}
   $metrics.Add([pscustomobject]@{Check='update-evidence';Status=$status.Current.Name;Detail=$detailText;WinGetListExitCode=$directExit;WinGetList=($direct -join "\n")})
   if($status.Current.Name -notmatch '^\u041e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u043e$'){throw ('WinGet update was not verified by app: '+$status.Current.Name+'; detail='+$detailText+'; direct list exit='+$directExit+'; direct list='+($direct -join ' '))}
   $metrics.Add([pscustomobject]@{Check='real-ui-update';Status=$status.Current.Name;NavigationLatencyMs=$latency.ElapsedMilliseconds;Version=$oldVersion})
   Start-Search $main '7-Zip' 'winget';$result=Wait-Results;$main=$result.Window;$main=Wait-Idle
   $list=Find-ByAutomationId $main 'SearchResults'
   $packageItem=Find-PackageListItem $list '7zip.7zip'
   $selection=Select-PackageItem '7zip.7zip'; $main=$selection.Window
   $button=Find-ByAutomationId $main 'InstallSelected'
   if($button.Current.Name -notmatch '\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f|\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c'){throw 'Installed 7-Zip status was not detected after update.'}
   $metrics.Add([pscustomobject]@{Check='installed-status';Action=$button.Current.Name})
   $null=Run-WinGet @('uninstall','--id','7zip.7zip','--exact','--source','winget','--accept-source-agreements','--silent','--disable-interactivity')
   Start-Search $main '7-Zip' 'winget';$result=Wait-Results;$main=$result.Window
   $list=Find-ByAutomationId $main 'SearchResults'
   $packageItem=Find-PackageListItem $list '7zip.7zip'
   $selection=Select-PackageItem '7zip.7zip'; $main=$selection.Window
   $button=Find-ByAutomationId $main 'InstallSelected'
   if($button.Current.Name -notmatch '\u0423\u0441\u0442\u0430\u043d\u043e\u0432\u0438\u0442\u044c'){throw ('Uninstalled 7-Zip not shown as installable: '+$button.Current.Name)}
   Press-Button $button;Click-Confirmation;$main=Wait-Idle 900
   $verify=@(& winget.exe list --id 7zip.7zip --exact --source winget --disable-interactivity 2>&1)
   if($LASTEXITCODE -ne 0){throw ('UI installation not found by real WinGet: '+($verify -join ' '))}
   $metrics.Add([pscustomobject]@{Check='real-ui-install';Status=(Find-ByAutomationId $main 'OperationStatus').Current.Name})
   Invoke-Element (Find-ByAutomationId $main 'OpenSystemInformation')
   $systemCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,[regex]::Unescape('\u041c\u043e\u044f \u0441\u0438\u0441\u0442\u0435\u043c\u0430 \u2014 Garant Store'))
   $deadline=[DateTime]::UtcNow.AddSeconds(50)
   do{
    $systemWindow=Find-ByAutomationId $main 'GarantStoreSystemWindow'
    if(-not $systemWindow){$systemWindow=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$systemCondition)}
    $copy=if($systemWindow){Find-ByAutomationId $systemWindow 'CopySystem'}else{$null}
    if($copy -and $copy.Current.IsEnabled){break}
    Start-Sleep -Milliseconds 250
   }while([DateTime]::UtcNow -lt $deadline)
   if(-not $copy -or -not $copy.Current.IsEnabled){
    $systemDetail=if($systemWindow){(Find-ByAutomationId $systemWindow 'SystemStatus').Current.Name}else{'window not found'}
    throw ('System information did not load: '+$systemDetail)
   }
   Invoke-Element (Find-ByAutomationId $systemWindow 'RefreshSystem')
   $deadline=[DateTime]::UtcNow.AddSeconds(50)
   do{
    $refresh=Find-ByAutomationId $systemWindow 'RefreshSystem'
    if($refresh -and $refresh.Current.IsEnabled){break}
    Start-Sleep -Milliseconds 250
   }while([DateTime]::UtcNow -lt $deadline)
   $systemStatus=Find-ByAutomationId $systemWindow 'SystemStatus'
   if(-not $systemStatus -or $systemStatus.Current.Name -notmatch '^\u0421\u0432\u0435\u0434\u0435\u043d\u0438\u044f \u043f\u043e\u043b\u0443\u0447\u0435\u043d\u044b'){throw 'Refreshed system information did not load.'}
   Set-Clipboard -Value 'Garant Store clipboard test sentinel'
   Invoke-Element $copy
   $deadline=[DateTime]::UtcNow.AddSeconds(5)
   do{$copied=Get-Clipboard -Raw;if($copied -match '(?m)^Build \d+'){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
   if($copied -notmatch '(?m)^Build \d+'){throw 'System information was not copied to the clipboard.'}
   $metrics.Add([pscustomobject]@{Check='system-open-refresh-copy';Result=$true})
   foreach($extension in @('txt','json','html')){
    $reportPath=Join-Path ([IO.Path]::GetTempPath()) ('gs-ui-'+[guid]::NewGuid().ToString('N')+'.'+$extension)
    Invoke-Element (Find-ByAutomationId $systemWindow 'ExportSystem')
    $saveCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,[regex]::Unescape('Garant Store: \u044d\u043a\u0441\u043f\u043e\u0440\u0442 \u043e\u0442\u0447\u0451\u0442\u0430'))
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do{
     $save=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$saveCondition)
     if($save){break}
     Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $save){throw 'Export dialog did not open.'}
    $fileName=Find-ByAutomationId $save '1001'
    if(-not $fileName){throw 'Export dialog filename field not found.'}
    $fileName.SetFocus()
    Set-Clipboard -Value $reportPath
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    $actualName=$fileName.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    if($actualName -ne $reportPath){throw ('Save dialog did not receive the requested path: '+$actualName)}
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    while(-not (Test-Path -LiteralPath $reportPath) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
    if(-not (Test-Path -LiteralPath $reportPath)){
     $exportStatus=(Find-ByAutomationId $systemWindow 'SystemStatus').Current.Name
     throw ('Export did not write the requested path. WPF status: '+$exportStatus)
    }
    $body=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    if($extension -eq 'json'){
     $profile=$body|ConvertFrom-Json
     if(-not $profile.processor -or $profile.memoryBytes -le 0 -or $profile.build -notmatch '^\d+$'){throw 'System JSON report lacks measured hardware or Windows build.'}
     if($profile.PSObject.Properties['localId'] -or $profile.PSObject.Properties['computerName']){throw 'Default JSON includes a private identifier.'}
     if(-not $profile.details.operatingSystem -or -not $profile.details.processors){throw 'System JSON is missing detailed OS or CPU measurements.'}
    }elseif($extension -eq 'html'){
     if($body -notmatch '<!doctype html>' -or $body -notmatch '@media print' -or $body -notmatch "href='#section-" -or $body -match '(?i)(?:src|href)=["'']https?://'){throw 'HTML report is missing local navigation or print styles, or includes an external resource.'}
     # The first page must be the detailed tile summary collected on this real Windows,
     # not the short fallback used when the collector fails.
     if($body -notmatch 'class="tiles"' -or $body -match [regex]::Unescape('\u041f\u043e\u0434\u0440\u043e\u0431\u043d\u0430\u044f \u0441\u0432\u043e\u0434\u043a\u0430 \u043d\u0435 \u0441\u043e\u0431\u0440\u0430\u043d\u0430') -or $body -notmatch [regex]::Escape([regex]::Unescape('\u0412\u0438\u0434\u0435\u043e\u043a\u0430\u0440\u0442\u0430 (GPU)'))){
      $note=[regex]::Match($body,'class="tile note".{0,400}').Value
      throw ('HTML report has no detailed hardware summary. '+$note)
     }
    }elseif($body -notmatch '(?m)^Garant Store' -or $body -notmatch '(?m)^BuildNumber: \d+'){throw 'TXT report lacks a measured Windows build.'}
    Remove-Item -LiteralPath $reportPath -Force
    $metrics.Add([pscustomobject]@{Check='system-export';Format=$extension;Result=$true})
   }
   $systemWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
  }
 }
 if(-not (Get-MainWindow)){throw 'Garant Store closed before the scenario completed.'}
 $metrics.Add([pscustomobject]@{Check='main-window-open';Result=$true})
 $screen=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
 $bmp=New-Object System.Drawing.Bitmap($screen.Width,$screen.Height);$graphics=[System.Drawing.Graphics]::FromImage($bmp)
 try{$graphics.CopyFromScreen($screen.Left,$screen.Top,0,0,$screen.Size);$bmp.Save((Join-Path $evidence ($Scenario+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bmp.Dispose()}
 $report=[pscustomobject]@{Scenario=$Scenario;Result='passed';Runner=$env:RUNNER_OS;ElapsedMs=([DateTime]::UtcNow-$started).TotalMilliseconds;Metrics=@($metrics)}
 $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $evidence ($Scenario+'.json')) -Encoding UTF8
 Write-Host ($report|ConvertTo-Json -Depth 8)
}catch{
 if($Scenario -eq 'lifecycle'){
  foreach($dir in @('GarantStore\Logs','Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir')){
   Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA $dir) -File -ErrorAction SilentlyContinue |
    Where-Object {$_.LastWriteTimeUtc -ge $started} |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 12 |
    Copy-Item -Destination $evidence -ErrorAction SilentlyContinue
  }
 }
 $failure=[pscustomobject]@{Scenario=$Scenario;Result='failed';Error=$_.Exception.ToString();Metrics=@($metrics)}
 $failure|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $evidence ($Scenario+'.json')) -Encoding UTF8
 throw
}finally{
 try{$main=Get-MainWindow;if($main){$main.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()}}catch{}
}
