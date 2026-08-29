<#
.SYNOPSIS
    Links this dotfiles repository into place. Idempotent.

.DESCRIPTION
    Creates a symbolic link for every tracked config file so that editing the
    file in its normal location edits the repo, and `git status` shows drift.

    Existing real files are backed up to .backup/<timestamp>/ before being
    replaced -- nothing is destroyed.

    Symlinks on Windows require EITHER Developer Mode (Settings -> System ->
    For developers) OR an elevated shell. The script checks up front and tells
    you which is missing instead of failing halfway through.

.PARAMETER WhatIfOnly
    Show what would change without touching anything.

.PARAMETER Force
    Replace targets even if they already point somewhere else.

.EXAMPLE
    .\install.ps1 -WhatIfOnly
    .\install.ps1
#>
[CmdletBinding()]
param(
    [switch]$WhatIfOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Join-Path $Root ".backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Write-Head($t) {
    Write-Host ''
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('  ' + '-' * 66) -ForegroundColor DarkGray
}
function Say($status, $msg, $color = 'Gray') {
    Write-Host ("   {0,-9} {1}" -f $status, $msg) -ForegroundColor $color
}

# --------------------------------------------------------------- capability --

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CanSymlink {
    $probe = Join-Path $env:TEMP "dotfiles-symprobe-$(Get-Random)"
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Target $env:TEMP -ErrorAction Stop | Out-Null
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch { return $false }
}

# -------------------------------------------------------------------- links --

# $PROFILE is used rather than a hard-coded path because Documents may be
# redirected to OneDrive (as it is on this machine).
$Links = @(
    @{ Src = 'config\powershell\Microsoft.PowerShell_profile.ps1'; Dst = $PROFILE.CurrentUserCurrentHost }
    @{ Src = 'config\git\gitconfig';                               Dst = Join-Path $HOME '.gitconfig' }
    @{ Src = 'config\copilot\settings.json';                       Dst = Join-Path $HOME '.copilot\settings.json' }
    @{ Src = 'config\copilot\copilot-instructions.md';             Dst = Join-Path $HOME '.copilot\copilot-instructions.md' }
    @{ Src = 'config\oh-my-posh\night-owl-ccusage.omp.json';       Dst = Join-Path $HOME '.config\oh-my-posh\night-owl-ccusage.omp.json' }
    @{ Src = 'config\nushell\config.nu';                           Dst = Join-Path $env:APPDATA 'nushell\config.nu' }
    @{ Src = 'config\nushell\env.nu';                              Dst = Join-Path $env:APPDATA 'nushell\env.nu' }
)

# ------------------------------------------------------------ preconditions --

Write-Head 'Preconditions'

if (-not (Test-CanSymlink)) {
    Say 'BLOCKED' 'Cannot create symbolic links.' 'Red'
    Write-Host ''
    Write-Host '   Enable Developer Mode:' -ForegroundColor Yellow
    Write-Host '     Settings -> System -> For developers -> Developer Mode = On' -ForegroundColor Yellow
    Write-Host '   ...or re-run this script from an elevated PowerShell.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
Say 'OK' ('symlinks available ({0})' -f $(if (Test-Elevated) { 'elevated' } else { 'Developer Mode' })) 'Green'

# ------------------------------------------- preserve git identity (once) --

Write-Head 'Git identity'

$localGit = Join-Path $HOME '.gitconfig.local'
if (Test-Path $localGit) {
    Say 'ALREADY' '~/.gitconfig.local exists' 'DarkGray'
}
else {
    # Read identity from the CURRENT config before it is replaced by the symlink.
    $name  = (& git config --global user.name)  2>$null
    $email = (& git config --global user.email) 2>$null

    if ($WhatIfOnly) {
        Say 'WHATIF' "would create ~/.gitconfig.local (name='$name')" 'Yellow'
    }
    else {
        $body = @(
            '# Machine-local git settings. NOT tracked by dotfiles.',
            '',
            '[user]'
        )
        if ($name)  { $body += "`tname = $name" }
        if ($email) { $body += "`temail = $email" }
        Set-Content -LiteralPath $localGit -Value ($body -join "`n") -Encoding utf8NoBOM
        Say 'OK' "created ~/.gitconfig.local (preserved name='$name')" 'Green'
    }
}

# -------------------------------------------------------------- link them --

Write-Head 'Linking'

$made = 0; $kept = 0; $backed = 0
foreach ($l in $Links) {
    $src = Join-Path $Root $l.Src
    $dst = $l.Dst
    $rel = $l.Src

    if (-not (Test-Path -LiteralPath $src)) { Say 'MISSING' "$rel (not in repo)" 'Yellow'; continue }

    $existing = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue

    if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
        $target = $existing.Target | Select-Object -First 1
        if ($target -eq $src) { Say 'OK' "$rel (already linked)" 'DarkGray'; $kept++; continue }
        if (-not $Force) { Say 'CONFLICT' "$dst -> $target (use -Force)" 'Yellow'; continue }
    }

    if ($WhatIfOnly) { Say 'WHATIF' "$rel -> $dst" 'Yellow'; continue }

    # back up a real file before replacing it
    if ($existing -and $existing.LinkType -ne 'SymbolicLink') {
        $bk = Join-Path $BackupDir $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
        Copy-Item -LiteralPath $dst -Destination $bk -Force
        $backed++
    }
    if ($existing) { Remove-Item -LiteralPath $dst -Force -Recurse }

    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
    Say 'LINKED' "$rel -> $dst" 'Green'
    $made++
}

# ---------------------------------------------------------------- summary --

Write-Head 'Summary'
Say 'linked'  $made
Say 'kept'    $kept
if ($backed) { Say 'backed up' "$backed file(s) -> $BackupDir" 'Green' }

if (-not $WhatIfOnly) {
    Write-Host ''
    Write-Host '   Open a NEW terminal to pick up the linked profile.' -ForegroundColor DarkGray
    Write-Host "   Restore packages with: .\packages\restore.ps1" -ForegroundColor DarkGray
}
Write-Host ''
