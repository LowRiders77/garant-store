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
$version = '0.8.0-dev'

$moduleFiles = @(
    'GarantStore.Common.ps1',
    'GarantStore.Progress.ps1',
    'GarantStore.Parser.ps1',
    'GarantStore.Winget.ps1',
    'GarantStore.State.ps1',
    'GarantStore.Deployment.ps1',
    'GarantStore.Store.ps1',
    'GarantStore.Diagnostics.ps1'
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
            $name = [string]$request.Name
            $knownStatus = if ($request.PSObject.Properties.Name -contains 'KnownStatus') { [string]$request.KnownStatus } else { '' }
            $availableVersion = if ($request.PSObject.Properties.Name -contains 'AvailableVersion') { [string]$request.AvailableVersion } else { '' }
            $agreementConsent = if ($request.PSObject.Properties.Name -contains 'AgreementConsent') { [bool]$request.AgreementConsent } else { $false }

            if (-not (Test-GSValidPackageId -Id $id) -or $source -notin @('msstore','winget')) {
                throw (New-GSClassifiedException -Code 'InternalError' -Message 'Invalid selected package identity.')
            }

            if ($source -eq 'msstore') {
                $storeResult = Invoke-GSStorePackagePipeline `
                    -Id $id `
                    -Name $name `
                    -KnownStatus $knownStatus `
                    -AvailableVersion $availableVersion `
                    -AgreementConsent $agreementConsent

                $before = $storeResult.Before
                $after = $storeResult.After

                $finalResult = New-GSResult `
                    -Success $true `
                    -Status ([string]$storeResult.Outcome) `
                    -Message ('Microsoft Store package operation verified: ' + $id) `
                    -PackageId $id `
                    -Source $source `
                    -OldVersion ([string]$before.InstalledVersion) `
                    -NewVersion ([string]$after.InstalledVersion) `
                    -Data $storeResult

                break
            }

            if (-not $agreementConsent) {
                throw (New-GSClassifiedException -Code 'PackageAgreementsRequired' -Message 'Explicit per-operation consent is required for package installation.')
            }

            [void](Confirm-GSWingetPackage -Id $id -Source $source -AcceptAgreements $true)
            $before = Get-GSExactPackageState -Id $id -Source $source -AcceptAgreements $true

            if ($before.Status -eq 'Installed') {
                $finalResult = New-GSResult -Success $true -Status 'AlreadyCurrent' -Message 'The selected application is already installed and current.' -PackageId $id -Source $source -OldVersion $before.InstalledVersion -NewVersion $before.InstalledVersion
                break
            }

            if ($before.Status -eq 'Unknown') {
                throw (New-GSClassifiedException -Code 'InternalError' -Message 'Installed state could not be verified. System modification was blocked.')
            }

            $command = if ($before.Status -eq 'UpdateAvailable') { 'upgrade' } else { 'install' }
            [void](Ensure-GSAgreementCapabilities -Command $command)
            [void](Invoke-GSWingetPackageAction -Command $command -Id $id -Source $source -AgreementConsent $true -Silent)

            Clear-GSInventoryCache
            $after = Get-GSExactPackageState -Id $id -Source $source -AcceptAgreements $true

            if ($after.Status -eq 'NotInstalled' -or $after.Status -eq 'Unknown' -or $after.Status -eq 'UpdateAvailable') {
                throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'Post-action verification failed for the selected package.')
            }

            $status = if ($command -eq 'upgrade') { 'UpdateVerified' } else { 'InstalledVerified' }
            $finalResult = New-GSResult -Success $true -Status $status -Message ('Package action verified: ' + $id) -PackageId $id -Source $source -OldVersion $before.InstalledVersion -NewVersion $after.InstalledVersion
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

        'repairwinget' {
            $repair = Repair-GSWinget
            Clear-GSCache -Scope All
            $finalResult = New-GSResult -Success $true -Status 'RepairVerified' -Message 'WinGet/App Installer repair completed and post-checks were executed.' -Data $repair
        }

        'diagnostics' {
            $diagnostics = New-GSDiagnosticsArchive -Version $version
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

    $finalResult = New-GSResult -Success $false -Status $classification.Status -ErrorCode $classification.Code -Message $classification.UserMessage -TechnicalMessage $classification.TechnicalMessage
    $exitCode = 1
}

if ($null -eq $finalResult) {
    $finalResult = New-GSResult -Success $false -Status 'Failed' -ErrorCode 'InternalError' -Message 'No operation result was produced.' -TechnicalMessage 'Core completed without a result object.'
    $exitCode = 1
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
