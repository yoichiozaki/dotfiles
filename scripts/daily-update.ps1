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
      * choosenim / zvm / moonup toolchains are CHECKED, not auto-upgraded:
        a language version bump should be a deliberate act, so the script only
        reports when a newer version exists.
      * user PATH de-duplication (installers re-append their bin dir)

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
    [switch]$WhatIfOnly
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

# --------------------------------------- language toolchains: report only ---
# A language version bump can break a project, so surface it and let the user
# decide rather than moving the compiler under their feet.
Invoke-Step 'toolchain check' {
    if (Test-Tool choosenim) {
        $cur = (nim --version 2>$null | Select-Object -First 1) -replace '.*Version ([0-9.]+).*', '$1'
        Add-Result 'nim' 'INFO' "$cur (upgrade: choosenim update stable)"
    }
    if (Test-Tool zvm) {
        Add-Result 'zig' 'INFO' "$(zig version 2>$null) (upgrade: zvm i --zls <ver>)"
    }
    if (Test-Tool moonup) {
        Add-Result 'moonbit' 'INFO' 'upgrade: moonup update'
    }
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
