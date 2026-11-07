# Garant Store - StrictMode AST hazard checks
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = New-Object 'System.Collections.Generic.List[string]'

function Add-Failure([string]$Message) {
    [void]$failures.Add($Message)
    Write-Host ('FAIL: ' + $Message) -ForegroundColor Red
}

$parserContractPath = Join-Path $Root 'GarantStore.Parser.ps1'
if (Test-Path -LiteralPath $parserContractPath -PathType Leaf) {
    $contractTokens = $null
    $contractErrors = $null
    $contractAst = [Management.Automation.Language.Parser]::ParseFile($parserContractPath,[ref]$contractTokens,[ref]$contractErrors)

    $emptySafeContracts = @(
        @{ Function='ConvertFrom-GSLooseSearchRow'; Parameter='Line' },
        @{ Function='ConvertFrom-WingetSearchText'; Parameter='Text' },
        @{ Function='ConvertFrom-WingetListText'; Parameter='Text' },
        @{ Function='Get-WingetKnownIdRecord'; Parameter='Text' }
    )

    foreach ($contract in $emptySafeContracts) {
        $functionNode = @($contractAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            [string]$node.Name -eq [string]$contract.Function
        },$true) | Select-Object -First 1)

        if ($functionNode.Count -ne 1) {
            Add-Failure ('Parser contract function missing: ' + [string]$contract.Function)
            continue
        }

        $parameterNode = @($functionNode[0].Body.ParamBlock.Parameters | Where-Object {
            [string]$_.Name.VariablePath.UserPath -eq [string]$contract.Parameter
        })

        if ($parameterNode.Count -ne 1) {
            Add-Failure ('Parser contract parameter missing: ' + [string]$contract.Function + '::' + [string]$contract.Parameter)
            continue
        }

        $hasAllowEmptyString = @($parameterNode[0].Attributes | Where-Object {
            $_ -is [Management.Automation.Language.AttributeAst] -and
            [string]$_.TypeName.Name -eq 'AllowEmptyString'
        }).Count -gt 0

        if (-not $hasAllowEmptyString) {
            Add-Failure ('Parser empty-string contract missing AllowEmptyString: ' + [string]$contract.Function + '::' + [string]$contract.Parameter)
        }
    }
}

function Get-GSMemberName {
    param(
        [Parameter(Mandatory=$true)]
        [Management.Automation.Language.MemberExpressionAst]$Node
    )

    $memberAst = $Node.Member
    if ($null -eq $memberAst) { return '' }

    if ($memberAst -is [Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$memberAst.Value
    }

    # Dynamic/member AST nodes do not all expose a Value property in Windows
    # PowerShell 5.1. Extent is common to AST nodes and is safe as a fallback.
    if ($null -ne $memberAst.Extent) {
        return [string]$memberAst.Extent.Text
    }

    return ''
}

function Find-GSUnsafeCountMemberNodes {
    param(
        [Parameter(Mandatory=$true)]
        [Management.Automation.Language.Ast]$Ast
    )

    return @($Ast.FindAll({
        param($node)

        if (-not ($node -is [Management.Automation.Language.MemberExpressionAst])) {
            return $false
        }

        $memberName = Get-GSMemberName -Node $node
        if (-not [string]::Equals($memberName,'Count',[StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        return ($node.Expression -is [Management.Automation.Language.ParenExpressionAst])
    },$true))
}

# Behavioral self-test for the AST linter itself. This executes on the same real
# Windows PowerShell 5.1 runtime used by the release gate.
$unsafeTokens = $null
$unsafeErrors = $null
$unsafeAst = [Management.Automation.Language.Parser]::ParseInput(
    '$value = (Get-ChildItem | Where-Object { $_ }).Count',
    [ref]$unsafeTokens,
    [ref]$unsafeErrors
)
if (@($unsafeErrors).Count -ne 0) {
    Add-Failure 'StrictMode AST self-test could not parse unsafe fixture.'
} else {
    $unsafeFixtureNodes = @(Find-GSUnsafeCountMemberNodes -Ast $unsafeAst)
    if ($unsafeFixtureNodes.Count -ne 1) {
        Add-Failure ('StrictMode AST self-test failed to detect unsafe parenthesized .Count. Found=' + $unsafeFixtureNodes.Count)
    } else {
        Write-Host 'PASS: StrictMode AST detects unsafe parenthesized .Count' -ForegroundColor Green
    }
}

$safeTokens = $null
$safeErrors = $null
$safeAst = [Management.Automation.Language.Parser]::ParseInput(
    '$value = @(Get-ChildItem | Where-Object { $_ }).Count',
    [ref]$safeTokens,
    [ref]$safeErrors
)
if (@($safeErrors).Count -ne 0) {
    Add-Failure 'StrictMode AST self-test could not parse safe fixture.'
} else {
    $safeFixtureNodes = @(Find-GSUnsafeCountMemberNodes -Ast $safeAst)
    if ($safeFixtureNodes.Count -ne 0) {
        Add-Failure ('StrictMode AST self-test falsely flagged @(...).Count. Found=' + $safeFixtureNodes.Count)
    } else {
        Write-Host 'PASS: StrictMode AST accepts array-wrapped .Count' -ForegroundColor Green
    }
}

$dynamicTokens = $null
$dynamicErrors = $null
$dynamicAst = [Management.Automation.Language.Parser]::ParseInput(
    '$value = $object.$memberName',
    [ref]$dynamicTokens,
    [ref]$dynamicErrors
)
if (@($dynamicErrors).Count -ne 0) {
    Add-Failure 'StrictMode AST self-test could not parse dynamic-member fixture.'
} else {
    try {
        $dynamicFixtureNodes = @(Find-GSUnsafeCountMemberNodes -Ast $dynamicAst)
        if ($dynamicFixtureNodes.Count -ne 0) {
            Add-Failure 'StrictMode AST dynamic-member fixture produced a false Count hazard.'
        } else {
            Write-Host 'PASS: StrictMode AST handles non-string member nodes' -ForegroundColor Green
        }
    } catch {
        Add-Failure ('StrictMode AST dynamic-member safety failed: ' + $_.Exception.Message)
    }
}

$files = @(Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse)
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)

    if (@($parseErrors).Count -gt 0) {
        foreach ($parseError in @($parseErrors)) {
            Add-Failure ($file.Name + ': syntax: ' + $parseError.Message)
        }
        continue
    }

    $memberNodes = @(Find-GSUnsafeCountMemberNodes -Ast $ast)

    foreach ($node in $memberNodes) {
        Add-Failure ($file.Name + ':' + $node.Extent.StartLineNumber + ': unsafe parenthesized .Count; wrap with @(...): ' + $node.Extent.Text)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ('STRICTMODE HAZARD CHECK FAILED: ' + $failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: StrictMode AST hazard scan' -ForegroundColor Green
exit 0
