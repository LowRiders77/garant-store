# Garant Store - CMD metacharacter safety check
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = New-Object 'System.Collections.Generic.List[string]'
$cmdFiles = @(Get-ChildItem -LiteralPath $Root -Filter '*.cmd' -File -Recurse)

foreach ($file in $cmdFiles) {
    $lineNumber = 0
    foreach ($rawLine in [IO.File]::ReadAllLines($file.FullName,[Text.Encoding]::ASCII)) {
        $lineNumber++
        $line = [string]$rawLine
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^(?i)(rem\b|::)') { continue }
        if ($trimmed -match '^(?i)set\s+"[^"=]+=[^"]*"\s*$') { continue }

        $probe = $line
        $probe = $probe -replace '\^&',''
        $probe = $probe -replace '\^\|',''
        $probe = $probe -replace '\^<',''
        $probe = $probe -replace '\^>',''
        $probe = $probe -replace '\^\^',''
        $probe = $probe -replace '(?i)(?:\d?>\s*nul|\d?<\s*nul)',''

        if ($probe -match '[&|<>^]') {
            [void]$failures.Add(($file.Name + ':' + $lineNumber + ': raw CMD metacharacter: ' + $line.Trim()))
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ('FAIL: ' + $failure) -ForegroundColor Red
    }
    Write-Host ('CMD METACHARACTER CHECK FAILED: ' + $failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: CMD metacharacter safety check (& | < > ^)' -ForegroundColor Green

if ($env:OS -eq 'Windows_NT') {
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $fixturePath = Join-Path $env:TEMP ('GarantStore-cmd-meta-' + [Guid]::NewGuid().ToString('N') + '.cmd')
    try {
        $fixture = "@echo off`r`necho A ^& B ^| C ^< D ^> E ^^ F`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText($fixturePath,$fixture,[Text.Encoding]::ASCII)
        $commandLine = 'call "' + $fixturePath + '"'
        $output = @(& $cmdExe /d /s /c $commandLine)
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'FAIL: cmd.exe escaped metacharacter fixture returned non-zero.' -ForegroundColor Red
            exit 1
        }
        $joined = (($output -join "`n").Trim())
        if ($joined -ne 'A & B | C < D > E ^ F') {
            Write-Host ('FAIL: cmd.exe metacharacter round-trip mismatch: ' + $joined) -ForegroundColor Red
            exit 1
        }
        Write-Host 'PASS: real cmd.exe metacharacter round-trip' -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
    }
}

exit 0
