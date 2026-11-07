# Garant Store v0.8 DEV - Parsers
# ASCII-only source file.

Set-StrictMode -Version Latest

function Test-GSSearchVersionToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    if ($Token -match '(?i)^unknown$') { return $true }
    if ($Token -match '^[vV]?\d') { return $true }
    if ($Token -match '^(<|>|<=|>=|~)$') { return $true }
    return $false
}

function Get-GSSearchIdScore {
    param(
        [string]$Candidate,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) { return -1 }
    if ($Candidate -notmatch '^[A-Za-z0-9][A-Za-z0-9._+:-]{1,199}$') { return -1 }

    if ($Source -eq 'msstore') {
        if ($Candidate -match '^(?i)(9[A-Z0-9]{11}|XP[A-Z0-9]{12})$') { return 200 }
        if ($Candidate -match '^[A-Za-z0-9]{10,16}$') { return 100 }
        return -1
    }

    if ($Source -in @('winget','winget-font')) {
        if ($Candidate.Contains('.')) { return 180 }
        if ($Candidate.Contains('-') -or $Candidate.Contains('_')) { return 80 }
        return 10
    }

    if ($Candidate.Contains('.')) { return 100 }
    if ($Candidate -match '^(?i)(9[A-Z0-9]{11}|XP[A-Z0-9]{12})$') { return 150 }
    return 1
}

function ConvertFrom-GSLooseSearchRow {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Line,
        [string]$FallbackSource = ''
    )

    $work = ([string]$Line).Trim()
    if ([string]::IsNullOrWhiteSpace($work)) { return $null }
    if ($work -match '^-+(?:\s+-+){2,}$') { return $null }

    $source = ''
    $sourceMatch = [regex]::Match($work,'(?i)\s+(msstore|winget|winget-font)\s*$')
    if ($sourceMatch.Success) {
        $source = $sourceMatch.Groups[1].Value.ToLowerInvariant()
        $work = $work.Substring(0,$sourceMatch.Index).TrimEnd()
    } elseif ($FallbackSource -in @('msstore','winget','winget-font')) {
        $source = $FallbackSource
    } else {
        return $null
    }

    $tokens = @($work -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($tokens.Count -lt 3) { return $null }

    $bestIndex = -1
    $bestScore = -1

    for ($i = 1; $i -lt ($tokens.Count - 1); $i++) {
        $candidate = [string]$tokens[$i]
        $nextToken = [string]$tokens[$i + 1]

        if (-not (Test-GSSearchVersionToken -Token $nextToken)) { continue }

        $score = Get-GSSearchIdScore -Candidate $candidate -Source $source
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestIndex = $i
        }
    }

    if ($bestIndex -lt 1) { return $null }

    $packageId = [string]$tokens[$bestIndex]
    $name = (($tokens[0..($bestIndex - 1)]) -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }

    $versionIndex = $bestIndex + 1
    $version = [string]$tokens[$versionIndex]
    $nextIndex = $versionIndex + 1

    if ($version -in @('<','>','<=','>=','~') -and $nextIndex -lt $tokens.Count) {
        $version = ($version + ' ' + [string]$tokens[$nextIndex])
        $nextIndex++
    }

    $matchText = ''
    if ($nextIndex -lt $tokens.Count) {
        $matchText = (($tokens[$nextIndex..($tokens.Count - 1)]) -join ' ').Trim()
    }

    return [pscustomobject]@{
        Name = $name
        Id = $packageId
        Version = $version
        Match = $matchText
        Source = $source
    }
}

