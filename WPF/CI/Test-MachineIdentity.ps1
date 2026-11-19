# Stable machine ID (field: Lenovo 81W8 changed localId when a USB NVMe was
# unplugged, splitting its history). The ID must not depend on disks, RAM,
# CPU or Windows build; placeholder SMBIOS values of Chinese boards fall back
# to another source; history saved under old IDs is merged without loss.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
function Import-GSFunction([string]$File,[string]$Name){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($File,[ref]$t,[ref]$e)
 $f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name}.GetNewClosure(),$true)
 if(-not $f){throw ($Name+' is missing from '+$File)}
 return $f.Extent.Text
}
foreach($n in @('Get-GSSha256Hex','Test-GSPlaceholderIdentifier','Get-GSWindowsMachineGuid','Get-GSMachineIdentity','Get-GSComputerProfile')){. ([scriptblock]::Create((Import-GSFunction (Join-Path $project 'DriverEngine\SystemProfile.ps1') $n)))}
foreach($n in @('Save-JsonFile','Load-JsonFile','Merge-GSLegacyDeviceHistory')){. ([scriptblock]::Create((Import-GSFunction (Join-Path $project 'DriverEngine\Core.ps1') $n)))}
function Assert-Equal($Name,$Expected,$Actual){if([string]$Expected -cne [string]$Actual){throw ($Name+': expected <'+$Expected+'>, got <'+$Actual+'>')}}

foreach($p in @('','Default string','To be filled by O.E.M.','03000200-0400-0500-0006-000700080009','00000000-0000-0000-0000-000000000000','FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF','123456789','0','None','System Serial Number')){if(-not (Test-GSPlaceholderIdentifier $p)){throw ('placeholder accepted: '+$p)}}
foreach($v in @('A1B2C3D4-0000-4000-8000-0123456789AB','PF2ABCDE','MP1XYZ12')){if(Test-GSPlaceholderIdentifier $v){throw ('real identifier rejected: '+$v)}}

$a=Get-GSMachineIdentity -Manufacturer 'LENOVO' -BoardManufacturer 'LENOVO' -BoardProduct 'LNVNB161216' -SystemUuid 'A1B2C3D4-0000-4000-8000-0123456789AB' -BoardSerial 'PF2ABCDE' -BiosSerial 'PF2ABCDE' -MachineGuid 'g'
Assert-Equal 'uuid basis' 'smbios-uuid' $a.Basis
$china=Get-GSMachineIdentity -Manufacturer 'T159R' -BoardManufacturer '' -BoardProduct 'EM_APX938_V2.0' -SystemUuid '03000200-0400-0500-0006-000700080009' -BoardSerial 'Default string' -BiosSerial '123456789' -MachineGuid 'B1E2C3D4-1111-2222-3333-444455556666'
Assert-Equal 'placeholder firmware -> MachineGuid' 'windows-machine-guid' $china.Basis
$other=Get-GSMachineIdentity -Manufacturer 'T159R' -BoardManufacturer '' -BoardProduct 'EM_APX938_V2.0' -SystemUuid '03000200-0400-0500-0006-000700080009' -BoardSerial 'Default string' -BiosSerial '123456789' -MachineGuid 'A9E2C3D4-1111-2222-3333-444455556666'
if($china.Id -eq $other.Id){throw 'two machines with the same placeholder UUID got the same ID'}

