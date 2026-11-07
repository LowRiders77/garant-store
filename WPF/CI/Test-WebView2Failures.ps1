[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\DriverEngine\Libraries.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Libraries.ps1 has parsing errors.'}
$definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ValidMicrosoftInstaller'},$true)|Select-Object -First 1
if(-not $definition){throw 'Installer authenticity verification function is missing.'}
. ([scriptblock]::Create($definition.Extent.Text))
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gs-webview2-negative-'+[guid]::NewGuid().ToString('N'))
# Installers are verified and run from the trusted engine folder; the user's
# Downloads folder only ever receives a copy of a verified file.
$script:EngineLibraryDir=Join-Path $testRoot 'engine'
$script:LibraryDir=Join-Path $testRoot 'user-downloads'
New-Item -ItemType Directory -Force -Path $script:EngineLibraryDir,$script:LibraryDir|Out-Null
$script:LatestLog=Join-Path $testRoot 'negative.log'
function Publish-GSUserCopy{param([string]$Path,[string]$UserDirectory)Copy-Item -LiteralPath $Path -Destination $UserDirectory;return $true}
function Write-LibraryLog([string]$message){Add-Content -LiteralPath $script:LatestLog -Value $message}
try{
 function Invoke-WebRequest {
  param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing,[int]$TimeoutSec)
  throw 'GS_TEST_NETWORK_FAILURE'
 }
 $failed=$false
 try{$null=Get-ValidMicrosoftInstaller 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' 'WebView2-DownloadFailure.exe'}catch{$failed=($_.Exception.Message -match 'GS_TEST_NETWORK_FAILURE')}
 if(-not $failed){throw 'Network error was swallowed instead of preventing installation.'}
 if(Test-Path -LiteralPath (Join-Path $script:EngineLibraryDir 'WebView2-DownloadFailure.exe')){throw 'Failed download was incorrectly accepted.'}
 Remove-Item Function:\Invoke-WebRequest -Force
 function Invoke-WebRequest {
  param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing,[int]$TimeoutSec)
  [IO.File]::WriteAllBytes($OutFile,(New-Object byte[] 20000))
 }
 $rejected=$false
 try{$null=Get-ValidMicrosoftInstaller 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' 'WebView2-InvalidSignature.exe'}catch{$rejected=($_.Exception.Message -match 'подпись Microsoft')}
 if(-not $rejected){throw 'Unsigned downloaded binary was not rejected.'}
 if(Test-Path -LiteralPath (Join-Path $script:EngineLibraryDir 'WebView2-InvalidSignature.exe')){throw 'Unsigned installer was retained.'}
 if(Test-Path -LiteralPath (Join-Path $script:EngineLibraryDir 'WebView2-InvalidSignature.exe.partial.exe')){throw 'Unsigned partial download was not removed.'}
 if(@(Get-ChildItem -LiteralPath $script:LibraryDir -File).Count){throw 'A rejected installer was copied to the user Downloads folder.'}
 Write-Host 'WebView2 negative checks passed: network failure and unsigned payload rejected.'
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
