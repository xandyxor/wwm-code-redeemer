using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using System.IO;

public sealed class TestBlurSurface : Panel {
    public TestBlurSurface() { SetStyle(ControlStyles.Selectable,true); TabStop=true; }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); Focus(); }
}

public static class RedeemInputTest {
    static IDataObject SnapshotClipboard() {
        var source=Clipboard.GetDataObject();
        if(source==null) return null;
        var saved=new DataObject();
        foreach(string format in source.GetFormats(false)) {
            object value=source.GetData(format,false);
            if(value!=null) saved.SetData(format,false,value);
        }
        return saved;
    }
    [STAThread] public static void Main(string[] args) {
        try { string result=Run(); if(args.Length>0) File.WriteAllText(args[0],result); }
        catch(Exception e) { if(args.Length>0) File.WriteAllText(args[0],"FAIL: "+e.Message); Environment.ExitCode=1; }
    }
    static void Pump(int ms) {
        var until=DateTime.UtcNow.AddMilliseconds(ms);
        while(DateTime.UtcNow<until) { Application.DoEvents(); Thread.Sleep(10); }
    }
    static void Require(bool value,string message) { if(!value) throw new InvalidOperationException(message); }
    public static string Run() {
        RedeemNative.InitializeDpiAwareness();
        Application.EnableVisualStyles();
        using(var f=new Form()) {
            f.Text="WWM helper - local input test";
            f.StartPosition=FormStartPosition.CenterScreen;
            f.ClientSize=new Size(520,300);
            var button=new Button {Text="Test click",Bounds=new Rectangle(20,20,200,65)};
            var box=new TextBox {Bounds=new Rectangle(20,120,360,30)};
            var run=new Button {Text="Run input test",Bounds=new Rectangle(250,20,240,65)};
            var status=new Label {Text="Click Run input test. Only this window is used.",Bounds=new Rectangle(20,175,480,100)};
            var blank=new TestBlurSurface {Bounds=new Rectangle(20,90,360,25)};
            int clicks=0; button.Click+=(s,e)=>clicks++;
            bool testDialogKeys=false; int spaceCount=0,escapeCount=0;
            f.KeyPreview=true;
            f.KeyDown+=(s,e)=> {
                if(!testDialogKeys || box.Focused) return;
                if(e.KeyCode==Keys.Space) { spaceCount++; e.Handled=true; e.SuppressKeyPress=true; }
                if(e.KeyCode==Keys.Escape) { escapeCount++; e.Handled=true; e.SuppressKeyPress=true; }
            };
            string result=null;
            f.Controls.Add(button); f.Controls.Add(box); f.Controls.Add(run); f.Controls.Add(status); f.Controls.Add(blank);
            run.Click+=(s,e)=> {
                run.Enabled=false;
                var delay=new System.Windows.Forms.Timer {Interval=1000};
                delay.Tick+=(sender,eventArgs)=> {
                delay.Stop(); delay.Dispose();
                try {
                    Require(RedeemNative.GetForegroundWindow()==f.Handle,"Test window is not foreground; no input sent.");
                    using(var snapshot=RedeemNative.CaptureClient(f.Handle))
                        Require(snapshot.Width==f.ClientSize.Width && snapshot.Height==f.ClientSize.Height,"Client capture size mismatch.");
                    RedeemNative.MoveTo(f.Handle,100,50); Pump(150);
                    Require(clicks==0,"Move-only test unexpectedly clicked.");
                    Require(RedeemNative.LastPointerTrace.Contains("target="),"Move diagnostics missing.");
                    RedeemNative.Click(f.Handle,100,50); Pump(180);
                    Require(clicks==1,"Test button did not receive exactly one click.");
                    RedeemNative.Click(f.Handle,180,135); Pump(150);
                    RedeemNative.Text(f.Handle,"ABC123"); Pump(180);
                    Require(box.Text=="ABC123","Text input was not received.");
                    for(int i=0;i<3;i++) RedeemNative.Backspace(f.Handle);
                    Pump(100); Require(box.Text=="ABC","Backspace clearing failed.");
                    RedeemNative.Chord(f.Handle,0x41); Pump(100);
                    RedeemNative.Text(f.Handle,"XYZ789"); Pump(180);
                    Require(box.Text=="XYZ789","Ctrl+A text replacement failed.");
                    var clipboard=SnapshotClipboard();
                    try {
                        Clipboard.SetText("PASTE123");
                        RedeemNative.Chord(f.Handle,0x41); Pump(50);
                        RedeemNative.Chord(f.Handle,0x56); Pump(100);
                        Require(box.Text=="PASTE123","Whole-code paste did not replace old input.");
                    } finally {
                        if(Clipboard.ContainsText() && Clipboard.GetText()=="PASTE123") {
                            if(clipboard==null) Clipboard.Clear(); else Clipboard.SetDataObject(clipboard,true);
                        }
                    }
                    Require(box.Focused,"Expected input focus before blank-area click.");
                    RedeemNative.Click(f.Handle,180,105); Pump(100);
                    Require(!box.Focused,"Blank-area click did not remove input focus.");
                    testDialogKeys=true;
                    RedeemNative.TapScan(f.Handle,0x39); Pump(100);
                    Require(spaceCount==1 && box.Text=="PASTE123","Space confirmation after blur failed.");
                    RedeemNative.TapScan(f.Handle,0x01); Pump(100);
                    Require(escapeCount==1 && f.Visible,"Escape cancellation scan code failed.");
                    testDialogKeys=false;
                    result="Native input integration passed: whole-code paste, blank-area blur, Space, Escape, mouse, Unicode, capture; test window only.";
                    f.Text="WWM local input test - PASSED";
                    status.Text="PASSED: whole-code paste, blank-area click removes input focus, Space confirm, Escape cancel, mouse and capture. Close this window to finish.";
                } catch(Exception error) { result="FAIL: "+error.Message; status.Text=result; f.Text="WWM local input test - FAILED"; }
                };
                delay.Start();
            };
            f.ShowDialog();
            if(result==null || result.StartsWith("FAIL:")) throw new InvalidOperationException(result??"Test was not started.");
            return result;
        }
    }
}
