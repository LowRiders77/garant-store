# Every Windows component that can be ticked must reach a real installer:
# Core.ps1 libraryId -> Selected.ps1 routing -> Libraries.ps1 allow-list and handler.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$core=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Core.ps1') -Raw -Encoding UTF8
$selected=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Selected.ps1') -Raw -Encoding UTF8
$libraries=Get-Content -LiteralPath (Join-Path $project 'DriverEngine\Libraries.ps1') -Raw -Encoding UTF8
$offered=New-Object System.Collections.Generic.HashSet[string]
foreach($m in [regex]::Matches($core,"libraryId=(?:'([a-z0-9-]+)'|\`$\(if\([^)]*\)\{''\}else\{'([a-z0-9-]+)'\}\)|\`$\(if\([^)]*\)\{'([a-z0-9-]+)'\}else\{''\}\))")){foreach($g in 1..3){if($m.Groups[$g].Success){[void]$offered.Add($m.Groups[$g].Value)}}}
foreach($m in [regex]::Matches($core,"id='(dotnet-desktop[a-z0-9-]*|physx[a-z-]*|openal)'")){[void]$offered.Add($m.Groups[1].Value)}
if($core -match "libraryId=\`$\(if\(\`$isInstalled\)\{''\}else\{\`$major\.id\}\)"){}else{throw 'Desktop runtime rows lost their installer mapping'}
if($core -match "libraryId=\`$\(if\(\`$found\)\{''\}else\{\`$runtime\.id\}\)"){}else{throw 'PhysX/OpenAL rows lost their installer mapping'}
# Explicit contract: the components the window offers for installation.
$expected=@('vcredist-x64','vcredist-x86','directx-legacy','netfx3','webview2','dotnet-desktop','dotnet-desktop-10','windows-app-runtime','physx','physx-legacy','openal')
foreach($id in $expected){
 $inCore=($core -match [regex]::Escape("'"+$id+"'")) -or ($id -like 'vcredist-*' -and $core -match [regex]::Escape("`$id='vcredist-'+`$arch"))
 if(-not $inCore){throw ('Core.ps1 no longer offers component '+$id)}
 [void]$offered.Add($id)
}
$routing=[regex]::Match($selected,"\^library:\(([^)]*)\)\$").Groups[1].Value -split '\|'
$wingetMap=@([regex]::Matches($libraries,"^\s*'([a-z0-9-]+)'='[A-Za-z0-9.+-]+'\s*$",'Multiline')|ForEach-Object{$_.Groups[1].Value})
$direct=@('vcredist-x64','vcredist-x86','directx-legacy','netfx3','webview2')
foreach($id in $offered){
 if($routing -notcontains $id){throw ('Component can be ticked but Selected.ps1 does not route it: '+$id)}
 if($direct -notcontains $id -and $wingetMap -notcontains $id){throw ('Component can be ticked but has no installer: '+$id)}
}
if($libraries -notmatch "\`$allowed=@\('vcredist-x64','vcredist-x86','directx-legacy','netfx3','webview2'\)\+@\(\`$script:GSLibraryWingetIds\.Keys\)"){throw 'Libraries.ps1 allow-list no longer includes the WinGet components'}
Write-Host ('Component routing gate passed: '+$offered.Count+' selectable components reach Selected.ps1 and an installer.')
