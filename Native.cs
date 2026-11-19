using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Drawing;
using System.Threading;
using System.Diagnostics;

public static class RedeemNative {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT {
        public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT {
        public ushort wVk, wScan; public uint dwFlags, time; public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Explicit)] struct UNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetPhysicalCursorPos(out POINT p);
    [DllImport("user32.dll", EntryPoint="GetCursorPos", SetLastError=true)] static extern bool NativeGetCursorPos(out POINT p);
    [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int awareness);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetClipCursor(out RECT r);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", EntryPoint="WindowFromPoint")] static extern IntPtr NativeWindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flag);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll", EntryPoint="GetClientRect")] static extern bool NativeGetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", EntryPoint="ScreenToClient")] static extern bool NativeScreenToClient(IntPtr h, ref POINT p);
    [DllImport("user32.dll", EntryPoint="ClientToScreen")] static extern bool NativeClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint n, INPUT[] input, int size);
    sealed class PhysicalScope : IDisposable {
        readonly IntPtr previous;
        public PhysicalScope() {
            try { previous=SetThreadDpiAwarenessContext(new IntPtr(-4)); }
            catch(EntryPointNotFoundException) { previous=IntPtr.Zero; }
        }
        public void Dispose() { if(previous!=IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static string InitializeDpiAwareness() {
        try { SetProcessDpiAwareness(2); } catch(EntryPointNotFoundException) {} catch(DllNotFoundException) {}
        try { if(SetThreadDpiAwarenessContext(new IntPtr(-4))!=IntPtr.Zero) return "PerMonitorV2 / physical pixels"; }
        catch(EntryPointNotFoundException) {}
        SetProcessDPIAware(); return "System aware / physical cursor";
    }
    public static bool GetCursorPos(out POINT p) { using(var scope=new PhysicalScope()) return NativeGetCursorPos(out p); }
    public static IntPtr WindowFromPoint(POINT p) { using(var scope=new PhysicalScope()) return NativeWindowFromPoint(p); }
    public static bool GetClientRect(IntPtr h,out RECT r) { using(var scope=new PhysicalScope()) return NativeGetClientRect(h,out r); }
    public static bool ScreenToClient(IntPtr h,ref POINT p) { using(var scope=new PhysicalScope()) return NativeScreenToClient(h,ref p); }
    public static bool ClientToScreen(IntPtr h,ref POINT p) { using(var scope=new PhysicalScope()) return NativeClientToScreen(h,ref p); }
    public static string LastPointerTrace {get; private set;}
    public static string Title(IntPtr h) { var b = new StringBuilder(512); GetWindowText(h,b,b.Capacity); return b.ToString(); }
    public static bool Down(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
    static INPUT Key(ushort vk, bool up) {
        var i = new INPUT(); i.type=1; i.u.ki.wVk=vk; i.u.ki.dwFlags=up?2u:0u; return i;
    }
    static void Send(INPUT[] inputs) {
        SetLastError(0);
        uint sent=SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(INPUT)));
        int error=Marshal.GetLastWin32Error();
        if (sent != inputs.Length) {
            string detail=error==0 ? "Windows 未提供錯誤碼；可能受到權限或遊戲輸入限制。" : new Win32Exception(error).Message;
            throw new InvalidOperationException(String.Format("SendInput 失敗：送出 {0}/{1}，Win32={2}。{3} 請確認工具與遊戲使用相同權限。",sent,inputs.Length,error,detail));
        }
    }
    static void RequireForeground(IntPtr h) {
        if (h==IntPtr.Zero || !IsWindow(h) || GetForegroundWindow()!=h)
            throw new InvalidOperationException("輸入目標已不在前景，停止送出輸入。");
    }
    public static int NormalizeCoordinate(int value,int origin,int size) {
        if (size<=0 || value<origin || (long)value >= (long)origin+size)
            throw new ArgumentOutOfRangeException("value","校準點不在目前螢幕範圍內。");
        return (int)Math.Min(65535, ((long)(value-origin)*65536+32768)/size);
    }
    static INPUT Move(int x,int y) {
        var i=new INPUT();
        i.u.mi.dx=NormalizeCoordinate(x,GetSystemMetrics(76),GetSystemMetrics(78));
        i.u.mi.dy=NormalizeCoordinate(y,GetSystemMetrics(77),GetSystemMetrics(79));
        i.u.mi.dwFlags=0xC001; // MOVE | ABSOLUTE | VIRTUALDESK
        return i;
    }
    static bool Near(POINT a,POINT b) { return Math.Abs((long)a.X-b.X)<=2 && Math.Abs((long)a.Y-b.Y)<=2; }
    public static POINT[] BuildMovePath(int startX,int startY,int endX,int endY,int steps) {
        if(steps<2 || steps>200) throw new ArgumentOutOfRangeException("steps");
        var path=new POINT[steps];
        for(int i=0;i<steps;i++) {
            double t=(double)(i+1)/steps;
            double eased=t*t*(3-2*t);
            path[i]=new POINT {
                X=(int)Math.Round(startX+((double)endX-startX)*eased),
                Y=(int)Math.Round(startY+((double)endY-startY)*eased)
            };
        }
        path[steps-1]=new POINT {X=endX,Y=endY};
        return path;
    }
    static string PointerTrace(IntPtr h,int x,int y,POINT target,POINT actual,RECT clip,string attempts) {
        var raw=new POINT(); GetPhysicalCursorPos(out raw);
        return String.Format("client=({0},{1}); target=({2},{3}); actual=({4},{5}); delta=({6},{7}); clip=({8},{9})-({10},{11}); virtual=({12},{13},{14},{15}); dpi={16}; physicalRaw=({18},{19}); {17}",
            x,y,target.X,target.Y,actual.X,actual.Y,(long)actual.X-target.X,(long)actual.Y-target.Y,
            clip.Left,clip.Top,clip.Right,clip.Bottom,GetSystemMetrics(76),GetSystemMetrics(77),GetSystemMetrics(78),GetSystemMetrics(79),GetDpiForWindow(h),attempts,raw.X,raw.Y);
    }
    static POINT PlanTarget(IntPtr h,int x,int y,out RECT clip) {
        RequireForeground(h);
            var rect=new RECT();
            if(!NativeGetClientRect(h,out rect) || x<0 || y<0 || x>=rect.Right || y>=rect.Bottom)
                throw new InvalidOperationException("校準點不在遊戲內容範圍內，請重新校準。");
            var p=new POINT {X=x,Y=y};
            if(!NativeClientToScreen(h,ref p)) throw new InvalidOperationException("ClientToScreen 失敗：請重新校準。");
            clip=new RECT();
            if(!GetClipCursor(out clip)) throw new InvalidOperationException("GetClipCursor 失敗，無法確認滑鼠可移動範圍。");
            if(p.X<clip.Left || p.Y<clip.Top || p.X>=clip.Right || p.Y>=clip.Bottom) {
                var actual=new POINT(); NativeGetCursorPos(out actual);
                LastPointerTrace=PointerTrace(h,x,y,p,actual,clip,"target outside cursor clip");
                throw new InvalidOperationException("校準點在目前滑鼠限制範圍外，未移動或點擊。請檢查遊戲視窗模式。 "+LastPointerTrace);
            }
            if(GetAncestor(NativeWindowFromPoint(p),2)!=h) throw new InvalidOperationException("校準點被其他視窗遮住，已停止移動與點擊。");
            return p;
    }
    public static string MoveTo(IntPtr h,int x,int y) {
        LastPointerTrace="";
        using(var scope=new PhysicalScope()) {
            RECT clip; var target=PlanTarget(h,x,y,out clip);
            var start=new POINT();
            if(!NativeGetCursorPos(out start)) throw new InvalidOperationException("無法讀取滑鼠起點，已停止移動。");
            int frames=Near(start,target)?2:20;
            int duration=frames==2?40:240;
            var path=BuildMovePath(start.X,start.Y,target.X,target.Y,frames);
            var movementClock=Stopwatch.StartNew();
            for(int i=0;i<path.Length;i++) {
                RequireForeground(h);
                if(Down(119)) throw new InvalidOperationException("已按 F8，滑鼠移動已暫停。");
                Send(new INPUT[]{Move(path[i].X,path[i].Y)});
                int remaining=(int)Math.Round((double)duration*(i+1)/frames-movementClock.Elapsed.TotalMilliseconds);
                if(remaining>0) Thread.Sleep(remaining);
            }
            RequireForeground(h);
            var actual=new POINT(); bool readable=NativeGetCursorPos(out actual);
            LastPointerTrace=PointerTrace(h,x,y,target,actual,clip,"smooth move; frames="+frames+"; durationMs="+movementClock.ElapsedMilliseconds+"; readback="+(readable && Near(actual,target)));
            return LastPointerTrace;
        }
    }
    public static void Click(IntPtr h,int x,int y) { Click(h,x,y,null); }
    public static void Click(IntPtr h, int x, int y,Action beforeClick) {
        MoveTo(h,x,y);
        if(beforeClick!=null) beforeClick();
        using(var scope=new PhysicalScope()) {
        RECT clip; var target=PlanTarget(h,x,y,out clip);
        // Put the destination in the button-down event itself; do not rely on cursor readback.
        var a=Move(target.X,target.Y); a.u.mi.dwFlags|=2;
        var b=new INPUT(); b.u.mi.dwFlags=4;
        try { Send(new INPUT[]{a}); Thread.Sleep(60); }
        finally { Send(new INPUT[]{b}); }
        }
    }
    public static void Chord(IntPtr h,ushort key) {
        RequireForeground(h);
        try {
            Send(new INPUT[]{Key(0x11,false)}); Thread.Sleep(15);
            RequireForeground(h);
            Send(new INPUT[]{Key(key,false)}); Thread.Sleep(30);
        } finally { Send(new INPUT[]{Key(key,true),Key(0x11,true)}); }
    }
    public static void Text(IntPtr h,string text) {
        for(int j=0;j<text.Length;j++) {
            RequireForeground(h);
            var a=new INPUT(); a.type=1; a.u.ki.wScan=text[j]; a.u.ki.dwFlags=4;
            var b=a; b.u.ki.dwFlags=6;
            try { Send(new INPUT[]{a}); Thread.Sleep(15); }
            finally { Send(new INPUT[]{b}); }
            Thread.Sleep(5);
        }
    }
    public static void Backspace(IntPtr h) {
        RequireForeground(h);
        var a=new INPUT(); a.type=1; a.u.ki.wScan=0x0E; a.u.ki.dwFlags=8;
        var b=a; b.u.ki.dwFlags=10;
        try { Send(new INPUT[]{a}); Thread.Sleep(10); }
        finally { Send(new INPUT[]{b}); }
    }
    public static void TapScan(IntPtr h,ushort scan) {
        RequireForeground(h);
        var down=new INPUT(); down.type=1; down.u.ki.wScan=scan; down.u.ki.dwFlags=8;
        var up=down; up.u.ki.dwFlags=10;
        try { Send(new INPUT[]{down}); Thread.Sleep(30); }
        finally { Send(new INPUT[]{up}); }
    }
    public static Bitmap CaptureClient(IntPtr h) {
        using(var scope=new PhysicalScope()) {
        RequireForeground(h);
        var rect=new RECT();
        if (!GetClientRect(h,out rect) || rect.Right<=0 || rect.Bottom<=0)
            throw new InvalidOperationException("無法擷取遊戲內容範圍。");
        var p=new POINT();
        if (!ClientToScreen(h,ref p)) throw new InvalidOperationException("無法換算遊戲擷取位置。");
        var image=new Bitmap(rect.Right,rect.Bottom);
        try {
            using(var g=Graphics.FromImage(image)) {
                g.CopyFromScreen(p.X,p.Y,0,0,image.Size,CopyPixelOperation.SourceCopy);
            }
            RequireForeground(h);
            return image;
        } catch { image.Dispose(); throw; }
        }
    }
    public static byte[] Signature(Bitmap image,int[] anchors) {
        if (anchors==null || anchors.Length!=6) throw new ArgumentException("需要三個校準點。");
        var result=new byte[315]; int n=0;
        for(int a=0;a<6;a+=2) for(int y=-2;y<=2;y++) for(int x=-3;x<=3;x++) {
            int px=Math.Max(0,Math.Min(image.Width-1,anchors[a]+x*6));
            int py=Math.Max(0,Math.Min(image.Height-1,anchors[a+1]+y*6));
            var c=image.GetPixel(px,py);
            result[n++]=c.R; result[n++]=c.G; result[n++]=c.B;
        }
        return result;
    }
    public static double Distance(byte[] a,byte[] b) {
        if (a==null || b==null || a.Length!=b.Length || a.Length==0) throw new ArgumentException("畫面樣本不完整。");
        long sum=0;
        for(int i=0;i<a.Length;i++) sum+=Math.Abs(a[i]-b[i]);
        return (double)sum/a.Length;
    }
    public static double BarBrightness(Bitmap image,int row) {
        if(row<0 || row>=image.Height) throw new ArgumentOutOfRangeException("row");
        double sum=0; int count=0;
        for(int i=0;i<9;i++) for(int j=-2;j<=2;j++) {
            int x=Math.Min(image.Width-1,(int)(image.Width*(0.22+i*0.01)));
            int y=Math.Max(0,Math.Min(image.Height-1,row+j*2));
            var c=image.GetPixel(x,y); sum+=0.299*c.R+0.587*c.G+0.114*c.B; count++;
        }
        return sum/count;
    }
}
