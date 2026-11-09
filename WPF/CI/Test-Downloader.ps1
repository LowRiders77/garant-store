# Unit gate for the streaming downloader: a local HTTP server drops the first
# connection half-way (as seen on Windows 10 in the field); the next attempt
# must resume with a Range request, keep the bytes already received and report
# bytes, total and speed through the progress file.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'GarantStore.Common.ps1')
. (Join-Path $project 'GarantStore.Winget.ps1')
. (Join-Path $project 'GarantStore.Deployment.ps1')
function Assert-Equal { param([string]$Name,[object]$Expected,[object]$Actual) if($Expected -cne $Actual){throw ($Name+': expected '+$Expected+', got '+$Actual)} }
function Start-Sleep { param([int]$Seconds,[int]$Milliseconds) }

Assert-Equal 'first speed sample' 100.0 (Get-GSDownloadSpeed -Previous 0 -Sample 100)
Assert-Equal 'smoothed speed' 130.0 (Get-GSDownloadSpeed -Previous 100 -Sample 200)

$work=Join-Path ([IO.Path]::GetTempPath()) ('gs-dl-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
if(-not $env:LOCALAPPDATA){$env:LOCALAPPDATA=$work}
$progressFile=Join-Path $work 'progress.json'
Initialize-GSContext -OutputFile (Join-Path $work 'out.log') -Action 'test' -OperationId 'TEST-DOWNLOADER' -ProgressFile $progressFile

$payload=New-Object byte[] (3MB)
(New-Object Random 7).NextBytes($payload)
$probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
$prefix='http://localhost:'+$port+'/'

$serverScript={
 param($Prefix,$Payload,$Log)
 $listener=New-Object Net.HttpListener
 $listener.Prefixes.Add($Prefix)
 $listener.Start()
 try{
  for($n=1;$n -le 6;$n++){
   $ctx=$listener.GetContext()
   $path=$ctx.Request.Url.AbsolutePath
   $range=[string]$ctx.Request.Headers['Range']
   [void]$Log.Add($path+'|'+$range)
   $response=$ctx.Response
   try{
    if($path -eq '/stop'){$response.StatusCode=200;$response.Close();break}
    $from=0
    if($path -eq '/resume' -and $range -match '^bytes=(\d+)-$'){$from=[int]$Matches[1]}
    $length=$Payload.Length-$from
    if($from -gt 0){$response.StatusCode=206;$response.AddHeader('Content-Range',('bytes '+$from+'-'+($Payload.Length-1)+'/'+$Payload.Length))}
    $response.ContentLength64=$length
    $response.SendChunked=$false
    $out=$response.OutputStream
    if($path -eq '/resume' -and $from -eq 0){
     # First connection: send half, then cut the connection.
     $out.Write($Payload,0,[int]($Payload.Length/2));$out.Flush();Start-Sleep -Milliseconds 100;$response.Abort();continue
    }
    $out.Write($Payload,$from,$length);$out.Close()
   }catch{try{$response.Abort()}catch{}}
  }
 }finally{$listener.Close()}
}
$log=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$ps=[PowerShell]::Create()
[void]$ps.AddScript($serverScript).AddArgument($prefix).AddArgument($payload).AddArgument($log)
$async=$ps.BeginInvoke()
[Threading.Thread]::Sleep(700)
try{
 $target=Join-Path $work 'resume.bin'
 Download-GSFileWithRetry -Uri ($prefix+'resume') -Destination $target -MinimumBytes 1024 -Attempts 3 -Label 'Resume test'
 $bytes=[IO.File]::ReadAllBytes($target)
 Assert-Equal 'resumed file length' $payload.Length $bytes.Length
 $same=$true;for($i=0;$i -lt $bytes.Length;$i+=4093){if($bytes[$i] -ne $payload[$i]){$same=$false;break}}
 Assert-Equal 'resumed file content' $true $same
 Assert-Equal 'no partial file left' $false (Test-Path -LiteralPath ($target+'.partial'))
 $requests=@($log.ToArray()|Where-Object{$_ -like '/resume|*'})
 if($requests.Count -lt 2){throw ('expected a resumed second request, got: '+($requests -join '; '))}
 if($requests[1] -notmatch '\|bytes=\d+-$'){throw ('second request did not resume with Range: '+$requests[1])}
 $p=Get-Content -LiteralPath $progressFile -Raw | ConvertFrom-Json
 Assert-Equal 'progress stage' 'Downloading' ([string]$p.Stage)
 Assert-Equal 'progress bytes' ([UInt64]$payload.Length) ([UInt64]$p.BytesDownloaded)
 Assert-Equal 'progress total' ([UInt64]$payload.Length) ([UInt64]$p.BytesTotal)
 Assert-Equal 'progress percent' 100 ([int]$p.Percent)

 $plain=Join-Path $work 'plain.bin'
 Download-GSFileWithRetry -Uri ($prefix+'plain') -Destination $plain -MinimumBytes 1024 -Label 'Plain'
 Assert-Equal 'plain length' $payload.Length ((Get-Item -LiteralPath $plain).Length)

 $small=Join-Path $work 'small.bin'
 $failed=$false
 try{Download-GSFileWithRetry -Uri ($prefix+'plain') -Destination $small -MinimumBytes (10MB) -Attempts 1 -Label 'Too small'}catch{$failed=($_.Exception.Message -match '^GSERR:NetworkFailure:')}
 Assert-Equal 'size guard' $true $failed
 Assert-Equal 'size guard leaves nothing' $false ((Test-Path -LiteralPath $small) -or (Test-Path -LiteralPath ($small+'.partial')))
}finally{
 try{$r=[Net.WebRequest]::Create($prefix+'stop');$r.Timeout=3000;$r.GetResponse().Close()}catch{}
 try{[void]$async.AsyncWaitHandle.WaitOne(5000)}catch{}
 $ps.Dispose()
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'Streaming downloader resume/progress checks passed.'
