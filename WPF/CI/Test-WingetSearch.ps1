[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Parser.ps1')
. (Join-Path $project 'GarantStore.Winget.ps1')

function Assert-Equal {
    param([string]$Name,[object]$Expected,[object]$Actual)
    if ($Expected -cne $Actual) {
        throw ($Name+': expected "'+[string]$Expected+'", got "'+[string]$Actual+'"')
    }
}

# WinGet may return usable rows from one source and an error/no-results message
# from another. The valid package must survive the non-zero process exit.
$partial=ConvertFrom-GSWingetSearchCapture `
    -ExitCode 1 `
    -StdOut '7-Zip 7zip.7zip 24.09 winget' `
    -StdErr 'No packages found in msstore source.' `
    -FallbackSource ''
Assert-Equal 'partial search row count' 1 @($partial).Count
Assert-Equal 'partial search package id' '7zip.7zip' ([string]$partial[0].Id)
Assert-Equal 'partial search source' 'winget' ([string]$partial[0].Source)

# A genuine no-match response remains a clean empty result.
$empty=ConvertFrom-GSWingetSearchCapture -ExitCode -1978335212 -StdOut '' -StdErr '' -FallbackSource ''
Assert-Equal 'no-match row count' 0 @($empty).Count

# An unexplained process failure with no parseable rows must remain an error.
$threw=$false
try {
    [void](ConvertFrom-GSWingetSearchCapture -ExitCode 1 -StdOut '' -StdErr 'Network unavailable' -FallbackSource '')
} catch {
    $threw=$true
    if ($_.Exception.Message -notmatch 'WingetError') { throw }
}
Assert-Equal 'unexplained failure is not an empty search' $true $threw

$capabilities=@{
    '--query'=$true
    '--count'=$true
    '--disable-interactivity'=$true
    '--accept-source-agreements'=$true
}
$withoutConsent=New-GSWingetSearchArguments -Query 'WhatsApp' -Source 'msstore' -AcceptAgreements:$false -Capabilities $capabilities
Assert-Equal 'search does not accept Store terms implicitly' $false ($withoutConsent -contains '--accept-source-agreements')
$withConsent=New-GSWingetSearchArguments -Query 'WhatsApp' -Source 'msstore' -AcceptAgreements:$true -Capabilities $capabilities
Assert-Equal 'explicit consent accepts Store source terms' $true ($withConsent -contains '--accept-source-agreements')
$withoutHelpText=New-GSWingetSearchArguments -Query 'WhatsApp' -Source '' -AcceptAgreements:$true -Capabilities @{
    '--query'=$true
    '--count'=$true
    '--disable-interactivity'=$true
    '--accept-source-agreements'=$false
}
Assert-Equal 'explicit consent is not dropped when help omits the option' $true ($withoutHelpText -contains '--accept-source-agreements')

# Installed-state inventory for a WinGet search must not depend on Store source consent.
$script:capturedInventoryArgs=@()
function Test-GSWingetOption {
    param([string]$Command,[string]$Option)
    return $true
}
function Invoke-GSWinget {
    param([string[]]$Arguments,[switch]$AllowNonZero,[switch]$SuppressOutput,[int]$TimeoutSeconds)
    $script:capturedInventoryArgs=@($Arguments)
    return [pscustomobject]@{ExitCode=0;StdOut=('Name Id Version Available'+[Environment]::NewLine+'7-Zip 7zip.7zip 26.04 26.05');StdErr=''}
}
$inventory=Get-GSWingetRawList -AcceptAgreements:$false -Source 'winget'
Assert-Equal 'source scoped inventory succeeds' $true $inventory.Success
Assert-Equal 'source scoped inventory has no implicit Store consent' $false ($script:capturedInventoryArgs -contains '--accept-source-agreements')
$sourceIndex=[Array]::IndexOf([string[]]$script:capturedInventoryArgs,'--source')
Assert-Equal 'source scoped inventory adds source option' $true ($sourceIndex -ge 0)
Assert-Equal 'source scoped inventory selects winget' 'winget' ([string]$script:capturedInventoryArgs[$sourceIndex+1])
$stateRow=Get-WingetKnownIdRecord -Text $inventory.Text -Id '7zip.7zip' -ExpectedSource 'winget'
Assert-Equal 'source scoped inventory detects installed version' '26.04' $stateRow.InstalledVersion
Assert-Equal 'source scoped inventory detects available update' '26.05' $stateRow.AvailableVersion

Write-Host 'WinGet partial-result, source-state, and error handling checks passed.'
