[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
)

$ErrorActionPreference = 'Stop'

Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
Remove-Item -LiteralPath $ArchivePath -Force
