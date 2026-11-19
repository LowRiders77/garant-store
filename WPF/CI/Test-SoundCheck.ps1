[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
# Load only the pure helpers from the UI module (no WPF needed).
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'GarantStore.Drivers.ps1'),[ref]$null,[ref]$null)
foreach($name in 'Get-GSDriverProperty','Get-GSSoundTestVerdict'){
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if(-not $fn){throw "Function $name not found"}
 . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$none=Get-GSSoundTestVerdict @() ''
Assert ($none.State -eq 'NoEndpoint' -and -not $none.Play) 'No endpoints must not play or claim success'
$broken=Get-GSSoundTestVerdict @([pscustomobject]@{Status='Error';Name='Speakers'}) ''
Assert ($broken.State -eq 'NoEndpoint' -and $broken.Text -match '1') 'Failed endpoint must be reported as not working'
$ready=Get-GSSoundTestVerdict @([pscustomobject]@{Status='OK';Name='Speakers'}) ''
Assert ($ready.State -eq 'Ready' -and $ready.Play) 'Working endpoint must lead to an audible test, not to a verdict'
$yes=Get-GSSoundTestVerdict @([pscustomobject]@{Status='OK';Name='Speakers'}) 'Yes'
Assert ($yes.State -eq 'Confirmed') 'Operator confirmation must be the only success state'
$no=Get-GSSoundTestVerdict @([pscustomobject]@{Status='OK';Name='Speakers'}) 'No'
Assert ($no.State -eq 'NotHeard' -and $no.Text -notmatch 'подтвержд') 'A driver in OK state must not hide that nothing was heard'
$xaml=Get-Content -LiteralPath (Join-Path $project 'DriverWindow.xaml') -Raw -Encoding UTF8
Assert ($xaml -match 'x:Name="DriverSoundTest"') 'Sound test button is missing from the driver window'
Write-Host 'Sound check gate passed: no endpoint, failed endpoint, audible test, confirmed, not heard, button present.'
