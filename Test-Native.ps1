param([switch]$InputTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path @((Join-Path $PSScriptRoot 'Native.cs'),(Join-Path $PSScriptRoot 'NativeTest.cs')) -ReferencedAssemblies System.Drawing,System.Windows.Forms

if ([RedeemNative]::NormalizeCoordinate(-1920,-1920,3840) -ne 8) { throw 'Negative-monitor origin conversion failed.' }
if ([RedeemNative]::NormalizeCoordinate(0,-1920,3840) -ne 32776) { throw 'Virtual desktop midpoint conversion failed.' }
if ([RedeemNative]::NormalizeCoordinate(1919,-1920,3840) -gt 65535) { throw 'Virtual desktop endpoint overflow.' }
$rejected=$false
try { $null=[RedeemNative]::NormalizeCoordinate(1920,-1920,3840) } catch { $rejected=$true }
if (!$rejected) { throw 'Off-screen coordinate was accepted.' }
$path=[RedeemNative]::BuildMovePath(-100,300,900,100,20)
if($path.Length -ne 20 -or $path[19].X -ne 900 -or $path[19].Y -ne 100) { throw 'Smooth movement did not end at the exact target.' }
if($path[0].X -ge 0 -or $path[0].Y -le 290) { throw 'First movement frame must not jump to the target.' }
$previousX=-100; $previousY=300
foreach($point in $path) {
    if($point.X -lt $previousX -or $point.Y -gt $previousY -or $point.X -gt 900 -or $point.Y -lt 100) { throw 'Smooth path reversed or overshot its target.' }
    $previousX=$point.X; $previousY=$point.Y
}
$still=[RedeemNative]::BuildMovePath(50,50,50,50,2)
if($still[0].X -ne 50 -or $still[1].Y -ne 50) { throw 'Stationary movement introduced drift.' }
$rejected=$false
try { [RedeemNative]::Click([IntPtr]::Zero,0,0) } catch { $rejected=$true }
if (!$rejected) { throw 'Invalid click target was accepted.' }
$rejected=$false
try { $null=[RedeemNative]::MoveTo([IntPtr]::Zero,0,0) } catch { $rejected=$true }
if (!$rejected) { throw 'Invalid move-only target was accepted.' }
$rejected=$false
try { [RedeemNative]::TapScan([IntPtr]::Zero,0x39) } catch { $rejected=$true }
if (!$rejected) { throw 'Keyboard confirmation accepted an invalid target.' }
$taskCursor=New-Object RedeemNative+POINT
if (![RedeemNative]::GetCursorPos([ref]$taskCursor)) { throw 'Physical cursor query failed.' }
$a=New-Object Drawing.Bitmap(100,100)
$b=New-Object Drawing.Bitmap(100,100)
try {
    $ga=[Drawing.Graphics]::FromImage($a); $ga.Clear([Drawing.Color]::FromArgb(200,200,200)); $ga.Dispose()
    $gb=[Drawing.Graphics]::FromImage($b); $gb.Clear([Drawing.Color]::FromArgb(60,60,60)); $gb.Dispose()
    $anchors=[int[]]@(0,0,50,50,99,99)
    $sa=[RedeemNative]::Signature($a,$anchors); $sb=[RedeemNative]::Signature($b,$anchors)
    if ($sa.Length -ne 315 -or [RedeemNative]::Distance($sa,$sa) -ne 0 -or [RedeemNative]::Distance($sa,$sb) -ne 140) { throw 'Screen signature comparison failed.' }
    if ([Math]::Abs([RedeemNative]::BarBrightness($a,50)-200) -gt 0.1) { throw 'Footer brightness sampling failed.' }
} finally { $a.Dispose(); $b.Dispose() }
Write-Output 'Native tests passed: monitor coordinate mapping, target guard, screen signatures.'
if ($InputTest) { [RedeemInputTest]::Run() }
