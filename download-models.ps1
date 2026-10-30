<#
.SYNOPSIS
Downloads AI models into models\ from the rembg project's GitHub releases, verifying their SHA-256 checksums.

.PARAMETER Model
Model name(s) to download (see -List). Already-downloaded, intact models are skipped.

.PARAMETER List
Show the available models and which are downloaded.

.EXAMPLE
.\download-models.ps1 -List

.EXAMPLE
.\download-models.ps1 BiRefNet-general-epoch_244
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)] [string[]] $Model,
    [switch] $List
)

$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://github.com/danielgatis/rembg/releases/download/v0.0.0'
$folder = Join-Path $PSScriptRoot 'models'

$catalog = [ordered]@{
    'isnet-general-use'          = @{ Bytes = 178648008; Sha256 = '60920E99C45464F2BA57BEE2AD08C919A52BBF852739E96947FBB4358C0D964A'; Preset = 'ai';       Use = '3D renders, photos, general use' }
    'isnet-anime'                = @{ Bytes = 176069933; Sha256 = 'F15622D853E8260172812B657053460E20806F04B9E05147D49AF7BED31A6E99'; Preset = 'ai-anime'; Use = 'anime and illustration art' }
    'BiRefNet-general-epoch_244' = @{ Bytes = 972666916; Sha256 = '58F621F00F5D756097615970A88A791584600DCF7C45B18A0A6267535A1EBD3C'; Preset = 'ai-best';  Use = 'most accurate; slow without a GPU with 8+ GB' }
}

function Test-Model([string] $name) {
    $file = Join-Path $folder "$name.onnx"
    (Test-Path $file) -and ((Get-Item $file).Length -eq $catalog[$name].Bytes)
}

if ($List -or -not $Model) {
    Write-Host 'Models:'
    foreach ($name in $catalog.Keys) {
        $m = $catalog[$name]
        Write-Host ('  {0,-28} {1,5:N0} MB  preset {2,-9} {3}{4}' -f $name, ($m.Bytes / 1MB), $m.Preset, $m.Use, $(if (Test-Model $name) { '  [downloaded]' } else { '' }))
    }
    if (-not $List) { Write-Host "`nDownload with: download-models.cmd <name> [<name>...]" }
    return
}

New-Item -ItemType Directory -Force -Path $folder | Out-Null
foreach ($name in $Model) {
    if (-not $catalog.Contains($name)) { throw "Unknown model '$name'. Models: $($catalog.Keys -join ', ')" }
    $m = $catalog[$name]
    $file = Join-Path $folder "$name.onnx"
    if (Test-Model $name) { Write-Host "$name already downloaded."; continue }

    Write-Host ("Downloading {0} ({1:N0} MB)..." -f $name, ($m.Bytes / 1MB))
    $part = "$file.part"
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads very slow
    try { Invoke-WebRequest -Uri "$BaseUrl/$name.onnx" -OutFile $part -UseBasicParsing }
    finally { $ProgressPreference = $old }

    $hash = (Get-FileHash $part -Algorithm SHA256).Hash
    if ($hash -ne $m.Sha256) {
        Remove-Item $part -Force
        throw "$name failed its checksum (got $hash); the download was deleted. Try again."
    }
    Move-Item $part $file -Force
    Write-Host "$name downloaded and verified."
}
