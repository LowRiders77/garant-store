# Garant-PO: trusted storage for files that an elevated worker installs.
# Windows PowerShell 5.1. Everything that pnputil or an installer runs from must
# live in a directory that standard users cannot modify; otherwise a non-admin
# process could replace a package between verification and installation.

$script:GSTrustedSids = @(
 'S-1-5-32-544',  # BUILTIN\Administrators
 'S-1-5-18',      # NT AUTHORITY\SYSTEM
 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' # NT SERVICE\TrustedInstaller
)

# Any of these rights lets a principal change, add, remove or re-permission content.
$script:GSWriteRightsMask = [int](
 0x00000002 -bor # WriteData / CreateFiles
 0x00000004 -bor # AppendData / CreateDirectories
 0x00000010 -bor # WriteExtendedAttributes
 0x00000040 -bor # DeleteSubdirectoriesAndFiles
 0x00000100 -bor # WriteAttributes
 0x00010000 -bor # Delete
 0x00040000 -bor # ChangePermissions (WRITE_DAC)
 0x00080000 -bor # TakeOwnership (WRITE_OWNER)
 0x10000000 -bor # GENERIC_ALL
 0x40000000      # GENERIC_WRITE
)

function New-GSTrustedDirectorySecurity {
 $security = New-Object System.Security.AccessControl.DirectorySecurity
 $security.SetAccessRuleProtection($true,$false)
 $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
 $none = [System.Security.AccessControl.PropagationFlags]::None
 $allow = [System.Security.AccessControl.AccessControlType]::Allow
 $admins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
 $system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
 $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
 $security.SetOwner($admins)
 $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($admins,'FullControl',$inherit,$none,$allow)))
 $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system,'FullControl',$inherit,$none,$allow)))
 $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($users,'ReadAndExecute',$inherit,$none,$allow)))
 # OWNER RIGHTS caps the implicit rights of whoever owns a file inside the root.
 # Without it the owner always keeps WRITE_DAC and could re-permission the file
 # from a non-elevated process that carries the same user SID.
 $ownerRights = New-Object System.Security.Principal.SecurityIdentifier('S-1-3-4')
 $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($ownerRights,'ReadAndExecute',$inherit,$none,$allow)))
 return $security
}

function Get-GSDirectoryTrustProblem {
 # Pure .NET on purpose: Get-Item/Get-Acl live in modules that fail to load when
 # Windows PowerShell inherits a PowerShell 7 PSModulePath from its parent.
 param([Parameter(Mandatory=$true)][string]$Path)
 $item = New-Object IO.DirectoryInfo($Path)
 if (-not $item.Exists) { return 'not a directory' }
 if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 'is a reparse point (junction or symbolic link)' }
 $acl = $item.GetAccessControl([System.Security.AccessControl.AccessControlSections]'Owner,Access')
 $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
 if ($script:GSTrustedSids -notcontains $owner) { return ('owner ' + $owner + ' is not Administrators or SYSTEM') }
 foreach ($rule in $acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])) {
  if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
  $sid = $rule.IdentityReference.Value
  if ($script:GSTrustedSids -contains $sid) { continue }
  if (([int]$rule.FileSystemRights -band $script:GSWriteRightsMask) -ne 0) {
   return ('principal ' + $sid + ' can modify the directory (' + [string]$rule.FileSystemRights + ')')
  }
 }
 return ''
}

function Initialize-GSSecureDataRoot {
 param([Parameter(Mandatory=$true)][string]$Path)
 $full = [IO.Path]::GetFullPath($Path)
 $parent = Split-Path -Parent $full
 if (-not [IO.Directory]::Exists($parent)) {
  throw ('Parent of the secure data root does not exist: ' + $parent)
 }
 $parentProblem = Get-GSDirectoryTrustProblem -Path $parent
 if ($parentProblem) {
  # %ProgramData% lets users create new folders but not delete or rename foreign
  # ones, so a root created there with a protected ACL stays put. Any other
  # user-modifiable parent could swap the root away, so refuse it.
  $programData = [IO.Path]::GetFullPath([Environment]::GetFolderPath('CommonApplicationData'))
  if (-not [string]::Equals($parent.TrimEnd('\'),$programData.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
   throw ('Parent directory is not trusted: ' + $parent + ' (' + $parentProblem + ')')
  }
 }
 if (-not [IO.Directory]::Exists($full) -and -not [IO.File]::Exists($full)) {
  # The ACL is applied atomically at creation: there is no window in which a
  # standard user could add files or change permissions.
  [void][IO.Directory]::CreateDirectory($full,(New-GSTrustedDirectorySecurity))
 }
 $problem = Get-GSDirectoryTrustProblem -Path $full
 if ($problem) {
  throw ('Engine data directory is not trusted and was not used: ' + $full + ' - ' + $problem + '. Delete this folder as administrator and start the driver module again.')
 }
 return $full
}

function Copy-GSUntrustedTree {
 # Snapshot a user-writable folder into a trusted staging folder. Reparse points
 # are skipped so a planted junction cannot redirect the copy, and the total
 # size is capped so a hostile folder cannot exhaust the system disk.
 param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Destination,
  [long]$MaxBytes = 8GB,
  [string[]]$ExcludeDirectories = @()
 )
 $result = [ordered]@{ Files=0; Bytes=[long]0; Skipped=0; Truncated=$false }
 if (-not [IO.Directory]::Exists($Source)) { return [pscustomobject]$result }
 $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\')
 $excluded = @($ExcludeDirectories | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
 $stack = New-Object System.Collections.Generic.Stack[string]
 $stack.Push($sourceRoot)
 while ($stack.Count -gt 0) {
  $directory = $stack.Pop()
  if ($excluded -contains $directory) { continue }
  $info = New-Object IO.DirectoryInfo($directory)
  if ($directory -ne $sourceRoot -and ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $result.Skipped++; continue }
  foreach ($child in $info.GetDirectories()) { $stack.Push($child.FullName) }
  foreach ($file in $info.GetFiles()) {
   if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $result.Skipped++; continue }
   if (($result.Bytes + $file.Length) -gt $MaxBytes) { $result.Truncated = $true; $result.Skipped++; continue }
   $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
   $target = Join-Path $Destination $relative
   [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
   [IO.File]::Copy($file.FullName,$target,$true)
   $result.Files++
   $result.Bytes += $file.Length
  }
 }
 return [pscustomobject]$result
}

function Publish-GSUserCopy {
 # Give the user a convenience copy of a verified package. Never fatal: the
 # trusted copy remains the one that is installed.
 param([Parameter(Mandatory=$true)][string]$Path,[string]$UserDirectory)
 if ([string]::IsNullOrWhiteSpace($UserDirectory)) { return $false }
 $sourceDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $Path)).TrimEnd('\')
 $userFull = [IO.Path]::GetFullPath($UserDirectory).TrimEnd('\')
 if ([string]::Equals($sourceDirectory,$userFull,[StringComparison]::OrdinalIgnoreCase)) { return $false }
 try {
  [void][IO.Directory]::CreateDirectory($userFull)
  $target = Join-Path $userFull ([IO.Path]::GetFileName($Path))
  if ([IO.File]::Exists($target) -and (New-Object IO.FileInfo($target)).Length -eq (New-Object IO.FileInfo($Path)).Length) { return $true }
  [IO.File]::Copy($Path,$target,$true)
  return $true
 } catch {
  return $false
 }
}
