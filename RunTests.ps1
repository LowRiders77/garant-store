# Garant Store v0.8 DEV - Regression Tests
# Windows PowerShell 5.1 compatible. ASCII-only source.

[CmdletBinding()]
param(
    [ValidateSet('SelfTest','ReleaseGate')][string]$Mode = 'SelfTest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$fixtures = Join-Path $base 'Tests\fixtures'

. (Join-Path $base 'GarantStore.Common.ps1')
. (Join-Path $base 'GarantStore.Progress.ps1')
. (Join-Path $base 'GarantStore.Parser.ps1')
. (Join-Path $base 'GarantStore.Winget.ps1')
. (Join-Path $base 'GarantStore.State.ps1')
. (Join-Path $base 'GarantStore.Deployment.ps1')

$requiredTestFunctions = @(
    'ConvertFrom-WingetSearchText',
    'Get-WingetKnownIdRecord',
    'ConvertFrom-GSWingetExportObject',
    'Compare-GSVersionValues',
    'ConvertFrom-GSException',
    'Test-GSWingetNoApplicationsFound',
    'Get-GSWingetAgreementRequirement',
    'New-GSWingetPackageArguments',
    'Get-GSDeliveryOptimizationConfig',
    'ConvertFrom-GSLooseSearchRow',
    'Get-GSWingetSourceListSnapshot',
    'Resolve-GSStoreSearchRowFromSnapshot',
    'Get-GSWingetTelemetryKind',
    'Get-GSDeploymentDependencyRequest',
    'Select-GSVCLibsDependencyCandidate',
    'Get-GSVersionFromDependencyFileName',
    'Test-GSVCLibsFileNameForPackage',
    'Test-GSFrameworkArchitectureCompatible',
    'ConvertFrom-GSWingetSearchCapture',
    'Get-GSRepairPostCheckPlan',
    'Get-GSCacheKey',
    'Get-GSSearchCacheName',
    'Get-GSLastSearchMetadata',
    'New-GSInventorySnapshot',
    'Get-GSCachedStoreSnapshot',
    'New-GSWingetSearchArguments'
)

$missingTestFunctions = @()
foreach ($requiredFunction in $requiredTestFunctions) {
    $command = Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $missingTestFunctions += $requiredFunction
    }
}

