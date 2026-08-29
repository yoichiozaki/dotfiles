#requires -Version 7.0
# =============================================================================
#  PowerShell profile
#
#  Design notes:
#   * Every integration is GUARDED, so a missing/removed tool degrades
#     gracefully instead of breaking shell startup.
#   * Tool lookups are done in ONE batched Get-Command call (a per-tool call
#     costs ~14 ms of PATH scanning each).
#   * `gh` completion is cached to disk and only regenerated when gh.exe
#     changes, instead of spawning gh on every startup.
#   * Built-in `ls` / `cat` / `cd` are deliberately NOT overridden -- clobbering
#     them breaks scripts that expect PowerShell objects.
#
#  Previous profile backed up at: ~\.copilot\maintenance\
# =============================================================================

Set-StrictMode -Off

# Batched capability probe -------------------------------------------------
# -ErrorAction Ignore (not SilentlyContinue): SilentlyContinue still appends to
# $Error, so one missing tool would leave every shell starting "with errors".
$__tools = @{}
foreach ($c in (Get-Command oh-my-posh, zoxide, fzf, fd, eza, bat, lazygit, gh, delta, fnm, uv, atuin, dust, duf, btm `
                -CommandType Application -ErrorAction Ignore)) {
    if (-not $__tools.ContainsKey($c.Name)) { $__tools[$c.Name] = $c.Source }
}
function script:Has { param([string]$n) $__tools.ContainsKey("$n.exe") -or $__tools.ContainsKey($n) }

$__mods = @{}
foreach ($m in (Get-Module PSFzf, CompletionPredictor -ListAvailable -ErrorAction Ignore)) {
    $__mods[$m.Name] = $true
}

# Prompt -------------------------------------------------------------------
if (Has oh-my-posh) {
    $ompTheme = "$HOME\.config\oh-my-posh\night-owl-ccusage.omp.json"
    if (Test-Path $ompTheme) { oh-my-posh init pwsh --config $ompTheme | Invoke-Expression }
    else                     { oh-my-posh init pwsh | Invoke-Expression }
}

# PSReadLine ---------------------------------------------------------------
if (Get-Module PSReadLine) {
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Predictive IntelliSense (PSReadLine 2.2+). Only when attached to a real
    # terminal -- enabling it on a redirected/non-VT host throws, which would
    # spam errors in every `pwsh -Command ...` invocation.
    if (-not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal `
        -and (Get-Module PSReadLine).Version -ge [version]'2.2.0') {
        try {
            if ($__mods['CompletionPredictor']) {
                Import-Module CompletionPredictor -ErrorAction Stop
                Set-PSReadLineOption -PredictionSource HistoryAndPlugin
            }
            else { Set-PSReadLineOption -PredictionSource History }
            Set-PSReadLineOption -PredictionViewStyle ListView
        }
        catch { Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue }
    }
}

# zoxide  ->  z / zi -------------------------------------------------------
if (Has zoxide) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }

# fzf  ->  Ctrl+t files / Alt+c dir --------------------------------------
# Ctrl+r is deliberately NOT bound here when atuin is present: atuin owns
# history search (it is context-aware and syncable), fzf owns file/dir picking.
if ((Has fzf) -and $__mods['PSFzf']) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    if (Has atuin) { Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' }
    else           { Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' }
    if (Has fd) {
        $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
        $env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
        $env:FZF_ALT_C_COMMAND   = 'fd --type d --hidden --follow --exclude .git'
    }
    $env:FZF_DEFAULT_OPTS = '--height 45% --layout=reverse --border --info=inline'
}

# atuin  ->  Ctrl+r shell history ----------------------------------------
# Only in a real terminal: atuin installs PSReadLine key handlers.
if ((Has atuin) -and -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal) {
    try { atuin init powershell | Out-String | Invoke-Expression } catch { }
}

# Node version management (fnm) ------------------------------------------
# `fnm env` prepends its multishell dir to $env:Path for THIS session, which is
# how it wins over the machine-wide C:\Program Files\nodejs (machine PATH is
# searched before user PATH, so a user-PATH shim alone would be shadowed).
# --use-on-cd auto-switches when a directory has .nvmrc / .node-version.
if (Has fnm) {
    fnm env --use-on-cd --shell power-shell | Out-String | Invoke-Expression
}

# Listings / pager ---------------------------------------------------------
# NOTE: `$PWD` is passed explicitly rather than relying on the implicit "."
# for two reasons:
#   1. PowerShell does NOT keep the .NET process CWD in sync with Set-Location,
#      so a native exe can otherwise list the wrong directory.
#   2. eza with no path argument emits nothing when stdout is redirected
#      (e.g. `ll | Select-String foo`).
if (Has eza) {
    function Invoke-Eza {
        param([string[]]$Opts, [string[]]$Rest)
        if ($Rest | Where-Object { $_ -notlike '-*' }) { eza @Opts @Rest }
        else { eza @Opts @Rest "$PWD" }
    }
    function ll { Invoke-Eza @('--icons','--group-directories-first','--long','--git') $args }
    function la { Invoke-Eza @('--icons','--group-directories-first','--long','--git','--all') $args }
    function lt { Invoke-Eza @('--icons','--tree','--level=2','--group-directories-first') $args }
}
if (Has bat) {
    $env:BAT_THEME = 'Nord'
    function b     { bat @args }
    function bhelp { param([string]$Cmd) & $Cmd --help 2>&1 | bat -pl help }
}
if (Has lazygit) { function lg { lazygit @args } }

# Unix-style helpers that simply do not exist on Windows, so nothing is
# clobbered by defining them (unlike ls / cat / ps, which are left alone).
if (Has dust) { function du { dust @args } }
if (Has duf)  { function df { duf  @args } }
if (Has btm)  { function top { btm @args } }

# gh completion (cached; regenerated only when gh.exe changes) -------------
if (Has gh) {
    $ghSrc   = $__tools['gh.exe']
    $ghCache = "$HOME\.config\powershell\gh-completion.ps1"
    try {
        $needs = -not (Test-Path $ghCache) -or
                 (Get-Item $ghSrc).LastWriteTimeUtc -gt (Get-Item $ghCache).LastWriteTimeUtc
        if ($needs) {
            New-Item -ItemType Directory -Force -Path (Split-Path $ghCache) | Out-Null
            gh completion -s powershell | Set-Content -LiteralPath $ghCache -Encoding utf8
        }
        . $ghCache
    }
    catch { }
}

Remove-Variable __tools, __mods -ErrorAction SilentlyContinue
Remove-Item Function:\Has -ErrorAction SilentlyContinue
