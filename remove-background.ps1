<#
.SYNOPSIS
Removes a flat (single-colour) background from images and saves them as transparent PNGs.

.DESCRIPTION
For each image, the background colour is taken from -BackgroundColor or detected from the four corners.
Background is removed by flood fill from the image edges, so areas inside the subject that happen to be
background-coloured stay solid (use -RemoveEnclosed to remove those too). The subject's outline gets
soft, anti-aliased edges, and the background colour is removed from those edge pixels so there's no
fringe on other backgrounds.

Output is "<name>-nobg.png" next to the input (or in -OutDir). Inputs are never overwritten.

.PARAMETER Path
Image file(s): PNG, JPG, BMP, GIF or TIFF. Wildcards allowed.

.PARAMETER OutDir
Folder for the results. Default: next to each input.

.PARAMETER BackgroundColor
Background colour as "#RRGGBB" (or "RRGGBB"). Default: detected from the corners.

.PARAMETER Tolerance
Colour distance from the background (0-441, RGB) at or below which a pixel counts as background.
Default: measured per image from how much the background varies in the corners (shown in the output).
Raise it if a halo or patches of background remain; lower it if dark/light parts of the subject that are
close to the background colour get removed.

.PARAMETER Softness
Width of the soft edge, as colour distance above Tolerance: outline pixels fade from transparent at
Tolerance to opaque at Tolerance + Softness. Default 30. Use 0 for hard edges.

.PARAMETER RemoveEnclosed
Also remove background-coloured areas that aren't connected to the image edge (gaps between arm and body).
Careful: this also removes parts of the subject that match the background.

.PARAMETER FollowGradient
For backgrounds that shade gradually (e.g. darker towards one side): keep removing background beyond
Tolerance as long as the colour changes only slightly from one pixel to the next. Can leak into soft,
background-coloured shading in the subject, so check the result.

.PARAMETER Trim
Crop the result to the subject's bounds.

.PARAMETER Padding
Transparent pixels to keep around the subject when trimming. Default 0.

.PARAMETER Preview
Also write "<name>-nobg-preview.png": the result on a checkerboard, to check the edges.

.EXAMPLE
.\remove-background.ps1 portrait.png

.EXAMPLE
.\remove-background.ps1 art\*.jpg -OutDir cutouts -Trim -Padding 8 -Preview

