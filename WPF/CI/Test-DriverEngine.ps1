[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$project=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $project 'DriverEngine'
$driverModule=Join-Path $project 'GarantStore.Drivers.ps1'
$unselectedDevice=[pscustomobject]@{instanceId='TEST\DEVICE'}
. $driverModule
if([bool](Get-GSDriverProperty $unselectedDevice 'Selected' $false)){throw 'A device without a selection property was treated as selected'}
if([string](Get-GSDriverProperty $unselectedDevice 'instanceId' '') -ne 'TEST\DEVICE'){throw 'Safe device property lookup returned an invalid instance ID'}
if(@(Get-GSSelectedDriverRows $null).Count -ne 0 -or @(Get-GSSelectedDriverRows @($unselectedDevice)).Count -ne 0){throw 'Selection filtering failed for empty or unselected devices'}
$selectedDevice=[pscustomobject]@{instanceId='TEST\SELECTED';Selected=$true}
if(@(Get-GSSelectedDriverRows @($unselectedDevice,$selectedDevice)).Count -ne 1){throw 'Selection filtering failed for a selected device'}
$script:driverActionBusy=$false
$script:driverEndpoint=$null
$script:driverDevices=[pscustomobject]@{ItemsSource=@($unselectedDevice)}
$script:driverDetail=[pscustomobject]@{Text=''}
$script:driverState=[pscustomobject]@{Text=''}
$script:lastDriverAction=$null
function Set-GSDriverState {param([string]$Title,[string]$Detail,[bool]$Busy=$false);$script:driverState.Text=$Title;$script:driverDetail.Text=$Detail}
function Invoke-GSDriverApi {param([string]$Path,[string]$Method='GET',$Body=$null);$script:lastDriverAction=$Body;return [pscustomobject]@{ok=$true}}
Invoke-GSDriverAction 'scan'
if($null -eq $script:lastDriverAction -or $script:lastDriverAction.action -ne 'scan'){throw 'Scan action was blocked by a device without a Selected property'}
if(@($script:lastDriverAction.ids).Count -ne 0){throw 'Scan action unexpectedly forwarded a selected item when nothing was checked'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gs-driver-engine-'+[guid]::NewGuid().ToString('N'))
$engineRoot=Join-Path $temp 'engine'
$dataRoot=Join-Path $temp 'data'
$bootstrap=Join-Path $temp 'connection.json'
$testDownloads=Join-Path $temp 'user-downloads\Garant Store\Drivers'
$testLibraries=Join-Path $temp 'user-downloads\Garant Store\Libraries'
$oldDownloadDir=$env:GARANT_PO_DOWNLOAD_DIR
$oldDriverDir=$env:GARANT_PO_DRIVER_DIR
$oldLibraryDir=$env:GARANT_PO_LIBRARY_DIR
$env:GARANT_PO_DOWNLOAD_DIR=$testDownloads
$env:GARANT_PO_DRIVER_DIR=$testDownloads
$env:GARANT_PO_LIBRARY_DIR=$testLibraries
$endpoint=$null
$serverProcess=$null
New-Item -ItemType Directory -Force -Path $engineRoot,(Join-Path $engineRoot 'UI'),$dataRoot|Out-Null
Copy-Item -LiteralPath (Join-Path $engine 'GarantServer.cs') -Destination $engineRoot
Copy-Item -LiteralPath (Join-Path $engine 'Server.ps1') -Destination $engineRoot
Copy-Item -LiteralPath (Join-Path $engine 'SecureRoot.ps1') -Destination $engineRoot
$clientToken=-join ((1..64)|ForEach-Object{'0123456789abcdef'[(Get-Random -Maximum 16)]})

$worker=@'
param([string]$Action='auto')
$ErrorActionPreference='Stop'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
$cancel=Join-Path $state 'cancel.flag'
if($Action -eq 'scan' -and -not (Test-Path -LiteralPath (Join-Path $state 'cancel-tested.marker'))){
 for($i=0;$i -lt 300;$i++){
  if(Test-Path -LiteralPath $cancel){break}
  Start-Sleep -Milliseconds 200
 }
}
$cancelled=(Test-Path -LiteralPath $cancel) -and -not (Test-Path -LiteralPath (Join-Path $state 'cancel-tested.marker'))
$selection=@(Get-Content -LiteralPath (Join-Path $state 'selection.json') -Raw|ConvertFrom-Json -ErrorAction SilentlyContinue)
$snapshot=[ordered]@{action=$Action;scanned=$true;running=$false;phase=$(if($cancelled){'Прервано'}else{'Готово'});message=$(if($cancelled){'Тест отменён'}else{'Тест завершён'});percent=100;total=$selection.Count;remaining=0;finished=$selection.Count;downloaded=$selection.Count;errors=0;bytes=0;expectedBytes=0;speedBps=0;etaSec=-1;current='';receivedIds=$selection;started=(Get-Date).ToString('o');finishedAt=(Get-Date).ToString('o');lastError='';needReboot=$false}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $snapshot -Compress),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'Worker.ps1') -Value $worker -Encoding UTF8
$updateWorker=@'
param([ValidateSet('scan','install')][string]$Mode='scan')
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
$id='TEST-UPDATE|1'
$devices=@()
if($Mode -eq 'scan'){$devices=@([pscustomobject]@{instanceId=$id;name='Test Windows driver update';hwid='Test Hardware ID';kind='Update';eulaAccepted=$true})}
else{$selected=Get-Content -LiteralPath (Join-Path $state 'selection.json') -Raw;if($selected -match [regex]::Escape($id)){$devices=@()}}
[IO.File]::WriteAllText((Join-Path $state 'devices.json'),(ConvertTo-Json -InputObject $devices -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
$status=[ordered]@{action=$(if($Mode -eq 'scan'){'update-scan'}else{'update-install'});scanned=$true;running=$false;phase='Готово';message='Test update worker completed';percent=100;receivedId=$(if($Mode -eq 'scan'){''}else{[string]$selected})}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'Updates.ps1') -Value $updateWorker -Encoding UTF8
$librariesWorker=@'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
$selected=Get-Content -LiteralPath (Join-Path $state 'selection.json') -Raw|ConvertFrom-Json
$status=[ordered]@{action='libraries';scanned=$true;running=$false;phase='Готово';message='Test libraries worker completed';percent=100;receivedIds=@($selected)}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'Libraries.ps1') -Value $librariesWorker -Encoding UTF8
$selectedWorker=@'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
$selected=Get-Content -LiteralPath (Join-Path $state 'selection.json') -Raw|ConvertFrom-Json
$status=[ordered]@{action='selected-install';scanned=$true;running=$false;phase='Готово';message='Test selected worker completed';percent=100;receivedIds=@($selected)}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'Selected.ps1') -Value $selectedWorker -Encoding UTF8
$networkWorker=@'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
$marker=Join-Path $state 'network-repair-test.marker'
[IO.File]::WriteAllText($marker,'NetworkRepair.ps1 invoked',[Text.Encoding]::ASCII)
$status=[ordered]@{action='network';scanned=$true;running=$false;phase='Готово';message='Test network repair route completed';percent=100}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'NetworkRepair.ps1') -Value $networkWorker -Encoding UTF8
$restoreWorker=@'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
[IO.File]::WriteAllText((Join-Path $state 'restore-point-test.marker'),'restore route',[Text.Encoding]::ASCII)
$status=[ordered]@{action='restore-point';scanned=(Test-Path -LiteralPath (Join-Path $state 'scan.flag'));running=$false;phase='Готово';message='Test restore point route completed';percent=100}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'RestorePoint.ps1') -Value $restoreWorker -Encoding UTF8
$wuRepairWorker=@'
$state=Join-Path $env:GARANT_PO_DATA_ROOT 'State'
[IO.File]::WriteAllText((Join-Path $state 'wu-repair-test.marker'),'Windows Update repair route',[Text.Encoding]::ASCII)
$status=[ordered]@{action='windows-update-repair';scanned=(Test-Path -LiteralPath (Join-Path $state 'scan.flag'));running=$false;phase='Готово';message='Test Windows Update repair route completed';percent=100}
[IO.File]::WriteAllText((Join-Path $state 'status.json'),(ConvertTo-Json -InputObject $status -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
'@
Set-Content -LiteralPath (Join-Path $engineRoot 'WindowsUpdateRepair.ps1') -Value $wuRepairWorker -Encoding UTF8

function Invoke-TestRequest {
 param([string]$Base,[string]$Path,[string]$Method='GET',[string]$Token='',$object=$null,[switch]$AllowError,[switch]$Bytes)
 $request=[Net.HttpWebRequest]::Create($Base+$Path);$request.Method=$Method;$request.Proxy=$null;$request.Timeout=5000
 if($Token){$request.Headers['X-Garant-Token']=$Token}
 if($null -ne $object){$body=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $object -Compress));$request.ContentType='application/json';$request.ContentLength=$body.Length;$stream=$request.GetRequestStream();$stream.Write($body,0,$body.Length);$stream.Dispose()}
 try{$response=$request.GetResponse()}catch [Net.WebException]{
  $response=$_.Exception.Response
  if(-not $AllowError -or $null -eq $response){throw}
  $code=[int]$response.StatusCode;$reader=New-Object IO.StreamReader($response.GetResponseStream());$text=$reader.ReadToEnd();$reader.Dispose();$response.Dispose()
  $data=$null;if($text){$data=$text|ConvertFrom-Json}
  return [pscustomobject]@{StatusCode=$code;Text=$text;Data=$data}
 }
 try{
  $stream=$response.GetResponseStream()
  if($Bytes){$memory=New-Object IO.MemoryStream;$stream.CopyTo($memory);return [pscustomobject]@{StatusCode=[int]$response.StatusCode;Bytes=$memory.ToArray()}}
  $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8);$text=$reader.ReadToEnd();$reader.Dispose()
  $data=$null;if($text){$data=$text|ConvertFrom-Json}
  return [pscustomobject]@{StatusCode=[int]$response.StatusCode;Text=$text;Data=$data}
 }finally{$response.Dispose()}
}