function ConvertFrom-WingetSearchText {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [string]$FallbackSource = ''
    )

    $clean = $Text.Replace(([string][char]8),'')
    $lines = @($clean -split "`r?`n")
    $resultList = New-Object 'System.Collections.Generic.List[object]'

    # Preferred parser: use the dashed separator emitted by WinGet.
    # This is independent of localized column names.
    $separatorIndex = -1
    $columnMatches = $null

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        if ($line -match '^\s*-+(?:\s+-+){2,}\s*$') {
            $matchesFound = [regex]::Matches($line,'-+')
            if ($matchesFound.Count -ge 3) {
                $separatorIndex = $lineIndex
                $columnMatches = $matchesFound
                break
            }
        }
    }

    if ($separatorIndex -ge 0 -and $null -ne $columnMatches) {
        for ($rowIndex = $separatorIndex + 1; $rowIndex -lt $lines.Count; $rowIndex++) {
            $rowText = [string]$lines[$rowIndex]
            if ([string]::IsNullOrWhiteSpace($rowText)) { continue }

            $values = New-Object 'System.Collections.Generic.List[string]'

            for ($columnIndex = 0; $columnIndex -lt $columnMatches.Count; $columnIndex++) {
                $start = [int]$columnMatches[$columnIndex].Index
                if ($rowText.Length -le $start) {
                    [void]$values.Add('')
                    continue
                }

                if ($columnIndex -lt ($columnMatches.Count - 1)) {
                    $nextStart = [int]$columnMatches[$columnIndex + 1].Index
                    $length = [Math]::Max(0,[Math]::Min($rowText.Length,$nextStart) - $start)
                } else {
                    $length = $rowText.Length - $start
                }

                if ($length -le 0) {
                    [void]$values.Add('')
                } else {
                    [void]$values.Add($rowText.Substring($start,$length).Trim())
                }
            }

            if ($values.Count -lt 3) { continue }

            $name = [string]$values[0]
            $packageId = [string]$values[1]
            $version = [string]$values[2]
            $lastValue = [string]$values[$values.Count - 1]
            $source = ''
            $matchText = ''
            $matchEndIndex = $values.Count - 1

            if ($lastValue -in @('msstore','winget','winget-font')) {
                $source = $lastValue
                $matchEndIndex = $values.Count - 2
            } elseif ($FallbackSource -in @('msstore','winget','winget-font')) {
                # Some source-specific WinGet builds may omit the Source column.
                $source = $FallbackSource
                $matchEndIndex = $values.Count - 1
            }

            if ($matchEndIndex -ge 3) {
                $matchParts = @()
                for ($matchIndex = 3; $matchIndex -le $matchEndIndex; $matchIndex++) {
                    if (-not [string]::IsNullOrWhiteSpace($values[$matchIndex])) {
                        $matchParts += [string]$values[$matchIndex]
                    }
                }
                $matchText = ($matchParts -join ' ').Trim()
            }

            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($packageId)) {
                continue
            }

            if ($packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+:-]{1,199}$') {
                continue
            }

            if ($source -notin @('msstore','winget','winget-font')) {
                # Ignore non-table text if it somehow appears below the separator.
                continue
            }

            [void]$resultList.Add([pscustomobject]@{
                Name = $name
                Id = $packageId
                Version = $version
                Match = $matchText
                Source = $source
            })
        }
    }

    if ($resultList.Count -gt 0) {
        return @($resultList.ToArray())
    }

    # Parser V2 fallback. WinGet can collapse table spacing when stdout is redirected,
    # especially for short result sets. Parse rows by source token + package ID/version
    # anchors instead of relying on fixed-width columns.
    foreach ($lineRaw in $lines) {
        $parsed = ConvertFrom-GSLooseSearchRow -Line ([string]$lineRaw) -FallbackSource $FallbackSource
        if ($null -eq $parsed) { continue }

        $duplicate = $false
        foreach ($existing in @($resultList.ToArray())) {
            if ([string]::Equals([string]$existing.Id,[string]$parsed.Id,[StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$existing.Source,[string]$parsed.Source,[StringComparison]::OrdinalIgnoreCase)) {
                $duplicate = $true
                break
            }
        }

        if (-not $duplicate) {
            [void]$resultList.Add($parsed)
        }
    }

    return @($resultList.ToArray())
}

