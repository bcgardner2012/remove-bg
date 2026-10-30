<#
.SYNOPSIS
Removes the background from images with an AI segmentation model, for backgrounds that aren't one plain
colour (scenes, rooms, furniture, gradients). Saves transparent PNGs like remove-background.ps1.

.PARAMETER Path
Image file(s): PNG, JPG, BMP, GIF or TIFF. Wildcards allowed.

.PARAMETER Model
Model name: a file "models\<name>.onnx" next to this script. Default isnet-general-use.

.PARAMETER Cpu
Run on the CPU instead of the GPU.

.EXAMPLE
.\remove-background-ai.ps1 render.png -Trim -Preview
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)] [string[]] $Path,
    [string] $Model = 'isnet-general-use',
    [string] $OutDir,
    [switch] $Trim,
    [int] $Padding = 0,
    [switch] $Preview,
    [switch] $Cpu
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'ai-bin\BgRemoveAi.exe'
$modelFile = Join-Path $PSScriptRoot "models\$Model.onnx"
if (-not (Test-Path $exe)) { throw "AI program not found at $exe. Run setup.cmd first (see README)." }
if (-not (Test-Path $modelFile)) { throw "Model '$Model' isn't downloaded. Run: download-models.cmd $Model" }

# @() so a single file stays an array (splatting a lone string would pass it one character at a time).
$files = @(foreach ($p in $Path) { Get-Item -Path $p | Where-Object { -not $_.PSIsContainer } | ForEach-Object FullName })
if (-not $files) { throw "No files match: $($Path -join ', ')" }

$arguments = @('--model', $modelFile)
if ($OutDir) { $arguments += @('--outdir', $OutDir) }
if ($Trim) { $arguments += '--trim' }
if ($Padding) { $arguments += @('--padding', $Padding) }
if ($Preview) { $arguments += '--preview' }
if ($Cpu) { $arguments += '--cpu' }

& $exe @arguments @files
if ($LASTEXITCODE -ne 0) { throw "AI background removal failed for some files (exit code $LASTEXITCODE)." }
