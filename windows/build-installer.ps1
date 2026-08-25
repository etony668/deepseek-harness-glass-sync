[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$publishRoot = Join-Path $PSScriptRoot ("dist\DeepSeekHarnessGlass-win-$Architecture")
$installerSource = Join-Path $PSScriptRoot 'installer\DeepSeekHarnessGlass.nsi'
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
if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
    throw "Installer version contains unsupported characters: '$Version'."
}

$application = Join-Path $publishRoot 'DeepSeekHarnessGlass.exe'
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'package.ps1') -Architecture $Architecture
}
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    throw "Published Windows application was not found: $application"
}

$nsisCommand = Get-Command makensis.exe -ErrorAction SilentlyContinue
$nsisPath = if ($null -ne $nsisCommand) {
    $nsisCommand.Source
}
else {
    $nsisCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $nsisCandidates += Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $nsisCandidates += Join-Path $env:ProgramFiles 'NSIS\makensis.exe'
    }

    $nsisCandidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($nsisPath)) {
    throw 'NSIS was not found. Install makensis.exe or add it to PATH before running build-installer.ps1.'
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
$output = Join-Path $releaseRoot "DeepSeekHarnessGlass-win-$Architecture-Setup-v$Version.exe"
Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue

& $nsisPath /V3 `
    "/DAPP_SOURCE=$publishRoot" `
    "/DPRODUCT_VERSION=$Version" `
    "/DOUTPUT_FILE=$output" `
    $installerSource
if ($LASTEXITCODE -ne 0) {
    throw "NSIS Setup build failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "NSIS Setup was not created: $output"
}

Write-Output '== NSIS Setup complete =='
Write-Output $output
