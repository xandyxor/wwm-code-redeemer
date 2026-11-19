using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class RedeemHotkeys : NativeWindow, IDisposable {
    const int WM_HOTKEY=0x0312;
    const uint MOD_NOREPEAT=0x4000;
    readonly HashSet<int> keys=new HashSet<int>();
    readonly Queue<int> pending=new Queue<int>();
    public int LastError {get; private set;}
    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(IntPtr h,int id,uint modifiers,uint key);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(IntPtr h,int id);
    public RedeemHotkeys() {
        CreateHandle(new CreateParams {Caption="WWM helper global hotkeys",Parent=new IntPtr(-3)});
    }
    public bool Register(int key,uint modifiers) {
        if (keys.Contains(key)) throw new InvalidOperationException("Hotkey already registered by this receiver.");
        if (!RegisterHotKey(Handle,key,modifiers|MOD_NOREPEAT,(uint)key)) {
            LastError=Marshal.GetLastWin32Error(); return false;
        }
        keys.Add(key); LastError=0; return true;
    }
    public bool IsRegistered(int key) { return keys.Contains(key); }
    public int Take() { return pending.Count==0 ? 0 : pending.Dequeue(); }
    protected override void WndProc(ref Message m) {
        if (m.Msg==WM_HOTKEY && keys.Contains(m.WParam.ToInt32())) {
            pending.Enqueue(m.WParam.ToInt32()); return;
        }
        base.WndProc(ref m);
    }
    public void Dispose() {
        foreach(int key in keys) UnregisterHotKey(Handle,key);
        keys.Clear(); pending.Clear();
        if(Handle!=IntPtr.Zero) DestroyHandle();
        GC.SuppressFinalize(this);
    }
}
