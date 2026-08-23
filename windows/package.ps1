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

$commit = (git -C (Join-Path $repositoryRoot 'upstream\deepseek-harness') rev-parse HEAD).Trim()
Set-Content -LiteralPath (Join-Path $resourceRoot 'bundled-runtime-commit') -Value $commit -NoNewline -Encoding Ascii

Write-Output "== complete =="
Write-Output $output
