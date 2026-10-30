using System.Runtime.InteropServices;

// Picks the graphics adapter for DirectML. DirectML device ids follow DXGI's EnumAdapters order, where the
// first adapter is the one driving the display - on Optimus-style laptops the integrated GPU. The adapter
// with the most dedicated video memory is the discrete GPU.
static class Gpus
{
    public static (int Index, string Name) Best()
    {
        int best = 0; string bestName = null; ulong bestMemory = 0;
        try
        {
            var iid = typeof(IDXGIFactory1).GUID;
            if (CreateDXGIFactory1(ref iid, out var factoryObj) != 0) return (0, null);
            var factory = (IDXGIFactory1)factoryObj;
            for (int i = 0; ; i++)
            {
                if (factory.EnumAdapters1(i, out var adapter) != 0) break; // DXGI_ERROR_NOT_FOUND: no more adapters
                adapter.GetDesc1(out var desc);
                Marshal.ReleaseComObject(adapter);
                if ((desc.Flags & 2) != 0) continue; // DXGI_ADAPTER_FLAG_SOFTWARE (Microsoft Basic Render Driver)
                ulong memory = (ulong)desc.DedicatedVideoMemory;
                if (bestName == null || memory > bestMemory) { best = i; bestName = desc.Description; bestMemory = memory; }
            }
            Marshal.ReleaseComObject(factory);
        }
        catch { /* fall back to DirectML's default */ }
        return (best, bestName);
    }

    [DllImport("dxgi.dll")]
    static extern int CreateDXGIFactory1(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object factory);

    // Only EnumAdapters1 is called; the other entries keep the vtable order of IDXGIObject/IDXGIFactory.
    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIFactory1
    {
        void SetPrivateData();
        void SetPrivateDataInterface();
        void GetPrivateData();
        void GetParent();
        void EnumAdapters();
        void MakeWindowAssociation();
        void GetWindowAssociation();
        void CreateSwapChain();
        void CreateSoftwareAdapter();
        [PreserveSig] int EnumAdapters1(int index, out IDXGIAdapter1 adapter);
        void IsCurrent();
    }

    [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIAdapter1
    {
        void SetPrivateData();
        void SetPrivateDataInterface();
        void GetPrivateData();
        void GetParent();
        void EnumOutputs();
        void GetDesc();
        void CheckInterfaceSupport();
        [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 desc);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DXGI_ADAPTER_DESC1
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId, DeviceId, SubSysId, Revision;
        public nuint DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public uint AdapterLuidLow;
        public int AdapterLuidHigh;
        public uint Flags;
    }
}
