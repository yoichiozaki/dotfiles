<#
.SYNOPSIS
    Modernizes the developer toolchain on this machine. Requires an elevated PowerShell.

.DESCRIPTION
    Idempotent: safe to re-run. Every step checks current state before acting and
    continues on failure so one bad package cannot abort the run.

    Default run (no switches) covers the developer toolchain only:
      * winget upgrades for dev runtimes / CLI tools
      * Rust: migrate from the winget MSI to rustup (proper toolchain manager)
      * .NET 10 LTS SDK   (current .NET 6 is END OF LIFE)
      * Microsoft OpenJDK 21 LTS (current JDK 11 is old)
      * npm self-update

    Opt-in switches cover things that are large, breaking, or non-developer.

.PARAMETER IncludeEditors
    Also upgrade Cursor, Antigravity, Docker Desktop and VS Build Tools.
    These are multi-GB downloads and Cursor jumps 0.47 -> 3.x.

.PARAMETER IncludeApps
    Also upgrade non-developer apps (Zoom, Teams, Outlook, Obsidian, Discord,
    Logitech Options, Unity Hub, NVIDIA PhysX, Claude desktop).

.PARAMETER IncludeOhMyPosh
    Also upgrade oh-my-posh 21 -> 30. This is a MAJOR version bump with breaking
    config changes and may break your shell prompt until the theme is migrated.

.PARAMETER RemoveDuplicateDotnet6Sdks
    Remove the redundant .NET 6 SDKs 6.0.202 and 6.0.203, keeping 6.0.428.
    Off by default because old projects may pin an exact SDK via global.json.

.PARAMETER WhatIfOnly
    Print what would happen without changing anything.

.EXAMPLE
    # Recommended first run
    .\modernize-dev-env.ps1

.EXAMPLE
    # Everything, including breaking prompt upgrade
    .\modernize-dev-env.ps1 -IncludeEditors -IncludeApps -IncludeOhMyPosh
#>
[CmdletBinding()]
param(
    [switch]$IncludeEditors,
    [switch]$IncludeApps,
    [switch]$IncludeOhMyPosh,
    [switch]$RemoveDuplicateDotnet6Sdks,
    [switch]$WhatIfOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# winget emits UTF-8; without this the log fills with mojibake on a CP932 console.
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
    $OutputEncoding = [Text.UTF8Encoding]::new()
}
catch { }

$script:Results = [System.Collections.Generic.List[object]]::new()
$script:LogFile = Join-Path $PSScriptRoot 'modernize.log'

