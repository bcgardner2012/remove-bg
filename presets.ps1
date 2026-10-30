<#
.SYNOPSIS
Runs remove-background.ps1 or remove-background-ai.ps1 with a named preset (see preset-definitions.ps1, or -List).

.EXAMPLE
.\presets.ps1 -Preset gradient hero.png -Trim
#>
[CmdletBinding()]
param(
    [string] $Preset,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)] [string[]] $Path,
    [string] $OutDir,
    [string] $BackgroundColor,
    [double] $Tolerance = -1,
    [switch] $Trim,
    [int] $Padding = 0,
    [switch] $Preview,
    [switch] $List
)

$ErrorActionPreference = 'Stop'
$presets = & (Join-Path $PSScriptRoot 'preset-definitions.ps1')

if ($List -or -not $Preset) {
    Write-Host 'Presets:'
    foreach ($name in $presets.Keys) { Write-Host ('  {0,-15} {1}' -f $name, $presets[$name].Description) }
    if (-not $List) { throw 'Choose a preset with -Preset <name>.' }
    return
}
if (-not $presets.Contains($Preset)) { throw "Unknown preset '$Preset'. Presets: $($presets.Keys -join ', ')" }
if (-not $Path) { throw 'No images given. Drag image files onto the .cmd file, or pass their paths.' }

$def = $presets[$Preset]
$params = @{} + $def.Params
if ($OutDir) { $params.OutDir = $OutDir }
if ($Trim) { $params.Trim = $true }
if ($Padding) { $params.Padding = $Padding }
if ($Preview) { $params.Preview = $true }
if ($def.Engine -eq 'ai') {
    if ($BackgroundColor -or $Tolerance -ge 0) { Write-Warning '-BackgroundColor and -Tolerance only apply to the colour presets; ignored.' }
    $engine = 'remove-background-ai.ps1'
} else {
    if ($BackgroundColor) { $params.BackgroundColor = $BackgroundColor }
    if ($Tolerance -ge 0) { $params.Tolerance = $Tolerance }
    $engine = 'remove-background.ps1'
}

Write-Host "Preset: $Preset - $($def.Description)"
& (Join-Path $PSScriptRoot $engine) -Path $Path @params