function ConvertFrom-WingetListText {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
    )

    $clean = $Text.Replace(([string][char]8),'')
    $lines = @($clean -split "`r?`n")
    $resultList = New-Object 'System.Collections.Generic.List[object]'

    $separatorIndex = -1
    $columnMatches = $null

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        if ($line -match '^\s*-+(?:\s+-+){2,}\s*$') {
            $matchesFound = [regex]::Matches($line,'-+')
            if ($matchesFound.Count -ge 3) {
                $separatorIndex = $lineIndex
                $columnMatches = $matchesFound
                break
            }
        }
    }

    if ($separatorIndex -lt 0 -or $null -eq $columnMatches) {
        return @()
    }

    for ($rowIndex = $separatorIndex + 1; $rowIndex -lt $lines.Count; $rowIndex++) {
        $rowText = [string]$lines[$rowIndex]
        if ([string]::IsNullOrWhiteSpace($rowText)) { continue }

        $values = New-Object 'System.Collections.Generic.List[string]'

        for ($columnIndex = 0; $columnIndex -lt $columnMatches.Count; $columnIndex++) {
            $start = [int]$columnMatches[$columnIndex].Index

            if ($rowText.Length -le $start) {
                [void]$values.Add('')
                continue
            }

            if ($columnIndex -lt ($columnMatches.Count - 1)) {
                $nextStart = [int]$columnMatches[$columnIndex + 1].Index
                $length = [Math]::Max(0,[Math]::Min($rowText.Length,$nextStart) - $start)
            } else {
                $length = $rowText.Length - $start
            }

            if ($length -le 0) {
                [void]$values.Add('')
            } else {
                [void]$values.Add($rowText.Substring($start,$length).Trim())
            }
        }

        if ($values.Count -lt 3) { continue }

        $name = [string]$values[0]
        $packageId = [string]$values[1]
        $installedVersion = [string]$values[2]

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        if ($packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+:-]{1,199}$') {
            continue
        }

        $availableVersion = ''
        $source = ''

        if ($values.Count -ge 4) {
            $lastValue = [string]$values[$values.Count - 1]
            if ($lastValue -in @('msstore','winget','winget-font')) {
                $source = $lastValue

                if ($values.Count -ge 5) {
                    $availableVersion = [string]$values[3]
                }
            } else {
                $availableVersion = [string]$values[3]
            }
        }

        if ($availableVersion -eq $installedVersion) {
            $availableVersion = ''
        }

        [void]$resultList.Add([pscustomobject]@{
            Name = $name
            Id = $packageId
            InstalledVersion = $installedVersion
            AvailableVersion = $availableVersion
            Source = $source
        })
    }

    return @($resultList.ToArray())
}

function Join-WingetVersionTokens {
    param(
        [string[]]$Tokens,
        [int]$StartIndex
    )

    if ($null -eq $Tokens -or $StartIndex -ge $Tokens.Count) {
        return [pscustomobject]@{
            Value = ''
            NextIndex = $StartIndex
        }
    }

    $first = [string]$Tokens[$StartIndex]

    if ($first -in @('<','>','<=','>=','~')) {
        if (($StartIndex + 1) -lt $Tokens.Count) {
            return [pscustomobject]@{
                Value = ($first + ' ' + [string]$Tokens[$StartIndex + 1])
                NextIndex = $StartIndex + 2
            }
        }
    }

    return [pscustomobject]@{
        Value = $first
        NextIndex = $StartIndex + 1
    }
}

