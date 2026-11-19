using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class RedeemRights {
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,int length,out int required);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid,uint index);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    public static int ProcessIntegrity(int pid) {
        IntPtr process=OpenProcess(0x1000,false,(uint)pid),token=IntPtr.Zero,buffer=IntPtr.Zero;
        if(process==IntPtr.Zero) return -1;
        try {
            if(!OpenProcessToken(process,8,out token)) return -1;
            int length;
            GetTokenInformation(token,25,IntPtr.Zero,0,out length);
            if(length<=0) return -1;
            buffer=Marshal.AllocHGlobal(length);
            if(!GetTokenInformation(token,25,buffer,length,out length)) return -1;
            IntPtr sid=Marshal.ReadIntPtr(buffer);
            byte count=Marshal.ReadByte(GetSidSubAuthorityCount(sid));
            if(count==0) return -1;
            return Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(count-1)));
        } finally {
            if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer);
            if(token!=IntPtr.Zero) CloseHandle(token);
            CloseHandle(process);
        }
    }
    public static int OwnIntegrity() { return ProcessIntegrity(Process.GetCurrentProcess().Id); }
    public static int WindowIntegrity(IntPtr window) {
        uint pid; GetWindowThreadProcessId(window,out pid);
        return pid==0 ? -1 : ProcessIntegrity((int)pid);
    }
    public static bool NeedsElevation(int own,int target) { return own>=0 && target>=0x3000 && target>own; }
    public static string Label(int value) {
        if(value<0) return "unknown";
        if(value>=0x4000) return "System";
        if(value>=0x3000) return "High / administrator";
        if(value>=0x2000) return "Medium / normal";
        return "Low";
    }
}
