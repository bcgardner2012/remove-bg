# remove-bg

Removes the background from images and saves them as transparent PNGs, keeping the original size.
Drag-and-drop presets for Windows, plus a comparison sheet that runs them all so you can pick the best result.
Everything runs locally; no images are uploaded anywhere.

Two engines:

- **AI** (`ai` presets) — a segmentation model that recognises the subject, so it handles **any background**:
  rooms, furniture, scenery, gradients, and subjects that share colours with the background. Runs on your GPU
  (or CPU); under a second per image on a mid-range GPU (except `ai-best`, see [GPU memory](#gpu-and-gpu-memory)).
- **Colour key** (the other presets) — removes one **plain background colour**. Exact and fast (half a
  second for 2400 × 2600), best for flat backgrounds, pixel art and icons, where the AI can misjudge what
  the subject is.

## Requirements and setup

- **Windows 10 or 11.** The scripts use Windows PowerShell 5.1, which is built into Windows.
- **Colour presets:** nothing else. They work straight after downloading.
- **AI presets:** the [.NET SDK](https://dotnet.microsoft.com/download) 8 or newer, then run **`setup.cmd`**
  once. It builds the AI program and downloads the two default models (~340 MB, checksum-verified). A GPU
  is optional: any DirectX 12 GPU (NVIDIA, AMD or Intel) is used automatically, no CUDA needed; otherwise
  the CPU is used.
- Optional, for the `ai-best` preset: `download-models.cmd BiRefNet-general-epoch_244` (928 MB).

## Quick start

1. **Drag your image(s) onto `remove-bg-compare.cmd`.**
   Every preset is run, and a comparison sheet opens showing the original and each preset's result on a
   magenta/green checkerboard (so leftover background and holes stand out).
2. **Pick the result that looks best.** It's already saved:
   `name-presets\<preset>\name-nobg.png`, next to your image.
3. Next time you have similar images, drag them straight onto that preset's `.cmd` file.

## Presets

| Drag onto | Use when | Settings |
|---|---|---|
| `remove-bg-ai.cmd` | Anything that isn't a plain background: 3D renders, photos, scenes with furniture/rooms. Start here. | AI, `isnet-general-use` |
| `remove-bg-ai-anime.cmd` | Anime / illustration art. Keeps line-art details and white parts of the character on white backgrounds. Not for 3D renders (it can remove almost everything). | AI, `isnet-anime` |
| `remove-bg-ai-best.cmd` | The most accurate AI, good on both renders and drawn art, finest hair/fur edges. Needs an optional download. Slow unless your GPU has more than 6 GB of memory: about 20 s per image on the CPU. | AI, `BiRefNet-general-epoch_244` |
| `remove-bg-flat.cmd` | Plain one-colour background. Keeps shadows/highlights that are close to the background colour. | defaults |
| `remove-bg-gradient.cmd` | The background shades across the image (vignette, soft lighting, darker on one side). | `-FollowGradient` |
| `remove-bg-holes.cmd` | The background shows through gaps in the subject (between arm and body, hair loops, rings). | `-RemoveEnclosed` |
| `remove-bg-gradient-holes.cmd` | Both of the above. | `-FollowGradient -RemoveEnclosed` |
| `remove-bg-sprite.cmd` | Pixel art / icons on an exact key colour (magenta, green screen). Hard edges, every key-coloured pixel removed. | `-RemoveEnclosed -Softness 0` |
| `remove-bg-compare.cmd` | Not sure — try them all side by side. | all of the above |
| `remove-bg-compare-quick.cmd` | Same, without the slow `ai-best` (a few seconds per image instead of ~30). | all but `ai-best` |

How to tell which you need, from the comparison sheet:

- **Furniture, walls or scenery left behind** → an `ai` preset: `ai` for 3D renders and photos,
  `ai-anime` for drawn/illustrated art (each can fail badly on the other kind), or `ai-best`, which handles
  both and gives the finest edges if you can wait ~20 s per image.
- **The AI removed part of the subject or kept a bit of background** on a plain background → a colour preset.
- **Patches of background left** (often a lighter/darker area) → a `gradient` preset.
- **Holes in the subject** where it's close to the background colour (dark shadows on a dark background,
  white highlights on white) → avoid the `holes`/`sprite` presets, and `gradient` if it's the one eating in.
- **Background still visible inside gaps** → a `holes` preset.

Each preset `.cmd` writes `name-nobg.png` next to the image. They also work from a terminal, with extra options:

```
remove-bg-gradient.cmd hero.png villain.png -Trim -Padding 8 -OutDir cutouts
remove-bg-compare.cmd art\*.png
```

Extra options: `-Trim`, `-Padding <px>`, `-OutDir <folder>`, `-BackgroundColor "#RRGGBB"`,
`-Tolerance <n>`, `-Preview` (`-Trim`, `-Padding`, `-OutDir` and `-BackgroundColor` also work with compare).

When started by double-click or drag-and-drop, the window stays open until you press a key so you can read
the output. Set `BGREMOVE_NOPAUSE=1` to skip that when running from a terminal.

To add or change a preset, edit `preset-definitions.ps1` (the comparison picks it up automatically) and copy
one of the `remove-bg-*.cmd` files, changing the `-Preset` name in it.

## AI engine

`remove-background-ai.ps1` runs `ai-bin\BgRemoveAi.exe`, which runs an ONNX model from `models\` with
Microsoft ONNX Runtime. It uses the GPU through DirectML (any DirectX 12 GPU, no CUDA needed) and falls back
to the CPU automatically.

```
powershell -ExecutionPolicy Bypass -File .\remove-background-ai.ps1 render.png [-Model isnet-general-use] [-OutDir dir] [-Trim] [-Padding 8] [-Preview] [-Cpu]
```

Output and options match the colour-key script (`name-nobg.png`, never overwrites the input).

### Models

The models are the open-source ones published by the [rembg](https://github.com/danielgatis/rembg) project.
`download-models.cmd` (no arguments) lists them and shows which are downloaded.

| Model | Size | Preset | Good for | Downloaded by |
|---|---|---|---|---|
| `isnet-general-use` | 170 MB | `ai` | 3D renders, photos, general use | `setup.cmd` |
| `isnet-anime` | 168 MB | `ai-anime` | anime and illustration art | `setup.cmd` |
| `BiRefNet-general-epoch_244` | 928 MB | `ai-best` | most accurate, renders and drawn art | `download-models.cmd BiRefNet-general-epoch_244` |

Other rembg models work too (e.g. `BiRefNet-general-bb_swin_v1_tiny-epoch_232`, 214 MB, a lighter BiRefNet,
or `u2net`): download `https://github.com/danielgatis/rembg/releases/download/v0.0.0/<model>.onnx` into
`models\` and use its name (without `.onnx`) as `-Model`, or add a preset for it in `preset-definitions.ps1`
(an entry with `Engine = 'ai'`) and copy a `.cmd` file. The comparison skips AI presets whose model isn't
downloaded.

### GPU and GPU memory

The program uses the graphics adapter with the most dedicated video memory — on a laptop with both
integrated and discrete graphics, the discrete card. The output names the GPU it used.

Example timings, measured on an NVIDIA RTX 3060 Laptop GPU (6 GB) with images up to 2400 × 2600:

| Model | GPU memory used | Time per image |
|---|---|---|
| `isnet-general-use`, `isnet-anime` | about 1 GB | 0.2–0.8 s |
| `BiRefNet-general-epoch_244` | more than 6 GB (it ran out at 5.8 GB) | ~20 s, on the CPU |

BiRefNet itself only needs about 2 GB of system memory on the CPU, but DirectML (the GPU path) needs much
more; a GPU with **8 GB or more** should fit it, which would bring it down to a second or two.

When a model runs out of GPU memory, the program finishes on the CPU and writes
`models\<model>.onnx.cpu-only`, so later runs of that model go straight to the CPU instead of trying the GPU
first. Delete that file to retry the GPU (after a driver update, or on a bigger GPU). `-Cpu` forces the CPU
for any model.

### Rebuilding

`ai\` is the source (C#, .NET 8, ONNX Runtime with DirectML). `setup.cmd` builds it; to rebuild after
changing it, run `setup.cmd -NoModels`, or:

```
dotnet publish ai -c Release -o ai-bin
```

Running the built program needs the .NET runtime 8 or newer.

## The colour-key script

`remove-background.ps1` does the colour-key work; the colour presets just pick its options.

```
powershell -ExecutionPolicy Bypass -File .\remove-background.ps1 <image(s)> [options]
```

Each input `name.ext` produces `name-nobg.png` next to it (or in `-OutDir`). Inputs are never overwritten.
Reads PNG, JPG, BMP, GIF and TIFF. Wildcards work: `art\*.jpg`.

| Option | Default | What it does |
|---|---|---|
| `-OutDir <folder>` | next to input | Where to write results (created if needed). |
| `-BackgroundColor "#RRGGBB"` | detected | The background colour, if detection picks the wrong one. |
| `-Tolerance <0-441>` | auto | How far (RGB distance) a colour can be from the background and still be removed. Auto measures it per image. |
| `-Softness <0-441>` | 30 | Width of the anti-aliased edge. `0` = hard edges. |
| `-FollowGradient` | off | Also follow a background that shades gradually across the image. |
| `-RemoveEnclosed` | off | Also remove background-coloured areas not connected to the edge. |
| `-Trim` | off | Crop to the subject. |
| `-Padding <px>` | 0 | Transparent margin to keep around the subject when trimming. |
| `-Preview` | off | Also write `name-nobg-preview.png`, the result on a checkerboard. |

Each file prints what it did:

```
hero.png -> hero-nobg.png  background #3B3638 (detected, 3/4 corners agree), tolerance 20.7 (auto), 34% removed, 328x358
```

### How it works

1. **Background colour** — a small patch is sampled in each corner. Patches that are uniform (not covering
   part of the subject) are compared, and the colour most of them share is used. If they disagree, it warns
   that the background may not be flat.
2. **Tolerance** (auto) — from how much those background corners vary, plus a margin: a perfectly flat
   background gets a tight tolerance (protecting subject colours close to it), a slightly uneven one a looser
   tolerance.
3. **Flood fill from the edges** — only background-coloured pixels **connected to the image border** are
   removed, so background-coloured details inside the subject stay solid. `-FollowGradient` lets the fill keep
   going through small colour steps (a shading background); `-RemoveEnclosed` also removes matching pixels
   anywhere.
4. **Soft edges** — pixels on the subject's outline get partial transparency based on how close they are to
   the background colour, and the background tint is removed from them, so they don't show a dark/light
   fringe on a different background.

### Fine-tuning

If no preset is quite right, start from the closest one and adjust:

| Problem | Try |
|---|---|
| A thin halo/fringe of background around the subject | raise `-Tolerance` a little (the output shows the auto value), or lower `-Softness` |
| Holes in the subject | lower `-Tolerance` |
| Edges look jagged | raise `-Softness` |
| Warning "corners don't share one colour" | the background isn't flat; pass `-BackgroundColor`, or try a `gradient` preset |
| Wrong colour detected (the subject fills the corners) | pass `-BackgroundColor` |

## Files

| File | |
|---|---|
| `remove-bg-*.cmd` | Drag-and-drop presets and the comparison. |
| `setup.cmd` / `setup.ps1` | One-time setup for the AI presets: build + default models. |
| `download-models.cmd` / `download-models.ps1` | Downloads and verifies AI models (no arguments: list them). |
| `remove-background-ai.ps1` | The AI background remover (runs `ai-bin\BgRemoveAi.exe`). |
| `ai\`, `ai-bin\`, `models\` | The AI program's source, the built program (created by setup), and the models (downloaded). |
| `remove-background.ps1` | The colour-key background remover. |
| `presets.ps1` | Runs one preset (`-Preset <name>`, `-List` shows them). |
| `compare-presets.ps1` | Runs all presets and builds the comparison sheet (`-Open` opens it, `-SkipSlow` leaves out `ai-best`). |
| `preset-definitions.ps1` | The preset list. |

## Notes

- The C# part of `remove-background.ps1` is compiled once per PowerShell window. If you edit it, bump the
  `BgRemove4` namespace everywhere it appears in the script, or open a new window, otherwise the old compiled
  version keeps being used.
- Images that already have transparency keep it; already-transparent pixels count as background.

## Credits

The AI models are downloaded from the [rembg](https://github.com/danielgatis/rembg) project's releases (MIT)
and are not part of this repository:

- **IS-Net** (`isnet-general-use`, `isnet-anime`) — [xuebinqin/DIS](https://github.com/xuebinqin/DIS)
  (Apache 2.0); anime model from [SkyTNT/anime-segmentation](https://github.com/SkyTNT/anime-segmentation).
- **BiRefNet** — [ZhengPeng7/BiRefNet](https://github.com/ZhengPeng7/BiRefNet) (MIT).

Runs on Microsoft [ONNX Runtime](https://github.com/microsoft/onnxruntime) with DirectML (MIT).