function Get-WingetKnownIdRecord {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory=$true)][string]$Id,
        [string]$ExpectedSource = ''
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    $clean = $Text.Replace(([string][char]8),'')
    $escapedId = [regex]::Escape($Id)
    $idPattern = '(?i)(?<!\S)' + $escapedId + '(?!\S)'

    foreach ($lineRaw in ($clean -split "`r?`n")) {
        $line = [string]$lineRaw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $idMatch = [regex]::Match($line,$idPattern)
        if (-not $idMatch.Success) { continue }

        $tailStart = $idMatch.Index + $idMatch.Length
        if ($tailStart -ge $line.Length) { continue }

        $tail = $line.Substring($tailStart).Trim()
        if ([string]::IsNullOrWhiteSpace($tail)) { continue }

        $tokens = @($tail -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($tokens.Count -lt 1) { continue }

        $source = ''
        if ($tokens[$tokens.Count - 1] -in @('msstore','winget','winget-font')) {
            $source = [string]$tokens[$tokens.Count - 1]
            if ($tokens.Count -eq 1) { continue }
            $tokens = @($tokens[0..($tokens.Count - 2)])
        } elseif ($ExpectedSource -in @('msstore','winget','winget-font')) {
            $source = $ExpectedSource
        }

        $installedPart = Join-WingetVersionTokens -Tokens $tokens -StartIndex 0
        $installedVersion = [string]$installedPart.Value
        $availableVersion = ''

        if ($installedPart.NextIndex -lt $tokens.Count) {
            $availablePart = Join-WingetVersionTokens -Tokens $tokens -StartIndex $installedPart.NextIndex
            $availableVersion = [string]$availablePart.Value
        }

        if ([string]::IsNullOrWhiteSpace($installedVersion)) {
            continue
        }

        $name = $line.Substring(0,$idMatch.Index).Trim()

        return [pscustomobject]@{
            Name = $name
            Id = $Id
            InstalledVersion = $installedVersion
            AvailableVersion = $availableVersion
            Source = $source
            RawLine = $line.Trim()
        }
    }

    return $null
}

function ConvertFrom-GSWingetExportObject {
    param(
        [Parameter(Mandatory=$true)][object]$ExportObject
    )

    $items = New-Object 'System.Collections.Generic.List[object]'

    if ($null -eq $ExportObject -or $null -eq $ExportObject.Sources) {
        return @()
    }

    foreach ($sourceEntry in @($ExportObject.Sources)) {
        $sourceName = ''
        $sourceIdentifier = ''

        if ($sourceEntry.PSObject.Properties.Name -contains 'SourceDetails' -and $sourceEntry.SourceDetails) {
            if ($sourceEntry.SourceDetails.PSObject.Properties.Name -contains 'Name') {
                $sourceName = [string]$sourceEntry.SourceDetails.Name
            }
            if ($sourceEntry.SourceDetails.PSObject.Properties.Name -contains 'Identifier') {
                $sourceIdentifier = [string]$sourceEntry.SourceDetails.Identifier
            }
        }

        if ([string]::IsNullOrWhiteSpace($sourceName) -and $sourceEntry.PSObject.Properties.Name -contains 'Name') {
            $sourceName = [string]$sourceEntry.Name
        }
        if ([string]::IsNullOrWhiteSpace($sourceIdentifier) -and $sourceEntry.PSObject.Properties.Name -contains 'Identifier') {
            $sourceIdentifier = [string]$sourceEntry.Identifier
        }

        if ($null -eq $sourceEntry.Packages) { continue }

        foreach ($package in @($sourceEntry.Packages)) {
            $packageId = ''
            $version = ''

            if ($package.PSObject.Properties.Name -contains 'PackageIdentifier') {
                $packageId = [string]$package.PackageIdentifier
            }
            if ($package.PSObject.Properties.Name -contains 'Version') {
                $version = [string]$package.Version
            }

            if ([string]::IsNullOrWhiteSpace($packageId)) { continue }

            [void]$items.Add([pscustomobject]@{
                Id = $packageId
                Version = $version
                Source = $sourceName
                SourceIdentifier = $sourceIdentifier
            })
        }
    }

    return @($items.ToArray())
}

function Test-GSValidPackageId {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    return ($Id -match '^[A-Za-z0-9][A-Za-z0-9._+:\-\\{} ]{1,299}$')
}


