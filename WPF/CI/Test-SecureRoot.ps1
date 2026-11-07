# Regression gate for the administrators-only driver engine folder.
# Requires an elevated Windows PowerShell 5.1 session (GitHub Windows runners are elevated).
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'DriverEngine\SecureRoot.ps1')

$programData=[Environment]::GetFolderPath('CommonApplicationData')
$suffix=[guid]::NewGuid().ToString('N')
$secureRoot=Join-Path $programData ('GarantStoreEngine-Test-'+$suffix)
$untrustedRoot=Join-Path $programData ('GarantStoreEngine-Untrusted-'+$suffix)
$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-secure-root-'+$suffix)
$junction=$null
try{
 # 1. A fresh root is created atomically with an administrators-only ACL.
 $created=Initialize-GSSecureDataRoot -Path $secureRoot
 if(-not (Test-Path -LiteralPath $created -PathType Container)){throw 'Secure data root was not created'}
 $problem=Get-GSDirectoryTrustProblem -Path $created
 if($problem){throw ('Freshly created secure root is not trusted: '+$problem)}
 $acl=Get-Acl -LiteralPath $created
 if(-not $acl.AreAccessRulesProtected){throw 'Secure root inherits permissions from ProgramData'}
 $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -ne 'S-1-5-32-544'){throw ('Secure root owner is not Administrators: '+$owner)}
 $usersWrite=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|Where-Object{$_.IdentityReference.Value -eq 'S-1-5-32-545' -and (([int]$_.FileSystemRights -band $script:GSWriteRightsMask) -ne 0)})
 if($usersWrite.Count){throw 'Standard users can write to the secure root'}
 if(-not @($acl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])|Where-Object{$_.IdentityReference.Value -eq 'S-1-3-4'}).Count){throw 'Secure root has no OWNER RIGHTS entry limiting implicit owner permissions'}
 # Children inherit the protected ACL: no standard-user write and OWNER RIGHTS limited to read.
 $child=Join-Path $created 'State'
 New-Item -ItemType Directory -Path $child | Out-Null
 $childAcl=Get-Acl -LiteralPath $child
 $childWriters=@($childAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|Where-Object{$_.AccessControlType -eq 'Allow' -and $script:GSTrustedSids -notcontains $_.IdentityReference.Value -and (([int]$_.FileSystemRights -band $script:GSWriteRightsMask) -ne 0)})
 if($childWriters.Count){throw ('A child folder of the secure root grants write access to: '+(($childWriters|ForEach-Object{$_.IdentityReference.Value}) -join ', '))}
 # Re-initialising an existing trusted root is idempotent.
 $again=Initialize-GSSecureDataRoot -Path $secureRoot
 if($again -ne $created){throw 'Re-initialising the secure root returned a different path'}

 # 2. A pre-existing folder that standard users can modify is refused, not silently reused.
 New-Item -ItemType Directory -Path $untrustedRoot | Out-Null
 $untrustedAcl=Get-Acl -LiteralPath $untrustedRoot
 $users=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
 $untrustedAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'Modify','ContainerInherit,ObjectInherit','None','Allow')))
 Set-Acl -LiteralPath $untrustedRoot -AclObject $untrustedAcl
 $refused=$false
 try{$null=Initialize-GSSecureDataRoot -Path $untrustedRoot}catch{$refused=$true}
 if(-not $refused){throw 'A user-writable pre-existing data root was accepted'}

 # 3. A user-writable parent other than ProgramData is refused.
 New-Item -ItemType Directory -Path $work | Out-Null
 $userParentAcl=Get-Acl -LiteralPath $work
 $userParentAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'Modify','ContainerInherit,ObjectInherit','None','Allow')))
 Set-Acl -LiteralPath $work -AclObject $userParentAcl
 $refusedParent=$false
 try{$null=Initialize-GSSecureDataRoot -Path (Join-Path $work 'engine')}catch{$refusedParent=$true}
 if(-not $refusedParent){throw 'A secure root under a user-writable parent was accepted'}

 # 4. Snapshot copy skips junctions and honours the size cap.
 $source=Join-Path $work 'source'
 New-Item -ItemType Directory -Path (Join-Path $source 'pkg') | Out-Null
 [IO.File]::WriteAllText((Join-Path $source 'pkg\driver.inf'),'[Version]',[Text.Encoding]::ASCII)
 [IO.File]::WriteAllBytes((Join-Path $source 'big.bin'),(New-Object byte[] 4096))
 $junction=Join-Path $source 'redirect'
 $mk=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -ArgumentList @('/c','mklink','/J',('"'+$junction+'"'),('"'+(Join-Path $env:WINDIR 'System32\drivers\etc')+'"')) -Wait -PassThru -WindowStyle Hidden
 if($mk.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $junction)){throw 'Could not create the junction used by the snapshot test'}
 $staging=Join-Path $created 'Staging\copy'
 $copy=Copy-GSUntrustedTree -Source $source -Destination $staging -MaxBytes 1MB
 if(-not (Test-Path -LiteralPath (Join-Path $staging 'pkg\driver.inf'))){throw 'Snapshot copy did not include the driver package'}
 if(Test-Path -LiteralPath (Join-Path $staging 'redirect')){throw 'Snapshot copy followed a junction out of the user folder'}
 if($copy.Skipped -lt 1){throw 'Snapshot copy did not report the skipped junction'}
 $capped=Copy-GSUntrustedTree -Source $source -Destination (Join-Path $created 'Staging\capped') -MaxBytes 100
 if(-not $capped.Truncated){throw 'Snapshot copy ignored its size cap'}

 # 5. User copies never replace the trusted original.
 $userCopyDir=Join-Path $work 'user-downloads'
 $trustedFile=Join-Path $created 'pkg.zip'
 [IO.File]::WriteAllText($trustedFile,'payload',[Text.Encoding]::ASCII)
 if(-not (Publish-GSUserCopy -Path $trustedFile -UserDirectory $userCopyDir)){throw 'User copy was not published'}
 if(-not (Test-Path -LiteralPath (Join-Path $userCopyDir 'pkg.zip'))){throw 'User copy is missing'}
 if(Publish-GSUserCopy -Path $trustedFile -UserDirectory $created){throw 'Publishing into the trusted folder itself must be a no-op'}

 # 6. Static guard: elevated installs never read the user's Downloads directly.
 $worker=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Worker.ps1') -Raw -Encoding UTF8
 foreach($line in ($worker -split "`r?`n")){
  if($line -match 'Install-MatchingInf\s+\$script:(DriverDir|DownloadDir)'){throw ('Worker installs INF directly from a user-writable folder: '+$line.Trim())}
  if($line -match '\$path=Join-Path \$script:DownloadDir'){throw 'Worker downloads packages for installation into the user-writable Downloads folder'}
 }
 $libraries=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Libraries.ps1') -Raw -Encoding UTF8
 if($libraries -match '\$path=Join-Path \$script:LibraryDir'){throw 'Library installers are verified and launched from the user-writable Downloads folder'}

 Write-Host 'Secure driver engine storage gate passed: atomic admin-only root, untrusted root and parent refused, junction-safe capped snapshot, user copies, no direct installs from Downloads.'
}finally{
 if($junction -and (Test-Path -LiteralPath $junction)){[IO.Directory]::Delete($junction)}
 foreach($path in @($secureRoot,$untrustedRoot,$work)){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue}
}
