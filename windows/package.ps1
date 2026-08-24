[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',
    [switch]$SkipRuntimeBuild
)

# Produce a self-contained, unpackaged Windows app folder. The result can be
# zipped or installed by an enterprise deployment tool without a certificate.
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$build = Join-Path $PSScriptRoot 'build'
$output = Join-Path $PSScriptRoot ("dist\DeepSeekHarnessGlass-win-$Architecture")
$resourceRoot = Join-Path $output 'Resources'
$bin = Join-Path $resourceRoot 'bin'
$project = Join-Path $PSScriptRoot 'DeepSeekHarnessGlass.Windows.csproj'

if (-not $SkipRuntimeBuild) {
    & (Join-Path $PSScriptRoot 'build-runtime.ps1') -Architecture $Architecture
}

Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish $project -c Release -r "win-$Architecture" --self-contained true `
    -p:WindowsPackageType=None -p:WindowsAppSDKSelfContained=true -o $output
if ($LASTEXITCODE -ne 0) { throw 'Windows shell publish failed.' }

New-Item -ItemType Directory -Force -Path $resourceRoot, $bin | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'node') -Destination (Join-Path $resourceRoot 'node') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $build 'pnpm') -Destination (Join-Path $resourceRoot 'pnpm') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $build 'bin\pnpm.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $build 'bin\pnpx.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $build 'backend') -Destination (Join-Path $resourceRoot 'backend') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\sync-official-runtime.ps1') `
    -Destination (Join-Path $bin 'sync-official-runtime.ps1') -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts\materialize-runtime.mjs') `
    -Destination (Join-Path $bin 'materialize-runtime.mjs') -Force

# Windows App SDK is native code and may require the Microsoft Visual C++
# runtime even when the app is published self-contained. Copy the public
# app-local VC runtime DLLs when the build machine has them, so a clean Windows
# machine does not fail before managed startup with a missing DLL dialog.
$vcRuntimeNames = @(
    'concrt140.dll',
    'msvcp140.dll',
    'msvcp140_1.dll',
    'msvcp140_2.dll',
    'msvcp140_atomic_wait.dll',
    'msvcp140_codecvt_ids.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll'
)
$systemDirectory = Join-Path $env:WINDIR 'System32'
foreach ($name in $vcRuntimeNames) {
    $source = Join-Path $systemDirectory $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $output $name) -Force
    }
}

# A tiny launcher makes it obvious that the complete published folder must be
# kept together, and gives users a convenient entry point when Explorer blocks
# direct execution of an unsigned unpackaged WinUI app.
$launcher = @'
@echo off
setlocal
set "APP_DIR=%~dp0"
if not exist "%APP_DIR%DeepSeekHarnessGlass.exe" (
  echo DeepSeekHarnessGlass.exe was not found. Keep the entire extracted folder together.
  pause
  exit /b 2
)
start "" "%APP_DIR%DeepSeekHarnessGlass.exe"
'@
Set-Content -LiteralPath (Join-Path $output 'Launch-DeepSeekHarnessGlass.cmd') `
    -Value $launcher -Encoding Ascii

$commit = (git -C (Join-Path $repositoryRoot 'upstream\deepseek-harness') rev-parse HEAD).Trim()
Set-Content -LiteralPath (Join-Path $resourceRoot 'bundled-runtime-commit') -Value $commit -NoNewline -Encoding Ascii

Write-Output "== complete =="
Write-Output $output
