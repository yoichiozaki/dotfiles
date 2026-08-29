<#
    Elevated launcher for modernize-dev-env.ps1.
    Captures a full transcript so the run can be reviewed afterwards.
    Started via:  Start-Process pwsh -Verb RunAs -ArgumentList ... -File run-elevated.ps1
#>
[CmdletBinding()]
param([string[]]$Extra = @())

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$target     = Join-Path $here 'modernize-dev-env.ps1'
$transcript = Join-Path $here 'modernize-transcript.log'
$doneMarker = Join-Path $here 'modernize.done'

Remove-Item $doneMarker -ErrorAction SilentlyContinue
try { Start-Transcript -Path $transcript -Force | Out-Null } catch { }

try {
    & $target @Extra
    $code = 0
}
catch {
    Write-Host "UNHANDLED: $($_.Exception.Message)" -ForegroundColor Red
    $code = 1
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    "exit=$code finished=$(Get-Date -Format o)" | Set-Content -LiteralPath $doneMarker
}

Write-Host ''
Write-Host '  Finished. This window closes in 20 seconds.' -ForegroundColor Cyan
Start-Sleep -Seconds 20
