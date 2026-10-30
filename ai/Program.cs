using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

// AI background removal with rembg's ONNX segmentation models.
// Usage: BgRemoveAi --model <file.onnx> [--outdir <dir>] [--trim] [--padding <px>] [--preview] [--cpu] <image>...
// Writes <name>-nobg.png (and <name>-nobg-preview.png with --preview), like remove-background.ps1.

string model = null, outDir = null;
bool trim = false, preview = false, cpu = false;
int padding = 0;
var inputs = new List<string>();
for (int i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--model": model = args[++i]; break;
        case "--outdir": outDir = args[++i]; break;
        case "--trim": trim = true; break;
        case "--padding": padding = int.Parse(args[++i]); break;
        case "--preview": preview = true; break;
        case "--cpu": cpu = true; break;
        default: inputs.Add(args[i]); break;
    }
}
if (model == null || inputs.Count == 0)
{
    Console.Error.WriteLine("Usage: BgRemoveAi --model <file.onnx> [--outdir <dir>] [--trim] [--padding <px>] [--preview] [--cpu] <image>...");
    return 2;
}
if (!File.Exists(model)) { Console.Error.WriteLine($"Model not found: {model}"); return 2; }

var spec = ModelSpec.For(Path.GetFileNameWithoutExtension(model));
var (session, device) = Open(model, cpu);
var inputName = session.InputMetadata.Keys.First();
var dims = session.InputMetadata[inputName].Dimensions;
int size = dims.Length == 4 && dims[2] > 0 ? dims[2] : spec.Size;

