<#
.SYNOPSIS
Sets up the AI presets: builds ai-bin\BgRemoveAi.exe and downloads the default models
(isnet-general-use and isnet-anime, ~340 MB). The colour presets work without this.

.PARAMETER NoModels
Only build the program; don't download models.
#>
[CmdletBinding()]
param([switch] $NoModels)

$ErrorActionPreference = 'Stop'

# The AI program is built from source with the .NET SDK (8 or newer).
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
$sdks = if ($dotnet) { @(& dotnet --list-sdks 2>$null) } else { @() }
$usable = $sdks | Where-Object { $_ -match '^(\d+)\.' -and [int]$Matches[1] -ge 8 }
if (-not $usable) {
    Write-Host 'The AI presets need the .NET SDK, version 8 or newer, to build. Install it from'
    Write-Host '  https://dotnet.microsoft.com/download'
    Write-Host 'then run setup again. (The colour presets work without it.)'
    exit 1
}

Write-Host 'Building the AI program...'
& dotnet publish (Join-Path $PSScriptRoot 'ai') -c Release -o (Join-Path $PSScriptRoot 'ai-bin') -nologo -v quiet
if ($LASTEXITCODE -ne 0) { throw 'Build failed (see the messages above).' }
Write-Host "Built $(Join-Path $PSScriptRoot 'ai-bin\BgRemoveAi.exe')"

if (-not $NoModels) {
    & (Join-Path $PSScriptRoot 'download-models.ps1') isnet-general-use isnet-anime
    Write-Host "`nOptional: the most accurate (and largest, 928 MB) model, for the ai-best preset:"
    Write-Host '  download-models.cmd BiRefNet-general-epoch_244'
}
Write-Host "`nSetup done. Drag images onto remove-bg-compare.cmd to try every preset."