# Full profile: unplugging the USB NVMe, adding RAM and a Windows update keep the ID.
$script:disks=@([pscustomobject]@{Model='WDC PC SN520';Size=128034708480;InterfaceType='SCSI';MediaType='Fixed hard disk media'},[pscustomobject]@{Model='Realtek RTL9210 NVME';Size=512105932800;InterfaceType='SCSI';MediaType='External hard disk media'})
$script:ram=8589934592;$script:build='26100'
function Get-CimInstance { [CmdletBinding()]param([string]$ClassName)
 switch($ClassName){
  'Win32_ComputerSystem'{[pscustomobject]@{Manufacturer='LENOVO';Model='81W8';PCSystemType=2}}
  'Win32_BaseBoard'{[pscustomobject]@{Manufacturer='LENOVO';Product='LNVNB161216';SerialNumber='PF2ABCDE'}}
  'Win32_BIOS'{[pscustomobject]@{SMBIOSBIOSVersion='DKCN26WW';SerialNumber='PF2ABCDE'}}
  'Win32_OperatingSystem'{[pscustomobject]@{Caption='Windows 11 Pro';BuildNumber=$script:build;OSArchitecture='64-bit'}}
  'Win32_Processor'{[pscustomobject]@{Name='Intel(R) Core(TM) i5-1035G1';Manufacturer='GenuineIntel';NumberOfCores=4;NumberOfLogicalProcessors=8}}
  'Win32_ComputerSystemProduct'{[pscustomobject]@{UUID='A1B2C3D4-0000-4000-8000-0123456789AB'}}
  'Win32_PhysicalMemory'{[pscustomobject]@{Capacity=$script:ram}}
  'Win32_VideoController'{}
  'Win32_DiskDrive'{$script:disks}
 }
}
function Get-ItemProperty { [CmdletBinding()]param([string]$LiteralPath,[string]$Name) throw 'n/a' }
function Get-Service { [CmdletBinding()]param([string]$Name) [pscustomobject]@{Status='Running'} }
$before=Get-GSComputerProfile
$script:disks=@($script:disks[0]);$script:ram=17179869184;$script:build='26200'
$after=Get-GSComputerProfile
Assert-Equal 'localId stable across disk/RAM/build changes' $before.localId $after.localId
if($before.legacyLocalId -eq $after.legacyLocalId){throw 'fixture error: the old algorithm should have changed'}

# Migration: history under two old IDs is merged into the new one, nothing lost, idempotent.
$script:DataRoot=Join-Path ([IO.Path]::GetTempPath()) ('gs-id-'+[guid]::NewGuid().ToString('N'))
$devices=Join-Path $script:DataRoot 'Devices'
try{
 $env:GARANT_PO_DATA_ROOT=''
 foreach($pair in @(@($before.legacyLocalId,'2026-11-19T14:23:52Z','2026-11-19T14:37:58Z'),@($after.legacyLocalId,'2026-11-19T14:55:06Z','2026-11-19T14:56:41Z'))){
  $dir=Join-Path $devices $pair[0];New-Item -ItemType Directory -Force -Path $dir|Out-Null
  Save-JsonFile (Join-Path $dir 'sessions.json') @(@($pair[1],$pair[2])|ForEach-Object{[pscustomobject]@{capturedUtc=$_;localId=$pair[0];problemCount=1}})
 }
 $merged=@(Merge-GSLegacyDeviceHistory -Profile $after)
 Assert-Equal 'two legacy folders merged' 2 $merged.Count
 $history=@(Load-JsonFile (Join-Path (Join-Path $devices $after.localId) 'sessions.json') @())
 Assert-Equal 'all four sessions kept' 4 $history.Count
 Assert-Equal 'newest first' ([datetime]'2026-11-19T14:56:41Z').ToUniversalTime().ToString('o') (([datetime]$history[0].capturedUtc).ToUniversalTime().ToString('o'))
 if(-not (Test-Path -LiteralPath (Join-Path (Join-Path $devices $before.legacyLocalId) 'sessions.json'))){throw 'legacy folder must be kept'}
 Assert-Equal 'second run merges nothing' 0 @(Merge-GSLegacyDeviceHistory -Profile $after).Count
 Assert-Equal 'no duplicates after rerun' 4 @(Load-JsonFile (Join-Path (Join-Path $devices $after.localId) 'sessions.json') @()).Count
}finally{Remove-Item -LiteralPath $script:DataRoot -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item Env:\GARANT_PO_DATA_ROOT -ErrorAction SilentlyContinue}
Write-Host 'Machine identity gate passed: placeholder SMBIOS, stable ID across disk/RAM/Windows changes, lossless history migration.'