if ($missingTestFunctions.Count -gt 0) {
    foreach ($missingFunction in $missingTestFunctions) {
        Write-Host ('TEST DEPENDENCY MISSING: ' + $missingFunction) -ForegroundColor Red
    }
    Write-Host 'REGRESSION TESTS ABORTED: one or more required test functions are not loaded.' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: Regression test module dependency gate' -ForegroundColor Green

$failures = New-Object 'System.Collections.Generic.List[string]'

function Assert-GSTest {
    param(
        [bool]$Condition,
        [string]$Name
    )
    if ($Condition) {
        Write-Host ('PASS: ' + $Name) -ForegroundColor Green
    } else {
        Write-Host ('FAIL: ' + $Name) -ForegroundColor Red
        [void]$failures.Add($Name)
    }
}

$searchText = [IO.File]::ReadAllText((Join-Path $fixtures 'search-mixed.txt'))
$searchRows = @(ConvertFrom-WingetSearchText -Text $searchText -FallbackSource '')
Assert-GSTest ($searchRows.Count -eq 2) 'Search parser row count'
Assert-GSTest ($searchRows[0].Id -eq '9NKSQGP7F2NH' -and $searchRows[0].Source -eq 'msstore') 'Search parser Store row'
Assert-GSTest ($searchRows[1].Id -eq 'AloproAgency.WAutoChat' -and $searchRows[1].Source -eq 'winget') 'Search parser WinGet row'

$listText = [IO.File]::ReadAllText((Join-Path $fixtures 'list-known-id.txt'))
$seven = Get-WingetKnownIdRecord -Text $listText -Id '7zip.7zip' -ExpectedSource 'winget'
$wa = Get-WingetKnownIdRecord -Text $listText -Id '9NKSQGP7F2NH' -ExpectedSource 'msstore'
$happ = Get-WingetKnownIdRecord -Text $listText -Id 'Happ.Happ' -ExpectedSource 'winget'
$missing = Get-WingetKnownIdRecord -Text $listText -Id 'Definitely.Not.Installed' -ExpectedSource 'winget'

Assert-GSTest ($null -ne $seven -and $seven.InstalledVersion -eq '26.05') 'Known-ID 7-Zip installed fixture'
Assert-GSTest ($null -ne $wa -and $wa.InstalledVersion -eq '2.2625.101.0') 'Known-ID WhatsApp installed fixture'
Assert-GSTest ($null -ne $happ -and $happ.AvailableVersion -eq '4.6.1') 'Known-ID update fixture'
Assert-GSTest ($null -eq $missing) 'Known-ID missing package false-positive guard'

$exportText = [IO.File]::ReadAllText((Join-Path $fixtures 'winget-export.json'),[Text.Encoding]::UTF8)
$exportObject = $exportText | ConvertFrom-Json
$exportRows = @(ConvertFrom-GSWingetExportObject -ExportObject $exportObject)
Assert-GSTest ($exportRows.Count -eq 3) 'WinGet export JSON parser count'
Assert-GSTest (($exportRows | Where-Object { $_.Id -eq '7zip.7zip' }).Version -eq '26.05') 'WinGet export JSON 7-Zip version'
Assert-GSTest (($exportRows | Where-Object { $_.Id -eq '9NKSQGP7F2NH' }).Source -eq 'msstore') 'WinGet export JSON Store source'

Assert-GSTest ((Compare-GSVersionValues -Installed '1.0.0' -Available '1.0.1') -eq 'AvailableNewer') 'Version comparer newer'
Assert-GSTest ((Compare-GSVersionValues -Installed '1.0.1' -Available '1.0.1') -eq 'Same') 'Version comparer same'
Assert-GSTest ((Compare-GSVersionValues -Installed '< 4.3.0' -Available '4.6.1') -eq 'Unknown') 'Version comparer comparator safety'
Assert-GSTest ((Compare-GSVersionValues -Installed 'Unknown' -Available '4.6.1') -eq 'Unknown') 'Version comparer unknown safety'

$classified = ConvertFrom-GSException -Exception (New-Object System.Exception('GSERR:DependencyMissing:Microsoft.WindowsAppRuntime.1.8'))
Assert-GSTest ($classified.Code -eq 'DependencyMissing' -and $classified.Status -eq 'NeedsDependency') 'Error classifier dependency'


$runtimeDependencyMessage = 'Deployment failed. Provide framework "Microsoft.WindowsAppRuntime.1.8" with neutral or x64 architecture, version 8000.616.304.0 or later.'
$runtimeDependency = Get-GSDeploymentDependencyRequest -Message $runtimeDependencyMessage
Assert-GSTest ($null -ne $runtimeDependency -and $runtimeDependency.Name -eq 'Microsoft.WindowsAppRuntime.1.8' -and $runtimeDependency.MinimumVersion -eq '8000.616.304.0') 'Dependency parser Windows App Runtime 1.8'

$baseVCLibsMessage = 'Deployment failed. Provide framework "Microsoft.VCLibs.140.00" with neutral or x64 architecture, version 14.0.33519.0 or later.'
$baseVCLibsDependency = Get-GSDeploymentDependencyRequest -Message $baseVCLibsMessage
Assert-GSTest ($null -ne $baseVCLibsDependency -and $baseVCLibsDependency.Name -eq 'Microsoft.VCLibs.140.00' -and $baseVCLibsDependency.MinimumVersion -eq '14.0.33519.0') 'Dependency parser base VCLibs'

$desktopVCLibsMessage = 'Dependency framework Microsoft.VCLibs.140.00.UWPDesktop requires minimum version 14.0.33728.0.'
$desktopVCLibsDependency = Get-GSDeploymentDependencyRequest -Message $desktopVCLibsMessage
Assert-GSTest ($null -ne $desktopVCLibsDependency -and $desktopVCLibsDependency.Name -eq 'Microsoft.VCLibs.140.00.UWPDesktop' -and $desktopVCLibsDependency.MinimumVersion -eq '14.0.33728.0') 'Dependency parser UWPDesktop VCLibs'

$unknownDependency = Get-GSDeploymentDependencyRequest -Message 'Deployment failed because Microsoft.NET.Native.Runtime.2.2 is missing.'
Assert-GSTest ($null -eq $unknownDependency) 'Dependency parser does not misclassify unknown framework'

$vclibsPaths = @(
    'C:\deps\x64\Microsoft.VCLibs.140.00_14.0.30704.0_Universal_X64.appx',
    'C:\deps\x64\Microsoft.VCLibs.140.00_14.0.33519.0_Universal_X64.appx',
    'C:\deps\x64\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64.appx',
    'C:\deps\x86\Microsoft.VCLibs.140.00_14.0.33519.0_Universal_X86.appx'
)

$baseCandidate = Select-GSVCLibsDependencyCandidate -Paths $vclibsPaths -PackageName 'Microsoft.VCLibs.140.00' -Architecture 'x64' -MinimumVersion '14.0.33519.0'
Assert-GSTest ($null -ne $baseCandidate -and [string]$baseCandidate.Version -eq '14.0.33519.0' -and $baseCandidate.Path -match 'Universal_X64') 'VCLibs selector exact base family and x64'

$desktopCandidate = Select-GSVCLibsDependencyCandidate -Paths $vclibsPaths -PackageName 'Microsoft.VCLibs.140.00.UWPDesktop' -Architecture 'x64' -MinimumVersion '14.0.33728.0'
Assert-GSTest ($null -ne $desktopCandidate -and [string]$desktopCandidate.Version -eq '14.0.33728.0') 'VCLibs selector UWPDesktop family'

$tooNewCandidate = Select-GSVCLibsDependencyCandidate -Paths $vclibsPaths -PackageName 'Microsoft.VCLibs.140.00' -Architecture 'x64' -MinimumVersion '99.0.0.0'
Assert-GSTest ($null -eq $tooNewCandidate) 'VCLibs selector minimum-version guard'

Assert-GSTest (Test-GSVCLibsFileNameForPackage -Path 'Microsoft.VCLibs.140.00_14.0.33519.0_Universal_X64.appx' -PackageName 'Microsoft.VCLibs.140.00') 'Base VCLibs filename matcher'
Assert-GSTest (-not (Test-GSVCLibsFileNameForPackage -Path 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64.appx' -PackageName 'Microsoft.VCLibs.140.00')) 'Base VCLibs matcher excludes UWPDesktop'

Assert-GSTest (Test-GSFrameworkArchitectureCompatible -PackageArchitecture 'X64' -RequiredArchitecture 'x64') 'Framework architecture exact x64'
Assert-GSTest (Test-GSFrameworkArchitectureCompatible -PackageArchitecture 'Neutral' -RequiredArchitecture 'x64') 'Framework architecture accepts Neutral'
Assert-GSTest (-not (Test-GSFrameworkArchitectureCompatible -PackageArchitecture 'X86' -RequiredArchitecture 'x64')) 'Framework architecture rejects x86 for x64'

$classified2 = ConvertFrom-GSException -Exception (New-Object System.Exception('WinGet crashed with 0xC0000005'))
Assert-GSTest ($classified2.Code -eq 'AccessViolation' -and $classified2.Status -eq 'NeedsRepair') 'Error classifier access violation'


$classified3 = ConvertFrom-GSException -Exception (New-Object System.Exception('GSERR:StoreServiceDisabled:Microsoft Store operation failed with 0x80070422'))
Assert-GSTest ($classified3.Code -eq 'StoreServiceDisabled' -and $classified3.Status -eq 'NeedsRepair') 'Error classifier Store service disabled'


Assert-GSTest ((Get-GSWingetAgreementRequirement -ExitCode -1978335167) -eq 'Package') 'WinGet package agreement HRESULT classification'
Assert-GSTest ((Get-GSWingetAgreementRequirement -ExitCode -1978335162) -eq 'Source') 'WinGet source agreement HRESULT classification'

# Source agreements are NEVER auto-accepted by search without GUI consent.
$searchCapabilities = @{
    '--query' = $true
    '--count' = $true
    '--disable-interactivity' = $true
    '--accept-source-agreements' = $true
}
$unconsentedSearch = @(New-GSWingetSearchArguments -Query 'CapCut' -Source '' -AcceptAgreements $false -Capabilities $searchCapabilities)
$consentedSearch = @(New-GSWingetSearchArguments -Query 'CapCut' -Source '' -AcceptAgreements $true -Capabilities $searchCapabilities)
$catalogSearch = @(New-GSWingetSearchArguments -Query 'CapCut' -Source 'winget' -AcceptAgreements $false -Capabilities $searchCapabilities)
$storeSearch = @(New-GSWingetSearchArguments -Query 'CapCut' -Source 'msstore' -AcceptAgreements $true -Capabilities $searchCapabilities)
Assert-GSTest ($unconsentedSearch -notcontains '--accept-source-agreements') 'Unconsented search does not accept Store terms'
Assert-GSTest ($consentedSearch -contains '--accept-source-agreements') 'Explicitly consented search accepts source terms'
Assert-GSTest ($catalogSearch -contains 'winget' -and $catalogSearch -notcontains '--accept-source-agreements') 'WinGet-only fallback without Store consent'
Assert-GSTest ($storeSearch -contains 'msstore' -and $storeSearch -contains '--accept-source-agreements') 'Explicit Store search with consent'
Assert-GSTest ($unconsentedSearch -contains '--disable-interactivity') 'Search remains noninteractive'

$allCapabilities = @{
    '--exact' = $true
    '--accept-package-agreements' = $true
    '--accept-source-agreements' = $true
    '--include-unknown' = $true
    '--force' = $true
    '--silent' = $true
    '--disable-interactivity' = $true
}

$consentedArgs = @(New-GSWingetPackageArguments -Command 'install' -Id '9NKSQGP7F2NH' -Source 'msstore' -AgreementConsent $true -Silent -Capabilities $allCapabilities)
Assert-GSTest ($consentedArgs -contains '--accept-package-agreements') 'Consented Store install includes package agreement flag'
Assert-GSTest ($consentedArgs -contains '--accept-source-agreements') 'Consented Store install includes source agreement flag'
Assert-GSTest ($consentedArgs -contains '--disable-interactivity') 'Consented Store install disables interactivity'
Assert-GSTest ($consentedArgs -contains '--silent') 'Consented Store install requests silent mode'

$unconsentedArgs = @(New-GSWingetPackageArguments -Command 'install' -Id '9NKSQGP7F2NH' -Source 'msstore' -AgreementConsent $false -Capabilities $allCapabilities)
Assert-GSTest (-not ($unconsentedArgs -contains '--accept-package-agreements')) 'No consent means no package agreement flag'
Assert-GSTest (-not ($unconsentedArgs -contains '--accept-source-agreements')) 'No consent means no source agreement flag'


$doConfigFixture = Get-GSDeliveryOptimizationConfig
Assert-GSTest ($null -ne $doConfigFixture) 'Delivery Optimization telemetry object creation'

Assert-GSTest ((Get-GSWingetTelemetryKind -Arguments @('install','--id','9NKSQGP7F2NH','--source','msstore')) -eq 'Store') 'Store install selects native Store telemetry'
Assert-GSTest ((Get-GSWingetTelemetryKind -Arguments @('upgrade','--id','9NKSQGP7F2NH','--source','msstore')) -eq 'Store') 'Store upgrade selects native Store telemetry'
Assert-GSTest ((Get-GSWingetTelemetryKind -Arguments @('search','WhatsApp','--source','msstore')) -eq 'None') 'Store search does not use install telemetry'
Assert-GSTest ((Get-GSWingetTelemetryKind -Arguments @('install','--id','7zip.7zip','--source','winget')) -eq 'None') 'Community install does not use Store telemetry'


$collapsedCapCut = @'
Name Id Version Match Source
CapCut XP9KN75RRB9NHS Unknown msstore
CapCut ByteDance.CapCut 9.5.0.4050 ProductCode: capcut winget
'@
$collapsedRows = @(ConvertFrom-WingetSearchText -Text $collapsedCapCut)
Assert-GSTest ($collapsedRows.Count -eq 2) 'Collapsed search parser CapCut row count'
Assert-GSTest (@($collapsedRows | Where-Object { $_.Id -eq 'XP9KN75RRB9NHS' }).Count -eq 1) 'Collapsed search parser Store ID'
Assert-GSTest (@($collapsedRows | Where-Object { $_.Id -eq 'ByteDance.CapCut' }).Count -eq 1) 'Collapsed search parser WinGet ID'

$collapsedToDo = @'
Name Id Version Source
Microsoft To Do: Lists, Tasks & Reminders 9NBLGGH5R558 Unknown msstore
'@
$todoRows = @(ConvertFrom-WingetSearchText -Text $collapsedToDo)
Assert-GSTest ($todoRows.Count -eq 1 -and $todoRows[0].Id -eq '9NBLGGH5R558') 'Collapsed search parser Microsoft To Do'

$emptyStateRows = @(Add-GSPackageStates -Rows @())
Assert-GSTest ($emptyStateRows.Count -eq 0) 'Empty search result state engine safety'

$batchSnapshotFixture = [pscustomobject]@{
    Reliable = $true
    Empty = $false
    Text = "Name ID Version`r`nPC Manager 9PM860492SZD 3.23.0.0"
}
$batchRowFixture = [pscustomobject]@{
    Name = 'Microsoft PC Manager'
    Id = '9PM860492SZD'
    Version = 'Unknown'
    Match = ''
    Source = 'msstore'
}
$batchState = Resolve-GSStoreSearchRowFromSnapshot -SearchRow $batchRowFixture -Snapshot $batchSnapshotFixture
Assert-GSTest ($batchState.Status -eq 'StoreUpdateUnknown' -and $batchState.InstalledVersion -eq '3.23.0.0') 'Batch Store state installed fixture'

$batchMissingFixture = [pscustomobject]@{
    Reliable = $true
    Empty = $true
    Text = ''
}
$batchMissingState = Resolve-GSStoreSearchRowFromSnapshot -SearchRow $batchRowFixture -Snapshot $batchMissingFixture
Assert-GSTest ($batchMissingState.Status -eq 'NotInstalled') 'Batch Store state absence fixture'


Assert-GSTest (Test-GSWingetNoApplicationsFound -ExitCode -1978335212 -StdOut '' -StdErr '') 'WinGet 0x8A150014 semantic NotInstalled code'
Assert-GSTest (Test-GSWingetNoApplicationsFound -ExitCode 1 -StdOut 'No app found matching input criteria' -StdErr '') 'WinGet localized no-app text fallback'

$zeroSearchRowsByCode = @(ConvertFrom-GSWingetSearchCapture -ExitCode -1978335212 -StdOut '' -StdErr '' -FallbackSource 'winget')
Assert-GSTest ($zeroSearchRowsByCode.Count -eq 0) 'Search 0x8A150014 is successful zero-result search'

$zeroSearchRowsByText = @(ConvertFrom-GSWingetSearchCapture -ExitCode 1 -StdOut 'No packages found matching input criteria.' -StdErr '' -FallbackSource 'winget')
Assert-GSTest ($zeroSearchRowsByText.Count -eq 0) 'Search no-packages text is successful zero-result search'

$searchErrorCaught = $false
try {
    [void](ConvertFrom-GSWingetSearchCapture -ExitCode 12345 -StdOut '' -StdErr 'Synthetic failure' -FallbackSource 'winget')
} catch {
    $classifiedSearchError = ConvertFrom-GSException -Exception $_.Exception
    $searchErrorCaught = ($classifiedSearchError.Code -eq 'WingetError')
}
Assert-GSTest $searchErrorCaught 'Unknown nonzero search result remains an error'

$postRepairPlan = Get-GSRepairPostCheckPlan
Assert-GSTest (@($postRepairPlan.List) -contains '--source') 'Repair post-check list is source-scoped'
Assert-GSTest (@($postRepairPlan.List) -contains 'winget') 'Repair post-check list uses community source'
Assert-GSTest (-not (@($postRepairPlan.List) -contains 'msstore')) 'Repair post-check list does not trigger Store agreement handshake'
Assert-GSTest (-not (@($postRepairPlan.List) -contains '--accept-source-agreements')) 'Repair post-check does not silently accept Store agreements'
Assert-GSTest (@($postRepairPlan.Search) -contains 'winget') 'Repair online smoke-test uses community source'

$storeInstalledFixture = @'
Name      Id           Version
WhatsApp  9NKSQGP7F2NH 2.2625.101.0
'@
$storeRecord = Get-WingetKnownIdRecord -Text $storeInstalledFixture -Id '9NKSQGP7F2NH' -ExpectedSource 'msstore'
Assert-GSTest ($null -ne $storeRecord -and $storeRecord.InstalledVersion -eq '2.2625.101.0') 'Store exact-ID installed correlation fixture'

# StrictMode / parameter-binding behavior boundaries: empty, null-like result, scalar, zero, one and many.
$emptyLoose = ConvertFrom-GSLooseSearchRow -Line '' -FallbackSource ''
Assert-GSTest ($null -eq $emptyLoose) 'Empty-string loose parser binding safety'

$nullLoose = ConvertFrom-GSLooseSearchRow -Line 'this is not a winget row' -FallbackSource ''
Assert-GSTest ($null -eq $nullLoose) 'StrictMode null result safety'

$singleLoose = @(ConvertFrom-GSLooseSearchRow -Line 'CapCut XP9KN75RRB9NHS Unknown msstore' -FallbackSource '')
Assert-GSTest ($singleLoose.Count -eq 1 -and $singleLoose[0].Id -eq 'XP9KN75RRB9NHS') 'StrictMode scalar-to-array safety'

$zeroParsed = @(ConvertFrom-WingetSearchText -Text '' -FallbackSource '')
Assert-GSTest ($zeroParsed.Count -eq 0) 'Empty-string search parser binding safety'

$zeroList = @(ConvertFrom-WingetListText -Text '')
Assert-GSTest ($zeroList.Count -eq 0) 'Empty-string list parser binding safety'

$zeroKnownId = Get-WingetKnownIdRecord -Text '' -Id '9NKSQGP7F2NH' -ExpectedSource 'msstore'
Assert-GSTest ($null -eq $zeroKnownId) 'Empty-string known-ID parser binding safety'

$oneParsed = @(ConvertFrom-WingetSearchText -Text "Name Id Version Source`r`nCapCut XP9KN75RRB9NHS Unknown msstore" -FallbackSource '')
Assert-GSTest ($oneParsed.Count -eq 1) 'StrictMode one-result parser safety'

$manyParsed = @(ConvertFrom-WingetSearchText -Text $collapsedCapCut -FallbackSource '')
Assert-GSTest ($manyParsed.Count -eq 2) 'StrictMode many-result parser safety'

if ($Mode -eq 'ReleaseGate') {
    $requiredDocs = @('README.md','CHANGELOG.md','VERSION.txt','TEST_REPORT.md','TEST_PLAN.txt')
    foreach ($doc in $requiredDocs) {
        Assert-GSTest (Test-Path -LiteralPath (Join-Path $base $doc) -PathType Leaf) ('Release artifact exists: ' + $doc)
    }
}

$cacheKeyA = Get-GSCacheKey -Text 'winget|capcut'
$cacheKeyB = Get-GSCacheKey -Text 'winget|capcut'
$cacheKeyC = Get-GSCacheKey -Text 'msstore|capcut'
Assert-GSTest (-not [string]::IsNullOrWhiteSpace($cacheKeyA) -and $cacheKeyA -eq $cacheKeyB -and $cacheKeyA -ne $cacheKeyC) 'Performance cache key determinism and source isolation'

$searchCacheA = Get-GSSearchCacheName -Query 'CapCut' -Source 'winget'
$searchCacheB = Get-GSSearchCacheName -Query ' capcut ' -Source 'winget'
Assert-GSTest ($searchCacheA -eq $searchCacheB -and $searchCacheA -like 'search-*.json') 'Search cache normalized query key'

$inventoryFixture = New-GSInventorySnapshot -Items @([pscustomobject]@{ Id='7zip.7zip'; Version='26.05'; Source='winget'; SourceIdentifier='winget' }) -StructuredSuccess $true -RawListSuccess $true -RawListText ''
Assert-GSTest ($inventoryFixture.StructuredCount -eq 1 -and $inventoryFixture.Map.ContainsKey('7zip.7zip')) 'Persistent inventory snapshot rehydration contract'

$emptyInventoryFixture = New-GSInventorySnapshot -Items @() -StructuredSuccess $true -RawListSuccess $true -RawListText ''
Assert-GSTest ($emptyInventoryFixture.StructuredCount -eq 0 -and $emptyInventoryFixture.Map.Count -eq 0) 'Persistent inventory empty collection binding safety'

if ($failures.Count -gt 0) {
    Write-Host ('REGRESSION TESTS FAILED: ' + $failures.Count) -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host (' - ' + $failure) -ForegroundColor Red
    }
    exit 1
}

Write-Host 'REGRESSION TESTS PASSED.' -ForegroundColor Green
exit 0
