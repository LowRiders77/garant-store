# Garant Store v0.8 DEV - Core Dispatcher
# Windows PowerShell 5.1 compatible. ASCII-only source.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [Parameter(Mandatory=$true)][string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = '0.11.0.1'

$buildInfo = [ordered]@{ Schema=1; AppVersion=$version; ProductVersion='unknown'; SourceCommit='unavailable'; BuildId='unavailable'; BuildAttempt=''; BuiltUtc=''; Components=@{} }
$buildInfoPath = Join-Path $base 'BuildInfo.json'
if (Test-Path -LiteralPath $buildInfoPath -PathType Leaf) {
    try {
        $parsedBuildInfo = [IO.File]::ReadAllText($buildInfoPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($field in @('AppVersion','ProductVersion','SourceCommit','BuildId','BuildAttempt','BuiltUtc')) {
            if ($parsedBuildInfo.PSObject.Properties.Name -contains $field -and -not [string]::IsNullOrWhiteSpace([string]$parsedBuildInfo.$field)) {
                $buildInfo[$field] = [string]$parsedBuildInfo.$field
            }
        }
        if ($parsedBuildInfo.PSObject.Properties.Name -contains 'Components') { $buildInfo.Components = $parsedBuildInfo.Components }
    } catch {
        # Preserve the compiled version; a corrupt build manifest is reported below and in diagnostics.
        $buildInfo.ManifestError = $_.Exception.Message
    }
}
$version = [string]$buildInfo.AppVersion

$moduleFiles = @(
    'GarantStore.Common.ps1',
    'GarantStore.Progress.ps1',
    'GarantStore.Parser.ps1',
    'GarantStore.Winget.ps1',
    'GarantStore.State.ps1',
    'GarantStore.Deployment.ps1',
    'GarantStore.Prepare.ps1',
    'GarantStore.Store.ps1',
    'GarantStore.Bundles.ps1',
    'GarantStore.Diagnostics.ps1',
    'GarantStore.SystemSummary.ps1'
)

foreach ($moduleFile in $moduleFiles) {
    $modulePath = Join-Path $base $moduleFile
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw ('Required module missing: ' + $moduleFile)
    }
    . $modulePath
}

if (-not (Test-Path -LiteralPath $RequestFile -PathType Leaf)) {
    throw 'Request JSON file not found.'
}

$requestText = [IO.File]::ReadAllText($RequestFile,[Text.Encoding]::UTF8)
$request = $requestText | ConvertFrom-Json

if (-not $request.Action) {
    throw 'Request does not contain Action.'
}

$operationId = ''
if ($request.PSObject.Properties.Name -contains 'OperationId') {
    $operationId = [string]$request.OperationId
}

$progressFile = ''
if ($request.PSObject.Properties.Name -contains 'ProgressFile') {
    $progressFile = [string]$request.ProgressFile
}

Initialize-GSContext -OutputFile $OutputFile -Action ([string]$request.Action) -OperationId $operationId -ProgressFile $progressFile
Write-GSLog -Message ('Build: AppVersion=' + $version + '; SourceCommit=' + [string]$buildInfo.SourceCommit + '; BuildId=' + [string]$buildInfo.BuildId) -Level 'INFO'
Write-GSProgress -Stage 'Starting' -Indeterminate $true -Detail ([string]$request.Action)

$resultFile = ''
if ($request.PSObject.Properties.Name -contains 'ResultFile') {
    $resultFile = [string]$request.ResultFile
}

$previewFile = ''
if ($request.PSObject.Properties.Name -contains 'PreviewFile') {
    $previewFile = [string]$request.PreviewFile
}

$finalResult = $null
$exitCode = 0
$resultPackageId = ''
$resultSource = ''

