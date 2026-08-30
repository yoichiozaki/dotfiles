<#
.SYNOPSIS
    Daily unattended update of the user-scope toolchain. No elevation required.

.DESCRIPTION
    Designed to run from Task Scheduler, so it never prompts and never fails the
    whole run because one tool is unhappy. Each step is isolated; failures are
    recorded and the run continues.

    ONLY user-scope things are touched. Machine-wide packages (anything that
    needs UAC) are deliberately left to scripts\modernize-dev-env.ps1, which you
    run by hand. That keeps this script silent and safe to automate.

    Covered:
      * winget user-scope packages (CLI tools)
      * rustup, fnm (Node LTS), uv, uv tools, npm globals, cargo tools
      * language toolchains: choosenim (Nim), zvm (Zig + matching zls),
        moonup (MoonBit)
      * user PATH de-duplication (installers re-append their bin dir)

.PARAMETER PinToolchains
    Do NOT upgrade Nim / Zig / MoonBit, only report when a newer version
    exists. Use this while a project needs a specific compiler version.

.PARAMETER Install
    Register the scheduled task (daily, at logon+delay, only when idle-ish).

.PARAMETER Uninstall
    Remove the scheduled task.

.PARAMETER WhatIfOnly
    Show what would run without changing anything.

.EXAMPLE
    .\daily-update.ps1 -Install     # set up automation
    .\daily-update.ps1              # run once, now
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$WhatIfOnly,
    [switch]$PinToolchains
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
    $OutputEncoding = [Text.UTF8Encoding]::new()
}
catch { }

$TaskName = 'dotfiles-daily-update'
$LogDir   = Join-Path $PSScriptRoot 'logs'
$LogFile  = Join-Path $LogDir ('daily-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))

$script:Results = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $color = switch -Wildcard ($Status) {
        'OK'      { 'Green' }
        'UPDATE*' { 'Green' }
        'FAIL*'   { 'Yellow' }
        default   { 'DarkGray' }
    }
    Write-Log ("  {0,-9} {1} {2}" -f $Status, $Name, $Detail) $color
    $script:Results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    if ($WhatIfOnly) { Add-Result $Name 'WHATIF' 'would run'; return }
    try { & $Body }
    catch { Add-Result $Name 'FAIL' $_.Exception.Message }
}

function Test-Tool { param([string]$n) [bool](Get-Command $n -CommandType Application -ErrorAction Ignore) }

# The scheduled task runs with -NoProfile, so the shell profile that normally
# activates fnm never executes and `node`/`npm` are invisible. Activate fnm for
# THIS process so Node actually gets updated during unattended runs.
function Enable-Fnm {
    if (-not (Test-Tool fnm)) { return }
    try { fnm env --shell power-shell | Out-String | Invoke-Expression } catch { }
}

# ============================================================ scheduled task =

