<#
.SYNOPSIS
    Restores tooling on a fresh machine from the manifests in this folder.

.DESCRIPTION
    Safe to re-run: every installer skips packages that are already present.

    Order matters -- winget first (it provides node/npm), then npm globals.

.PARAMETER SkipWinget
    Don't run `winget import` (useful when you only want the npm/PS modules).

.EXAMPLE
    .\restore.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipWinget
)

Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($s, $m, $c = 'Gray') { Write-Host ("   {0,-9} {1}" -f $s, $m) -ForegroundColor $c }

# ------------------------------------------------------------------ winget --
if (-not $SkipWinget) {
    $manifest = Join-Path $here 'winget.json'
    if (Test-Path $manifest) {
        Write-Host ''
        Write-Host '  winget import' -ForegroundColor Cyan
        Write-Host '  NOTE: run elevated -- most packages are machine-scope MSIs.' -ForegroundColor DarkGray
        # --ignore-unavailable: manifests drift, one delisted package must not abort the run
        winget import --import-file $manifest `
            --accept-package-agreements --accept-source-agreements `
            --ignore-versions --ignore-unavailable
        Say 'DONE' "winget import (exit=$LASTEXITCODE)" 'Green'
    }
    else { Say 'SKIP' 'winget.json not found' 'Yellow' }
}

# --------------------------------------------------------- PowerShell mods --
$mods = Join-Path $here 'psmodules.txt'
if (Test-Path $mods) {
    Write-Host ''
    Write-Host '  PowerShell modules' -ForegroundColor Cyan
    foreach ($m in (Get-Content $mods | Where-Object { $_.Trim() })) {
        if (Get-Module $m -ListAvailable) { Say 'ALREADY' $m 'DarkGray'; continue }
        try {
            Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Say 'OK' $m 'Green'
        }
        catch { Say 'FAIL' "$m : $($_.Exception.Message)" 'Yellow' }
    }
}

# ------------------------------------------------------------ npm globals --
$npm = Join-Path $here 'npm-global.txt'
if ((Test-Path $npm) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  npm global packages' -ForegroundColor Cyan
    $want = Get-Content $npm | Where-Object { $_.Trim() -and $_ -ne 'npm' }
    if ($want) {
        npm install -g @want
        Say 'DONE' "npm install -g (exit=$LASTEXITCODE)" 'Green'
    }
}

# ------------------------------------------------------------------- uv ----
$uvPy = Join-Path $here 'uv-python.txt'
if ((Test-Path $uvPy) -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  uv-managed Python versions (see uv-python.txt)' -ForegroundColor Cyan
    Say 'INFO' 'install with:  uv python install <version>' 'DarkGray'
}

Write-Host ''
Write-Host '  Then run ..\install.ps1 to link the config files.' -ForegroundColor DarkGray
Write-Host ''
