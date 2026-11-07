# Garant Store v0.8 DEV - Package State Engine
# Windows PowerShell 5.1 compatible. ASCII-only source.

Set-StrictMode -Version Latest

$script:GSInventoryCache = $null

function Clear-GSInventoryCache {
    $script:GSInventoryCache = $null
    Clear-GSCache -Scope State
}

function Compare-GSVersionValues {
    param(
        [string]$Installed,
        [string]$Available
    )

    if ([string]::IsNullOrWhiteSpace($Installed) -or [string]::IsNullOrWhiteSpace($Available)) {
        return 'Unknown'
    }
    if ($Installed -match '^(<|>|<=|>=|~)\s*' -or $Available -match '^(<|>|<=|>=|~)\s*') {
        return 'Unknown'
    }
    if ($Installed -match '(?i)^unknown$' -or $Available -match '(?i)^unknown$') {
        return 'Unknown'
    }
    if ([string]::Equals($Installed,$Available,[StringComparison]::OrdinalIgnoreCase)) {
        return 'Same'
    }

    try {
        $installedVersion = [version]$Installed
        $availableVersion = [version]$Available

        if ($availableVersion -gt $installedVersion) { return 'AvailableNewer' }
        if ($availableVersion -lt $installedVersion) { return 'InstalledNewer' }
        return 'Same'
    } catch {
        return 'Unknown'
    }
}

function New-GSInventorySnapshot {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Items,
        [bool]$StructuredSuccess,
        [bool]$RawListSuccess,
        [AllowEmptyString()][string]$RawListText = '',
        [AllowEmptyString()][string]$StructuredTechnicalMessage = '',
        [datetime]$Created = (Get-Date)
    )

    $map = @{}
    foreach ($item in @($Items)) {
        $id = [string]$item.Id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $map[$id.ToLowerInvariant()] = [pscustomobject]@{
            Id = $id
            Version = [string]$item.Version
            Source = [string]$item.Source
            SourceIdentifier = [string]$item.SourceIdentifier
            Origin = 'winget-export-json'
        }
    }

    return [pscustomobject]@{
        Created = $Created
        StructuredSuccess = $StructuredSuccess
        StructuredCount = $map.Count
        Map = $map
        Items = @($Items)
        RawListSuccess = $RawListSuccess
        RawListText = $RawListText
        ReliableForAbsence = $RawListSuccess
        StructuredTechnicalMessage = $StructuredTechnicalMessage
    }
}

