$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot 'Hotkeys.cs') -ReferencedAssemblies System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HotkeyMessageTest {
    [DllImport("user32.dll",SetLastError=true)] public static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
}
'@
$first=New-Object RedeemHotkeys
$second=New-Object RedeemHotkeys
$key=135 # Ctrl+Alt+Shift+F24 avoids claiming the user's F6/F8/F9 during tests.
try {
    if (!$first.Register($key,7)) { throw "Test hotkey registration failed: $($first.LastError)" }
    if ($second.Register($key,7)) { throw 'Conflicting registration unexpectedly succeeded.' }
    if (!$first.IsRegistered($key)) { throw 'Registered key was not tracked.' }
    if (!( [HotkeyMessageTest]::PostMessage($first.Handle,0x0312,[IntPtr]$key,[IntPtr]0))) { throw 'Could not post test message to owned receiver.' }
    for ($i=0;$i -lt 10;$i++) { [Windows.Forms.Application]::DoEvents() }
    if ($first.Take() -ne $key -or $first.Take() -ne 0) { throw 'Background message was not queued exactly once.' }
    if (!( [HotkeyMessageTest]::PostMessage($first.Handle,0x0312,[IntPtr]999,[IntPtr]0))) { throw 'Could not post ignored test message.' }
    for ($i=0;$i -lt 10;$i++) { [Windows.Forms.Application]::DoEvents() }
    if ($first.Take() -ne 0) { throw 'Unregistered key was accepted.' }
    $first.Dispose()
    if (!$second.Register($key,7)) { throw 'Disposing receiver did not release the global shortcut.' }
    Write-Output 'Hotkey tests passed: registration, conflict detection, background message dispatch, ignore unknown IDs, release on dispose.'
} finally { $first.Dispose(); $second.Dispose() }