if ($Install -or $Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  removed existing task '$TaskName'" -ForegroundColor DarkGray
    }
    if ($Uninstall) { Write-Host '  done.' -ForegroundColor Green; return }

    # pwsh is an MSIX package here, so the versioned payload path under
    # WindowsApps changes on every update. Prefer the stable app execution
    # alias. Get-Command can return BOTH, hence Select-Object -First 1.
    $alias = "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    if (Test-Path $alias) { $pwshPath = $alias }
    else {
        $pwshPath = @(Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
                      Select-Object -ExpandProperty Source)[0]
    }
    if (-not $pwshPath) { throw 'Could not locate pwsh.exe' }

    $action = New-ScheduledTaskAction -Execute $pwshPath `
        -Argument ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)

    # Daily at 12:30 plus a 5 min random spread, and a catch-up run 10 min after
    # logon so a machine that was off at 12:30 still gets updated.
    # -User is REQUIRED on the logon trigger: without it the task targets *any*
    # user, which needs admin rights and fails with "access denied".
    $daily = New-ScheduledTaskTrigger -Daily -At '12:30'
    $daily.RandomDelay = 'PT5M'
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $logon.Delay = 'PT10M'

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -MultipleInstances IgnoreNew

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger @($daily, $logon) -Settings $settings `
            -Description 'Updates user-scope dev tooling (winget, rustup, fnm, uv, npm, cargo).' `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host ''
        Write-Host "  Failed to register '$TaskName': $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ''
        exit 1
    }

    Write-Host ''
    Write-Host "  Registered '$TaskName'" -ForegroundColor Green
    Write-Host '    - daily 12:30 (+0-5 min jitter)' -ForegroundColor DarkGray
    Write-Host '    - and 10 min after logon if a run was missed' -ForegroundColor DarkGray
    Write-Host "    - logs: $LogDir" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Run now with:  Start-ScheduledTask -TaskName ' -NoNewline -ForegroundColor DarkGray
    Write-Host $TaskName -ForegroundColor DarkGray
    Write-Host ''
    return
}

# ===================================================================== run ===

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Write-Log ''
Write-Log ("=== daily update {0} ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) 'Cyan'

# ---------------------------------------------------------------- winget ----
# --scope user only: anything machine-wide needs UAC, which would make this
# task pop a prompt (or fail silently) during an unattended run.
Invoke-Step 'winget' {
    if (-not (Test-Tool winget)) { Add-Result 'winget' 'SKIP' 'not available'; return }
    $out  = winget upgrade --all --scope user --silent --disable-interactivity `
                --accept-package-agreements --accept-source-agreements --include-unknown 2>&1 | Out-String
    $code = $LASTEXITCODE
    # -1978335188 just means "some packages are pinned, upgrade them explicitly".
    # GitHub.Copilot is pinned ON PURPOSE (it self-updates and winget would
    # downgrade it), so this is the expected steady state, not a failure.
    if ($code -eq 0)               { Add-Result 'winget' 'OK' 'user-scope packages upgraded' }
    elseif ($code -eq -1978335189) { Add-Result 'winget' 'CURRENT' 'nothing to upgrade' }
    elseif ($code -eq -1978335188) { Add-Result 'winget' 'OK' 'upgraded (pinned packages skipped by design)' }
    else {
        $tail = ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        Add-Result 'winget' "FAIL($code)" $tail
    }
}

# ---------------------------------------------------------------- rustup ----
Invoke-Step 'rustup' {
    if (-not (Test-Tool rustup)) { Add-Result 'rustup' 'SKIP' 'not installed'; return }
    $before = (rustc --version 2>$null) -join ''
    rustup update stable 2>&1 | Out-Null
    $after = (rustc --version 2>$null) -join ''
    if ($after -ne $before) { Add-Result 'rustup' 'UPDATED' "-> $after" }
    else                    { Add-Result 'rustup' 'CURRENT' $after }
}

# ------------------------------------------------------------------ fnm ----
Invoke-Step 'fnm (Node LTS)' {
    if (-not (Test-Tool fnm)) { Add-Result 'fnm' 'SKIP' 'not installed'; return }
    Enable-Fnm
    $before = ((fnm current 2>$null) -join '').Trim()
    fnm install --lts 2>&1 | Out-Null
    # keep 'default' pointing at the newest LTS
    $lts = (fnm list 2>$null | Select-String 'lts-latest' | ForEach-Object {
                if ($_ -match '(v\d+\.\d+\.\d+)') { $Matches[1] }
            } | Select-Object -First 1)
    if ($lts) { fnm default $lts 2>&1 | Out-Null }
    Enable-Fnm   # re-activate so the new default is what npm below sees
    $after = ((fnm current 2>$null) -join '').Trim()
    if ($after -and $after -ne $before) { Add-Result 'fnm' 'UPDATED' "$before -> $after" }
    else                                { Add-Result 'fnm' 'CURRENT' $after }
}