.EXAMPLE
.\remove-background.ps1 photo.jpg -BackgroundColor "#F4F4F4" -Tolerance 30 -Softness 20
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)] [string[]] $Path,
    [string] $OutDir,
    [string] $BackgroundColor,
    [ValidateRange(-1, 441)] [double] $Tolerance = -1,   # -1 = measure per image
    [ValidateRange(0, 441)] [double] $Softness = 30,
    [switch] $RemoveEnclosed,
    [switch] $FollowGradient,
    [switch] $Trim,
    [ValidateRange(0, 10000)] [int] $Padding = 0,
    [switch] $Preview
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# The pixel work, compiled once per PowerShell session (PowerShell loops are far too slow for photos).
# C# 5: this must compile with Windows PowerShell 5.1's built-in compiler.
# A compiled type can't be replaced within a session, so the namespace carries a version: bump it when
# changing the C# below, or an already-open PowerShell window would keep using the old code.
if (-not ('BgRemove4.Remover' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;

namespace BgRemove4
{
    public class Result
    {
        public Bitmap Image;
        public Color Background;
        public bool Detected;
        public int CornersAgreeing;   // plain-background corners whose colour is close to the background
        public int CornersDisagreeing; // plain-background corners of a clearly different colour
        public double Tolerance;      // the tolerance used (measured when auto)
        public bool AutoTolerance;
        public int RemovedPercent;
    }

    public static class Remover
    {
        // Corners further than this from the background colour are treated as subject, not background.
        const double CornerAgreeDistance = 60;
        // A corner patch whose pixels vary more than this (95th percentile) isn't plain background.
        const double UniformCornerNoise = 15;
        // Auto tolerance when no corner is plain background.
        const double DefaultTolerance = 20;
        // followGradient: the fill may step to a pixel this close in colour to its background neighbour,
        // up to GradientReach x tolerance from the background colour.
        const double GradientStep = 4;
        const double GradientReach = 3;

        // tolerance < 0 = measure it from how much the background varies in the corners.
        public static Result Process(Bitmap source, Color? background, double tolerance, double softness,
                                     bool removeEnclosed, bool followGradient, bool trim, int padding)
        {
            int w = source.Width, h = source.Height, n = w * h;
            byte[] px = ReadBgra(source);
            var result = new Result();

            int size = Math.Max(2, Math.Min(16, Math.Min(w, h) / 20));
            var corners = CornerPatches(px, w, h, size);

            // A corner that's mostly one colour is background; one covering part of the subject varies a lot.
            var uniform = corners.Where(c => c.Noise <= UniformCornerNoise).ToArray();
            var candidates = uniform.Length > 0 ? uniform : corners;

            int bgR, bgG, bgB;
            if (background.HasValue)
            {
                bgR = background.Value.R; bgG = background.Value.G; bgB = background.Value.B;
            }
            else
            {
                MedianCorner(candidates, out bgR, out bgG, out bgB);
                result.Detected = true;
            }
            result.Background = Color.FromArgb(bgR, bgG, bgB);

            // How much the background varies: furthest uniform background corner, plus its own noise.
            double variation = 0;
            foreach (var c in uniform)
            {
                double d = Distance(c.Average, bgR, bgG, bgB);
                if (d > CornerAgreeDistance) { result.CornersDisagreeing++; continue; }
                result.CornersAgreeing++;
                variation = Math.Max(variation, d + c.Noise);
            }
            if (tolerance < 0)
            {
                result.AutoTolerance = true;
                tolerance = result.CornersAgreeing == 0 ? DefaultTolerance : Math.Max(6, Math.Min(80, variation * 1.25 + 6));
            }
            result.Tolerance = tolerance;

            // Colour distance of every pixel from the background; already-transparent pixels count as background.
            var dist = new double[n];
            for (int p = 0; p < n; p++)
            {
                int i = p * 4;
                if (px[i + 3] == 0) { dist[p] = 0; continue; }
                double db = px[i] - bgB, dg = px[i + 1] - bgG, dr = px[i + 2] - bgR;
                dist[p] = Math.Sqrt(dr * dr + dg * dg + db * db);
            }

            // Background = pixels within tolerance connected to the image edge (following a gradient if asked),
            // plus, with removeEnclosed, every pixel within tolerance anywhere.
            // The soft edge lies outside it: outline pixels between tolerance and tolerance + softness.
            double threshold = tolerance;
            var isBg = new bool[n];
            var queue = new Queue<int>();
            for (int x = 0; x < w; x++) { Seed(x, isBg, dist, threshold, queue); Seed((h - 1) * w + x, isBg, dist, threshold, queue); }
            for (int y = 0; y < h; y++) { Seed(y * w, isBg, dist, threshold, queue); Seed(y * w + w - 1, isBg, dist, threshold, queue); }
            double reach = threshold * GradientReach;
            while (queue.Count > 0)
            {
                int p = queue.Dequeue(), x = p % w;
                if (p >= w) Spread(p, p - w, px, isBg, dist, threshold, followGradient, reach, queue);
                if (p < n - w) Spread(p, p + w, px, isBg, dist, threshold, followGradient, reach, queue);
                if (x > 0) Spread(p, p - 1, px, isBg, dist, threshold, followGradient, reach, queue);
                if (x < w - 1) Spread(p, p + 1, px, isBg, dist, threshold, followGradient, reach, queue);
            }
            if (removeEnclosed)
                for (int p = 0; p < n; p++) if (dist[p] <= threshold) isBg[p] = true;

            int removed = 0;
            var output = new byte[n * 4];
            for (int p = 0; p < n; p++)
            {
                int i = p * 4, x = p % w;
                if (isBg[p]) { removed++; continue; }

                // Solid, except on the outline, where alpha follows the colour distance for a soft edge.
                double a = 1;
                double refR = bgR, refG = bgG, refB = bgB, edgeDist = dist[p];
                bool onEdge = (x > 0 && isBg[p - 1]) || (x < w - 1 && isBg[p + 1]) || (p >= w && isBg[p - w]) || (p < n - w && isBg[p + w]);
                if (onEdge)
                {
                    if (followGradient)
                    {
                        // Compare with the background right next to it, which may differ from the corners' colour.
                        LocalBackground(p, w, n, px, isBg, out refR, out refG, out refB);
                        double dr0 = px[i + 2] - refR, dg0 = px[i + 1] - refG, db0 = px[i] - refB;
                        edgeDist = Math.Min(edgeDist, Math.Sqrt(dr0 * dr0 + dg0 * dg0 + db0 * db0));
                    }
                    a = softness <= 0 ? (edgeDist > tolerance ? 1 : 0) : Clamp01((edgeDist - tolerance) / softness);
                }
                a *= px[i + 3] / 255.0;
                if (a <= 0) { removed++; continue; }

                double b = px[i], g = px[i + 1], r = px[i + 2];
                if (a < 1)
                {
                    // Undo the background showing through the edge pixel, so it doesn't fringe on other backgrounds.
                    b = (b - (1 - a) * refB) / a; g = (g - (1 - a) * refG) / a; r = (r - (1 - a) * refR) / a;
                }
                output[i] = ToByte(b); output[i + 1] = ToByte(g); output[i + 2] = ToByte(r);
                output[i + 3] = ToByte(a * 255);
            }
            result.RemovedPercent = (int)Math.Round(100.0 * removed / n);

            int left = 0, top = 0, right = w - 1, bottom = h - 1;
            if (trim && removed < n)
            {
                left = w; top = h; right = -1; bottom = -1;
                for (int p = 0; p < n; p++)
                {
                    if (output[p * 4 + 3] == 0) continue;
                    int x = p % w, y = p / w;
                    if (x < left) left = x; if (x > right) right = x;
                    if (y < top) top = y; if (y > bottom) bottom = y;
                }
            }
            int outW = right - left + 1 + (trim ? 2 * padding : 0);
            int outH = bottom - top + 1 + (trim ? 2 * padding : 0);
            int offset = trim ? padding : 0;

            var cropped = new byte[outW * outH * 4];
            for (int y = top; y <= bottom; y++)
                Buffer.BlockCopy(output, (y * w + left) * 4, cropped, ((y - top + offset) * outW + offset) * 4, (right - left + 1) * 4);
            result.Image = WriteBgra(cropped, outW, outH);
            return result;
        }

        class Patch
        {
            public double[] Average;          // r, g, b
            public double Noise;              // 95th percentile distance of its pixels from Average
            public List<double[]> Pixels = new List<double[]>();
        }

        static Patch[] CornerPatches(byte[] px, int w, int h, int size)
        {
            var patches = new Patch[4];
            int[][] origins = { new[] { 0, 0 }, new[] { w - size, 0 }, new[] { 0, h - size }, new[] { w - size, h - size } };
            for (int c = 0; c < 4; c++)
            {
                var patch = new Patch();
                double sr = 0, sg = 0, sb = 0;
                for (int y = origins[c][1]; y < origins[c][1] + size; y++)
                    for (int x = origins[c][0]; x < origins[c][0] + size; x++)
                    {
                        int i = (y * w + x) * 4;
                        patch.Pixels.Add(new double[] { px[i + 2], px[i + 1], px[i] });
                        sb += px[i]; sg += px[i + 1]; sr += px[i + 2];
                    }
                int count = patch.Pixels.Count;
                patch.Average = new[] { sr / count, sg / count, sb / count };
                var spread = patch.Pixels.Select(p => Distance(p, patch.Average)).OrderBy(d => d).ToList();
                patch.Noise = spread[(int)((count - 1) * 0.95)];
                patches[c] = patch;
            }
            return patches;
        }

        // The corner colour closest to the others (a median).
        static void MedianCorner(Patch[] corners, out int r, out int g, out int b)
        {
            int best = 0; double bestTotal = double.MaxValue;
            for (int c = 0; c < corners.Length; c++)
            {
                double total = 0;
                for (int o = 0; o < corners.Length; o++) total += Distance(corners[c].Average, corners[o].Average);
                if (total < bestTotal) { bestTotal = total; best = c; }
            }
            var a = corners[best].Average;
            r = (int)Math.Round(a[0]); g = (int)Math.Round(a[1]); b = (int)Math.Round(a[2]);
        }

        static double Distance(double[] a, int r, int g, int b)
        {
            double dr = a[0] - r, dg = a[1] - g, db = a[2] - b;
            return Math.Sqrt(dr * dr + dg * dg + db * db);
        }

        static void Seed(int p, bool[] isBg, double[] dist, double threshold, Queue<int> queue)
        {
            if (isBg[p] || dist[p] > threshold) return;
            isBg[p] = true;
            queue.Enqueue(p);
        }

        // From background pixel p to neighbour q: within tolerance, or (following a gradient) a tiny colour
        // step from p while still within reach of the background colour.
        static void Spread(int p, int q, byte[] px, bool[] isBg, double[] dist, double threshold,
                           bool followGradient, double reach, Queue<int> queue)
        {
            if (isBg[q]) return;
            bool ok = dist[q] <= threshold;
            if (!ok && followGradient && dist[q] <= reach)
            {
                int i = p * 4, j = q * 4;
                double db = px[i] - px[j], dg = px[i + 1] - px[j + 1], dr = px[i + 2] - px[j + 2];
                ok = Math.Sqrt(dr * dr + dg * dg + db * db) <= GradientStep;
            }
            if (!ok) return;
            isBg[q] = true;
            queue.Enqueue(q);
        }

        // Average original colour of the background pixels next to p.
        static void LocalBackground(int p, int w, int n, byte[] px, bool[] isBg, out double r, out double g, out double b)
        {
            r = g = b = 0; int count = 0, x = p % w;
            int[] neighbours = { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, p >= w ? p - w : -1, p < n - w ? p + w : -1 };
            foreach (int q in neighbours)
            {
                if (q < 0 || !isBg[q]) continue;
                b += px[q * 4]; g += px[q * 4 + 1]; r += px[q * 4 + 2]; count++;
            }
            if (count > 0) { r /= count; g /= count; b /= count; }
        }

        static double Distance(double[] a, double[] b)
        {
            double dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
            return Math.Sqrt(dr * dr + dg * dg + db * db);
        }

        static double Clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
        static byte ToByte(double v) { return (byte)(v < 0 ? 0 : v > 255 ? 255 : Math.Round(v)); }

        static byte[] ReadBgra(Bitmap bmp)
        {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            using (var copy = new Bitmap(bmp.Width, bmp.Height, PixelFormat.Format32bppArgb))
            {
                using (var gfx = Graphics.FromImage(copy)) gfx.DrawImage(bmp, rect);
                var data = copy.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var bytes = new byte[bmp.Width * bmp.Height * 4];
                for (int y = 0; y < bmp.Height; y++)
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), bytes, y * bmp.Width * 4, bmp.Width * 4);
                copy.UnlockBits(data);
                return bytes;
            }
        }

        static Bitmap WriteBgra(byte[] bytes, int w, int h)
        {
            var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            for (int y = 0; y < h; y++)
                Marshal.Copy(bytes, y * w * 4, IntPtr.Add(data.Scan0, y * data.Stride), w * 4);
            bmp.UnlockBits(data);
            return bmp;
        }

        // The image over a checkerboard, for checking edges.
        public static Bitmap Checkerboard(Bitmap image)
        {
            var preview = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
            using (var gfx = Graphics.FromImage(preview))
            using (var light = new SolidBrush(Color.FromArgb(255, 255, 0, 255)))
            using (var dark = new SolidBrush(Color.FromArgb(255, 0, 160, 0)))
            {
                const int cell = 12;
                for (int y = 0; y < image.Height; y += cell)
                    for (int x = 0; x < image.Width; x += cell)
                        gfx.FillRectangle(((x + y) / cell) % 2 == 0 ? light : dark, x, y, cell, cell);
                gfx.DrawImage(image, 0, 0, image.Width, image.Height);
            }
            return preview;
        }
    }
}
'@
}