function Get-GSInstalledInventory {
    param(
        [bool]$AcceptAgreements = $false,
        [string]$Source = '',
        [switch]$Force
    )

    $sourceScoped = -not [string]::IsNullOrWhiteSpace($Source)
    if (-not $sourceScoped -and -not $Force -and $script:GSInventoryCache) {
        $age = (Get-Date) - [datetime]$script:GSInventoryCache.Created
        if ($age.TotalSeconds -lt 120) {
            Write-GSLog -Message 'Installed inventory memory-cache hit.' -Level 'INFO'
            return $script:GSInventoryCache
        }
    }

    if (-not $sourceScoped -and -not $Force) {
        $cached = Read-GSCacheJson -Name 'inventory.json' -MaxAgeSeconds 120
        if ($null -ne $cached) {
            try {
                $created = [datetime]$cached.Created
                $snapshot = New-GSInventorySnapshot `
                    -Items @($cached.Items) `
                    -StructuredSuccess ([bool]$cached.StructuredSuccess) `
                    -RawListSuccess ([bool]$cached.RawListSuccess) `
                    -RawListText ([string]$cached.RawListText) `
                    -StructuredTechnicalMessage ([string]$cached.StructuredTechnicalMessage) `
                    -Created $created
                $script:GSInventoryCache = $snapshot
                Write-GSLog -Message ('Installed inventory persistent-cache hit. Items=' + $snapshot.StructuredCount) -Level 'INFO'
                return $snapshot
            } catch {
                Write-GSLog -Message ('Installed inventory cache ignored: ' + $_.Exception.Message) -Level 'WARN'
            }
        }
    }

    Write-GSLog -Message ('Building installed package inventory. Source=' + $(if($sourceScoped){$Source}else{'aggregate'})) -Level 'INFO'
    if ($sourceScoped) {
        $export = [pscustomobject]@{Success=$false;Items=@();TechnicalMessage='Source-scoped WinGet list is used.'}
    } else {
        $export = Export-GSWingetInventory -AcceptAgreements $AcceptAgreements
    }
    $raw = Get-GSWingetRawList -AcceptAgreements $AcceptAgreements -Source $(if($sourceScoped){$Source}else{''})

    $snapshot = New-GSInventorySnapshot `
        -Items @($export.Items) `
        -StructuredSuccess ([bool]$export.Success) `
        -RawListSuccess ([bool]$raw.Success) `
        -RawListText ([string]$raw.Text) `
        -StructuredTechnicalMessage ([string]$export.TechnicalMessage)

    if (-not $sourceScoped) {
        $script:GSInventoryCache = $snapshot
        $persist = [ordered]@{
            Schema = 1
            Created = ([datetime]$snapshot.Created).ToString('o')
            StructuredSuccess = [bool]$snapshot.StructuredSuccess
            Items = @($snapshot.Items)
            RawListSuccess = [bool]$snapshot.RawListSuccess
            RawListText = [string]$snapshot.RawListText
            StructuredTechnicalMessage = [string]$snapshot.StructuredTechnicalMessage
        }
        Write-GSCacheJson -Name 'inventory.json' -Value $persist
    }

    Write-GSLog -Message ('Inventory ready. JSON=' + $snapshot.StructuredSuccess + ', JSON items=' + $snapshot.StructuredCount + ', raw list=' + $snapshot.RawListSuccess) -Level 'INFO'
    return $snapshot
}

function Get-GSCachedStoreSnapshot {
    param([bool]$AcceptAgreements = $false)

    $cached = Read-GSCacheJson -Name 'store-snapshot.json' -MaxAgeSeconds 90
    if ($null -ne $cached) {
        Write-GSLog -Message 'Microsoft Store state persistent-cache hit.' -Level 'INFO'
        return [pscustomobject]@{
            Reliable = [bool]$cached.Reliable
            Empty = [bool]$cached.Empty
            Text = [string]$cached.Text
            ExitCode = $cached.ExitCode
            CacheHit = $true
        }
    }

    $snapshot = Get-GSWingetSourceListSnapshot -Source 'msstore' -AcceptAgreements $AcceptAgreements
    if ([bool]$snapshot.Reliable) {
        Write-GSCacheJson -Name 'store-snapshot.json' -Value ([ordered]@{
            Schema = 1
            Created = (Get-Date -Format o)
            Reliable = [bool]$snapshot.Reliable
            Empty = [bool]$snapshot.Empty
            Text = [string]$snapshot.Text
            ExitCode = $snapshot.ExitCode
        })
    }

    return [pscustomobject]@{
        Reliable = [bool]$snapshot.Reliable
        Empty = [bool]$snapshot.Empty
        Text = [string]$snapshot.Text
        ExitCode = $snapshot.ExitCode
        CacheHit = $false
    }
}

function Resolve-GSPackageState {
    param(
        [Parameter(Mandatory=$true)][object]$SearchRow,
        [Parameter(Mandatory=$true)][object]$Inventory
    )

    $id = [string]$SearchRow.Id
    $source = [string]$SearchRow.Source
    $available = [string]$SearchRow.Version

    $installed = ''
    $rawAvailable = ''
    $found = $false
    $origin = ''

    if ($Inventory.Map.ContainsKey($id.ToLowerInvariant())) {
        $record = $Inventory.Map[$id.ToLowerInvariant()]
        $installed = [string]$record.Version
        $found = $true
        $origin = 'winget-export-json'
    }

    if ($Inventory.RawListSuccess) {
        $rawRecord = Get-WingetKnownIdRecord -Text $Inventory.RawListText -Id $id -ExpectedSource $source
        if ($null -ne $rawRecord) {
            $found = $true
            if ([string]::IsNullOrWhiteSpace($installed)) {
                $installed = [string]$rawRecord.InstalledVersion
            }
            $rawAvailable = [string]$rawRecord.AvailableVersion
            if ([string]::IsNullOrWhiteSpace($origin)) {
                $origin = 'winget-list-known-id'
            } else {
                $origin += '+winget-list-known-id'
            }
        }
    }

    if (-not $found) {
        if ($Inventory.ReliableForAbsence) {
            return [pscustomobject]@{
                Status = 'NotInstalled'
                InstalledVersion = ''
                AvailableVersion = $available
                StateOrigin = 'winget-list-absence'
            }
        }

        return [pscustomobject]@{
            Status = 'Unknown'
            InstalledVersion = ''
            AvailableVersion = $available
            StateOrigin = 'inventory-incomplete'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($rawAvailable)) {
        return [pscustomobject]@{
            Status = 'UpdateAvailable'
            InstalledVersion = $installed
            AvailableVersion = $rawAvailable
            StateOrigin = $origin
        }
    }

    $comparison = Compare-GSVersionValues -Installed $installed -Available $available
    if ($comparison -eq 'AvailableNewer') {
        return [pscustomobject]@{
            Status = 'UpdateAvailable'
            InstalledVersion = $installed
            AvailableVersion = $available
            StateOrigin = $origin
        }
    }

    return [pscustomobject]@{
        Status = 'Installed'
        InstalledVersion = $installed
        AvailableVersion = if ($available -match '(?i)^unknown$') { '' } else { $available }
        StateOrigin = $origin
    }
}

function Get-GSExactPackageState {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Source,
        [bool]$AcceptAgreements = $false
    )

    $query = Get-GSWingetExactListQueryResult -Id $Id -Source $Source -AcceptAgreements $AcceptAgreements

    foreach ($listText in @($query.Texts)) {
        $record = Get-WingetKnownIdRecord -Text $listText -Id $Id -ExpectedSource $Source
        if ($null -ne $record) {
            $installed = [string]$record.InstalledVersion
            $available = [string]$record.AvailableVersion

            if ($Source -eq 'msstore') {
                return Resolve-GSStoreInstalledRecord `
                    -InstalledVersion $installed `
                    -AvailableVersion $available `
                    -StateOrigin 'exact-msstore-list'
            }

            $status = 'Installed'

            if (-not [string]::IsNullOrWhiteSpace($available) -and
                -not [string]::Equals($available,$installed,[StringComparison]::OrdinalIgnoreCase)) {
                $status = 'UpdateAvailable'
            }

            return [pscustomobject]@{
                Status = $status
                InstalledVersion = $installed
                AvailableVersion = $available
                StateOrigin = 'exact-winget-list'
            }
        }
    }

    if ($query.ConfirmedAbsent) {
        return [pscustomobject]@{
            Status = 'NotInstalled'
            InstalledVersion = ''
            AvailableVersion = ''
            StateOrigin = 'exact-winget-no-applications-found'
        }
    }

    # Structured export remains a secondary exact fallback when exact-list
    # completed but correlation did not yield a usable row.
    $inventory = Get-GSInstalledInventory -AcceptAgreements $AcceptAgreements -Force
    if ($inventory.Map.ContainsKey($Id.ToLowerInvariant())) {
        $item = $inventory.Map[$Id.ToLowerInvariant()]
        return [pscustomobject]@{
            Status = 'Installed'
            InstalledVersion = [string]$item.Version
            AvailableVersion = ''
            StateOrigin = 'winget-export-json'
        }
    }

    if ($inventory.RawListSuccess -and $query.QueryReliable) {
        return [pscustomobject]@{
            Status = 'NotInstalled'
            InstalledVersion = ''
            AvailableVersion = ''
            StateOrigin = 'exact-and-inventory-absence'
        }
    }

    return [pscustomobject]@{
        Status = 'Unknown'
        InstalledVersion = ''
        AvailableVersion = ''
        StateOrigin = 'unable-to-verify'
    }
}

