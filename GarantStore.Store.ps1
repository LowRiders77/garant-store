# Garant Store v0.8 DEV - Microsoft Store Pipeline
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

function Ensure-GSAgreementCapabilities {
    param([Parameter(Mandatory=$true)][ValidateSet('install','upgrade')][string]$Command)

    $capabilities = Get-GSWingetAgreementCapabilities -Command $Command
    if ($capabilities.PackageAgreements -and $capabilities.SourceAgreements -and $capabilities.DisableInteractivity) {
        return $capabilities
    }

    Write-GSLog -Message 'Installed WinGet lacks one or more required non-interactive agreement capabilities. Running WinGet repair/update.' -Level 'WARN'
    [void](Repair-GSWinget)
    Clear-GSWingetCache

    $capabilities = Get-GSWingetAgreementCapabilities -Command $Command
    if (-not $capabilities.PackageAgreements -or -not $capabilities.SourceAgreements -or -not $capabilities.DisableInteractivity) {
        throw (New-GSClassifiedException -Code 'NeedsRepair' -Message 'WinGet still lacks required agreement/non-interactive command options after repair.')
    }

    return $capabilities
}

function Invoke-GSStorePackagePipeline {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$KnownStatus = '',
        [string]$AvailableVersion = '',
        [bool]$AgreementConsent = $false
    )

    if (-not $AgreementConsent) {
        throw (New-GSClassifiedException -Code 'PackageAgreementsRequired' -Message 'Explicit per-operation consent is required for a Microsoft Store package action.')
    }

    Write-GSLog -Message ('Store pipeline start: ' + $Name + ' [' + $Id + ']; AgreementConsent=True') -Level 'INFO'
    Write-GSProgress -Stage 'ResolvingPackage' -Indeterminate $true -Detail 'StoreManifest'

    [void](Confirm-GSWingetPackage -Id $Id -Source 'msstore' -AcceptAgreements $true)

    Write-GSProgress -Stage 'CheckingState' -Indeterminate $true -Detail 'ExactStoreState'
    $before = Get-GSExactPackageState -Id $Id -Source 'msstore' -AcceptAgreements $true
    Write-GSLog -Message ('Store pre-state=' + $before.Status + '; installed=' + $before.InstalledVersion + '; available=' + $before.AvailableVersion) -Level 'INFO'

    $storeUnknownRefresh = (
        $before.Status -eq 'Installed' -and
        ($KnownStatus -eq 'StoreUpdateUnknown' -or
         [string]::IsNullOrWhiteSpace($AvailableVersion) -or
         $AvailableVersion -match '(?i)^unknown$')
    )

    if ($before.Status -eq 'Installed' -and -not $storeUnknownRefresh) {
        return [pscustomobject]@{
            Outcome = 'AlreadyCurrent'
            Before = $before
            After = $before
            Command = 'none'
            Attempts = 0
            ServiceRepair = $null
        }
    }

    if ($before.Status -eq 'Unknown') {
        throw (New-GSClassifiedException -Code 'InternalError' -Message 'Microsoft Store installed state could not be verified. The operation was blocked.')
    }

    $serviceRepair = Ensure-GSStoreServicePrerequisites
    Write-GSProgress -Stage 'PreparingInstall' -Indeterminate $true -Detail 'WinGetCapabilities'
    $command = if ($before.Status -eq 'UpdateAvailable' -or $storeUnknownRefresh) { 'upgrade' } else { 'install' }

    [void](Ensure-GSAgreementCapabilities -Command $command)

    $attempt = 0
    $maxAttempts = 2
    $actionResult = $null

    while ($attempt -lt $maxAttempts) {
        $attempt++

        try {
            Write-GSLog -Message ('Store action attempt ' + $attempt + '/' + $maxAttempts + ': ' + $command + '; agreements=accepted-for-operation') -Level 'INFO'

            $actionResult = Invoke-GSWingetPackageAction `
                -Command $command `
                -Id $Id `
                -Source 'msstore' `
                -AgreementConsent $true `
                -IncludeUnknown:$storeUnknownRefresh `
                -Force:$storeUnknownRefresh

            Write-GSLog -Message (
                'Store action process completed in ' + [string]$actionResult.ElapsedSeconds +
                ' seconds; telemetry=' + (ConvertTo-Json -InputObject $actionResult.Telemetry -Depth 4 -Compress)
            ) -Level 'INFO'

            break
        } catch {
            $failureMessage = [string]$_.Exception.Message

            if ($failureMessage -match '^GSERR:StoreServiceDisabled:' -and $attempt -lt $maxAttempts) {
                Write-GSLog -Message 'Store service failure detected during action. Repairing service prerequisites and retrying once.' -Level 'WARN'
                $serviceRepair = Ensure-GSStoreServicePrerequisites
                continue
            }

            if ($failureMessage -match '^GSERR:(PackageAgreementsRequired|SourceAgreementsRequired):') {
                throw (New-GSClassifiedException -Code 'AgreementHandshakeFailed' -Message ('Agreement consent was explicit and WinGet accept flags were supplied, but WinGet still refused the handshake. ' + $failureMessage))
            }

            throw
        }
    }

    Clear-GSInventoryCache
    Write-GSProgress -Stage 'Verifying' -Indeterminate $true -Detail 'ExactPostVerification'

    $after = Get-GSExactPackageState -Id $Id -Source 'msstore' -AcceptAgreements $true
    Write-GSLog -Message ('Store post-state=' + $after.Status + '; installed=' + $after.InstalledVersion + '; available=' + $after.AvailableVersion) -Level 'INFO'

    if ($after.Status -eq 'NotInstalled' -or $after.Status -eq 'Unknown') {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'Microsoft Store action returned, but exact post-verification did not detect the selected product.')
    }

    $outcome = if ($storeUnknownRefresh) {
        'StoreRefreshVerified'
    } elseif ($command -eq 'upgrade') {
        'UpdateVerified'
    } else {
        'InstalledVerified'
    }

    return [pscustomobject]@{
        Outcome = $outcome
        Before = $before
        After = $after
        Command = $command
        Attempts = $attempt
        ServiceRepair = $serviceRepair
        ActionElapsedSeconds = if ($null -ne $actionResult) { [double]$actionResult.ElapsedSeconds } else { 0 }
        Telemetry = if ($null -ne $actionResult) { $actionResult.Telemetry } else { $null }
    }
}
