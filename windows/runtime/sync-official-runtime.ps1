[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRoot,
    [Parameter(Mandatory = $true)]
    [string]$Commit
)

# Build the exact official source commit into a versioned Windows runtime.
# This script is shipped inside the app and is intentionally the only process
# that can update the active pointer. It does not write DSH_HOME.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$resources = Split-Path -Parent $PSScriptRoot
$node = Join-Path $resources 'node\node.exe'
$pnpm = Join-Path $resources 'pnpm\node_modules\pnpm\bin\pnpm.mjs'
$materializer = Join-Path $resources 'bin\materialize-runtime.mjs'
$commitPattern = '^[0-9a-f]{40}$'

function Emit-Progress {
    param(
        [string]$Phase,
        [double]$Fraction,
        [string]$Title,
        [string]$Detail
    )
    $payload = [ordered]@{
        phase = $Phase
        fraction = [Math]::Min([Math]::Max($Fraction, 0), 1)
        title = $Title
        detail = $Detail
    } | ConvertTo-Json -Compress
    Write-Output "@@DSH_SYNC@@$payload"
}

function Fail-Sync {
    param([string]$Phase, [string]$Detail)
    Emit-Progress $Phase $script:lastFraction 'Official Harness sync did not finish' $Detail
    throw $Detail
}

function Invoke-Pnpm {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $node $pnpm @Arguments *>> $script:syncLog
    if ($LASTEXITCODE -ne 0) {
        throw "pnpm exited with code $LASTEXITCODE"
    }
}

function Write-CurrentPointer {
    param([string]$Value)
    $temporary = Join-Path $RuntimeRoot (".current-{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $temporary -Value $Value -NoNewline -Encoding Ascii
    Move-Item -LiteralPath $temporary -Destination (Join-Path $RuntimeRoot 'current.txt') -Force
}

if ($Commit -notmatch $commitPattern) {
    throw 'The requested official commit is invalid.'
}
$Commit = $Commit.ToLowerInvariant()

$expectedRoot = Join-Path (
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'DeepSeek Harness Glass'
) 'runtime'
if ([IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($expectedRoot).TrimEnd('\')) {
    throw "Refusing a runtime path outside the app's LocalAppData directory."
}

foreach ($required in @($node, $pnpm, $materializer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "The bundled update tool is missing: $required"
    }
}

$versions = Join-Path $RuntimeRoot 'versions'
$target = Join-Path $versions $Commit
$downloads = Join-Path $RuntimeRoot 'downloads'
$archive = Join-Path $downloads "$Commit.tar.gz"
$partialArchive = "$archive.part"
$script:syncLog = Join-Path $RuntimeRoot 'latest-sync.log'
$script:lastFraction = 0
$stage = Join-Path $RuntimeRoot (".staging-$Commit-" + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $stage 'source'
$backend = Join-Path $stage 'backend'
$upstreamTarball = "https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/$Commit"

New-Item -ItemType Directory -Force -Path $RuntimeRoot, $versions, $downloads | Out-Null
Set-Content -LiteralPath $script:syncLog -Value '' -Encoding UTF8

if (Test-Path -LiteralPath (Join-Path $target 'lib\bin.js') -PathType Leaf) {
    $script:lastFraction = 0.96
    Emit-Progress 'activate' $script:lastFraction 'Activating cached official runtime' $Commit
    Write-CurrentPointer $Commit
    $script:lastFraction = 1
    Emit-Progress 'complete' $script:lastFraction 'Official Harness updated' "Activated cached commit $Commit"
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $source, $backend | Out-Null

    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        $script:lastFraction = 0.08
        Emit-Progress 'download' $script:lastFraction 'Downloading official source' 'Downloading the exact official GitHub commit.'
        & curl.exe --fail --location --silent --show-error `
            --continue-at - --retry 4 --retry-all-errors --retry-delay 2 `
            --connect-timeout 20 --max-time 1800 --speed-time 120 --speed-limit 1024 `
            $upstreamTarball --output $partialArchive *>> $script:syncLog
        if ($LASTEXITCODE -ne 0) {
            Fail-Sync 'download' 'The official source download failed. Check your network and try again; the partial download is retained.'
        }
        Move-Item -LiteralPath $partialArchive -Destination $archive -Force
    }

    $script:lastFraction = 0.27
    Emit-Progress 'extract' $script:lastFraction 'Extracting official source' "Verifying and extracting commit $Commit."
    & tar.exe -xzf $archive -C $source --strip-components=1 *>> $script:syncLog
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $source 'package.json'))) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Fail-Sync 'extract' 'The downloaded official source archive is invalid and was discarded.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'pnpm-lock.yaml'))) {
        Fail-Sync 'extract' 'The official source archive is incomplete.'
    }

    $script:lastFraction = 0.34
    Emit-Progress 'install' $script:lastFraction 'Installing official dependencies' 'The first sync can take several minutes.'
    Push-Location $source
    try {
        $env:CI = 'true'
        Invoke-Pnpm install --frozen-lockfile
    }
    catch {
        Fail-Sync 'install' 'Official dependency installation failed. Check your network and try again.'
    }
    finally {
        Pop-Location
    }

    $script:lastFraction = 0.56
    Emit-Progress 'build' $script:lastFraction 'Building official Harness' 'Compiling the official Web profile and plugin runtime.'
    Push-Location $source
    try {
        $env:CI = 'true'
        $env:DSH_CLIENT_COMMIT_HASH = $Commit
        Invoke-Pnpm run build
    }
    catch {
        Fail-Sync 'build' 'The official Harness build failed. A diagnostic log was retained.'
    }
    finally {
        Remove-Item Env:DSH_CLIENT_COMMIT_HASH -ErrorAction SilentlyContinue
        Pop-Location
    }

    $script:lastFraction = 0.76
    Emit-Progress 'deploy' $script:lastFraction 'Packaging complete runtime' 'Preparing official dsh and all shipped Profile Bundles.'
    Push-Location $source
    try {
        $env:CI = 'true'
        Invoke-Pnpm --filter '@deepseek-ai/dsh' deploy --prod --legacy --config.node-linker=hoisted $backend
    }
    catch {
        Fail-Sync 'deploy' 'The official runtime package step failed. A diagnostic log was retained.'
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath (Join-Path $backend 'lib\bin.js') -PathType Leaf)) {
        Fail-Sync 'deploy' 'The official dsh entry point was not present after packaging.'
    }

    $script:lastFraction = 0.90
    Emit-Progress 'materialize' $script:lastFraction 'Finalizing runtime files' 'Validating the official workspace dependency closure.'
    & $node $materializer $source $backend *>> $script:syncLog
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $backend 'lib\bin.js'))) {
        Fail-Sync 'materialize' 'Runtime dependency finalization failed. A diagnostic log was retained.'
    }

    @{
        upstream = 'https://github.com/deepseek-ai/deepseek-harness'
        commit = $Commit
        platform = 'windows'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backend '.deepseek-harness-glass-runtime.json') -Encoding UTF8

    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $backend -Destination $target
    $script:lastFraction = 0.98
    Emit-Progress 'activate' $script:lastFraction 'Activating official Harness' 'Atomically switching to the newly built runtime.'
    Write-CurrentPointer $Commit
    $script:lastFraction = 1
    Emit-Progress 'complete' $script:lastFraction 'Official Harness updated' "Activated commit $Commit"
}
catch {
    if ($_.Exception.Message -notmatch '^Official Harness sync did not finish') {
        Emit-Progress 'failed' $script:lastFraction 'Official Harness sync did not finish' $_.Exception.Message
    }
    exit 1
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
