<#
.SYNOPSIS
Runs every preset on each image and builds a side-by-side comparison sheet, so you can pick the best result
instead of guessing settings.

.DESCRIPTION
For each input "name.ext" this writes a folder "name-presets" (next to the input, or in -OutDir) with:
  name-compare.png          the original and every preset's result on a checkerboard, labelled
  <preset>\name-nobg.png    each preset's finished, transparent result - keep the one you like
  <preset>\name-nobg-preview.png

.PARAMETER Open
Open each comparison sheet in the default image viewer when done.

.PARAMETER SkipSlow
Leave out slow presets (ai-best) for a quicker comparison.

.EXAMPLE
.\compare-presets.ps1 hero.png -Open
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)] [string[]] $Path,
    [string] $OutDir,
    [string] $BackgroundColor,
    [switch] $Trim,
    [int] $Padding = 0,
    [switch] $Open,
    [switch] $SkipSlow
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$presets = & (Join-Path $PSScriptRoot 'preset-definitions.ps1')
$engine = Join-Path $PSScriptRoot 'remove-background.ps1'
$aiEngine = Join-Path $PSScriptRoot 'remove-background-ai.ps1'

$TileHeight = 360      # each image is scaled to this height on the sheet
$LabelHeight = 58
$Gap = 12

function New-Tile([System.Drawing.Image] $image, [string] $title, [string] $subtitle) {
    $scale = $TileHeight / $image.Height
    $w = [Math]::Max(160, [int][Math]::Round($image.Width * $scale))
    $tile = New-Object System.Drawing.Bitmap $w, ($TileHeight + $LabelHeight)
    $g = [System.Drawing.Graphics]::FromImage($tile)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(32, 32, 32))
        $g.InterpolationMode = 'HighQualityBicubic'
        $light = [System.Drawing.Brushes]::Magenta; $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 160, 0))
        $imgW = [int][Math]::Round($image.Width * $scale); $x0 = [int](($w - $imgW) / 2)
        for ($y = 0; $y -lt $TileHeight; $y += 12) { for ($x = 0; $x -lt $imgW; $x += 12) {
            $g.FillRectangle($(if ((($x + $y) / 12) % 2 -eq 0) { $light } else { $dark }), $x0 + $x, $y, [Math]::Min(12, $imgW - $x), [Math]::Min(12, $TileHeight - $y)) } }
        $g.DrawImage($image, $x0, 0, $imgW, $TileHeight)
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $g.DrawString($title, (New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 4, ($TileHeight + 4))
        $g.DrawString($subtitle, (New-Object System.Drawing.Font 'Segoe UI', 8), [System.Drawing.Brushes]::Silver,
            (New-Object System.Drawing.RectangleF 4, ($TileHeight + 26), ($w - 8), ($LabelHeight - 28)))
    } finally { $g.Dispose() }
    $tile
}

$files = foreach ($p in $Path) { Get-Item -Path $p | Where-Object { -not $_.PSIsContainer } }
if (-not $files) { throw "No files match: $($Path -join ', ')" }

foreach ($file in $files) {
    $baseDir = if ($OutDir) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null; (Resolve-Path $OutDir).Path } else { $file.DirectoryName }
    $folder = Join-Path $baseDir ($file.BaseName + '-presets')
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    Write-Host "`n== $($file.Name)"

    $tiles = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
    try {
        $original = [System.Drawing.Bitmap]::FromFile($file.FullName)
        try { $tiles.Add((New-Tile $original 'original' "$($original.Width) x $($original.Height)")) } finally { $original.Dispose() }

        foreach ($name in $presets.Keys) {
            $def = $presets[$name]
            if ($SkipSlow -and $def.Slow) { Write-Host ("  {0,-15} skipped (-SkipSlow)" -f $name); continue }
            $params = @{} + $def.Params
            if ($Trim) { $params.Trim = $true }
            if ($Padding) { $params.Padding = $Padding }
            if ($def.Engine -eq 'ai') {
                if (-not (Test-Path (Join-Path $PSScriptRoot "models\$($def.Params.Model).onnx"))) {
                    Write-Host ("  {0,-15} skipped: model not downloaded (download-models.cmd {1})" -f $name, $def.Params.Model)
                    continue
                }
                $script = $aiEngine
            } else {
                if ($BackgroundColor) { $params.BackgroundColor = $BackgroundColor }
                $script = $engine
            }
            try { $line = & $script -Path $file.FullName -OutDir (Join-Path $folder $name) @params 6>&1 | Out-String }
            catch { Write-Host ("  {0,-15} failed: {1}" -f $name, $_.Exception.Message); continue }
            Write-Host ("  {0,-15} {1}" -f $name, ($line.Trim() -replace '^.*?->\s*\S+\s+', ''))

            $result = Join-Path (Join-Path $folder $name) ($file.BaseName + '-nobg.png')
            $image = [System.Drawing.Bitmap]::FromFile($result)
            try { $tiles.Add((New-Tile $image $name $presets[$name].Description)) } finally { $image.Dispose() }
        }

        $sheetW = [int](($tiles | Measure-Object -Property Width -Sum).Sum + $Gap * ($tiles.Count + 1))
        $sheet = New-Object System.Drawing.Bitmap $sheetW, ($TileHeight + $LabelHeight + 2 * $Gap)
        $g = [System.Drawing.Graphics]::FromImage($sheet)
        try {
            $g.Clear([System.Drawing.Color]::FromArgb(16, 16, 16))
            $x = $Gap
            foreach ($tile in $tiles) { $g.DrawImage($tile, $x, $Gap, $tile.Width, $tile.Height); $x += $tile.Width + $Gap }
        } finally { $g.Dispose() }
        $sheetPath = Join-Path $folder ($file.BaseName + '-compare.png')
        $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
    } finally { foreach ($t in $tiles) { $t.Dispose() } }

    Write-Host "  Comparison: $sheetPath"
    Write-Host "  Results:    $folder\<preset>\$($file.BaseName)-nobg.png"
    if ($Open) { Invoke-Item $sheetPath }
}
