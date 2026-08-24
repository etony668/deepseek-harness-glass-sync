[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64'
)

# Build the official Harness checkout and materialize the exact Windows runtime
# shipped by the native WinUI shell. Nothing under DSH_HOME is read or written.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$harness = Join-Path $repositoryRoot 'upstream\deepseek-harness'
$build = Join-Path $PSScriptRoot 'build'
$versionsFile = Join-Path $repositoryRoot 'glass\runtime\versions.env'
$nodeDirectory = Join-Path $build 'node'
$node = Join-Path $nodeDirectory 'node.exe'
$npmCli = Join-Path $build 'npm\node_modules\npm\bin\npm-cli.js'
$pnpmDirectory = Join-Path $build 'pnpm'
$pnpm = Join-Path $pnpmDirectory 'node_modules\pnpm\bin\pnpm.mjs'
$backend = Join-Path $build 'backend'
$bin = Join-Path $build 'bin'

if (-not (Test-Path -LiteralPath $versionsFile -PathType Leaf)) {
    throw "Missing embedded runtime version file: $versionsFile"
}
$versions = ConvertFrom-StringData -StringData (Get-Content -LiteralPath $versionsFile -Raw)
$nodeVersion = $versions.NODE_VERSION
$pnpmVersion = $versions.PNPM_VERSION
$nodeArchive = "node-v$nodeVersion-win-$Architecture.zip"
$nodeUrl = "https://nodejs.org/dist/v$nodeVersion/$nodeArchive"

if (-not (Test-Path -LiteralPath (Join-Path $harness 'package.json') -PathType Leaf)) {
    throw 'The official Harness submodule is missing. Clone with --recurse-submodules or run: git submodule update --init --checkout upstream/deepseek-harness'
}

if (-not (Test-Path -LiteralPath $node -PathType Leaf) -or -not (Test-Path -LiteralPath $npmCli -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $nodeDirectory, (Split-Path -Parent $npmCli) | Out-Null
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("dsh-node-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $temporary | Out-Null
        $download = Join-Path $temporary $nodeArchive
        Invoke-WebRequest -Uri $nodeUrl -OutFile $download
        Expand-Archive -LiteralPath $download -DestinationPath $temporary -Force
        $extracted = Join-Path $temporary ("node-v$nodeVersion-win-$Architecture")
        Copy-Item -LiteralPath (Join-Path $extracted 'node.exe') -Destination $node -Force
        Remove-Item -LiteralPath (Join-Path $build 'npm\node_modules\npm') -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath (Join-Path $extracted 'node_modules\npm') `
            -Destination (Join-Path $build 'npm\node_modules\npm') -Recurse -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$installedPnpmVersion = if (Test-Path -LiteralPath (Join-Path $pnpmDirectory 'package.json')) {
    (& $node -p "try { require('$($pnpmDirectory.Replace('\', '/'))/package.json').version } catch { '' }").Trim()
}
if ($installedPnpmVersion -ne $pnpmVersion) {
    Remove-Item -LiteralPath $pnpmDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $pnpmDirectory | Out-Null
    & $node $npmCli install --prefix $pnpmDirectory --omit=dev --no-audit --no-fund "pnpm@$pnpmVersion"
    if ($LASTEXITCODE -ne 0) { throw "Could not install pnpm@$pnpmVersion" }
}

# The official Harness build recursively launches `pnpm` from package scripts.
# Put the bundled command wrapper on PATH before that build begins; invoking
# pnpm through an absolute Node path alone is insufficient on Windows.
& (Join-Path $PSScriptRoot 'runtime\make-pnpm-wrapper.ps1') -OutputDirectory $bin
# Nested official lifecycle scripts invoke both `pnpm` and `node` by name.
$env:PATH = "$bin;$nodeDirectory;$env:PATH"

function Invoke-Pnpm {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $node $pnpm @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "pnpm exited with code $LASTEXITCODE"
    }
}

Write-Output '== official Harness: install =='
Push-Location $harness
try {
    $env:CI = 'true'
    Invoke-Pnpm install --frozen-lockfile
    Write-Output '== official Harness: build =='
    Invoke-Pnpm run build
}
finally {
    Pop-Location
}

Write-Output '== official Harness: deploy complete runtime =='
Remove-Item -LiteralPath $backend -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $backend | Out-Null
Push-Location $harness
try {
    Invoke-Pnpm --filter '@deepseek-ai/dsh' deploy --prod --legacy --config.node-linker=hoisted $backend
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath (Join-Path $backend 'lib\bin.js') -PathType Leaf)) {
    throw 'The deployed official dsh entry point is missing.'
}

Write-Output '== materialize official workspace peer closure =='
& $node (Join-Path $repositoryRoot 'scripts\materialize-runtime.mjs') $harness $backend
if ($LASTEXITCODE -ne 0) { throw 'Runtime materialization failed.' }

Write-Output '== smoke test official dsh web profile =='
$temporaryHome = Join-Path ([IO.Path]::GetTempPath()) ("dsh-smoke-" + [Guid]::NewGuid().ToString('N'))
$smokeLog = Join-Path $build 'dsh-smoke.log'
New-Item -ItemType Directory -Force -Path $temporaryHome | Out-Null
$previousHome = $env:DSH_HOME
try {
    $env:DSH_HOME = $temporaryHome
    $process = Start-Process -FilePath $node `
        -ArgumentList @('--expose-internals', (Join-Path $backend 'lib\bin.js'), 'web', '--no-open', '--port', '0') `
        -RedirectStandardOutput $smokeLog `
        -RedirectStandardError "$smokeLog.err" `
        -PassThru
    $ready = $false
    for ($index = 0; $index -lt 45; $index++) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $smokeLog -PathType Leaf) {
            if (Select-String -LiteralPath $smokeLog -Pattern 'dsh web: http://127\.0\.0\.1:[0-9]+' -Quiet) {
                $ready = $true
                break
            }
        }
        if ($process.HasExited) { break }
    }
    if (-not $ready) {
        Write-Output '== dsh web smoke stdout =='
        if (Test-Path -LiteralPath $smokeLog) {
            Get-Content -LiteralPath $smokeLog -Tail 100
        }
        Write-Output '== dsh web smoke stderr =='
        if (Test-Path -LiteralPath "$smokeLog.err") {
            Get-Content -LiteralPath "$smokeLog.err" -Tail 100
        }
        throw 'Timed out waiting for the official dsh web profile.'
    }
    Write-Output 'official dsh web smoke test passed'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    if ($null -eq $previousHome) {
        Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:DSH_HOME = $previousHome
    }
    Remove-Item -LiteralPath $temporaryHome -Recurse -Force -ErrorAction SilentlyContinue
}