# ------------------------------------------------------------------- uv ----
Invoke-Step 'uv' {
    if (-not (Test-Tool uv)) { Add-Result 'uv' 'SKIP' 'not installed'; return }
    $before = (uv --version 2>$null) -join ''
    uv self update 2>&1 | Out-Null
    $after = (uv --version 2>$null) -join ''
    if ($after -ne $before) { Add-Result 'uv' 'UPDATED' $after } else { Add-Result 'uv' 'CURRENT' $after }

    uv tool upgrade --all 2>&1 | Out-Null
    Add-Result 'uv tools' 'OK' 'upgraded'
}

# ------------------------------------------------------------------ npm ----
Invoke-Step 'npm globals' {
    Enable-Fnm
    if (-not (Test-Tool npm)) { Add-Result 'npm' 'SKIP' 'not installed'; return }
    npm update -g 2>&1 | Out-Null
    Add-Result 'npm globals' 'OK' ('updated on ' + ((node --version 2>$null) -join ''))
}

# ---------------------------------------------------------------- cargo ----
Invoke-Step 'cargo tools' {
    if (-not (Test-Tool cargo-binstall)) { Add-Result 'cargo tools' 'SKIP' 'cargo-binstall absent'; return }
    $crates = @(cargo install --list 2>$null |
                Where-Object { $_ -notmatch '^\s' -and $_.Trim() } |
                ForEach-Object { ($_ -split ' ')[0] } |
                Where-Object { $_ -ne 'cargo-binstall' } | Sort-Object -Unique)
    if (-not $crates) { Add-Result 'cargo tools' 'SKIP' 'none installed'; return }
    foreach ($c in $crates) { cargo binstall --no-confirm --force $c 2>&1 | Out-Null }
    Add-Result 'cargo tools' 'OK' ($crates -join ', ')
}

# ------------------------------------------------- language toolchains ------
# These are upgraded too, but each step keeps the OLD toolchain installed so a
# bad release can be rolled back (choosenim <ver> / zvm use <ver> / moonup
# default <ver>). Pass -PinToolchains to report only.

Invoke-Step 'nim (choosenim)' {
    if (-not (Test-Tool choosenim)) { Add-Result 'nim' 'SKIP' 'choosenim absent'; return }
    $before = ((nim --version 2>$null | Select-Object -First 1) -replace '.*Version ([0-9.]+).*', '$1').Trim()
    if ($PinToolchains) { Add-Result 'nim' 'PINNED' $before; return }

    $out = choosenim update stable 2>&1 | Out-String
    $after = ((nim --version 2>$null | Select-Object -First 1) -replace '.*Version ([0-9.]+).*', '$1').Trim()

    if ($after -ne $before) { Add-Result 'nim' 'UPDATED' "$before -> $after"; return }

    # choosenim ships its own unzip which cannot read current archives and dies
    # with "Attempted to read past end of file". Fall back to downloading the
    # release zip and expanding it into the toolchains dir ourselves.
    if ($out -match 'corrupted zip|read past end of file') {
        $want = ([regex]::Match($out, 'Nim (\d+\.\d+\.\d+)')).Groups[1].Value
        if (-not $want -or $want -eq $before) { Add-Result 'nim' 'CURRENT' $before; return }
        try {
            $zip  = Join-Path $env:TEMP "nim-$want`_x64.zip"
            $dest = Join-Path $HOME ".choosenim\toolchains\nim-$want"
            Invoke-WebRequest "https://nim-lang.org/download/nim-$want`_x64.zip" -OutFile $zip -UseBasicParsing
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
            Move-Item (Join-Path $env:TEMP "nim-$want") $dest -Force
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            choosenim $want 2>&1 | Out-Null
            $after = ((nim --version 2>$null | Select-Object -First 1) -replace '.*Version ([0-9.]+).*', '$1').Trim()
            if ($after -eq $want) { Add-Result 'nim' 'UPDATED' "$before -> $after (manual unzip)" }
            else                  { Add-Result 'nim' 'FAIL' "could not switch to $want" }
        }
        catch { Add-Result 'nim' 'FAIL' $_.Exception.Message }
    }
    else { Add-Result 'nim' 'CURRENT' $before }
}

