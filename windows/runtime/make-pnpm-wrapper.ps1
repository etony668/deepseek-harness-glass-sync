[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

@'
@echo off
setlocal
set "ROOT=%~dp0.."
"%ROOT%\node\node.exe" "%ROOT%\pnpm\node_modules\pnpm\bin\pnpm.mjs" %*
'@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'pnpm.cmd') -Encoding Ascii

@'
@echo off
setlocal
set "ROOT=%~dp0.."
"%ROOT%\node\node.exe" "%ROOT%\pnpm\node_modules\pnpm\bin\pnpm.mjs" dlx %*
'@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'pnpx.cmd') -Encoding Ascii
