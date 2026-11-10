# Official GPU drivers: NVIDIA lookup tables (nvidia.com lookupValueSearch),
# AjaxDriverService answer, pci.ids naming for a GPU still on the basic driver,
# AMD Auto-Detect link. Network is replaced by fixtures in the real formats.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'DriverEngine\VendorGpu.ps1')
function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected <'+$Expected+'>, got <'+$Actual+'>')} }
$script:log=New-Object System.Collections.Generic.List[string]
function Log([string]$m){$script:log.Add($m)}
function Get-NormalIds($d){@($d.hardwareIds)}

$seriesXml='<?xml version="1.0"?><LookupValueSearch><LookupValues><LookupValue ParentID="1"><Name>GeForce RTX 50 Series</Name><Value>131</Value></LookupValue><LookupValue ParentID="1"><Name>GeForce RTX 30 Series (Notebooks)</Name><Value>123</Value></LookupValue><LookupValue ParentID="1"><Name>GeForce 10 Series</Name><Value>101</Value></LookupValue></LookupValues></LookupValueSearch>'
$productXml='<?xml version="1.0"?><LookupValueSearch><LookupValues><LookupValue ParentID="131"><Name>NVIDIA GeForce RTX 5060</Name><Value>1074</Value></LookupValue><LookupValue ParentID="131"><Name>NVIDIA GeForce RTX 5060 Ti</Name><Value>1076</Value></LookupValue><LookupValue ParentID="123"><Name>NVIDIA GeForce RTX 3050 Laptop GPU</Name><Value>963</Value></LookupValue><LookupValue ParentID="101"><Name>GeForce GTX 1060 6GB</Name><Value>817</Value></LookupValue></LookupValues></LookupValueSearch>'
$series=@(ConvertFrom-GSNvidiaLookupXml $seriesXml)
$products=@(ConvertFrom-GSNvidiaLookupXml $productXml)
Assert-Equal 'products parsed' 4 $products.Count
$map=Get-GSNvidiaProductMap -Series $series -Products $products
Assert-Equal 'desktop 5060' '1074' (Find-GSNvidiaPfid -Map $map -GpuName 'NVIDIA GeForce RTX 5060' -IsNotebook $false)
Assert-Equal '5060 Ti not confused' '1076' (Find-GSNvidiaPfid -Map $map -GpuName 'NVIDIA GeForce RTX 5060 Ti' -IsNotebook $false)
Assert-Equal 'memory suffix ignored' '817' (Find-GSNvidiaPfid -Map $map -GpuName 'NVIDIA GeForce GTX 1060 6GB' -IsNotebook $false)
Assert-Equal 'pci.ids Mobile -> Laptop GPU' '963' (Find-GSNvidiaPfid -Map $map -GpuName 'GeForce RTX 3050 Mobile' -IsNotebook $true)
Assert-Equal 'unknown gpu' '' (Find-GSNvidiaPfid -Map $map -GpuName 'GeForce 210' -IsNotebook $false)

$pci="# pci.ids`n10de  NVIDIA Corporation`n`t1c03  GP106 [GeForce GTX 1060 6GB]`n`t2d05  GB206 [GeForce RTX 5060]`n`t25a2  GA107M [GeForce RTX 3050 Mobile]`n10df  Emulex Corporation`n`t2d05  Not NVIDIA"
Assert-Equal 'pci name' 'GeForce RTX 5060' (Get-GSNvidiaNameFromPciIds $pci '2D05')
Assert-Equal 'pci other vendor ignored' '' (Get-GSNvidiaNameFromPciIds $pci '9999')

$json='{"Success":"1","IDS":[{"downloadInfo":{"Success":"1","ID":"260000","Version":"595.97","Name":"GeForce%20Game%20Ready%20Driver","DownloadURL":"https://us.download.nvidia.com/Windows/595.97/595.97-desktop-win10-win11-64bit-international-dch-whql.exe"}}]}'
$info=Get-GSNvidiaDownloadInfo $json
Assert-Equal 'nvidia version' '595.97' $info.Version
Assert-Equal 'nvidia name decoded' 'GeForce Game Ready Driver' $info.Name
if($null -ne (Get-GSNvidiaDownloadInfo ($json -replace 'us.download.nvidia.com','evil.example.com'))){throw 'non-NVIDIA host accepted'}
if($null -ne (Get-GSNvidiaDownloadInfo '{"Success":"0"}')){throw 'failed lookup accepted'}

# Basic display adapter (fresh Windows): name from pci.ids, then official package.
$device=[pscustomobject]@{name='Базовый видеоадаптер (Майкрософт)';kind='GPU';hardwareIds=@('PCI\VEN_10DE&DEV_2D05&SUBSYS_00001462','PCI\VEN_10DE&DEV_2D05')}
$fetch={param($u,$r) if($u -like '*pci.ids'){return $pci}; if($u -like '*TypeID=2'){return $seriesXml}; if($u -like '*TypeID=3'){return $productXml}; if($u -like '*AjaxDriverService*pfid=1074*osID=57*dch=1*'){return $json}; return $null}.GetNewClosure()
$pkg=Resolve-GSNvidiaOfficialDriver -Device $device -Fetch $fetch -IsNotebook $false
Assert-Equal 'package kind' 'NvidiaGPU' $pkg.kind
Assert-Equal 'package url' 'https://us.download.nvidia.com/Windows/595.97/595.97-desktop-win10-win11-64bit-international-dch-whql.exe' $pkg.url
Assert-Equal 'package version' '595.97' $pkg.version
$named=[pscustomobject]@{name='NVIDIA GeForce RTX 5060';kind='GPU';hardwareIds=@('PCI\VEN_10DE&DEV_2D05')}
$noPci={param($u,$r) if($u -like '*pci.ids'){throw 'pci.ids must not be needed when the name is known'}; & $fetch $u $r}.GetNewClosure()
Assert-Equal 'named gpu skips pci.ids' 'NvidiaGPU' (Resolve-GSNvidiaOfficialDriver -Device $named -Fetch $noPci -IsNotebook $false).kind
$offline={param($u,$r) $null}
if($null -ne (Resolve-GSNvidiaOfficialDriver -Device $named -Fetch $offline -IsNotebook $false)){throw 'offline lookup must fall back'}

$amdHtml='<a href="https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.10.2-minimalsetup-261103_web.exe">Download</a>'
Assert-Equal 'amd link' 'https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.10.2-minimalsetup-261103_web.exe' (Find-GSAmdInstallerUrl $amdHtml)
Assert-Equal 'no amd link' '' (Find-GSAmdInstallerUrl '<html>blocked</html>')
Write-Host 'Vendor GPU gate passed: NVIDIA lookup tables, pci.ids naming, official download info, AMD Auto-Detect link.'