int failures = 0;
foreach (var path in inputs)
{
    try
    {
        var sw = Stopwatch.StartNew();
        if (!File.Exists(path)) throw new FileNotFoundException($"file not found: {Path.GetFullPath(path)}");
        using var source = LoadBitmap(path);
        float[] mask;
        try { mask = Predict(session, inputName, source, size, spec); }
        catch (OnnxRuntimeException e) when (device.StartsWith("GPU"))
        {
            // Usually out of GPU memory with the larger models: carry on with the CPU, and remember that.
            bool outOfMemory = e.Message.Contains("8007000E") || e.Message.Contains("memory", StringComparison.OrdinalIgnoreCase);
            Console.Error.WriteLine(outOfMemory
                ? "Not enough GPU memory for this model; switching to CPU (slower). Future runs of this model will use the CPU."
                : $"GPU failed ({e.Message.Split('\n')[0].Trim()}); switching to CPU.");
            if (outOfMemory) File.WriteAllText(model + ".cpu-only", "This model ran out of GPU memory; BgRemoveAi uses the CPU for it. Delete this file to retry the GPU.\r\n");
            session.Dispose();
            (session, device) = Open(model, true);
            mask = Predict(session, inputName, source, size, spec);
        }
        using var result = Apply(source, mask, trim, padding);

        var dir = outDir ?? Path.GetDirectoryName(Path.GetFullPath(path));
        Directory.CreateDirectory(dir);
        var outPath = Path.Combine(dir, Path.GetFileNameWithoutExtension(path) + "-nobg.png");
        if (string.Equals(Path.GetFullPath(outPath), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            throw new IOException("output would overwrite the input");
        result.Save(outPath, ImageFormat.Png);
        if (preview)
        {
            using var check = Checkerboard(result);
            check.Save(Path.Combine(dir, Path.GetFileNameWithoutExtension(path) + "-nobg-preview.png"), ImageFormat.Png);
        }
        int removed = (int)Math.Round(100.0 * mask.Count(a => a < 0.5f) / mask.Length);
        Console.WriteLine($"{Path.GetFileName(path)} -> {Path.GetFileName(outPath)}  model {Path.GetFileNameWithoutExtension(model)} on {device}, {removed}% removed, {result.Width}x{result.Height}, {sw.Elapsed.TotalSeconds:0.0}s");
    }
    catch (Exception e)
    {
        failures++;
        Console.Error.WriteLine($"{Path.GetFileName(path)}: {e.Message}");
    }
}
session.Dispose();
return failures == 0 ? 0 : 1;

// GPU through DirectML when available, otherwise CPU.
// A "<model>.cpu-only" file next to the model (written when the GPU ran out of memory) skips the GPU.
static (InferenceSession, string) Open(string model, bool cpu)
{
    if (!cpu && File.Exists(model + ".cpu-only"))
    {
        Console.Error.WriteLine($"Using CPU: this model didn't fit in GPU memory before (delete {Path.GetFileName(model)}.cpu-only to retry the GPU).");
        cpu = true;
    }
    if (!cpu)
    {
        try
        {
            var gpu = new SessionOptions
            {
                EnableMemoryPattern = false,
                ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_FATAL, // we report GPU failures ourselves
            };
            // DirectML's device 0 is the display adapter - on laptops that's usually the integrated GPU.
            // Use the adapter with the most dedicated video memory (the discrete GPU) instead.
            var (index, name) = Gpus.Best();
            gpu.AppendExecutionProvider_DML(index);
            return (new InferenceSession(model, gpu), name == null ? "GPU" : $"GPU ({name})");
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"GPU unavailable ({e.Message.Split('\n')[0]}), using CPU.");
        }
    }
    return (new InferenceSession(model, new SessionOptions()), "CPU");
}

static Bitmap LoadBitmap(string path)
{
    using var raw = Image.FromFile(path);
    var bmp = new Bitmap(raw.Width, raw.Height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) g.DrawImage(raw, new Rectangle(0, 0, raw.Width, raw.Height));
    return bmp;
}

// Foreground probability (0..1) for every pixel of the source image.
static float[] Predict(InferenceSession session, string inputName, Bitmap source, int size, ModelSpec spec)
{
    // Resize to the model's input, as RGB floats normalised like rembg does (divide by the image max, then mean/std).
    using var resized = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(resized))
    {
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.Clear(Color.Black);
        g.DrawImage(source, new Rectangle(0, 0, size, size));
    }
    var px = ReadBgra(resized);
    float max = 1;
    for (int i = 0; i < px.Length; i += 4) max = Math.Max(max, Math.Max(px[i], Math.Max(px[i + 1], px[i + 2])));

    var tensor = new DenseTensor<float>(new[] { 1, 3, size, size });
    for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            int i = (y * size + x) * 4;
            tensor[0, 0, y, x] = (px[i + 2] / max - spec.Mean[0]) / spec.Std[0];
            tensor[0, 1, y, x] = (px[i + 1] / max - spec.Mean[1]) / spec.Std[1];
            tensor[0, 2, y, x] = (px[i] / max - spec.Mean[2]) / spec.Std[2];
        }

    using var results = session.Run(new[] { NamedOnnxValue.CreateFromTensor(inputName, tensor) });
    var output = results.First().AsTensor<float>();
    var pred = new float[size * size];
    for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float v = output[0, 0, y, x];
            pred[y * size + x] = spec.Sigmoid ? 1f / (1f + MathF.Exp(-v)) : v;
        }
    float lo = pred.Min(), hi = pred.Max(), range = Math.Max(1e-6f, hi - lo);
    for (int i = 0; i < pred.Length; i++) pred[i] = (pred[i] - lo) / range;

    // Scale the mask back up to the source size.
    using var small = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    var maskPx = new byte[size * size * 4];
    for (int i = 0; i < pred.Length; i++) { byte v = (byte)Math.Round(pred[i] * 255); maskPx[i * 4] = maskPx[i * 4 + 1] = maskPx[i * 4 + 2] = v; maskPx[i * 4 + 3] = 255; }
    WriteBgra(small, maskPx);
    using var full = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(full))
    {
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        using var attrs = new ImageAttributes();
        attrs.SetWrapMode(WrapMode.TileFlipXY); // no dark seams at the edges
        g.DrawImage(small, new Rectangle(0, 0, full.Width, full.Height), 0, 0, size, size, GraphicsUnit.Pixel, attrs);
    }
    var fullPx = ReadBgra(full);
    var mask = new float[source.Width * source.Height];
    for (int i = 0; i < mask.Length; i++) mask[i] = fullPx[i * 4] / 255f;
    return mask;
}

