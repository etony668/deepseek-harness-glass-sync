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

$driveLetter = @('X', 'Y', 'Z') |
    Where-Object { -not (Test-Path -LiteralPath ("{0}:\" -f $_)) } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($driveLetter)) {
    throw 'No free X:, Y:, or Z: drive letter is available for the WiX staging path.'
}

# WiX's native cabinet helper does not consistently support the deeply nested
# paths in the official Node runtime closure. Give it a temporary short source
# path without copying or mutating the published application files.
$shortPublishRoot = "{0}:\" -f $driveLetter
& $env:ComSpec /d /c @('subst', ("{0}:" -f $driveLetter), $publishRoot) | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not create the temporary $shortPublishRoot WiX staging drive."
}

$wixExitCode = 1
try {
    & $wix.Source build $installerSource `
        -arch $Architecture `
        -bindpath "PublishDir=$shortPublishRoot" `
        -d "ProductVersion=$Version" `
        -ext WixToolset.UI.wixext `
        -o $output
    $wixExitCode = $LASTEXITCODE
}
finally {
    & $env:ComSpec /d /c @('subst', ("{0}:" -f $driveLetter), '/d') | Out-Null
}

if ($wixExitCode -ne 0) {
    throw "WiX MSI build failed with exit code $wixExitCode."
}

Write-Output '== MSI complete =='
Write-Output $output
