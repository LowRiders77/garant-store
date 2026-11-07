# Regression gate for the elevated Store service helper and the Core-side delegation.
# Uses in-memory service fakes: no real service is changed.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.ServiceHelper.ps1')

$script:fakeServices=@{}
$script:mutations=New-Object System.Collections.Generic.List[string]
function Reset-FakeServices([hashtable]$Rows){
 $script:fakeServices=@{}
 foreach($name in $Rows.Keys){$script:fakeServices[$name]=[pscustomobject]@{Name=$name;State=$Rows[$name][0];StartMode=$Rows[$name][1]}}
 $script:mutations.Clear()
}
function Get-GSHelperServiceRows{return @($script:GSHelperServices|ForEach-Object{$script:fakeServices[$_]})}
function Set-Service{param([string]$Name,[string]$StartupType,$ErrorAction)
 $mode=switch($StartupType){'Automatic'{'Auto'}default{$StartupType}}
 $script:fakeServices[$Name].StartMode=$mode;$script:mutations.Add('set:'+$Name+':'+$mode)}
function Start-Service{param([string]$Name,$ErrorAction)
 if($script:fakeServices[$Name].StartMode -eq 'Disabled'){throw 'disabled'}
 $script:fakeServices[$Name].State='Running';$script:mutations.Add('start:'+$Name)}