// Mask -> alpha. Faint mask values are speckle, near-full ones are solid.
static Bitmap Apply(Bitmap source, float[] mask, bool trim, int padding)
{
    int w = source.Width, h = source.Height;
    var px = ReadBgra(source);
    for (int p = 0; p < mask.Length; p++)
    {
        float a = Math.Clamp((mask[p] - 0.04f) / 0.92f, 0f, 1f);
        px[p * 4 + 3] = (byte)Math.Round(px[p * 4 + 3] * a);
        if (px[p * 4 + 3] == 0) px[p * 4] = px[p * 4 + 1] = px[p * 4 + 2] = 0;
    }

    int left = 0, top = 0, right = w - 1, bottom = h - 1;
    if (trim)
    {
        left = w; top = h; right = -1; bottom = -1;
        for (int p = 0; p < mask.Length; p++)
        {
            if (px[p * 4 + 3] == 0) continue;
            int x = p % w, y = p / w;
            left = Math.Min(left, x); right = Math.Max(right, x); top = Math.Min(top, y); bottom = Math.Max(bottom, y);
        }
        if (right < 0) { left = top = 0; right = w - 1; bottom = h - 1; }
    }
    int pad = trim ? padding : 0;
    int outW = right - left + 1 + 2 * pad, outH = bottom - top + 1 + 2 * pad;
    var cropped = new byte[outW * outH * 4];
    for (int y = top; y <= bottom; y++)
        Buffer.BlockCopy(px, (y * w + left) * 4, cropped, ((y - top + pad) * outW + pad) * 4, (right - left + 1) * 4);
    var result = new Bitmap(outW, outH, PixelFormat.Format32bppArgb);
    WriteBgra(result, cropped);
    return result;
}

static Bitmap Checkerboard(Bitmap image)
{
    var preview = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
    using var g = Graphics.FromImage(preview);
    using var light = new SolidBrush(Color.FromArgb(255, 255, 0, 255));
    using var dark = new SolidBrush(Color.FromArgb(255, 0, 160, 0));
    const int cell = 12;
    for (int y = 0; y < image.Height; y += cell)
        for (int x = 0; x < image.Width; x += cell)
            g.FillRectangle(((x + y) / cell) % 2 == 0 ? light : dark, x, y, cell, cell);
    g.DrawImage(image, 0, 0, image.Width, image.Height);
    return preview;
}

static byte[] ReadBgra(Bitmap bmp)
{
    var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var bytes = new byte[bmp.Width * bmp.Height * 4];
    for (int y = 0; y < bmp.Height; y++)
        Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), bytes, y * bmp.Width * 4, bmp.Width * 4);
    bmp.UnlockBits(data);
    return bytes;
}

static void WriteBgra(Bitmap bmp, byte[] bytes)
{
    var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    for (int y = 0; y < bmp.Height; y++)
        Marshal.Copy(bytes, y * bmp.Width * 4, IntPtr.Add(data.Scan0, y * data.Stride), bmp.Width * 4);
    bmp.UnlockBits(data);
}

// Input size and normalisation per model family, matching rembg's sessions.
record ModelSpec(int Size, float[] Mean, float[] Std, bool Sigmoid)
{
    static readonly float[] ImageNetMean = { 0.485f, 0.456f, 0.406f }, ImageNetStd = { 0.229f, 0.224f, 0.225f };

    public static ModelSpec For(string name)
    {
        name = name.ToLowerInvariant();
        if (name.StartsWith("isnet")) return new(1024, new[] { 0.5f, 0.5f, 0.5f }, new[] { 1f, 1f, 1f }, false);
        if (name.StartsWith("birefnet")) return new(1024, ImageNetMean, ImageNetStd, true);
        return new(320, ImageNetMean, ImageNetStd, false); // u2net family
    }
}