try{
 $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $server=Join-Path $engineRoot 'Server.ps1'
 $args=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$server+'"'),'-DataRoot',('"'+$dataRoot+'"'),'-Embedded','-BootstrapFile',('"'+$bootstrap+'"'),'-Token',$clientToken)
 $serverProcess=Start-Process -FilePath $psExe -ArgumentList ($args -join ' ') -WorkingDirectory $engine -WindowStyle Hidden -PassThru
 $deadline=(Get-Date).AddSeconds(30)
 while((Get-Date)-lt $deadline -and -not (Test-Path -LiteralPath $bootstrap)){
  if($serverProcess.HasExited){throw 'Garant-ПО server exited before publishing its local endpoint'}
  Start-Sleep -Milliseconds 100
 }
 if(-not (Test-Path -LiteralPath $bootstrap)){throw 'Garant-ПО server did not publish bootstrap information'}
 if(-not (Test-Path -LiteralPath $testDownloads) -or -not (Test-Path -LiteralPath $testLibraries)){throw 'Driver and library folders were not created in the configured Windows Downloads location'}
 $bootstrapInfo=[IO.File]::ReadAllText($bootstrap,[Text.Encoding]::UTF8)|ConvertFrom-Json
 if($bootstrapInfo.url -notmatch '^http://127\.0\.0\.1:\d+/$'){throw 'Server endpoint is not loopback-only'}
 if($bootstrapInfo.PSObject.Properties['token']){throw 'Server wrote the client-supplied session token to the bootstrap file'}
 $endpoint=[pscustomobject]@{url=[string]$bootstrapInfo.url;token=$clientToken}
 $health=Invoke-TestRequest $endpoint.url '/api/health'
 if(-not $health.Data.ok -or $health.Data.version -ne '6.0'){throw 'Health route failed'}
 $status=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token
 if($status.Data.scanned){throw 'Fresh data directory unexpectedly reports a completed scan'}
 if($null -eq $status.Data.status -or $status.Data.status.running -ne $false){throw 'Initial status omitted the running flag or did not report an idle state'}
 if([string]::IsNullOrWhiteSpace([string]$status.Data.status.phase) -or [string]::IsNullOrWhiteSpace([string]$status.Data.status.message)){throw 'Initial status omitted its user-facing phase or message'}
 if($status.Data.status.percent -ne -1){throw 'Initial status should use -1 for an unknown progress percentage'}
 $unauthorized=Invoke-TestRequest $endpoint.url '/api/action' 'POST' '' @{action='scan';ids=@()} -AllowError
 if($unauthorized.StatusCode -ne 403){throw 'POST without session token was not rejected'}
 $queryTokenPost=Invoke-TestRequest $endpoint.url ('/api/action?t='+$endpoint.token) 'POST' '' @{action='scan';ids=@()} -AllowError
 if($queryTokenPost.StatusCode -ne 403){throw 'A query-string token was accepted for a state-changing POST'}
 foreach($readRoute in @('/api/status','/api/events','/api/diagnostics','/api/report','/api/ui-log')){
  $anonymous=Invoke-TestRequest $endpoint.url $readRoute 'GET' '' $null -AllowError
  if($anonymous.StatusCode -ne 403){throw ('Read route without session token was not rejected: '+$readRoute+' -> HTTP '+$anonymous.StatusCode)}
 }
 $wrongToken=Invoke-TestRequest $endpoint.url '/api/status' 'GET' ('0'*64) $null -AllowError
 if($wrongToken.StatusCode -ne 403){throw 'A wrong session token was accepted'}
 $page=Invoke-TestRequest $endpoint.url '/' 'GET' '' $null -AllowError
 if($page.StatusCode -ne 404 -or $page.Text -match [regex]::Escape($endpoint.token)){throw 'Embedded server exposed the browser page or the session token'}
 $queryStatus=Invoke-TestRequest $endpoint.url ('/api/status?t='+$endpoint.token)
 if($null -eq $queryStatus.Data.status){throw 'Query-string token was not accepted for a read-only GET route'}
 $sse=[Net.HttpWebRequest]::Create($endpoint.url+'api/events');$sse.Proxy=$null;$sse.Timeout=5000;$sse.Headers['X-Garant-Token']=$endpoint.token
 $eventResponse=$sse.GetResponse();$eventReader=New-Object IO.StreamReader($eventResponse.GetResponseStream());$sawData=$false
 for($i=0;$i -lt 8 -and -not $sawData;$i++){if($eventReader.ReadLine() -like 'data: *'){$sawData=$true}}
 $eventReader.Dispose();$eventResponse.Dispose();if(-not $sawData){throw 'SSE did not deliver an initial state event'}
 $start=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='scan';ids=@()}
 if(-not $start.Data.ok){throw 'Scan action did not start'}
 $busy=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='scan';ids=@()} -AllowError
 if($busy.StatusCode -ne 409){throw 'Concurrent action was not rejected with HTTP 409'}
 $diagnostics=Invoke-TestRequest $endpoint.url '/api/diagnostics' 'GET' $endpoint.token $null -Bytes
 if($diagnostics.Bytes.Length -lt 22){throw 'Diagnostics ZIP could not be downloaded during a worker operation'}
 $cancel=Invoke-TestRequest $endpoint.url '/api/cancel' 'POST' $endpoint.token @{}
 if(-not $cancel.Data.ok){throw 'Cancel action failed'}
 $until=(Get-Date).AddSeconds(12);$completed=$false
 while((Get-Date)-lt $until){
  Start-Sleep -Milliseconds 250
  $current=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token
  if($current.Data.scanned -and -not $current.Data.status.running){$completed=$true;break}
 }
 if(-not $completed){throw 'Worker final state was not observable through /api/status'}
 [IO.File]::WriteAllText((Join-Path $dataRoot 'State\cancel-tested.marker'),'done',[Text.Encoding]::ASCII)
 $updateStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='update-scan';ids=@()}
 if(-not $updateStart.Data.ok){throw 'Windows Update scan action did not start'}
 $updateUntil=(Get-Date).AddSeconds(8);$updateState=$null
 while((Get-Date)-lt $updateUntil){Start-Sleep -Milliseconds 200;$updateState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($updateState.Data.status.action -eq 'update-scan' -and -not $updateState.Data.status.running){break}}
 if($updateState.Data.status.action -ne 'update-scan' -or $updateState.Data.devices.Count -ne 1 -or $updateState.Data.devices[0].kind -ne 'Update'){$stateJson=ConvertTo-Json -InputObject $updateState.Data -Depth 6 -Compress;throw ('Windows Update scan was not routed to its isolated update worker: '+$stateJson)}
 $updateId=$updateState.Data.devices[0].instanceId
 $installStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='update-install';ids=@($updateId)}
 if(-not $installStart.Data.ok){throw 'Selected Windows Update installation action did not start'}
 $installUntil=(Get-Date).AddSeconds(8);$installState=$null
 while((Get-Date)-lt $installUntil){Start-Sleep -Milliseconds 200;$installState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($installState.Data.status.action -eq 'update-install' -and -not $installState.Data.status.running){break}}
 if($installState.Data.status.action -ne 'update-install' -or $installState.Data.devices.Count -ne 0 -or [string]$installState.Data.status.receivedId -notmatch [regex]::Escape($updateId)){$stateJson=ConvertTo-Json -InputObject $installState.Data -Depth 6 -Compress;throw ('Selected Windows Update IDs were not forwarded to the update worker: '+$stateJson)}
 $libraryIds=@('vcredist-x64','directx-legacy')
 $libraryStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='libraries';ids=$libraryIds}
 if(-not $libraryStart.Data.ok){throw 'Windows libraries installation action did not start'}
 $libraryUntil=(Get-Date).AddSeconds(8);$libraryState=$null
 while((Get-Date)-lt $libraryUntil){Start-Sleep -Milliseconds 200;$libraryState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($libraryState.Data.status.action -eq 'libraries' -and -not $libraryState.Data.status.running){break}}
 if($libraryState.Data.status.action -ne 'libraries' -or @($libraryState.Data.status.receivedIds).Count -ne 2 -or $libraryState.Data.status.receivedIds[0] -ne $libraryIds[0] -or $libraryState.Data.status.receivedIds[1] -ne $libraryIds[1]){$stateJson=ConvertTo-Json -InputObject $libraryState.Data -Depth 6 -Compress;throw ('Windows libraries selections were not forwarded to the library worker: '+$stateJson)}
 $prefixedIds=@('device:ACPI\TEST\DEVICE','update:6e9592d0-16ce-4b92-8672-e05978fcc413|1','library:vcredist-x64')
 $selectedStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='selected-install';ids=$prefixedIds}
 if(-not $selectedStart.Data.ok){throw 'Unified selected installation action did not start'}
 $selectedUntil=(Get-Date).AddSeconds(8);$selectedState=$null
 while((Get-Date)-lt $selectedUntil){Start-Sleep -Milliseconds 200;$selectedState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($selectedState.Data.status.action -eq 'selected-install' -and -not $selectedState.Data.status.running){break}}
 if($selectedState.Data.status.action -ne 'selected-install' -or @($selectedState.Data.status.receivedIds).Count -ne 3 -or $selectedState.Data.status.receivedIds[0] -ne $prefixedIds[0] -or $selectedState.Data.status.receivedIds[1] -ne $prefixedIds[1] -or $selectedState.Data.status.receivedIds[2] -ne $prefixedIds[2]){$stateJson=ConvertTo-Json -InputObject $selectedState.Data -Depth 6 -Compress;throw ('Unified selection was not forwarded intact: '+$stateJson)}
 $networkStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='network';ids=@()}
 if(-not $networkStart.Data.ok){throw 'Network repair action did not start'}
 $networkUntil=(Get-Date).AddSeconds(8);$networkState=$null
 while((Get-Date)-lt $networkUntil){Start-Sleep -Milliseconds 200;$networkState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($networkState.Data.status.action -eq 'network' -and -not $networkState.Data.status.running){break}}
 if($networkState.Data.status.action -ne 'network' -or $networkState.Data.status.message -ne 'Test network repair route completed' -or -not (Test-Path -LiteralPath (Join-Path $dataRoot 'State\network-repair-test.marker'))){$stateJson=ConvertTo-Json -InputObject $networkState.Data -Depth 6 -Compress;throw ('Network repair action was not routed to its module: '+$stateJson)}
 [IO.File]::WriteAllText((Join-Path $dataRoot 'State\scan.flag'),'scanned',[Text.Encoding]::ASCII)
 $restoreStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='restore-point';ids=@()}
 if(-not $restoreStart.Data.ok){throw 'Restore point action did not start'}
 $restoreUntil=(Get-Date).AddSeconds(8);$restoreState=$null
 while((Get-Date)-lt $restoreUntil){Start-Sleep -Milliseconds 200;$restoreState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($restoreState.Data.status.action -eq 'restore-point' -and -not $restoreState.Data.status.running){break}}
 if($restoreState.Data.status.action -ne 'restore-point' -or -not $restoreState.Data.scanned -or -not (Test-Path -LiteralPath (Join-Path $dataRoot 'State\restore-point-test.marker'))){$stateJson=ConvertTo-Json -InputObject $restoreState.Data -Depth 6 -Compress;throw ('Restore point action did not preserve scan state or route to its module: '+$stateJson)}
 $repairStart=Invoke-TestRequest $endpoint.url '/api/action' 'POST' $endpoint.token @{action='windows-update-repair';ids=@()}
 if(-not $repairStart.Data.ok){throw 'Windows Update repair action did not start'}
 $repairUntil=(Get-Date).AddSeconds(8);$repairState=$null
 while((Get-Date)-lt $repairUntil){Start-Sleep -Milliseconds 200;$repairState=Invoke-TestRequest $endpoint.url '/api/status' 'GET' $endpoint.token;if($repairState.Data.status.action -eq 'windows-update-repair' -and -not $repairState.Data.status.running){break}}
 if($repairState.Data.status.action -ne 'windows-update-repair' -or -not $repairState.Data.scanned -or -not (Test-Path -LiteralPath (Join-Path $dataRoot 'State\wu-repair-test.marker'))){$stateJson=ConvertTo-Json -InputObject $repairState.Data -Depth 6 -Compress;throw ('Windows Update repair action did not preserve scan state or route to its module: '+$stateJson)}
 if(Test-Path -LiteralPath (Join-Path $engineRoot 'State')){throw 'Runtime files were written into the read-only engine directory'}
 $null=Invoke-TestRequest $endpoint.url '/api/exit' 'POST' $endpoint.token @{}
 if(-not $serverProcess.WaitForExit(10000)){throw 'Embedded server did not exit cleanly'}
 Write-Host 'Garant-ПО integration gate passed: token required on every route except health, no token in bootstrap or page, compile, initial status, Windows Update scan/install and repair routing, library action, unified selection, network repair, restore-point routing and scan-state preservation, loopback, token, SSE, concurrent API, diagnostics, cancel, external data root, clean shutdown.'
}finally{
 if($serverProcess -and -not $serverProcess.HasExited){try{$null=Invoke-TestRequest $endpoint.url '/api/exit' 'POST' $endpoint.token @{};[void]$serverProcess.WaitForExit(5000)}catch{try{$serverProcess.Kill()}catch{}}}
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
 $env:GARANT_PO_DOWNLOAD_DIR=$oldDownloadDir
 $env:GARANT_PO_DRIVER_DIR=$oldDriverDir
 $env:GARANT_PO_LIBRARY_DIR=$oldLibraryDir
}
