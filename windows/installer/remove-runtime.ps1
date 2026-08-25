[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$CurrentScriptPath
)

$ErrorActionPreference = 'Stop'

Get-Process -Name 'DeepSeekHarnessGlass' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $InstallRoot) {
    Get-ChildItem -LiteralPath $InstallRoot -Force |
        Where-Object { $_.FullName -ne $CurrentScriptPath } |
        Remove-Item -Recurse -Force
}
