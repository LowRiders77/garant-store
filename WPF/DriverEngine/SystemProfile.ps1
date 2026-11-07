function Get-GSComputerProfile {
  function Get-GSCimFirst([string]$ClassName){try{return Get-CimInstance -ClassName $ClassName -ErrorAction Stop|Select-Object -First 1}catch{return $null}}
  function Get-GSProfileValue($Object,[string]$Name,$Default=''){if($null -eq $Object){return $Default};$property=$Object.PSObject.Properties[$Name];if($null -eq $property -or $null -eq $property.Value){return $Default};return $property.Value}
  $computer=Get-GSCimFirst 'Win32_ComputerSystem'
  $board=Get-GSCimFirst 'Win32_BaseBoard'
  $bios=Get-GSCimFirst 'Win32_BIOS'
  $os=Get-GSCimFirst 'Win32_OperatingSystem'
  $cpu=Get-GSCimFirst 'Win32_Processor'
  $systemProduct=Get-GSCimFirst 'Win32_ComputerSystemProduct'
  $machine=[string](Get-GSProfileValue $computer 'Manufacturer'); $model=[string](Get-GSProfileValue $computer 'Model')
  if($machine -match '(?i)^(to be filled|default string|system manufacturer|unknown)$'){$machine=''}
  if($model -match '(?i)^(to be filled|default string|system product name|unknown)$'){$model=''}
  $cpuName=[string](Get-GSProfileValue $cpu 'Name')
  $boardManufacturer=[string](Get-GSProfileValue $board 'Manufacturer');$boardProduct=[string](Get-GSProfileValue $board 'Product')
  $boardName=(@($boardManufacturer,$boardProduct)|Where-Object{![string]::IsNullOrWhiteSpace($_)}) -join ' '
  $memoryBytes=[long]0;try{$memoryBytes=[long](@(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop|Measure-Object -Property Capacity -Sum).Sum)}catch{}
  $gpu=@();try{$gpu=@(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop|ForEach-Object{[pscustomobject]@{name=[string]$_.Name;driverVersion=[string]$_.DriverVersion;driverDate=[string]$_.DriverDate}})}catch{}
  $disks=@();try{$disks=@(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop|ForEach-Object{[pscustomobject]@{model=[string]$_.Model;sizeBytes=[long]$_.Size;interface=[string]$_.InterfaceType;mediaType=[string]$_.MediaType}})}catch{}
  $osName=[string](Get-GSProfileValue $os 'Caption');$build=[string](Get-GSProfileValue $os 'BuildNumber');$displayVersion=''
  try{$cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop;if($cv.ProductName){$osName=[string]$cv.ProductName};$displayVersion=[string]$cv.DisplayVersion}catch{}
  if($osName -notmatch '(?i)Windows Server' -and $build -match '^\d+$' -and [int]$build -ge 22000){$osName='Windows 11'}elseif($osName -notmatch '(?i)Windows Server' -and $build -match '^\d+$' -and [int]$build -ge 10240 -and [int]$build -lt 22000){$osName='Windows 10'}
  $wua='Unavailable';try{$wua=[string](Get-Service -Name wuauserv -ErrorAction Stop).Status}catch{}
  $keyParts=@($machine,$model,$boardName,$cpuName,([string][math]::Round($memoryBytes/1GB)))
  foreach($disk in @($disks|Sort-Object model)){ $keyParts+=([string]$disk.model+':'+[string]$disk.sizeBytes) }
  $systemUuid=[string](Get-GSProfileValue $systemProduct 'UUID')
  if($systemUuid -match '^[0-9A-Fa-f-]{36}$' -and $systemUuid -notmatch '^0{8}-0{4}-0{4}-0{4}-0{12}$'){$keyParts+=('SMBIOS-UUID:'+ $systemUuid)}
  $identity=[string]::Join('|',[string[]]$keyParts)
  $sha=[System.Security.Cryptography.SHA256]::Create();try{$fingerprint=[System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($identity))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  return [pscustomobject]@{
    localId=$fingerprint;manufacturer=$(if($machine){$machine}else{'Производитель не определён'});model=$(if($model){$model}else{'Модель не указана в SMBIOS'});machineType=[string](Get-GSProfileValue $computer 'PCSystemType')
    boardManufacturer=$boardManufacturer;boardModel=$boardProduct;biosVersion=[string](Get-GSProfileValue $bios 'SMBIOSBIOSVersion')
    processor=$cpuName;processorManufacturer=[string](Get-GSProfileValue $cpu 'Manufacturer');architecture=[string](Get-GSProfileValue $os 'OSArchitecture');cores=[int](Get-GSProfileValue $cpu 'NumberOfCores' 0);logicalProcessors=[int](Get-GSProfileValue $cpu 'NumberOfLogicalProcessors' 0)
    memoryBytes=$memoryBytes;gpu=$gpu;disks=$disks;windows=$osName;edition=[string](Get-GSProfileValue $os 'Caption');displayVersion=$displayVersion;build=$build;osArchitecture=[string](Get-GSProfileValue $os 'OSArchitecture')
    powerShell=[string]$PSVersionTable.PSVersion;windowsUpdateService=$wua;capturedUtc=(Get-Date).ToUniversalTime().ToString('o')
  }
}

function Get-GSSystemDetail {
  # Independent providers can be absent on client Windows or on virtual machines.
  function Read-GSDetailClass([string]$Class,[string[]]$Fields,[string]$Namespace='root/cimv2',[string]$Filter=''){
    try {
      $query=@{ClassName=$Class;Namespace=$Namespace;Property=$Fields;OperationTimeoutSec=5;ErrorAction='Stop'}
      if($Filter){$query.Filter=$Filter}
      Get-CimInstance @query | Select-Object -Property $Fields
    } catch {}
  }
  [pscustomobject][ordered]@{
    operatingSystem=@(Read-GSDetailClass Win32_OperatingSystem @('Caption','Version','BuildNumber','OSArchitecture','InstallDate','LastBootUpTime','TotalVisibleMemorySize','FreePhysicalMemory'))
    processors=@(Read-GSDetailClass Win32_Processor @('Name','Manufacturer','Architecture','SocketDesignation','NumberOfCores','NumberOfLogicalProcessors','CurrentClockSpeed','MaxClockSpeed','L2CacheSize','L3CacheSize','LoadPercentage'))
    motherboard=@(Read-GSDetailClass Win32_BaseBoard @('Manufacturer','Product','Version'))
    firmware=@(Read-GSDetailClass Win32_BIOS @('Manufacturer','SMBIOSBIOSVersion','ReleaseDate','SMBIOSMajorVersion','SMBIOSMinorVersion'))
    memoryModules=@(Read-GSDetailClass Win32_PhysicalMemory @('DeviceLocator','Capacity','ConfiguredClockSpeed','Speed','SMBIOSMemoryType','FormFactor','Manufacturer'))
    physicalDisks=@(Read-GSDetailClass MSFT_PhysicalDisk @('FriendlyName','Manufacturer','Size','MediaType','BusType','HealthStatus') 'root/Microsoft/Windows/Storage')
    volumes=@(Read-GSDetailClass Win32_LogicalDisk @('DeviceID','FileSystem','Size','FreeSpace') 'root/cimv2' 'DriveType=3')
    graphics=@(Read-GSDetailClass Win32_VideoController @('Name','AdapterCompatibility','DriverVersion','DriverDate','CurrentHorizontalResolution','CurrentVerticalResolution','CurrentRefreshRate'))
    monitors=@(Read-GSDetailClass WmiMonitorID @('UserFriendlyName','ManufacturerName','Active') 'root/wmi' 'Active=TRUE'|ForEach-Object {
      [pscustomobject]@{Name=(-join ($_.UserFriendlyName|Where-Object{$_}|ForEach-Object{[char]$_}));Manufacturer=(-join ($_.ManufacturerName|Where-Object{$_}|ForEach-Object{[char]$_}))}
    })
    network=@(Read-GSDetailClass Win32_NetworkAdapter @('Name','Manufacturer','AdapterType','NetConnectionStatus','Speed','PhysicalAdapter'))
    audio=@(Read-GSDetailClass Win32_SoundDevice @('Name','Manufacturer','Status'))
    peripheral=@(Read-GSDetailClass Win32_PnPEntity @('Name','PNPClass','Status') 'root/cimv2' "PNPClass='USB' OR PNPClass='Keyboard' OR PNPClass='Mouse' OR PNPClass='Bluetooth' OR PNPClass='Camera' OR PNPClass='SCSIAdapter'"|Sort-Object PNPClass,Name,Status -Unique)
  }
}