Invoke-Step 'zig (zvm)' {
    if (-not (Test-Tool zvm)) { Add-Result 'zig' 'SKIP' 'zvm absent'; return }
    $before = ((zig version 2>$null) -join '').Trim()
    if ($PinToolchains) { Add-Result 'zig' 'PINNED' $before; return }

    # zvm has no "upgrade" verb, so pick the newest tagged release ourselves.
    # ls-remote is descending and includes a `master` dev line, hence the
    # strict x.y.z filter.
    $latest = zvm ls-remote 2>$null |
              ForEach-Object { ($_ -split '\s+')[0] } |
              Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
              Sort-Object { [version]$_ } -Descending |
              Select-Object -First 1

    if (-not $latest)          { Add-Result 'zig' 'FAIL' 'could not read remote versions'; return }
    if ($latest -eq $before)   { Add-Result 'zig' 'CURRENT' $before; return }

    # --zls keeps the language server on the same version as the compiler,
    # which zls requires.
    zvm i --zls $latest 2>&1 | Out-Null
    zvm use $latest 2>&1 | Out-Null
    $after = ((zig version 2>$null) -join '').Trim()
    if ($after -eq $latest) { Add-Result 'zig' 'UPDATED' "$before -> $after (zls matched)" }
    else                    { Add-Result 'zig' 'FAIL' "wanted $latest, got '$after'" }
}

Invoke-Step 'moonbit (moonup)' {
    if (-not (Test-Tool moonup)) { Add-Result 'moonbit' 'SKIP' 'moonup absent'; return }
    $before = ((moon version 2>$null | Select-Object -First 1) -join '').Trim()
    if ($PinToolchains) { Add-Result 'moonbit' 'PINNED' $before; return }

    moonup update 2>&1 | Out-Null
    $after = ((moon version 2>$null | Select-Object -First 1) -join '').Trim()
    if ($after -ne $before) { Add-Result 'moonbit' 'UPDATED' "-> $after" }
    else                    { Add-Result 'moonbit' 'CURRENT' $after }
}

# -------------------------------------------------------------- user PATH ---
Invoke-Step 'user PATH' {
    $raw  = [Environment]::GetEnvironmentVariable('Path', 'User')
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $kept = @()
    foreach ($e in ($raw -split ';')) {
        $t = $e.Trim(); if (-not $t) { continue }
        if ($seen.Add(([Environment]::ExpandEnvironmentVariables($t).TrimEnd('\')))) { $kept += $t }
    }
    $new = $kept -join ';'
    $before = @($raw -split ';' | Where-Object { $_.Trim() }).Count
    if ($new -eq $raw) { Add-Result 'user PATH' 'CURRENT' "$before entries" }
    else {
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'user-path.backup.txt') -Value $raw -NoNewline -Encoding utf8
        [Environment]::SetEnvironmentVariable('Path', $new, 'User')
        Add-Result 'user PATH' 'UPDATED' "$before -> $($kept.Count) entries"
    }
}

# ------------------------------------------------- refresh repo manifests ---
Invoke-Step 'manifests' {
    $exp = Join-Path (Split-Path $PSScriptRoot) 'packages\export.ps1'
    if (-not (Test-Path $exp)) { Add-Result 'manifests' 'SKIP' 'export.ps1 missing'; return }
    & $exp *>&1 | Out-Null
    Add-Result 'manifests' 'OK' 'packages/ refreshed'
}

# ----------------------------------------------------------------- prune ----
Get-ChildItem $LogDir -Filter 'daily-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 |
    Remove-Item -Force -ErrorAction SilentlyContinue

# --------------------------------------------------------------- summary ----
$changed = @($script:Results | Where-Object { $_.Status -like 'UPDATE*' })
$failed  = @($script:Results | Where-Object { $_.Status -like 'FAIL*' })
Write-Log ("--- {0} changed, {1} failed ---" -f $changed.Count, $failed.Count) 'Cyan'
if ($failed) { foreach ($f in $failed) { Write-Log ("    ! {0}: {1}" -f $f.Name, $f.Detail) 'Yellow' } }