function Write-Head($Text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Write-Step($Text) { Write-Host "  -> $Text" -ForegroundColor Gray }

function Add-Result($Name, $Status, $Detail = '') {
    $color = switch ($Status) {
        'OK'      { 'Green' }
        'SKIP'    { 'DarkGray' }
        'ALREADY' { 'DarkGray' }
        default   { 'Yellow' }
    }
    Write-Host ("     {0,-9} {1} {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
    $script:Results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
    "$(Get-Date -f 'HH:mm:ss')  $Status  $Name  $Detail" | Add-Content -Path $script:LogFile
}

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- winget ----

# winget exit codes (locale-independent; verified against winget on this machine)
$script:WG_UPDATE_NOT_APPLICABLE = -1978335189  # 0x8A15002B - no newer version available
$script:WG_NO_INSTALLED_PACKAGE  = -1978335212  # 0x8A150014 - nothing matches input criteria
$script:WG_INSTALL_FAILED        = -1978334974  # installer returned an error
$script:WG_TECH_MISMATCH         = -1978335090  # installer technology differs; needs uninstall first
$script:WG_USER_SCOPE_ELEVATED   = -1978335107  # user-scope package cannot be touched while elevated

# Windows Installer serialises MSI transactions machine-wide. Firing winget
# installs back-to-back makes later ones fail with 1618 / generic install
# errors, which is exactly what happened on the first run of this script.
function Wait-MsiIdle {
    param([int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        # Only the Global\_MSIExecute mutex is authoritative. An earlier version
        # also looked at msiexec processes, but the msiexec /V *service* runs
        # permanently, so that check reported "busy" forever.
        $busy = $false
        try {
            $mx = [System.Threading.Mutex]::OpenExisting('Global\_MSIExecute')
            $busy = -not $mx.WaitOne(0)
            if (-not $busy) { $mx.ReleaseMutex() }
            $mx.Dispose()
        }
        catch [System.Threading.WaitHandleCannotBeOpenedException] {
            $busy = $false          # mutex absent => no install in progress
        }
        catch {
            $busy = $true           # exists but not queryable => assume busy
        }

        if (-not $busy) { Start-Sleep -Milliseconds 500; return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Invoke-Winget {
    param([string]$Id, [string]$Label = $Id, [string[]]$Extra = @(), [int]$Retries = 2)

    if ($WhatIfOnly) { Add-Result $Label 'WHATIF' 'would upgrade'; return }

    $wgArgs = @(
        'upgrade', '--id', $Id, '--exact',
        '--silent', '--disable-interactivity',
        '--accept-package-agreements', '--accept-source-agreements',
        '--include-unknown'
    ) + $Extra

    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        if ($attempt -gt 0) {
            Write-Step "retry $attempt/$Retries for $Id (waiting for Windows Installer)"
            Start-Sleep -Seconds (5 * $attempt)
        }
        else { Write-Step "winget upgrade $Id" }

        # Best-effort: if the installer stays busy we still proceed, because
        # winget's own error is more informative than us guessing. Failing here
        # produced spurious "stayed busy" results for already-up-to-date packages.
        if (-not (Wait-MsiIdle)) { Write-Step 'Windows Installer still busy; proceeding anyway' }

        $out  = & winget @wgArgs 2>&1 | Out-String
        $code = $LASTEXITCODE

        switch ($code) {
            0 { Add-Result $Label 'OK'; return }
            $script:WG_NO_INSTALLED_PACKAGE  { Add-Result $Label 'SKIP' 'not installed'; return }
            $script:WG_UPDATE_NOT_APPLICABLE { Add-Result $Label 'ALREADY' 'up to date'; return }
            $script:WG_USER_SCOPE_ELEVATED   {
                Add-Result $Label 'SKIP' 'user-scope: re-run this package WITHOUT elevation'
                return
            }
            $script:WG_TECH_MISMATCH {
                # winget refuses an in-place upgrade when the installer type changed
                # and wants uninstall-then-install.
                #
                # DANGER: if the package being replaced is the PowerShell that is
                # RUNNING THIS SCRIPT, the uninstall deletes pwsh.exe and kills the
                # host mid-operation, leaving the machine with no PowerShell 7 at
                # all. (Learned the hard way.) Never do that to our own host.
                $isSelfHost = ($Id -eq 'Microsoft.PowerShell') -and
                              ($PSVersionTable.PSEdition -eq 'Core')
                if ($isSelfHost) {
                    Add-Result $Label 'SKIP' `
                        'needs uninstall+install, but that would delete the running pwsh. Run from Windows PowerShell: powershell -NoProfile -Command "winget install --id Microsoft.PowerShell --exact --silent"'
                    return
                }

                Write-Step "installer technology changed; uninstall+install $Id"
                if (-not (Wait-MsiIdle)) { Add-Result $Label 'FAIL' 'installer busy'; return }
                & winget uninstall --id $Id --exact --silent --disable-interactivity 2>&1 | Out-Null
                if (-not (Wait-MsiIdle)) { Add-Result $Label 'FAIL' 'installer busy'; return }
                & winget install --id $Id --exact --silent --disable-interactivity `
                    --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Add-Result $Label 'OK' 'reinstalled' }
                else { Add-Result $Label "FAIL($LASTEXITCODE)" 'reinstall failed' }
                return
            }
            default {
                if ($attempt -lt $Retries) { continue }   # transient installer error -> retry
                $tail = ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
                Add-Result $Label "FAIL($code)" $tail
                return
            }
        }
    }
}

function Install-Winget {
    param([string]$Id, [string]$Label = $Id, [string[]]$Extra = @(), [int]$Retries = 2)

    $listed = & winget list --id $Id --exact 2>&1 | Out-String
    if ($listed -match [regex]::Escape($Id)) { Add-Result $Label 'ALREADY' 'installed'; return }

    if ($WhatIfOnly) { Add-Result $Label 'WHATIF' 'would install'; return }

    $wgArgs = @(
        'install', '--id', $Id, '--exact',
        '--silent', '--disable-interactivity',
        '--accept-package-agreements', '--accept-source-agreements'
    ) + $Extra

    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        if ($attempt -gt 0) {
            Write-Step "retry $attempt/$Retries for $Id"
            Start-Sleep -Seconds (5 * $attempt)
        }
        else { Write-Step "winget install $Id" }

        if (-not (Wait-MsiIdle)) { Write-Step 'Windows Installer still busy; proceeding anyway' }

        $out  = & winget @wgArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($code -eq 0) { Add-Result $Label 'OK'; return }
        if ($code -eq $script:WG_UPDATE_NOT_APPLICABLE) { Add-Result $Label 'ALREADY' 'up to date'; return }
        if ($attempt -lt $Retries) { continue }

        $tail = ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        Add-Result $Label "FAIL($code)" $tail
        return
    }
}

# ------------------------------------------------------------------ main ----

if (-not (Test-Elevated)) {
    Write-Host ''
    Write-Host '  This script must run in an ELEVATED PowerShell.' -ForegroundColor Red
    Write-Host '  Right-click Windows Terminal / PowerShell -> "Run as administrator", then:' -ForegroundColor Red
    Write-Host ''
    Write-Host "      & '$PSCommandPath'" -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

"=== modernize-dev-env run $(Get-Date -f 'yyyy-MM-dd HH:mm:ss') ===" | Add-Content -Path $script:LogFile

Write-Head 'Protect the Copilot CLI from winget'

# The CLI self-updates; winget's manifest lags behind, so `winget upgrade --all`
# would DOWNGRADE it. A blocking pin makes that impossible, permanently.
if ($WhatIfOnly) { Add-Result 'pin GitHub.Copilot' 'WHATIF' 'would add blocking pin' }
else {
    $pins = & winget pin list 2>&1 | Out-String
    if ($pins -match 'GitHub\.Copilot') { Add-Result 'pin GitHub.Copilot' 'ALREADY' 'pinned' }
    else {
        & winget pin add --id GitHub.Copilot --exact --blocking --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Add-Result 'pin GitHub.Copilot' 'OK' 'blocking pin added' }
        else { Add-Result 'pin GitHub.Copilot' "FAIL($LASTEXITCODE)" 'use copilot /update instead' }
    }
}

Write-Head 'Developer runtimes and CLI tools'

# NOTE: GitHub.Copilot is deliberately EXCLUDED. winget's manifest lags behind
# the CLI's own self-updater, so `winget upgrade` would DOWNGRADE the CLI.
foreach ($p in @(
    @{ Id = 'Git.Git';                            Label = 'Git' }
    @{ Id = 'GitHub.cli';                         Label = 'GitHub CLI' }
    @{ Id = 'GoLang.Go';                          Label = 'Go' }
    @{ Id = 'Microsoft.PowerShell';               Label = 'PowerShell 7' }
    @{ Id = 'Microsoft.WSL';                      Label = 'WSL' }
    @{ Id = 'Nushell.Nushell';                    Label = 'Nushell' }
    @{ Id = 'DenoLand.Deno';                      Label = 'Deno' }
    @{ Id = 'Hugo.Hugo.Extended';                 Label = 'Hugo (Extended)' }
    @{ Id = 'Gyan.FFmpeg';                        Label = 'FFmpeg' }
    @{ Id = 'Microsoft.devtunnel';                Label = 'devtunnel' }
    @{ Id = 'Microsoft.Azure.FunctionsCoreTools'; Label = 'Azure Functions Core Tools' }
    @{ Id = 'Microsoft.VCRedist.2015+.x64';       Label = 'VC++ Redist x64' }
    @{ Id = 'Microsoft.VCRedist.2015+.x86';       Label = 'VC++ Redist x86' }
)) { Invoke-Winget -Id $p.Id -Label $p.Label }

# ------------------------------------------------- Git's own auto-updater ---

# Git for Windows installs a "Git for Windows Updater" scheduled task that runs
# `git update-git-for-windows --gui` daily as the LOGGED-IN user. Because it is
# not elevated it cannot write C:\Program Files\Git\etc\gitconfig, so it pops up
# an installer and then reports "could not set the system config" every single
# day. Git.Git is handled above with proper elevation instead, so silence it.
Write-Head "Git's own updater (daily unelevated nag)"

$gitTask = Get-ScheduledTask -TaskName 'Git for Windows Updater' -ErrorAction SilentlyContinue
if (-not $gitTask) { Add-Result 'Git updater task' 'SKIP' 'not present' }
elseif ($gitTask.State -eq 'Disabled') { Add-Result 'Git updater task' 'ALREADY' 'disabled' }
elseif ($WhatIfOnly) { Add-Result 'Git updater task' 'WHATIF' 'would disable' }
else {
    try {
        Disable-ScheduledTask -TaskName 'Git for Windows Updater' -ErrorAction Stop | Out-Null
        Add-Result 'Git updater task' 'OK' 'disabled; Git.Git now updates via winget above'
    }
    catch { Add-Result 'Git updater task' 'FAIL' $_.Exception.Message }
}

# ------------------------------------------------------------------ Rust ----

Write-Head 'Rust: winget MSI -> rustup'

$wingetRust = (& winget list --id Rustlang.Rust.MSVC --exact 2>&1 | Out-String) -match 'Rustlang\.Rust\.MSVC'
$haveRustup = [bool](Get-Command rustup -ErrorAction SilentlyContinue)

if ($haveRustup -and -not $wingetRust) {
    Write-Step 'rustup already manages this machine'
    if (-not $WhatIfOnly) { & rustup update stable 2>&1 | Out-Null }
    Add-Result 'rustup' 'OK' 'stable updated'
}
elseif ($WhatIfOnly) {
    Add-Result 'Rust -> rustup' 'WHATIF' 'would uninstall MSI + install rustup'
}
else {
    if ($wingetRust) {
        Write-Step 'Uninstalling winget Rust 1.79 (MSI)'
        Wait-MsiIdle | Out-Null
        & winget uninstall --id Rustlang.Rust.MSVC --exact --silent --disable-interactivity 2>&1 | Out-Null
        $uninstalled = ($LASTEXITCODE -eq 0)

        if (-not $uninstalled) {
            # winget sometimes refuses; fall back to the MSI product code from ARP.
            Write-Step 'winget uninstall failed; falling back to msiexec'
            $arp = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
                   ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                   Where-Object { $_.DisplayName -like 'Rust *MSVC*' }
            foreach ($p in $arp) {
                if ($p.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
                    Wait-MsiIdle | Out-Null
                    Start-Process msiexec -ArgumentList @('/x', $p.PSChildName, '/qn', '/norestart') -Wait
                    $uninstalled = $true
                }
            }
        }
        Add-Result 'Rust MSI removed' $(if ($uninstalled) { 'OK' } else { 'FAIL' })

        # The MSI leaves its bin dir on the MACHINE PATH, which would shadow
        # ~\.cargo\bin (machine PATH is searched before user PATH).
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $cleaned = ($machine -split ';' |
            Where-Object { $_.Trim() -and $_ -notmatch 'Rust stable MSVC' }) -join ';'
        if ($cleaned -ne $machine) {
            [Environment]::SetEnvironmentVariable('Path', $cleaned, 'Machine')
            Add-Result 'Machine PATH: drop stale Rust bin' 'OK'
        }
    }

    if (-not $haveRustup) {
        Write-Step 'Installing rustup'
        $init = Join-Path $env:TEMP 'rustup-init.exe'
        try {
            Invoke-WebRequest 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' `
                -OutFile $init -UseBasicParsing
            & $init -y --default-toolchain stable --profile default --no-modify-path 2>&1 | Out-Null
            $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath -notlike "*$cargoBin*") {
                [Environment]::SetEnvironmentVariable('Path', "$cargoBin;$userPath", 'User')
            }
            Add-Result 'rustup' 'OK' 'installed with stable toolchain'
        }
        catch { Add-Result 'rustup' 'FAIL' $_.Exception.Message }
        finally { Remove-Item $init -ErrorAction SilentlyContinue }
    }
    else {
        Write-Step 'rustup already present; updating stable toolchain'
        & rustup update stable 2>&1 | Out-Null
        Add-Result 'rustup' 'OK' 'stable updated'
    }
}

# ------------------------------------------------------- .NET and OpenJDK ----

Write-Head '.NET 10 LTS  (current .NET 6 is END OF LIFE)'
Install-Winget -Id 'Microsoft.DotNet.SDK.10' -Label '.NET 10 SDK'

if ($RemoveDuplicateDotnet6Sdks) {
    Write-Step 'Removing redundant .NET 6 SDKs (keeping 6.0.428)'
    foreach ($v in '6.0.202', '6.0.203') {
        $dir = "C:\Program Files\dotnet\sdk\$v"
        if (-not (Test-Path $dir)) { Add-Result ".NET SDK $v" 'SKIP' 'absent'; continue }
        if ($WhatIfOnly) { Add-Result ".NET SDK $v" 'WHATIF' 'would remove'; continue }
        try { Remove-Item $dir -Recurse -Force -ErrorAction Stop; Add-Result ".NET SDK $v" 'OK' 'removed' }
        catch { Add-Result ".NET SDK $v" 'FAIL' $_.Exception.Message }
    }
}
else {
    Add-Result '.NET 6 duplicate cleanup' 'SKIP' 'pass -RemoveDuplicateDotnet6Sdks to enable'
}

Write-Head 'Java: add OpenJDK 21 LTS  (current JDK 11 is old)'
Install-Winget -Id 'Microsoft.OpenJDK.21' -Label 'Microsoft OpenJDK 21'
Invoke-Winget  -Id 'Microsoft.OpenJDK.11' -Label 'Microsoft OpenJDK 11 (patch)'

# ------------------------------------------------------------------- npm ----

# Node is managed by fnm (per-user), not by winget, so npm does not exist in an
# elevated -NoProfile shell. npm is updated by scripts\daily-update.ps1, which
# activates fnm first. Skipping here keeps this script from dying at the very
# end after all the real work succeeded.
Write-Head 'npm self-update'
if ($WhatIfOnly) { Add-Result 'npm' 'WHATIF' 'would self-update' }
elseif (-not (Get-Command npm -CommandType Application -ErrorAction Ignore)) {
    Add-Result 'npm' 'SKIP' 'fnm-managed; handled by daily-update.ps1'
}
else {
    $before = (& npm --version 2>&1 | Select-Object -First 1)
    & npm install -g npm@latest 2>&1 | Out-Null
    $after = (& npm --version 2>&1 | Select-Object -First 1)
    if ($after -ne $before) { Add-Result 'npm' 'OK' "$before -> $after" }
    else { Add-Result 'npm' 'ALREADY' $after }
}

# --------------------------------------------------------- tidy user PATH ---

# Installers (the .NET SDK in particular) append their bin directory on every
# run, so duplicates creep back after each upgrade. De-duplicate, preserving
# first occurrence so precedence is unchanged. Entries that do not exist are
# KEPT: well-known dirs like ~\.dotnet\tools are created on demand.
Write-Head 'Tidy user PATH'

$rawPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$seenPath = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$keptPath = @()
foreach ($entry in ($rawPath -split ';')) {
    $trimmed = $entry.Trim()
    if (-not $trimmed) { continue }
    $norm = [Environment]::ExpandEnvironmentVariables($trimmed).TrimEnd('\')
    if ($seenPath.Add($norm)) { $keptPath += $trimmed }
}
$newPath = $keptPath -join ';'
$beforeCount = @($rawPath -split ';' | Where-Object { $_.Trim() }).Count

if ($newPath -eq $rawPath) {
    Add-Result 'user PATH' 'ALREADY' "$beforeCount entries, no duplicates"
}
elseif ($WhatIfOnly) {
    Add-Result 'user PATH' 'WHATIF' "would go $beforeCount -> $($keptPath.Count) entries"
}
else {
    $backup = Join-Path $PSScriptRoot 'user-path.backup.txt'
    Set-Content -LiteralPath $backup -Value $rawPath -NoNewline -Encoding utf8
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Add-Result 'user PATH' 'OK' "$beforeCount -> $($keptPath.Count) entries (backup: user-path.backup.txt)"
}

# -------------------------------------------------------------- optional ----

if ($IncludeOhMyPosh) {
    Write-Head 'oh-my-posh 21 -> 30  (BREAKING config changes)'
    Invoke-Winget -Id 'JanDeDobbeleer.OhMyPosh' -Label 'oh-my-posh'
    Write-Host '     Review your theme: https://ohmyposh.dev/docs/migrating' -ForegroundColor Yellow
}
else { Add-Result 'oh-my-posh' 'SKIP' 'major upgrade; pass -IncludeOhMyPosh' }

if ($IncludeEditors) {
    Write-Head 'Editors, Docker and Build Tools (large downloads)'
    foreach ($p in @(
        @{ Id = 'Anysphere.Cursor';                  Label = 'Cursor' }
        @{ Id = 'Google.AntigravityIDE';             Label = 'Antigravity IDE' }
        @{ Id = 'Docker.DockerDesktop';              Label = 'Docker Desktop' }
        @{ Id = 'Microsoft.VisualStudio.BuildTools'; Label = 'VS Build Tools' }
    )) { Invoke-Winget -Id $p.Id -Label $p.Label }
}
else { Add-Result 'editors/Docker/BuildTools' 'SKIP' 'pass -IncludeEditors' }

if ($IncludeApps) {
    Write-Head 'Non-developer applications'
    foreach ($p in @(
        @{ Id = 'Anthropic.Claude';    Label = 'Claude' }
        @{ Id = 'Obsidian.Obsidian';   Label = 'Obsidian' }
        @{ Id = 'Microsoft.Teams';     Label = 'Teams' }
        @{ Id = 'Microsoft.Outlook';   Label = 'Outlook' }
        @{ Id = 'Zoom.Zoom.EXE';       Label = 'Zoom' }
        @{ Id = 'Discord.Discord';     Label = 'Discord' }
        @{ Id = 'Logitech.Options';    Label = 'Logitech Options' }
        @{ Id = 'Unity.UnityHub';      Label = 'Unity Hub' }
        @{ Id = 'Nvidia.PhysX';        Label = 'NVIDIA PhysX' }
    )) { Invoke-Winget -Id $p.Id -Label $p.Label }
}
else { Add-Result 'desktop apps' 'SKIP' 'pass -IncludeApps' }

# --------------------------------------------------------------- summary ----

Write-Head 'Summary'
$script:Results | Group-Object Status | Sort-Object Name |
    ForEach-Object { Write-Host ("  {0,-10} {1}" -f $_.Name, $_.Count) }

$failed = $script:Results | Where-Object Status -like 'FAIL*'
if ($failed) {
    Write-Host ''
    Write-Host '  Failed steps:' -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "    - $($_.Name): $($_.Detail)" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host "  Log: $script:LogFile" -ForegroundColor DarkGray
Write-Host '  Open a NEW terminal so PATH changes take effect.' -ForegroundColor DarkGray
Write-Host ''
