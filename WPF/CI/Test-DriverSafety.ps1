# Driver safety from the Lenovo IdeaPad S145-15IIL (81W8) field case:
#  Intel High Definition DSP (Code 28) INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA
#  must not receive the Realtek codec package (INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848)
#  and vice versa; a DRP path label FORCED is not mistaken for a PnPUtil force
#  command, while comment-only IDs, wrong architecture/build/class are rejected.
#  summary says "source unavailable", not "driver not found".
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'DriverEngine\DriverSafety.ps1')
function Assert-Equal($Name,$Expected,$Actual){if([string]$Expected -cne [string]$Actual){throw ($Name+': expected <'+$Expected+'>, got <'+$Actual+'>')}}
$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-safety-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
function New-Inf([string]$Name,[string]$Body){$p=Join-Path $work $Name;New-Item -ItemType Directory -Force -Path (Split-Path $p)|Out-Null;[IO.File]::WriteAllText($p,$Body,[Text.Encoding]::Unicode);return $p}
try{
 $sst=New-Inf 'Intel-SST\IntcOED.inf' "[Version]`r`nSignature=`"`$WINDOWS NT`$`"`r`nClass=System`r`nProvider=%Intel%`r`n[Manufacturer]`r`n%Intel%=Intel,NTamd64.10.0...17763`r`n[Intel.NTamd64.10.0...17763]`r`n%DSP%=OED_Install,INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222`r`n[Strings]`r`nIntel=`"Intel`"`r`nDSP=`"Intel Smart Sound Technology OED`"`r`n"
 $codec=New-Inf 'Realtek\HDXIdeaPad.inf' "[Version]`r`nClass=MEDIA`r`n[Manufacturer]`r`n%Rtk%=Realtek,NTamd64`r`n[Realtek.NTamd64]`r`n%Codec%=Codec_Install,INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848, HDAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848`r`n"
 $comment=New-Inf 'Other\comment.inf' "[Version]`r`nClass=System`r`n; supports INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222 (not really)`r`n[Manufacturer]`r`n%X%=X,NTamd64`r`n[X.NTamd64]`r`n%Y%=Y,PCI\VEN_8086&DEV_1234`r`n"
 $forced=New-Inf 'Intel-FORCED-Bus-10x64-17763-HDAudioOEDrv_10.24.5427.210_icl-drp\IntcOED.inf' "[Version]`r`nClass=System`r`nDriverVer=10/01/2026,10.24.5427.210`r`nCatalogFile=IntcOED.cat`r`n[Manufacturer]`r`n%Intel%=Intel,NTamd64`r`n[Intel.NTamd64]`r`n%DSP%=OED,INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA&REV_0030,INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848&REV_1000`r`n"
 [IO.File]::WriteAllBytes((Join-Path (Split-Path $forced -Parent) 'IntcOED.cat'),[byte[]](1,2,3))
 $arm=New-Inf 'Arm\arm.inf' "[Version]`r`nClass=System`r`n[Manufacturer]`r`n%Intel%=Intel,NTarm64`r`n[Intel.NTarm64]`r`n%DSP%=OED,INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA`r`n"
 $future=New-Inf 'Future\future.inf' "[Version]`r`nClass=System`r`n[Manufacturer]`r`n%Intel%=Intel,NTamd64.10.0...99999`r`n[Intel.NTamd64.10.0...99999]`r`n%DSP%=OED,INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA`r`n"

 $m=Get-GSInfModel -Path $sst -Architecture x64 -Build 26100
 Assert-Equal 'class parsed' 'System' $m.Class
 if(-not $m.Ids.Contains('INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222')){throw 'SST id not parsed'}
 Assert-Equal 'comment ignored' $false ((Get-GSInfModel -Path $comment).Ids.Contains('INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222'))
 Assert-Equal 'arm64 section not applicable on x64' 0 (Get-GSInfModel -Path $arm -Architecture x64 -Build 26100).Ids.Count
 Assert-Equal 'newer-build section not applicable' 0 (Get-GSInfModel -Path $future -Architecture x64 -Build 26100).Ids.Count
 Assert-Equal 'older build accepted' $true (Test-GSInfDecoration 'NTamd64.10.0...17763' 'x64' 19041)
 Assert-Equal 'win7-era build blocked by min build' $false (Test-GSInfDecoration 'NTamd64.10.0...17763' 'x64' 10240)

 $models=@($sst,$codec,$comment,$forced,$arm,$future|ForEach-Object{Get-GSInfModel -Path $_ -Architecture x64 -Build 26100})
 $dsp=[pscustomobject]@{name='Intel High Definition DSP';instanceId='INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA&REV_0030\4&22FEE311&0&0800';category='';hardwareIds=@('INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA&REV_0030','INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222&SUBSYS_384017AA','INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222')}
 $rtk=[pscustomobject]@{name='Realtek Audio';instanceId='INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848&REV_1000\5&1';category='MEDIA';hardwareIds=@('INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848&REV_1000','INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230&SUBSYS_17AA3848','INTELAUDIO\FUNC_01&VEN_10EC&DEV_0230')}
 $d=Select-GSInfForDevice -Device $dsp -Models $models
 Assert-Equal 'DSP gets the Intel SST INF' $sst $d.Model.Path
 Assert-Equal 'DSP match is generic Intel' 3 $d.Tier
 $r=Select-GSInfForDevice -Device $rtk -Models $models
 Assert-Equal 'codec gets the Realtek INF' $codec $r.Model.Path
 Assert-Equal 'codec match is OEM subsystem' 1 $r.Tier
 $onlyCodec=@(Get-GSInfModel -Path $codec)
 Assert-Equal 'DSP never takes the codec package' $null (Select-GSInfForDevice -Device $dsp -Models $onlyCodec).Model
 $onlyForced=@(Get-GSInfModel -Path $forced)
 $f=Select-GSInfForDevice -Device $dsp -Models $onlyForced
 if($null -eq $f.Model){throw 'An exactly matching INF was rejected only because the folder contains FORCED'}
 $forcedByName=Select-GSInfForDevice -Device $dsp -Models $onlyForced -PackageName 'Intel-FORCED-Bus-10x64-17763-HDAudioOEDrv_10.24.5427.210_icl-drp.zip'
 if($null -eq $forcedByName.Model -or -not $forcedByName.SourceMarkedForced -or $forcedByName.Reason -notmatch 'принудительный режим PnPUtil не используется'){throw 'FORCED metadata was not handled safely and transparently'}
 $other=[pscustomobject]@{name='Other';instanceId='PCI\VEN_1234&DEV_5678\1';category='System';hardwareIds=@('PCI\VEN_1234&DEV_5678');compatibleIds=@()}
 if($null -ne (Select-GSInfForDevice -Device $other -Models $onlyForced -PackageName 'Intel-FORCED-Test.zip').Model){throw 'FORCED metadata bypassed the exact device-ID check'}
 $trust=Test-GSInfPackageTrust -Model $onlyForced[0] -SignatureResolver {param($p)[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Test WHQL'}}}
 if(-not $trust.Trusted){throw ('Signed catalog fixture was rejected: '+$trust.Reason)}
 $noCatalog=Get-GSInfModel -Path $sst
 if((Test-GSInfPackageTrust -Model $noCatalog -SignatureResolver {param($p)$null}).Trusted){throw 'INF without a catalog was accepted for automatic installation'}
 $compatibleOnly=[pscustomobject]@{name='Compatible';instanceId='X';category='System';hardwareIds=@('PCI\VEN_8086&DEV_FFFF&SUBSYS_00000000');compatibleIds=@('INTELAUDIO\DSP_CTLR_DEV_34C8&VEN_8086&DEV_0222')}
 if($null -eq (Select-GSInfForDevice -Device $compatibleOnly -Models @(Get-GSInfModel -Path $sst)).Model){throw 'A PnP Compatible ID was ignored'}
 $dspMedia=[pscustomobject]@{name='DSP';instanceId='x';category='MEDIA';hardwareIds=$dsp.hardwareIds}
 $cls=Select-GSInfForDevice -Device $dspMedia -Models @(Get-GSInfModel -Path $sst)
 if($null -ne $cls.Model -or $cls.Reason -notmatch 'класс'){throw 'INF of another device class accepted'}

 # DriverPack 403: pause, no per-ID hammering; summary says source unavailable.
 $health=Join-Path $work 'source-health.json'
 $t0=[datetime]'2026-11-19T17:56:42'
 Assert-Equal '403 classified' 'Blocked' (Register-GSSourceResult -Path $health -Url 'https://driverpack.io/en/hwids/X' -HttpCode '403' -CurlCode 0 -Now $t0)
 Assert-Equal 'source paused' 'HTTP 403' (Test-GSSourceBlocked -Path $health -Url 'https://driverpack.io/en/hwids/Y' -Now $t0.AddMinutes(1))
 Assert-Equal 'other host unaffected' $null (Test-GSSourceBlocked -Path $health -Url 'https://www.nvidia.com/x' -Now $t0.AddMinutes(1))
 Assert-Equal 'pause expires' $null (Test-GSSourceBlocked -Path $health -Url 'https://driverpack.io/' -Now $t0.AddMinutes(31))
 foreach($i in 1..3){$null=Register-GSSourceResult -Path $health -Url 'https://dl.driverpack.io/a.zip' -HttpCode '000' -CurlCode 28 -Now $t0}
 Assert-Equal 'three network failures pause' 'нет связи' (Test-GSSourceBlocked -Path $health -Url 'https://dl.driverpack.io/b.zip' -Now $t0.AddMinutes(1))
 $null=Register-GSSourceResult -Path $health -Url 'https://dl.driverpack.io/a.zip' -HttpCode '200' -CurlCode 0 -Now $t0.AddMinutes(2)
 Assert-Equal 'success clears pause' $null (Test-GSSourceBlocked -Path $health -Url 'https://dl.driverpack.io/b.zip' -Now $t0.AddMinutes(3))
 Assert-Equal '404 is not-found' 'NotFound' (Get-GSFetchClassification '404' 0)

 $sum=Format-GSOutcomeSummary -Outcomes @{dsp='SourceUnavailable'} -RemainingIds @('dsp') -WindowsUpdateState 'Disabled' -VendorUrl (Get-GSVendorSupportUrl 'LENOVO' '81W8')
 if($sum -match 'не найден'){throw ('source outage reported as "not found": '+$sum)}
 if($sum -notmatch 'недоступен' -or $sum -notmatch 'Windows Update отключена' -or $sum -notmatch 'pcsupport\.lenovo\.com'){throw ('summary incomplete: '+$sum)}
 $sum2=Format-GSOutcomeSummary -Outcomes @{a='NotFound';b='Incompatible';c='Installed'} -RemainingIds @('a','b')
 if($sum2 -notmatch 'не найден проверенный пакет: 1' -or $sum2 -notmatch 'не подходит устройству'){throw ('summary 2: '+$sum2)}

 # Audio verification after install.
 $before=[pscustomobject]@{Devices=@([pscustomobject]@{InstanceId='DSP';Name='Intel High Definition DSP';Status='Error';Problem='28'},[pscustomobject]@{InstanceId='RTK';Name='Realtek Audio';Status='OK';Problem=''});Endpoints=@()}
 $ok=[pscustomobject]@{Devices=@([pscustomobject]@{InstanceId='DSP';Name='Intel Smart Sound Technology OED';Status='OK';Problem=''},[pscustomobject]@{InstanceId='RTK';Name='Realtek Audio';Status='OK';Problem=''});Endpoints=@([pscustomobject]@{Name='Динамики (Realtek)';Status='OK'})}
 Assert-Equal 'audio ok' 'DriverOk' (Compare-GSAudioHealth $before $ok).State
 if((Compare-GSAudioHealth $before $ok).Text -notmatch 'Проверить звук'){throw 'speaker test not requested'}
 $noEp=[pscustomobject]@{Devices=$ok.Devices;Endpoints=@()}
 Assert-Equal 'no endpoint' 'NoEndpoint' (Compare-GSAudioHealth $before $noEp).State
 $reg=[pscustomobject]@{Devices=@([pscustomobject]@{InstanceId='DSP';Name='DSP';Status='OK';Problem=''},[pscustomobject]@{InstanceId='RTK';Name='Realtek Audio';Status='Error';Problem='10'});Endpoints=@()}
 Assert-Equal 'regression detected' 'Regression' (Compare-GSAudioHealth $before $reg).State
 Assert-Equal 'dsp is audio' $true (Test-GSAudioDevice $dsp)
}finally{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'Driver safety gate passed: exact Hardware/Compatible-ID selection, safe FORCED metadata handling, catalog trust, class/arch/build rejection, DRP pause, honest summary, audio verification.'
