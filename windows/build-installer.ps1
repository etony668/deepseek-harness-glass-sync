[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$publishRoot = Join-Path $PSScriptRoot ("dist\DeepSeekHarnessGlass-win-$Architecture")
$installerSource = Join-Path $PSScriptRoot 'installer\Product.wxs'
$releaseRoot = Join-Path $PSScriptRoot 'dist'

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $env:GITHUB_REF_NAME
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = '0.0.0'
}

$Version = $Version.Trim()
if ($Version.StartsWith('v')) {
    $Version = $Version.Substring(1)
}
if ($Version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') {
    throw "MSI version must be a numeric semantic version, got '$Version'."
}

$application = Join-Path $publishRoot 'DeepSeekHarnessGlass.exe'
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'package.ps1') -Architecture $Architecture
}
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    throw "Published Windows application was not found: $application"
}

$wix = Get-Command wix -ErrorAction SilentlyContinue
if ($null -eq $wix) {
    throw 'WiX Toolset was not found on PATH. Install wix.exe before running build-installer.ps1.'
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
$output = Join-Path $releaseRoot "DeepSeekHarnessGlass-win-$Architecture-v$Version.msi"

& $wix.Source build $installerSource `
    -arch $Architecture `
    -bindpath "PublishDir=$publishRoot" `
    -d "ProductVersion=$Version" `
    -ext WixToolset.UI.wixext `
    -o $output

if ($LASTEXITCODE -ne 0) {
    throw "WiX MSI build failed with exit code $LASTEXITCODE."
}

Write-Output '== MSI complete =='
Write-Output $output
