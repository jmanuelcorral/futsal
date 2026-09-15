#Requires -Version 7.2
Set-StrictMode -Version Latest

if (-not ('Futsal.Tooling.ValidationPowerRequest' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Futsal.Tooling {
    public sealed class ValidationPowerRequest : IDisposable {
        private enum RequestType { Display = 0, System = 1, Execution = 3 }
        [StructLayout(LayoutKind.Sequential)]
        private struct DetailedReason {
            public IntPtr Module;
            public uint Id, Count;
            public IntPtr Strings;
        }
        [StructLayout(LayoutKind.Explicit)]
        private struct ReasonUnion {
            [FieldOffset(0)] public IntPtr Simple;
            [FieldOffset(0)] public DetailedReason Detailed;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ReasonContext {
            public uint Version, Flags;
            public ReasonUnion Reason;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern SafeFileHandle PowerCreateRequest(ref ReasonContext context);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PowerSetRequest(SafeFileHandle handle, RequestType type);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PowerClearRequest(SafeFileHandle handle, RequestType type);

        private readonly SafeFileHandle handle;
        private readonly List<RequestType> requests = new List<RequestType>();
        public bool IsClosed { get { return handle.IsClosed; } }
        public bool DisplayRequested { get; }
        public bool SystemRequested { get { return requests.Contains(RequestType.System); } }
        public bool ExecutionRequested { get { return requests.Contains(RequestType.Execution); } }

        public ValidationPowerRequest(bool display) {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                throw new PlatformNotSupportedException("Godot validation power requests require Windows.");
            IntPtr text = Marshal.StringToHGlobalUni("Futsal: validacion local de Godot en curso");
            try {
                var reason = new ReasonContext {
                    Version = 0, Flags = 1, Reason = new ReasonUnion { Simple = text }
                };
                handle = PowerCreateRequest(ref reason);
                if (handle.IsInvalid) {
                    int error = Marshal.GetLastWin32Error();
                    handle.Dispose();
                    throw new Win32Exception(error, "PowerCreateRequest failed.");
                }
            }
            finally { Marshal.FreeHGlobal(text); }
            try {
                Request(RequestType.System);
                Request(RequestType.Execution);
                if (display) Request(RequestType.Display);
                DisplayRequested = display;
            }
            catch {
                // Closing this request object also releases any partially acquired requests.
                handle.Dispose();
                throw;
            }
        }

        private void Request(RequestType type) {
            if (!PowerSetRequest(handle, type))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "PowerSetRequest failed: " + type);
            requests.Add(type);
        }

        public void Dispose() {
            if (handle.IsClosed) return;
            Win32Exception failure = null;
            try {
                for (int index = requests.Count - 1; index >= 0; index--) {
                    if (!PowerClearRequest(handle, requests[index])) {
                        int error = Marshal.GetLastWin32Error();
                        if (failure == null)
                            failure = new Win32Exception(error, "PowerClearRequest failed: " + requests[index]);
                    }
                }
            }
            finally { handle.Dispose(); }
            if (failure != null) throw failure;
        }
    }
}
'@
}
