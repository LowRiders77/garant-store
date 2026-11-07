# Garant Store - package install pipeline shared by single installs and bundles.
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

function Invoke-GSPackageInstall {
    # Installs or upgrades one exactly identified package and verifies the result.
    # Returns the fields Core passes to New-GSResult. Throws classified errors.
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Source,
        [string]$Name = '',
        [string]$KnownStatus = '',
        [string]$AvailableVersion = '',
        [bool]$AgreementConsent = $false,
        [bool]$AllowServiceChanges = $false
    )

    if (-not (Test-GSValidPackageId -Id $Id) -or $Source -notin @('msstore','winget')) {
        throw (New-GSClassifiedException -Code 'InternalError' -Message 'Invalid selected package identity.')
    }

    if ($Source -eq 'msstore') {
        $storeResult = Invoke-GSStorePackagePipeline `
            -Id $Id `
            -Name $Name `
            -KnownStatus $KnownStatus `
            -AvailableVersion $AvailableVersion `
            -AgreementConsent $AgreementConsent `
            -AllowServiceChanges $AllowServiceChanges

        $storeMessage = switch ([string]$storeResult.Outcome) {
            'AlreadyCurrent' { 'The selected Microsoft Store application is already installed and current.'; break }
            'StoreUpdateUnknown' { 'The application is installed, but update availability could not be confirmed. No changes were made.'; break }
            'UpdateVerified' { 'The Microsoft Store update was installed and verified.'; break }
            'InstalledVerified' { 'The Microsoft Store application was installed and verified.'; break }
            default { 'The Microsoft Store operation completed.' }
        }

        return [pscustomobject]@{
            Status = [string]$storeResult.Outcome
            Message = $storeMessage
            PackageId = $Id
            Source = $Source
            OldVersion = [string]$storeResult.Before.InstalledVersion
            NewVersion = [string]$storeResult.After.InstalledVersion
            Data = $storeResult
        }
    }

    if (-not $AgreementConsent) {
        throw (New-GSClassifiedException -Code 'PackageAgreementsRequired' -Message 'Explicit per-operation consent is required for package installation.')
    }

    [void](Confirm-GSWingetPackage -Id $Id -Source $Source -AcceptAgreements $true)
    $before = Get-GSExactPackageState -Id $Id -Source $Source -AcceptAgreements $true

    if ($before.Status -eq 'Installed') {
        return [pscustomobject]@{
            Status = 'AlreadyCurrent'
            Message = 'The selected application is already installed and current.'
            PackageId = $Id
            Source = $Source
            OldVersion = [string]$before.InstalledVersion
            NewVersion = [string]$before.InstalledVersion
            Data = $null
        }
    }

    if ($before.Status -eq 'Unknown') {
        throw (New-GSClassifiedException -Code 'InternalError' -Message 'Installed state could not be verified. System modification was blocked.')
    }

    $command = if ($before.Status -eq 'UpdateAvailable') { 'upgrade' } else { 'install' }
    [void](Ensure-GSAgreementCapabilities -Command $command)
    [void](Invoke-GSWingetPackageAction -Command $command -Id $Id -Source $Source -AgreementConsent $true -Silent)

    Clear-GSInventoryCache
    $after = Get-GSExactPackageState -Id $Id -Source $Source -AcceptAgreements $true

    if ($after.Status -eq 'NotInstalled' -or $after.Status -eq 'Unknown' -or $after.Status -eq 'UpdateAvailable') {
        throw (New-GSClassifiedException -Code 'DeploymentFailure' -Message 'Post-action verification failed for the selected package.')
    }

    return [pscustomobject]@{
        Status = $(if ($command -eq 'upgrade') { 'UpdateVerified' } else { 'InstalledVerified' })
        Message = ('Package action verified: ' + $Id)
        PackageId = $Id
        Source = $Source
        OldVersion = [string]$before.InstalledVersion
        NewVersion = [string]$after.InstalledVersion
        Data = $null
    }
}