try {
    switch ([string]$request.Action) {
        'doctor' {
            $doctor = Get-GSDoctorData
            Write-GSDoctorLog -Doctor $doctor

            $finalResult = New-GSResult -Success $true -Status 'DiagnosticsCompleted' -Message 'Diagnostics completed.' -Data $doctor
        }

        'search' {
            $query = [string]$request.Query
            if ([string]::IsNullOrWhiteSpace($query)) {
                throw (New-GSClassifiedException -Code 'InternalError' -Message 'Search query is empty.')
            }
            if ($query.IndexOf([char]0) -ge 0 -or $query -match '[\r\n]') {
                throw (New-GSClassifiedException -Code 'InternalError' -Message 'Search query contains unsupported control characters.')
            }

            $source = [string]$request.Source
            $accept = [bool]$request.AcceptAgreements
            Write-GSLog -Message ('Search request accepted. Source=' + $(if ($source) { $source } else { 'aggregate' }) + '; AgreementConsent=' + $accept) -Level 'INFO'
            $totalWatch = [Diagnostics.Stopwatch]::StartNew()
            $searchWatch = [Diagnostics.Stopwatch]::StartNew()
            $rows = @(Search-GSWinget -Query $query -Source $source -AcceptAgreements $accept)
            $searchWatch.Stop()
            $searchMeta = Get-GSLastSearchMetadata

            $previewRows = @()
            foreach ($row in $rows) {
                $previewRows += [pscustomobject]@{
                    Name = [string]$row.Name
                    Id = [string]$row.Id
                    Version = [string]$row.Version
                    Match = [string]$row.Match
                    Source = [string]$row.Source
                    Status = 'Checking'
                    InstalledVersion = ''
                    AvailableVersion = [string]$row.Version
                    StateOrigin = 'preview'
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($previewFile)) {
                $previewPayload = [ordered]@{
                    Schema = 1
                    Query = $query
                    Count = $previewRows.Count
                    SearchMs = [Math]::Round($searchWatch.Elapsed.TotalMilliseconds,0)
                    SearchCacheHit = [bool]$searchMeta.CacheHit
                    Results = $previewRows
                }
                $previewJson = ConvertTo-Json -InputObject $previewPayload -Depth 8
                [IO.File]::WriteAllText($previewFile,$previewJson,(New-Object Text.UTF8Encoding($false)))
                Write-GSProgress -Stage 'CheckingState' -Indeterminate $true -Detail 'PreviewReady'
            }

            $stateWatch = [Diagnostics.Stopwatch]::StartNew()
            if ($rows.Count -eq 0) {
                Write-GSLog -Message ('Search completed with zero parsed rows. Query=' + $query + '; source=' + $source) -Level 'INFO'
                $rowsWithState = @()
            } else {
                $rowsWithState = @(Add-GSPackageStates -Rows $rows -AcceptAgreements $accept)
            }
            $stateWatch.Stop()

            $ordered = @(
                $rowsWithState | Sort-Object `
                    @{ Expression = { if ([string]::Equals($_.Name,$query,[StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 } } }, `
                    @{ Expression = { if ($_.Source -eq 'msstore') { 0 } else { 1 } } }, `
                    @{ Expression = { $_.Name } }
            )
            $totalWatch.Stop()

            $performance = [pscustomobject]@{
                SearchMs = [Math]::Round($searchWatch.Elapsed.TotalMilliseconds,0)
                StateMs = [Math]::Round($stateWatch.Elapsed.TotalMilliseconds,0)
                TotalMs = [Math]::Round($totalWatch.Elapsed.TotalMilliseconds,0)
                SearchCacheHit = [bool]$searchMeta.CacheHit
            }

            $data = [pscustomobject]@{
                Query = $query
                Count = $ordered.Count
                Results = $ordered
                Performance = $performance
            }

            $finalResult = New-GSResult -Success $true -Status 'SearchCompleted' -Message ('Search completed. Results=' + $ordered.Count + '; totalMs=' + $performance.TotalMs) -Data $data
            $finalResult | Add-Member -NotePropertyName Results -NotePropertyValue $ordered
        }

        'install' {
            $id = [string]$request.Id
            $source = [string]$request.Source
            $resultPackageId = $id
            $resultSource = $source
            $name = [string]$request.Name
            $knownStatus = if ($request.PSObject.Properties.Name -contains 'KnownStatus') { [string]$request.KnownStatus } else { '' }
            $availableVersion = if ($request.PSObject.Properties.Name -contains 'AvailableVersion') { [string]$request.AvailableVersion } else { '' }
            $agreementConsent = if ($request.PSObject.Properties.Name -contains 'AgreementConsent') { [bool]$request.AgreementConsent } else { $false }
            $allowServiceChanges = if ($request.PSObject.Properties.Name -contains 'AllowServiceChanges') { [bool]$request.AllowServiceChanges } else { $false }

            Assert-GSPreparedForInstall
            $installed = Invoke-GSPackageInstall `
                -Id $id `
                -Source $source `
                -Name $name `
                -KnownStatus $knownStatus `
                -AvailableVersion $availableVersion `
                -AgreementConsent $agreementConsent `
                -AllowServiceChanges $allowServiceChanges

            $finalResult = New-GSResult `
                -Success $true `
                -Status ([string]$installed.Status) `
                -Message ([string]$installed.Message) `
                -PackageId $id `
                -Source $source `
                -OldVersion ([string]$installed.OldVersion) `
                -NewVersion ([string]$installed.NewVersion) `
                -Data $installed.Data
        }

        'bundlestate' {
            $accept = [bool]$request.AcceptAgreements
            $states = @(Get-GSBundleStates -Items @($request.Items) -AcceptAgreements $accept)
            $finalResult = New-GSResult -Success $true -Status 'BundleStateReady' -Message ('Bundle state resolved. Items=' + $states.Count) -Data ([pscustomobject]@{ Results = $states })
            $finalResult | Add-Member -NotePropertyName Results -NotePropertyValue $states
        }

        'bundle' {
            $agreementConsent = if ($request.PSObject.Properties.Name -contains 'AgreementConsent') { [bool]$request.AgreementConsent } else { $false }
            $allowServiceChanges = if ($request.PSObject.Properties.Name -contains 'AllowServiceChanges') { [bool]$request.AllowServiceChanges } else { $false }
            Assert-GSPreparedForInstall
            $bundle = Invoke-GSBundleInstall -Items @($request.Items) -AgreementConsent $agreementConsent -AllowServiceChanges $allowServiceChanges
            Clear-GSInventoryCache
            $bundleStatus = if ($bundle.Failed -eq 0) { 'BundleCompleted' } else { 'BundlePartial' }
            $finalResult = New-GSResult -Success ($bundle.Failed -eq 0) -Status $bundleStatus -ErrorCode $(if ($bundle.Failed -eq 0) { '' } else { 'BundlePartial' }) -Message ('Bundle finished. Installed=' + $bundle.Installed + '; AlreadyPresent=' + $bundle.AlreadyPresent + '; Failed=' + $bundle.Failed) -Data $bundle
            if ($bundle.Failed -gt 0) { $exitCode = 1 }
        }

        'local' {
            $path = [string]$request.Package
            $deploy = Install-GSLocalPackage -Path $path

            if (-not $deploy.Verified) {
                $finalResult = New-GSResult -Success $false -Status 'VerificationInconclusive' -ErrorCode 'VerificationInconclusive' -Message 'Windows accepted the package, but registration change was not independently detected.' -TechnicalMessage 'Add-AppxPackage returned without an error, but no new or version-changed package registration was detected.' -Data $deploy
                $exitCode = 1
            } else {
                Clear-GSInventoryCache
                $finalResult = New-GSResult -Success $true -Status 'InstalledVerified' -Message 'Local signed package installation was verified.' -Data $deploy
            }
        }

        'preparestate' {
            $prepState = Get-GSPreparationState -SkipStoreProbe:([bool]($request.PSObject.Properties.Name -contains 'SkipStoreProbe' -and $request.SkipStoreProbe))
            $finalResult = New-GSResult -Success $true -Status $(if ($prepState.Ready) { 'PreparationReady' } else { 'PreparationNeeded' }) -Message ('WinGet=' + $prepState.WingetStatus + ' ' + $prepState.WingetVersion + '; msstore=' + $prepState.StoreSource + '; missing frameworks=' + (@($prepState.MissingFrameworks) -join ',')) -Data $prepState
        }

        'prepare' {
            $acceptTerms = if ($request.PSObject.Properties.Name -contains 'AgreementConsent') { [bool]$request.AgreementConsent } else { $false }
            $prep = Invoke-GSSystemPreparation -AcceptStoreTerms $acceptTerms
            Clear-GSCache -Scope All
            foreach ($step in @($prep.Steps)) { Write-GSLog -Message ('Prepare step ' + $step.Id + ': ' + $step.Status + ' ' + $step.Detail) -Level 'INFO' }
            $finalResult = New-GSResult -Success ([bool]$prep.Ready) -Status $(if ($prep.Ready) { 'PreparationCompleted' } else { 'PreparationIncomplete' }) -ErrorCode $(if ($prep.Ready) { '' } else { 'PreparationIncomplete' }) -Message ('Preparation finished. WinGet=' + $prep.After.WingetVersion) -Data $prep
            if (-not $prep.Ready) { $exitCode = 1 }
        }

        'repairwinget' {
            $repair = Repair-GSWinget
            Clear-GSCache -Scope All
            $finalResult = New-GSResult -Success ([bool]$repair.Success) -Status ([string]$repair.Status) -Message ([string]$repair.Message) -Data $repair
        }

        'diagnostics' {
            $diagnostics = New-GSDiagnosticsArchive -Version $version -BuildInfo $buildInfo
            $finalResult = New-GSResult -Success $true -Status 'DiagnosticsCreated' -Message ('Diagnostics ZIP: ' + $diagnostics.Path) -Data $diagnostics
        }

        default {
            throw (New-GSClassifiedException -Code 'InternalError' -Message ('Unknown action: ' + [string]$request.Action))
        }
    }
} catch {
    $classification = ConvertFrom-GSException -Exception $_.Exception
    Write-GSLog -Message ($classification.Code + ': ' + $classification.TechnicalMessage) -Level 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-GSLog -Message ('Stack: ' + $_.ScriptStackTrace) -Level 'ERROR'
    }

    $finalResult = New-GSResult -Success $false -Status $classification.Status -ErrorCode $classification.Code -Message $classification.UserMessage -TechnicalMessage $classification.TechnicalMessage -PackageId $resultPackageId -Source $resultSource
    $exitCode = 1
}

if ($null -eq $finalResult) {
    $finalResult = New-GSResult -Success $false -Status 'Failed' -ErrorCode 'InternalError' -Message 'No operation result was produced.' -TechnicalMessage 'Core completed without a result object.'
    $exitCode = 1
}

try { Restore-GSStoreServiceStartupTypes } catch {
    Write-GSLog -Message ('Store service rollback check failed: ' + $_.Exception.Message) -Level 'WARN'
}

Write-GSLog -Message ('Operation result: Success=' + $finalResult.Success + '; Status=' + $finalResult.Status + '; ErrorCode=' + $finalResult.ErrorCode) -Level 'INFO'

if ([bool]$finalResult.Success) {
    Complete-GSProgress
} else {
    Write-GSProgress -Stage 'Failed' -Indeterminate $false -Detail ([string]$finalResult.ErrorCode)
}

if (-not [string]::IsNullOrWhiteSpace($resultFile)) {
    Write-GSResultFile -Path $resultFile -Result $finalResult
}

exit $exitCode