function Resolve-GSStoreInstalledRecord {
    param(
        [AllowEmptyString()][string]$InstalledVersion = '',
        [AllowEmptyString()][string]$AvailableVersion = '',
        [string]$StateOrigin = 'msstore-list'
    )

    if ([string]::IsNullOrWhiteSpace($InstalledVersion) -or
        $InstalledVersion -match '(?i)^unknown$' -or
        $InstalledVersion -match '^(<|>|<=|>=|~)\s*') {
        return [pscustomobject]@{
            Status = 'StoreUpdateUnknown'
            InstalledVersion = $InstalledVersion
            AvailableVersion = ''
            StateOrigin = $StateOrigin + '-installed-version-unknown'
        }
    }

    # `winget list` omits its Available column when the installed package has
    # no update. Its exact, successful row is authoritative; the catalog
    # version from `winget search` is not an update signal.
    if ([string]::IsNullOrWhiteSpace($AvailableVersion)) {
        return [pscustomobject]@{
            Status = 'Installed'
            InstalledVersion = $InstalledVersion
            AvailableVersion = ''
            StateOrigin = $StateOrigin + '-no-update-listed'
        }
    }

    $comparison = Compare-GSVersionValues -Installed $InstalledVersion -Available $AvailableVersion
    if ($comparison -eq 'AvailableNewer') {
        return [pscustomobject]@{
            Status = 'UpdateAvailable'
            InstalledVersion = $InstalledVersion
            AvailableVersion = $AvailableVersion
            StateOrigin = $StateOrigin
        }
    }
    if ($comparison -in @('Same','InstalledNewer')) {
        return [pscustomobject]@{
            Status = 'Installed'
            InstalledVersion = $InstalledVersion
            AvailableVersion = ''
            StateOrigin = $StateOrigin + '-no-newer-version'
        }
    }

    return [pscustomobject]@{
        Status = 'StoreUpdateUnknown'
        InstalledVersion = $InstalledVersion
        AvailableVersion = $AvailableVersion
        StateOrigin = $StateOrigin + '-version-comparison-unknown'
    }
}