function ConvertTo-Color([string] $hex) {
    $h = $hex.Trim().TrimStart('#')
    if ($h -notmatch '^[0-9a-fA-F]{6}$') { throw "BackgroundColor must look like #RRGGBB, got '$hex'" }
    [System.Drawing.Color]::FromArgb([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

$background = if ($BackgroundColor) { [Nullable[System.Drawing.Color]](ConvertTo-Color $BackgroundColor) } else { [Nullable[System.Drawing.Color]]$null }

$files = foreach ($p in $Path) { Get-Item -Path $p | Where-Object { -not $_.PSIsContainer } }
if (-not $files) { throw "No files match: $($Path -join ', ')" }
if ($OutDir) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null; $OutDir = (Resolve-Path $OutDir).Path }

foreach ($file in $files) {
    $dir = if ($OutDir) { $OutDir } else { $file.DirectoryName }
    $out = Join-Path $dir ($file.BaseName + '-nobg.png')
    if ($out -eq $file.FullName) { Write-Warning "Skipping $($file.Name): output would overwrite it"; continue }

    $source = [System.Drawing.Bitmap]::FromFile($file.FullName)
    try {
        $result = [BgRemove4.Remover]::Process($source, $background, $Tolerance, $Softness, [bool]$RemoveEnclosed, [bool]$FollowGradient, [bool]$Trim, $Padding)
    } finally { $source.Dispose() }

    try {
        $result.Image.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bg = '#{0:X2}{1:X2}{2:X2}' -f $result.Background.R, $result.Background.G, $result.Background.B
        $how = if ($result.Detected) { "detected, $($result.CornersAgreeing)/4 corners agree" } else { 'given' }
        $tol = '{0:0.#}{1}' -f $result.Tolerance, $(if ($result.AutoTolerance) { ' (auto)' } else { '' })
        Write-Host ("{0} -> {1}  background {2} ({3}), tolerance {4}, {5}% removed, {6}x{7}" -f $file.Name, (Split-Path $out -Leaf), $bg, $how, $tol, $result.RemovedPercent, $result.Image.Width, $result.Image.Height)
        if ($result.CornersAgreeing -eq 0 -or $result.CornersDisagreeing -ge $result.CornersAgreeing) {
            Write-Warning "$($file.Name): the corners don't share one colour; the background may not be flat. Check the result, or pass -BackgroundColor."
        }
        if ($Preview) {
            $previewImage = [BgRemove4.Remover]::Checkerboard($result.Image)
            try { $previewImage.Save((Join-Path $dir ($file.BaseName + '-nobg-preview.png')), [System.Drawing.Imaging.ImageFormat]::Png) }
            finally { $previewImage.Dispose() }
        }
    } finally { $result.Image.Dispose() }
}