$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-service-helper-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try{
 $baseline=Join-Path $work 'baseline.json'

 # 1. Disabled services are enabled and started; the baseline is written first.
 Reset-FakeServices @{wuauserv=@('Stopped','Disabled');BITS=@('Stopped','Manual');InstallService=@('Stopped','Manual');ClipSVC=@('Stopped','Manual');AppXSvc=@('Running','Manual')}
 $enable=Enable-GSHelperServices -BaselineFile $baseline
 if(-not (Test-Path -LiteralPath $baseline)){throw 'Baseline was not recorded before changing a disabled service'}
 if($script:fakeServices.wuauserv.StartMode -ne 'Manual' -or $script:fakeServices.wuauserv.State -ne 'Running'){throw 'Disabled wuauserv was not enabled and started'}
 if(@($enable.Changed) -notcontains 'wuauserv:Disabled->Manual'){throw 'Enable result does not report the startup type change'}
 if($script:mutations -contains 'start:AppXSvc'){throw 'An already running service was started again'}

 # 2. Restore reverts only what was changed, back to the recorded value.
 $script:fakeServices.BITS.StartMode='Auto'  # changed by someone else meanwhile: must be left alone
 $restored=@(Restore-GSHelperBaseline -BaselineFile $baseline)
 if($script:fakeServices.wuauserv.StartMode -ne 'Disabled'){throw 'wuauserv was not restored to Disabled'}
 if($script:fakeServices.BITS.StartMode -ne 'Auto'){throw 'Restore touched a service the helper never changed'}
 if($restored.Count -ne 1){throw ('Unexpected restore list: '+($restored -join ', '))}
 if(Test-Path -LiteralPath $baseline){throw 'Baseline file was not removed after a successful restore'}

 # 3. Nothing disabled: no baseline file, nothing to restore.
 Reset-FakeServices @{wuauserv=@('Stopped','Manual');BITS=@('Running','Manual');InstallService=@('Stopped','Manual');ClipSVC=@('Running','Manual');AppXSvc=@('Running','Manual')}
 $null=Enable-GSHelperServices -BaselineFile $baseline
 if(Test-Path -LiteralPath $baseline){throw 'A baseline was written although no startup type changed'}
 if(@(Restore-GSHelperBaseline -BaselineFile $baseline).Count -ne 0){throw 'Restore without a baseline changed services'}

 # 4. A baseline left by a killed helper is restored on the next run.
 Reset-FakeServices @{wuauserv=@('Running','Manual');BITS=@('Running','Manual');InstallService=@('Running','Manual');ClipSVC=@('Running','Manual');AppXSvc=@('Running','Manual')}
 Write-GSHelperJson -Path $baseline -Value ([ordered]@{Schema=1;Changed=@([pscustomobject]@{Name='wuauserv';StartMode='Disabled'})})
 $recovered=@(Restore-GSHelperBaseline -BaselineFile $baseline)
 if($script:fakeServices.wuauserv.StartMode -ne 'Disabled' -or $recovered.Count -ne 1){throw 'Baseline from an interrupted run was not restored'}

 # 5. The helper waits for Core to exit by any means before it restores.
 $shortArgs=@{FilePath=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;ArgumentList=@('-NoProfile','-Command','Start-Sleep -Milliseconds 700');PassThru=$true}
 if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){$shortArgs.WindowStyle='Hidden'}
 $short=Start-Process @shortArgs
 $watch=[Diagnostics.Stopwatch]::StartNew()
 if(-not (Wait-GSHelperCoreExit -ProcessId $short.Id -MaxWaitSeconds 30)){throw 'Helper did not observe Core exit'}
 if($watch.ElapsedMilliseconds -lt 300){throw 'Helper returned before Core exited'}
 if(-not (Wait-GSHelperCoreExit -ProcessId 2147483000 -MaxWaitSeconds 5)){throw 'Helper did not treat a missing Core process as exited'}

 # 6. Core delegates to the helper only after consent, and never mutates services itself.
 . (Join-Path $project 'GarantStore.Common.ps1')
 . (Join-Path $project 'GarantStore.Deployment.ps1')
 function Write-GSProgress{}
 function Write-GSLog{}
 function Get-GSDeliveryOptimizationConfig{return [pscustomobject]@{Available=$true;DownloadMode='CdnOnly'}}
 function Get-GSStorePolicySnapshot{return [pscustomobject]@{RemoveWindowsStore=$null;DisableWindowsUpdateAccess=$null;DoNotConnectToWindowsUpdateInternetLocations=$null;SetDisableUXWUAccess=$null}}
 $script:snapshotCalls=0;$script:helperCalls=0
 function Get-GSStoreServiceSnapshot{
  $script:snapshotCalls++
  $mode=if($script:helperCalls -gt 0){'Manual'}else{'Disabled'}
  $state=if($script:helperCalls -gt 0){'Running'}else{'Stopped'}
  return @(
   [pscustomobject]@{Name='wuauserv';State=$state;StartMode=$mode},
   [pscustomobject]@{Name='BITS';State='Running';StartMode='Manual'},
   [pscustomobject]@{Name='InstallService';State='Running';StartMode='Manual'},
   [pscustomobject]@{Name='ClipSVC';State='Running';StartMode='Manual'},
   [pscustomobject]@{Name='AppXSvc';State='Running';StartMode='Manual'},
   [pscustomobject]@{Name='DoSvc';State='Running';StartMode='Manual'})
 }
 function Invoke-GSElevatedServiceHelper{$script:helperCalls++;return [pscustomobject]@{Ok=$true;Changed=@('wuauserv:Disabled->Manual','wuauserv:Started');Errors=@();PreviouslyRestored=@()}}
 $script:mutations.Clear()
 $consentRefused=$false
 try{$null=Ensure-GSStoreServicePrerequisites}catch{if($_.Exception.Message -match '^GSERR:StoreServiceConsentRequired:'){$consentRefused=$true}else{throw}}
 if(-not $consentRefused -or $script:helperCalls -ne 0){throw 'Helper was invoked without explicit consent'}
 $prepared=Ensure-GSStoreServicePrerequisites -AllowServiceChanges:$true
 if($script:helperCalls -ne 1){throw 'Core did not delegate the consented change to the elevated helper'}
 if($script:mutations.Count -ne 0){throw 'Core changed services in-process instead of through the helper'}
 if(@($prepared.Changed) -notcontains 'wuauserv:Disabled->Manual'){throw 'Helper outcome was not reported by Core'}
 $declined=ConvertFrom-GSException (New-GSClassifiedException -Code 'ServiceElevationDeclined' -Message 'cancelled')
 if($declined.Status -ne 'Cancelled' -or $declined.UserMessage -notmatch 'Microsoft Store'){throw 'Declined elevation does not produce a clear user message'}

 Write-Host 'Store service helper gate passed: baseline before change, selective restore, crash recovery, restore after Core exit, consent-gated delegation, no in-process mutation.'
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