function Get-GSStoreSearchRowState {
    param(
        [Parameter(Mandatory=$true)][object]$SearchRow,
        [bool]$AcceptAgreements = $false
    )

    $id = [string]$SearchRow.Id
    $query = Get-GSWingetExactListQueryResult -Id $id -Source 'msstore' -AcceptAgreements $AcceptAgreements

    foreach ($listText in @($query.Texts)) {
        $record = Get-WingetKnownIdRecord -Text $listText -Id $id -ExpectedSource 'msstore'
        if ($null -eq $record) { continue }

        return Resolve-GSStoreInstalledRecord `
            -InstalledVersion ([string]$record.InstalledVersion) `
            -AvailableVersion ([string]$record.AvailableVersion) `
            -StateOrigin 'exact-msstore-list'
    }

    # 0x8A150014 is a successful semantic answer for a list/status query:
    # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND = package is not installed.
    if ($query.ConfirmedAbsent) {
        return [pscustomobject]@{
            Status = 'NotInstalled'
            InstalledVersion = ''
            AvailableVersion = [string]$SearchRow.Version
            StateOrigin = 'msstore-no-applications-found'
        }
    }

    return [pscustomobject]@{
        Status = 'Unknown'
        InstalledVersion = ''
        AvailableVersion = [string]$SearchRow.Version
        StateOrigin = 'exact-msstore-list-unavailable'
    }
}

function Resolve-GSStoreSearchRowFromSnapshot {
    param(
        [Parameter(Mandatory=$true)][object]$SearchRow,
        [Parameter(Mandatory=$true)][object]$Snapshot
    )

    $id = [string]$SearchRow.Id
    if (-not [bool]$Snapshot.Reliable) {
        return $null
    }

    $record = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.Text)) {
        $record = Get-WingetKnownIdRecord -Text ([string]$Snapshot.Text) -Id $id -ExpectedSource 'msstore'
    }

    if ($null -eq $record) {
        return [pscustomobject]@{
            Status = 'NotInstalled'
            InstalledVersion = ''
            AvailableVersion = [string]$SearchRow.Version
            StateOrigin = 'msstore-batch-list-absence'
        }
    }

    return Resolve-GSStoreInstalledRecord `
        -InstalledVersion ([string]$record.InstalledVersion) `
        -AvailableVersion ([string]$record.AvailableVersion) `
        -StateOrigin 'msstore-batch-list'
}

function Add-GSPackageStates {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,
        [bool]$AcceptAgreements = $false
    )

    $rowArray = @($Rows)
    if ($rowArray.Count -eq 0) {
        return @()
    }

    $hasWinGetRows = (@($rowArray | Where-Object { [string]$_.Source -ne 'msstore' }).Count -gt 0)
    $hasStoreRows = (@($rowArray | Where-Object { [string]$_.Source -eq 'msstore' }).Count -gt 0)

    $inventory = $null
    if ($hasWinGetRows) {
        $inventory = Get-GSInstalledInventory -AcceptAgreements $AcceptAgreements -Source 'winget'
    }

    $storeSnapshot = $null
    if ($hasStoreRows) {
        Write-GSLog -Message 'Building one Microsoft Store installed-state snapshot for all search results.' -Level 'INFO'
        $storeSnapshot = Get-GSCachedStoreSnapshot -AcceptAgreements $AcceptAgreements
        Write-GSLog -Message ('Store batch state snapshot reliable=' + $storeSnapshot.Reliable + '; empty=' + $storeSnapshot.Empty) -Level 'INFO'
    }

    $output = New-Object 'System.Collections.Generic.List[object]'

    foreach ($row in $rowArray) {
        if ([string]$row.Source -eq 'msstore') {
            $resolvedState = $null

            if ($null -ne $storeSnapshot -and [bool]$storeSnapshot.Reliable) {
                $resolvedState = Resolve-GSStoreSearchRowFromSnapshot -SearchRow $row -Snapshot $storeSnapshot
            }

            if ($null -eq $resolvedState) {
                $resolvedState = Get-GSStoreSearchRowState -SearchRow $row -AcceptAgreements $AcceptAgreements
            }
        } else {
            $resolvedState = Resolve-GSPackageState -SearchRow $row -Inventory $inventory
        }

        [void]$output.Add([pscustomobject]@{
            Name = [string]$row.Name
            Id = [string]$row.Id
            Version = [string]$row.Version
            Match = [string]$row.Match
            Source = [string]$row.Source
            Status = [string]$resolvedState.Status
            InstalledVersion = [string]$resolvedState.InstalledVersion
            AvailableVersion = [string]$resolvedState.AvailableVersion
            StateOrigin = [string]$resolvedState.StateOrigin
        })
    }

    return @($output.ToArray())
}


