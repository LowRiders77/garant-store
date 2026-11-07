# Unit gate for the incremental operation-log reader in GarantStore.Next.ps1.
# The function is extracted from the UI script by AST, so the window is not opened.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'GarantStore.Next.ps1'),[ref]$tokens,[ref]$errors)
$definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-GSOperationLogDelta'},$true)
if($null -eq $definition){throw 'Read-GSOperationLogDelta is missing from the UI script'}
. ([scriptblock]::Create($definition.Extent.Text))

$script:Log=New-Object psobject -Property @{Text='';Scrolls=0}
$script:Log|Add-Member -MemberType ScriptMethod -Name AppendText -Value {param($t)$this.Text+=$t}
$script:Log|Add-Member -MemberType ScriptMethod -Name Clear -Value {$this.Text=''}
$script:Log|Add-Member -MemberType ScriptMethod -Name ScrollToEnd -Value {$this.Scrolls++}
$Log=$script:Log

$path=Join-Path ([IO.Path]::GetTempPath()) ('gs-log-tail-'+[guid]::NewGuid().ToString('N')+'.log')
try{
 $op=[pscustomobject]@{Out=$path;LogOffset=[long]0;LogDecoder=(New-Object Text.UTF8Encoding($false)).GetDecoder()}
 Read-GSOperationLogDelta $op
 if($Log.Text -ne ''){throw 'Missing log file produced text'}

 $utf8=New-Object Text.UTF8Encoding($false)
 $first=$utf8.GetBytes("Поиск: Telegram`r`n")
 # Split the next Cyrillic line in the middle of a two-byte character.
 $second=$utf8.GetBytes("Установка завершена`r`n")
 [IO.File]::WriteAllBytes($path,$first+$second[0..2])
 Read-GSOperationLogDelta $op
 $stream=New-Object IO.FileStream($path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$stream.Write($second,3,$second.Length-3)}finally{$stream.Dispose()}
 Read-GSOperationLogDelta $op
 if($Log.Text -ne "Поиск: Telegram`r`nУстановка завершена`r`n"){throw ('Incremental read corrupted text: '+$Log.Text)}
 if($op.LogOffset -ne ($first.Length+$second.Length)){throw 'Log offset does not match bytes consumed'}

 # No new bytes: nothing is appended or re-rendered.
 $scrolls=$Log.Scrolls
 Read-GSOperationLogDelta $op
 if($Log.Scrolls -ne $scrolls){throw 'An unchanged log was re-rendered'}

 # A truncated (new) file restarts from the beginning.
 [IO.File]::WriteAllBytes($path,$utf8.GetBytes("new`r`n"))
 Read-GSOperationLogDelta $op
 if($Log.Text -ne "new`r`n"){throw 'A truncated log was not re-read from the start'}

 # The view is capped.
 $big=New-Object string('x',450000)
 [IO.File]::AppendAllText($path,$big,$utf8)
 Read-GSOperationLogDelta $op
 if($Log.Text.Length -gt 400000){throw 'Log view exceeded its size cap'}

 Write-Host 'UI log tail gate passed: incremental reads, split UTF-8 characters, idle ticks, truncation, size cap.'
}finally{
 Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
