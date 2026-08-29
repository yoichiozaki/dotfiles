<#
.SYNOPSIS
    Regenerates the package manifests in this folder from the current machine.

.DESCRIPTION
    Run this after installing or removing tooling so the dotfiles repo reflects
    reality. The output is committed, so `git diff` shows exactly what changed
    on the machine.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host '  Exporting winget packages...' -ForegroundColor Cyan
# NOTE: do NOT pass `--include-versions:$false` -- that is PowerShell switch
# syntax, not winget syntax, and makes the whole command a no-op. Versions are
# omitted by default, which is what we want so restores pick up the latest.
winget export --output (Join-Path $here 'winget.json') --accept-source-agreements 2>&1 |
    Where-Object { $_ -notmatch 'ソースからも利用できません|available from any source' } |
    Out-Null

Write-Host '  Exporting PowerShell modules...' -ForegroundColor Cyan
Get-InstalledModule -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { '{0}' -f $_.Name } |
    Set-Content -LiteralPath (Join-Path $here 'psmodules.txt') -Encoding utf8NoBOM

Write-Host '  Exporting npm globals...' -ForegroundColor Cyan
$npm = @()
try {
    $json = npm ls -g --depth=0 --json 2>$null | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains 'dependencies') {
        $npm = $json.dependencies.PSObject.Properties.Name | Sort-Object
    }
}
catch { }
$npm | Set-Content -LiteralPath (Join-Path $here 'npm-global.txt') -Encoding utf8NoBOM

Write-Host '  Exporting uv-managed Python versions...' -ForegroundColor Cyan
$py = @()
try { $py = uv python list --only-installed 2>$null } catch { }
$py | Set-Content -LiteralPath (Join-Path $here 'uv-python.txt') -Encoding utf8NoBOM

Write-Host '  Exporting uv tools...' -ForegroundColor Cyan
$uvt = @()
try { $uvt = uv tool list 2>$null | Where-Object { $_ -notmatch '^\s*-' -and $_.Trim() } } catch { }
$uvt | Set-Content -LiteralPath (Join-Path $here 'uv-tools.txt') -Encoding utf8NoBOM

Write-Host '  Exporting cargo-installed tools...' -ForegroundColor Cyan
$crates = @()
try {
    # `cargo install --list` prints "name vX.Y:" then indented binaries
    $crates = cargo install --list 2>$null |
              Where-Object { $_ -notmatch '^\s' -and $_.Trim() } |
              ForEach-Object { ($_ -split ' ')[0] } | Sort-Object -Unique
} catch { }
$crates | Set-Content -LiteralPath (Join-Path $here 'cargo-tools.txt') -Encoding utf8NoBOM

Write-Host '  Exporting language toolchain versions...' -ForegroundColor Cyan
$tc = @()
foreach ($t in @(
    @{ n = 'rustup'; c = { rustup show active-toolchain } }
    @{ n = 'fnm';    c = { fnm current } }
    @{ n = 'nim';    c = { (nim --version | Select-Object -First 1) } }
    @{ n = 'zig';    c = { zig version } }
    @{ n = 'moon';   c = { (moon version | Select-Object -First 1) } }
    @{ n = 'go';     c = { go version } }
    @{ n = 'dotnet'; c = { dotnet --version } }
    @{ n = 'python'; c = { python --version } }
)) {
    try { $v = (& $t.c 2>$null) -join ' '; if ($v) { $tc += "{0,-8} {1}" -f $t.n, $v.Trim() } } catch { }
}
$tc | Set-Content -LiteralPath (Join-Path $here 'toolchains.txt') -Encoding utf8NoBOM

Write-Host ''
Get-ChildItem $here -File -Filter '*.txt' | ForEach-Object {
    # @() so a 0- or 1-line file still exposes .Count
    "   {0,-20} {1} lines" -f $_.Name, @(Get-Content $_.FullName -ErrorAction SilentlyContinue).Count
}
Get-ChildItem $here -File -Filter '*.json' | ForEach-Object { "   {0,-20} {1} bytes" -f $_.Name, $_.Length }
Write-Host ''
