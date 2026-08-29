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
winget export --output (Join-Path $here 'winget.json') `
    --accept-source-agreements --include-versions:$false 2>&1 | Out-Null

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

Write-Host ''
Get-ChildItem $here -File -Filter '*.txt' | ForEach-Object { "   {0,-20} {1} lines" -f $_.Name, (Get-Content $_.FullName).Count }
Get-ChildItem $here -File -Filter '*.json' | ForEach-Object { "   {0,-20} {1} bytes" -f $_.Name, $_.Length }
Write-Host ''
