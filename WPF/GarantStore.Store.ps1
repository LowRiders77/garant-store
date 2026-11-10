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
        [bool]$AgreementConsent = $false,
        [bool]$AllowServiceChanges = $false
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

    if ($before.Status -eq 'Installed') {
        return [pscustomobject]@{
            Outcome = 'AlreadyCurrent'
            Before = $before
            After = $before
            Command = 'none'
            Attempts = 0
            ServiceRepair = $null
        }
    }

    if ($before.Status -eq 'StoreUpdateUnknown') {
        return [pscustomobject]@{
            Outcome = 'StoreUpdateUnknown'
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

    $serviceRepair = Ensure-GSStoreServicePrerequisites -AllowServiceChanges $AllowServiceChanges
    Write-GSProgress -Stage 'PreparingInstall' -Indeterminate $true -Detail 'WinGetCapabilities'
    $command = if ($before.Status -eq 'UpdateAvailable') { 'upgrade' } else { 'install' }

    [void](Ensure-GSAgreementCapabilities -Command $command)

    $attempt = 0
    # One automatic retry when the Store download drops (0x80d03805 etc.).
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
                -Silent

            Write-GSLog -Message (
                'Store action process completed in ' + [string]$actionResult.ElapsedSeconds +
                ' seconds; telemetry=' + (ConvertTo-Json -InputObject $actionResult.Telemetry -Depth 4 -Compress)
            ) -Level 'INFO'

            break
        } catch {
            $failureMessage = [string]$_.Exception.Message

            if ($failureMessage -match '^GSERR:ProcessTimeout:') {
                $timeoutState = $null
                try {
                    Clear-GSInventoryCache
                    $timeoutState = Get-GSExactPackageState -Id $Id -Source 'msstore' -AcceptAgreements $true
                    $installConfirmed = ($command -eq 'install' -and $timeoutState.Status -eq 'Installed')
                    $upgradeConfirmed = ($command -eq 'upgrade' -and $timeoutState.Status -eq 'Installed' -and
                        -not [string]::IsNullOrWhiteSpace([string]$before.InstalledVersion) -and
                        -not [string]::IsNullOrWhiteSpace([string]$timeoutState.InstalledVersion) -and
                        [string]$timeoutState.InstalledVersion -ne [string]$before.InstalledVersion)
                    if ($installConfirmed -or $upgradeConfirmed) {
                        $actionResult = [pscustomobject]@{ElapsedSeconds=$script:GSPackageActionTimeoutSeconds;Telemetry=$null;TimedOut=$true;PostStateVerified=$true}
                        Write-GSLog -Message ('WinGet timed out, but exact package-state verification confirms the operation. InstalledVersion=' + [string]$timeoutState.InstalledVersion) -Level 'WARN'
                        break
                    }
                } catch {
                    $timeoutState = [pscustomobject]@{Status='Unknown';InstalledVersion='';VerificationError=$_.Exception.Message}
                }
                $observed = if ($timeoutState) { [string]$timeoutState.Status + '; version=' + [string]$timeoutState.InstalledVersion } else { 'not checked' }
                $detail = 'WinGet installation timed out after the Store entitlement phase. The exact package state was not verified as installed (' + $observed + '). The timeout is not classified as a network failure; check Microsoft Store deployment/licensing events and service/policy state before retrying.'
                throw (New-GSClassifiedException -Code 'StoreDeploymentTimeout' -Message $detail)
            }

            if ($failureMessage -match '^GSERR:NetworkFailure:' -and $attempt -lt $maxAttempts) {
                Write-GSLog -Message ('Store download interrupted, retrying once: ' + $failureMessage) -Level 'WARN'
                Write-GSProgress -Stage 'DownloadRetry' -Indeterminate $true -Detail ''
                Start-Sleep -Seconds 10
                continue
            }

            if ($failureMessage -match '^GSERR:(PackageAgreementsRequired|SourceAgreementsRequired):') {
                throw (New-GSClassifiedException -Code 'AgreementHandshakeFailed' -Message ('Agreement consent was explicit and WinGet accept flags were supplied, but WinGet still refused the handshake. ' + $failureMessage))
            }

            throw
        }
    }

    Clear-GSInventoryCache
    Write-GSProgress -Stage 'Verifying' -Indeterminate $true -Detail 'PostVerification'

    $after = Get-GSExactPackageState -Id $Id -Source 'msstore' -AcceptAgreements $true -PresenceOnly
    # Microsoft Store finishes registration in the background: WinGet already
    # printed "installed" while the package was not listed yet (field: WhatsApp).
    # Re-check for up to ~90 s before calling it a failure.
    $deadline = (Get-Date).AddSeconds(90)
    while ($after.Status -in @('NotInstalled','Unknown') -and (Get-Date) -lt $deadline) {
        Write-GSProgress -Stage 'Verifying' -Indeterminate $true -Detail 'StoreRegistration'
        Start-Sleep -Seconds 6
        Clear-GSInventoryCache
        $after = Get-GSExactPackageState -Id $Id -Source 'msstore' -AcceptAgreements $true -PresenceOnly
    }
    Write-GSLog -Message ('Store post-state=' + $after.Status + '; installed=' + $after.InstalledVersion + '; available=' + $after.AvailableVersion) -Level 'INFO'

    if ($after.Status -in @('NotInstalled','Unknown','UpdateAvailable')) {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'Microsoft Store action returned, but exact post-verification did not detect the selected product.')
    }

    $outcome = if ($command -eq 'upgrade') {
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

