[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

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
$payloadArchive = Join-Path $releaseRoot 'DeepSeekHarnessGlass-payload.zip'
Remove-Item -LiteralPath $payloadArchive -Force -ErrorAction SilentlyContinue

# The official Harness runtime contains a very large number of small files.
# Keep the MSI database lean by installing one payload archive, then expand it
# through the installer custom action. This avoids a per-file MSI component
# table while the complete runtime remains self-contained after install.
Compress-Archive -Path (Join-Path $publishRoot '*') `
    -DestinationPath $payloadArchive `
    -CompressionLevel Optimal `
    -Force
if (-not (Test-Path -LiteralPath $payloadArchive -PathType Leaf)) {
    throw "Could not create installer payload archive: $payloadArchive"
}

$wixExitCode = 1
try {
    & $wix.Source build $installerSource `
        -arch $Architecture `
        -bindpath "PayloadDir=$releaseRoot" `
        -d "ProductVersion=$Version" `
        -ext WixToolset.UI.wixext `
        -ext WixToolset.Util.wixext `
        -o $output
    $wixExitCode = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $payloadArchive -Force -ErrorAction SilentlyContinue
}

if ($wixExitCode -ne 0) {
    throw "WiX MSI build failed with exit code $wixExitCode."
}

Write-Output '== MSI complete =='
Write-Output $output