function ConvertTo-GSBundleItems {
    # Validates a bundle request: exact IDs, known sources, no duplicates, bounded size.
    param([object[]]$Items)
    $result = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.Id
        $source = [string]$item.Source
        $name = if ($item.PSObject.Properties.Name -contains 'Name') { [string]$item.Name } else { $id }
        if (-not (Test-GSValidPackageId -Id $id) -or $source -notin @('msstore','winget')) {
            throw (New-GSClassifiedException -Code 'InternalError' -Message ('Invalid bundle item: ' + $id + ' / ' + $source))
        }
        $key = $source + '|' + $id.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$result.Add([pscustomobject]@{ Name = $name; Id = $id; Source = $source })
    }
    if ($result.Count -eq 0) { throw (New-GSClassifiedException -Code 'InternalError' -Message 'The bundle request contains no packages.') }
    if ($result.Count -gt 40) { throw (New-GSClassifiedException -Code 'InternalError' -Message 'A bundle may contain at most 40 packages.') }
    return @($result.ToArray())
}

function Get-GSBundleStates {
    # One inventory pass for all items: the same state engine the search results use.
    param([object[]]$Items, [bool]$AcceptAgreements = $false)
    $rows = @(ConvertTo-GSBundleItems -Items $Items | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Version = ''; Match = ''; Source = $_.Source }
    })
    return @(Add-GSPackageStates -Rows $rows -AcceptAgreements $AcceptAgreements)
}

function Invoke-GSBundleInstall {
    # Installs items strictly one after another (parallel installers collide on the
    # Windows Installer mutex) and keeps going after a failure. Every item gets an
    # outcome; nothing is reported as installed without post-install verification.
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [bool]$AgreementConsent = $false,
        [bool]$AllowServiceChanges = $false
    )
    if (-not $AgreementConsent) {
        throw (New-GSClassifiedException -Code 'PackageAgreementsRequired' -Message 'Explicit consent is required for a bundle installation.')
    }
    $list = @(ConvertTo-GSBundleItems -Items $Items)
    $outcomes = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($item in $list) {
        $index++
        $percent = [Math]::Round((($index - 1) * 100.0) / $list.Count, 0)
        Write-GSProgress -Stage ('Bundle ' + $index + '/' + $list.Count) -Indeterminate $false -Percent $percent -Detail $item.Name
        Write-GSLog -Message ('Bundle item ' + $index + '/' + $list.Count + ': ' + $item.Id + ' [' + $item.Source + ']') -Level 'INFO'
        try {
            $result = Invoke-GSPackageInstall -Id $item.Id -Source $item.Source -Name $item.Name -AgreementConsent $true -AllowServiceChanges $AllowServiceChanges
            [void]$outcomes.Add([pscustomobject]@{ Name = $item.Name; Id = $item.Id; Source = $item.Source; Outcome = [string]$result.Status; ErrorCode = ''; Message = [string]$result.Message; NewVersion = [string]$result.NewVersion })
        } catch {
            $classification = ConvertFrom-GSException -Exception $_.Exception
            Write-GSLog -Message ('Bundle item failed: ' + $item.Id + ' - ' + $classification.Code + ': ' + $classification.TechnicalMessage) -Level 'ERROR'
            [void]$outcomes.Add([pscustomobject]@{ Name = $item.Name; Id = $item.Id; Source = $item.Source; Outcome = 'Failed'; ErrorCode = [string]$classification.Code; Message = [string]$classification.UserMessage; NewVersion = '' })
        } finally {
            # Store service changes made for this item are restored before the next one.
            try { Restore-GSStoreServiceStartupTypes } catch {}
        }
    }
    $all = @($outcomes.ToArray())
    $failed = @($all | Where-Object { $_.Outcome -eq 'Failed' })
    return [pscustomobject]@{
        Items = $all
        Total = $all.Count
        Installed = @($all | Where-Object { $_.Outcome -in @('InstalledVerified','UpdateVerified') }).Count
        AlreadyPresent = @($all | Where-Object { $_.Outcome -in @('AlreadyCurrent','StoreUpdateUnknown') }).Count
        Failed = $failed.Count
        NeedsServiceConsent = @($failed | Where-Object { $_.ErrorCode -eq 'StoreServiceConsentRequired' } | ForEach-Object { $_.Id })
    }
}
