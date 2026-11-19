param([switch]$SelfTest, [string]$PreviewPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path @((Join-Path $PSScriptRoot 'Native.cs'),(Join-Path $PSScriptRoot 'Hotkeys.cs')) -ReferencedAssemblies System.Drawing,System.Windows.Forms
if (!('RedeemRights' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Rights.cs') }
$script:dpiMode=[RedeemNative]::InitializeDpiAwareness()
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:instanceMutex=$null
if (!$SelfTest) {
    $oldTools=@(Get-Process -Name powershell,pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.MainWindowTitle -match '^燕雲十六聲｜序號兌換助手' })
    if ($oldTools.Count -gt 0) {
        [void][Windows.Forms.MessageBox]::Show('已經有兌換助手視窗開著。請先關閉舊工具，再重新開啟新版，以釋放 F6／F8／F9。','請先關閉舊工具')
        exit 0
    }
    try {
        $script:instanceMutex=New-Object Threading.Mutex($false,'Local\WWMCodeHelper.SingleInstance')
        try { $ownsInstance=$script:instanceMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsInstance=$true }
    } catch [UnauthorizedAccessException] { $ownsInstance=$false }
    if (!$ownsInstance) {
        if ($null -ne $script:instanceMutex) { $script:instanceMutex.Dispose() }
        [void][Windows.Forms.MessageBox]::Show('兌換助手已在執行，這次不會再開第二個視窗。請先關閉舊工具後重試。','工具已在執行')
        exit 0
    }
}

$script:dataDir = Join-Path $PSScriptRoot 'data'
$script:historyPath = Join-Path $script:dataDir 'attempts.jsonl'
$script:settingsPath = Join-Path $script:dataDir 'settings.json'
$script:history = @()
$script:profiles = @()
$script:points = @{}
$script:target = [IntPtr]::Zero
$script:targetWidth = 0
$script:targetHeight = 0
$script:captureName = ''
$script:captureDue = [datetime]::MaxValue
$script:captureSeconds = -1
$script:hotkeys = $null
$script:phase = 'idle'
$script:queue = @()
$script:queueIndex = 0
$script:due = [datetime]::MinValue
$script:oldClipboard = $null
$script:lastClipboard = $null
$script:baseImage = $null
$script:dialogImage = $null
$script:baseSignature = $null
$script:dialogSignature = $null
$script:separation = 0
$script:eraseRemaining = 0
$script:typeIndex = 0
$script:pendingPoint = ''
$script:entryAttempts = 0
$script:entryHits = 0
$script:entryDeadline = [datetime]::MinValue
$script:screenTrace = ''
$script:runClock = [Diagnostics.Stopwatch]::StartNew()
$script:lastSubmitMs = -100000.0
$script:resultDeadlineMs = 0.0
$script:resultBaseHits = 0
$script:resultDialogHits = 0
$script:lastInputLength = -1
$script:finishReason = ''
$script:closeDeadline = [datetime]::MinValue

$form = New-Object System.Windows.Forms.Form
$form.Text = '燕雲十六聲｜序號兌換助手 v1.9'
$form.ClientSize = New-Object System.Drawing.Size(800, 660)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)

function Add-Label([string]$Text, [int]$X, [int]$Y, [int]$W = 740, [int]$H = 25) {
    $c = New-Object System.Windows.Forms.Label
    $c.Text=$Text; $c.SetBounds($X,$Y,$W,$H); $form.Controls.Add($c); return $c
}
function Add-Button([string]$Text, [int]$X, [int]$Y, [int]$W, [scriptblock]$Action) {
    $c = New-Object System.Windows.Forms.Button
    $c.Text=$Text; $c.SetBounds($X,$Y,$W,34); $c.Add_Click($Action); $form.Controls.Add($c); return $c
}
function Add-Check([string]$Text, [int]$X, [int]$Y, [int]$W, [bool]$Checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text=$Text; $c.Checked=$Checked; $c.SetBounds($X,$Y,$W,28); $form.Controls.Add($c); return $c
}

$null = Add-Label '1  取得序號 → 2  校準位置 → 3  切回遊戲按 F9' 18 16
$fetch = Add-Button '讀取網站序號' 18 48 155 {
    if ($script:phase -ne 'idle') { return }
    $fetch.Enabled=$false; $form.UseWaitCursor=$true
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $payload = Invoke-RestMethod -Uri 'https://codes.yar.gg/api/codes' -TimeoutSec 15 -UserAgent 'WWM-Local-Redeem-Helper/1.0'
        $codes = @(Get-ActiveCodes $payload)
        if (!$codes.Count) { throw '網站目前沒有可用序號。' }
        $codeBox.Lines = [string[]]$codes
        Write-Log "已取得 $($codes.Count) 筆網站有效清單序號；實際可否兌換仍由遊戲決定。"
    } catch { Write-Log "讀取失敗：$($_.Exception.Message)；可自行貼上序號。" }
    finally { $fetch.Enabled=$true; $form.UseWaitCursor=$false }
}
$null = Add-Label '可自行貼上，每行一組：' 188 55 560
$codeBox = New-Object System.Windows.Forms.TextBox
$codeBox.Multiline=$true; $codeBox.ScrollBars='Vertical'; $codeBox.SetBounds(18,90,764,142)
$codeBox.Font=New-Object System.Drawing.Font('Consolas',10)
$form.Controls.Add($codeBox)
$null = Add-Label '紀錄名稱：' 18 242 90
$profileBox = New-Object System.Windows.Forms.ComboBox
$profileBox.DropDownStyle='DropDown'; $profileBox.AutoCompleteMode='SuggestAppend'; $profileBox.AutoCompleteSource='ListItems'
$profileBox.MaxDropDownItems=12; $profileBox.DropDownWidth=260
$profileBox.Text='預設帳號'; $profileBox.SetBounds(108,239,200,28); $form.Controls.Add($profileBox)
$saveProfile = Add-Button '記住名稱' 318 236 82 {
    if ($script:phase -ne 'idle') { return }
    if (!$profileBox.Text.Trim()) { Write-Log '請先輸入要記住的帳號名稱。'; return }
    try { Save-Settings; Write-Log "已記住紀錄名稱：$($profileBox.Text)。下次可直接從下拉列表選取。" }
    catch { Write-Log "名稱儲存失敗：$($_.Exception.GetBaseException().Message)" }
}
$skip = Add-Check '略過此名稱已嘗試的序號' 410 239 370 $true
$null = Add-Label '校準：按按鈕後 8 秒內切到遊戲，滑鼠停在指定點；也可按 F6 提前記住。' 18 278

$script:pointLabels = @{}
$names = @('open','field')
$texts = @('A  兌換碼入口','B  序號輸入框')
for ($i=0; $i -lt 2; $i++) {
    $pointName=$names[$i]
    $action = {
        param($sender,$eventArgs)
        if ($script:phase -eq 'idle') {
            Begin-Capture ([string]$sender.Tag)
        }
    }
    $pointButton = Add-Button $texts[$i] (18+($i%2)*385) (310+[math]::Floor($i/2)*70) 185 $action
    $pointButton.Tag=$pointName
    $script:pointLabels[$pointName] = Add-Label '尚未校準' (210+($i%2)*385) (316+[math]::Floor($i/2)*70) 185
}
$autoCapture = Add-Check '免按鍵：校準按鈕按下後 8 秒自動記住' 18 350 420 $true
$hotkeyLabel = Add-Label '全域熱鍵：尚未啟用' 440 353 340 25
$targetLabel = Add-Label '只校準 A、B；貼上後點輸入框上方空白，再按 Space／Esc。' 18 384
$continuous = Add-Check '連續嘗試（保留輸入框，直接換下一碼）' 18 415 420 $false
$typing = Add-Check '相容模式：逐字輸入' 440 415 345 $false
$null = Add-Label '送出間隔：' 18 452 100
$delay = New-Object System.Windows.Forms.NumericUpDown
$delay.DecimalPlaces=1; $delay.Increment=0.1; $delay.Minimum=0.1; $delay.Maximum=60; $delay.Value=1; $delay.SetBounds(116,448,66,28); $form.Controls.Add($delay)
$null = Add-Label '秒；可調 0.1～60，實際速度也受遊戲回應與操作時間影響。' 192 452 580
$start = Add-Button '開始／繼續 (F9)' 18 487 210 { Start-Run }
$stop = Add-Button '立即暫停 (F8)' 240 487 210 { Stop-Run '使用者暫停。若已送出，請先處理遊戲提示，再繼續。' }
$pointerTest = Add-Button '只測 A（移動、不點擊）' 462 487 320 { Start-PointerTest }
$status = Add-Label '就緒。預設每次只送出一筆，請自行查看遊戲結果。' 18 531 765 30
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.SetBounds(18,567,764,76); $form.Controls.Add($log)

function Write-Log([string]$Message) {
    $status.Text=$Message
    $log.AppendText("$(Get-Date -Format HH:mm:ss)  $Message`r`n")
}
function Begin-Capture([string]$Name) {
    $script:captureName=$Name; $script:captureSeconds=-1
    if ($autoCapture.Checked) {
        $script:captureDue=[datetime]::Now.AddSeconds(8)
        Write-Log "校準 $Name：8 秒內切到遊戲，滑鼠停在指定點；時間到自動記住，不必按 F6。"
    } else {
        $script:captureDue=[datetime]::MaxValue
        Write-Log "校準 $Name：切到遊戲，滑鼠移至指定位置後按全域 F6；亦可使用免按鍵校準。"
    }
}
function Invoke-CaptureCountdown {
    if (!$script:captureName -or $script:captureDue -eq [datetime]::MaxValue) { return }
    $seconds=[int][Math]::Ceiling(($script:captureDue-[datetime]::Now).TotalSeconds)
    if ($seconds -le 0) { Capture-Point; return }
    if ($seconds -ne $script:captureSeconds) {
        $script:captureSeconds=$seconds
        $status.Text="校準 $($script:captureName)：剩 $seconds 秒。請讓遊戲置前，滑鼠停在指定位置。"
    }
}
function Initialize-Hotkeys {
    $script:hotkeys=New-Object RedeemHotkeys
    $summary=@()
    foreach ($key in @(117,119,120)) {
        $name='F'+($key-111)
        if ($script:hotkeys.Register($key,0)) { $summary+= "$name 已啟用" }
        else { $summary+= "$name 被占用"; Write-Log "$name 全域熱鍵註冊失敗，Win32=$($script:hotkeys.LastError)。請關閉舊工具或占用熱鍵的程式；校準可先用 8 秒倒數。" }
    }
    $hotkeyLabel.Text=$summary -join ' / '
}
function Refresh-ProfileNames {
    $current=$profileBox.Text.Trim()
    $script:profiles=@(Get-ProfileNames -SavedProfiles $script:profiles -History $script:history -Current $current)
    $profileBox.BeginUpdate()
    try {
        $profileBox.Items.Clear()
        $profileBox.Items.AddRange([object[]]$script:profiles)
        $profileBox.Text=$current
    } finally { $profileBox.EndUpdate() }
}
function Save-Settings {
    Refresh-ProfileNames
    if ($SelfTest) { return }
    if (!(Test-Path -LiteralPath $script:dataDir)) { $null = New-Item -ItemType Directory -Path $script:dataDir }
    @{ profile=$profileBox.Text.Trim(); profiles=@($script:profiles); delay=[double]$delay.Value; typing=$typing.Checked; continuous=$continuous.Checked; formatVersion=18 } |
        ConvertTo-Json | Set-Content -LiteralPath $script:settingsPath -Encoding UTF8
}
function Restore-Clipboard {
    if ($null -ne $script:lastClipboard) {
        try {
            if ([Windows.Forms.Clipboard]::ContainsText() -and [Windows.Forms.Clipboard]::GetText() -ceq $script:lastClipboard) {
                if ($null -ne $script:oldClipboard) { [Windows.Forms.Clipboard]::SetDataObject($script:oldClipboard,$true) }
                else { [Windows.Forms.Clipboard]::Clear() }
            }
        } catch { $log.AppendText("剪貼簿還原失敗；目前可能保留最後一組序號。`r`n") }
    }
    $script:lastClipboard=$null; $script:oldClipboard=$null
}
function Copy-ClipboardSnapshot {
    $original=[Windows.Forms.Clipboard]::GetDataObject()
    if ($null -eq $original) { return $null }
    $snapshot=New-Object Windows.Forms.DataObject
    foreach ($format in $original.GetFormats($false)) {
        $value=$original.GetData($format,$false)
        if ($null -ne $value) { $snapshot.SetData($format,$false,$value) }
    }
    return $snapshot
}
function Stop-Run([string]$Reason) {
    $script:phase='idle'; $script:captureName=''
    $script:captureDue=[datetime]::MaxValue
    Restore-Clipboard
    $codeBox.ReadOnly=$false
    foreach ($control in @($fetch,$profileBox,$saveProfile,$skip,$continuous,$typing,$delay,$autoCapture)) { $control.Enabled=$true }
    Write-Log $Reason
}
function Test-Target {
    if (![RedeemNative]::IsWindow($script:target)) { throw '遊戲視窗已關閉，請重新校準。' }
    if ([RedeemNative]::GetForegroundWindow() -ne $script:target) { throw '遊戲失去焦點，已暫停。切回遊戲並確認畫面後再按 F9。' }
    $rect=New-Object RedeemNative+RECT
    if (![RedeemNative]::GetClientRect($script:target,[ref]$rect)) { throw '無法取得遊戲視窗範圍。' }
    if (($rect.Right -ne $script:targetWidth) -or ($rect.Bottom -ne $script:targetHeight)) { throw '遊戲視窗尺寸已改變，請重新校準 A、B。' }
}
function Invoke-Point([string]$Name) {
    Test-Target
    Assert-InputRights
    $point=$script:points[$Name]
    $script:pendingPoint=$Name
    [RedeemNative]::Click($script:target,[int]$point.x,[int]$point.y,[Action]{ Assert-ClickScreen })
}
function Assert-InputRights {
    $own=[RedeemRights]::OwnIntegrity()
    $game=[RedeemRights]::WindowIntegrity($script:target)
    if ([RedeemRights]::NeedsElevation($own,$game)) {
        throw '遊戲是管理員權限、工具是一般權限，尚未送出點擊。請關閉工具後重新雙擊 Start.cmd，並自行完成 Windows 管理員確認。'
    }
}
function Assert-ClickScreen {
    $name=$script:pendingPoint
    if ($name -eq 'open') { Assert-GameScreen 'base'; return }
    Assert-GameScreen 'dialog'
}
function Invoke-DialogKey([string]$Key) {
    Assert-GameScreen 'dialog'; Assert-InputRights; Test-Target
    Invoke-DialogBlur
    Assert-GameScreen 'dialog'; Test-Target
    $scan=Get-DialogScan $Key
    Send-DialogScan $scan
}
function Send-DialogScan([UInt16]$Scan) {
    [RedeemNative]::TapScan($script:target,$Scan)
}
function Invoke-DialogBlur {
    $point=Get-DialogBlurPoint $script:points.field.x $script:points.field.y $script:targetWidth $script:targetHeight
    Test-Target; Assert-InputRights
    $script:pendingPoint='blur'
    [RedeemNative]::Click($script:target,[int]$point.x,[int]$point.y,[Action]{ Assert-ClickScreen })
}
function Clear-ScreenSamples {
    foreach ($image in @($script:baseImage,$script:dialogImage)) { if ($null -ne $image) { $image.Dispose() } }
    $script:baseImage=$null; $script:dialogImage=$null
    $script:baseSignature=$null; $script:dialogSignature=$null; $script:separation=0
}
function Get-SignatureAnchors {
    return [int[]]@($script:points.open.x,$script:points.open.y,$script:points.field.x,$script:points.field.y,[int]($script:targetWidth*0.25),$script:points.field.y)
}
function Initialize-ScreenSamples {
    if ($null -eq $script:baseImage -or $null -eq $script:dialogImage) { throw '請重新校準 A（其他頁）和 B（兌換輸入視窗），以取得畫面樣本。' }
    $anchors=Get-SignatureAnchors
    $script:baseSignature=[RedeemNative]::Signature($script:baseImage,$anchors)
    $script:dialogSignature=[RedeemNative]::Signature($script:dialogImage,$anchors)
    $script:separation=[RedeemNative]::Distance($script:baseSignature,$script:dialogSignature)
    if ($script:separation -lt 12) { throw 'A、B 畫面差異不足。請在兌換視窗關閉時重設 A、開啟時重設 B。' }
}
function Get-GameScreenState {
    param([switch]$AllowUnknown)
    Test-Target
    $image=[RedeemNative]::CaptureClient($script:target)
    try { $signature=[RedeemNative]::Signature($image,(Get-SignatureAnchors)) }
    finally { $image.Dispose() }
    $baseDistance=[RedeemNative]::Distance($signature,$script:baseSignature)
    $dialogDistance=[RedeemNative]::Distance($signature,$script:dialogSignature)
    $state=Get-DialogState $baseDistance $dialogDistance $script:separation
    $script:screenTrace=('state={0}; baseDiff={1:N1}; dialogDiff={2:N1}; separation={3:N1}' -f $state,$baseDistance,$dialogDistance,$script:separation)
    if ($state -eq 'unknown' -and !$AllowUnknown) {
        throw ('無法辨識目前畫面（設定頁差異 {0:N1}／兌換框差異 {1:N1}），已停止。請回到其他頁，必要時重設 A、B。' -f $baseDistance,$dialogDistance)
    }
    return $state
}
function Assert-GameScreen([string]$Expected) {
    $state=Get-GameScreenState
    if ($state -ne $Expected) {
        if ($Expected -eq 'base') { throw '預期顯示「其他」頁，但兌換輸入視窗仍開啟。請先取消再繼續。' }
        throw "目前尚未辨識到兌換輸入視窗，已停止後續輸入。階段=$($script:phase)；$($script:screenTrace)"
    }
}
function Capture-Point {
    if (!$script:captureName) { return }
    $p=New-Object RedeemNative+POINT
    [void][RedeemNative]::GetCursorPos([ref]$p)
    $h=[RedeemNative]::GetAncestor([RedeemNative]::WindowFromPoint($p),2)
    $title=[RedeemNative]::Title($h)
    if ($title -notmatch '燕雲十六聲|燕云十六声|Where\s*Winds\s*Meet') { throw '滑鼠下方不是燕雲十六聲視窗，請移到遊戲內再按 F6。' }
    if ([RedeemNative]::GetForegroundWindow() -ne $h) { throw '校準前請先點一下遊戲，讓遊戲置於最上層，再移到校準點按 F6。' }
    $r=New-Object RedeemNative+RECT
    [void][RedeemNative]::GetClientRect($h,[ref]$r)
    [void][RedeemNative]::ScreenToClient($h,[ref]$p)
    if ($p.X -lt 0 -or $p.Y -lt 0 -or $p.X -ge $r.Right -or $p.Y -ge $r.Bottom) { throw '請選擇遊戲內容區域內的位置。' }
    if ($h -ne $script:target -or $r.Right -ne $script:targetWidth -or $r.Bottom -ne $script:targetHeight) {
        $script:points=@{}
        Clear-ScreenSamples
        foreach ($label in $script:pointLabels.Values) { $label.Text='尚未校準' }
    }
    $script:target=$h; $script:targetWidth=$r.Right; $script:targetHeight=$r.Bottom
    $name=$script:captureName
    $script:points[$name]=@{x=$p.X;y=$p.Y}
    if ($name -eq 'open') {
        if ($null -ne $script:baseImage) { $script:baseImage.Dispose() }
        $script:baseImage=[RedeemNative]::CaptureClient($h)
    }
    if ($name -eq 'field') {
        if ($null -ne $script:dialogImage) { $script:dialogImage.Dispose() }
        $script:dialogImage=[RedeemNative]::CaptureClient($h)
    }
    $script:pointLabels[$name].Text="已記住 ($($p.X), $($p.Y))"
    $targetLabel.Text="遊戲：$title  ｜內容大小：$($r.Right) × $($r.Bottom)"
    $script:captureName=''
    $script:captureDue=[datetime]::MaxValue
    Write-Log "已校準 $name。請維持相同遊戲解析度與介面縮放。"
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
}
function Start-Run {
    if ($script:phase -ne 'idle') { return }
    try {
        foreach ($name in @('open','field')) { if (!$script:points.ContainsKey($name)) { throw "請先校準 $name。" } }
        Initialize-ScreenSamples
        Assert-InputRights
        if (!$profileBox.Text.Trim()) { throw '請填寫紀錄名稱；不同遊戲帳號請使用不同名稱。' }
        $codes=@(ConvertTo-CodeList -Values @($codeBox.Lines))
        $script:queue=@(Get-PendingCodes -Codes $codes -History $script:history -Profile $profileBox.Text.Trim() -SkipAttempted $skip.Checked)
        if (!$script:queue.Count) { throw '沒有待處理序號。可讀取網站、貼上序號，或取消略過已嘗試。' }
        Save-Settings
        $script:queueIndex=0; $script:lastInputLength=-1; $script:phase='arming'; $script:due=[datetime]::Now.AddSeconds(10)
        $script:captureName=''; $script:captureDue=[datetime]::MaxValue; $codeBox.ReadOnly=$true
        foreach ($control in @($fetch,$profileBox,$saveProfile,$skip,$continuous,$typing,$delay,$autoCapture)) { $control.Enabled=$false }
        Write-Log "待處理 $($script:queue.Count) 筆。10 秒內切回遊戲『其他』頁或兌換輸入框；Space 確認，F8 暫停。"
    } catch { Stop-Run $_.Exception.Message }
}
function Start-PointerTest {
    if ($script:phase -ne 'idle') { return }
    if (!$script:points.ContainsKey('open')) { Write-Log '請先校準 A，再測試滑鼠位置。'; return }
    try { Assert-InputRights } catch { Write-Log $_.Exception.GetBaseException().Message; return }
    $script:captureName=''; $script:captureDue=[datetime]::MaxValue
    $script:phase='pointerArming'; $script:due=[datetime]::Now.AddSeconds(10)
    Write-Log '只測滑鼠：10 秒內切回遊戲「其他」頁。只會移到 A，不會點擊或送出序號。'
}
function Set-Phase([string]$Name,[int]$Milliseconds) {
    $script:phase=$Name; $script:due=[datetime]::Now.AddMilliseconds($Milliseconds)
}
function Add-Attempt([string]$Code) {
    $entry=[pscustomobject]@{time=[datetimeoffset]::Now.ToString('o');profile=$profileBox.Text.Trim();code=$Code;status='attempted'}
    # Append immediately after submitting; this is deliberately not a success claim.
    $script:history+=@($entry)
    ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $script:historyPath -Encoding UTF8
}
function Finish-Submission([string]$State,[string]$Reason) {
    if ($State -eq 'dialog') {
        Invoke-DialogKey 'cancel'
        $script:lastInputLength=-1; $script:finishReason=$Reason
        $script:closeDeadline=[datetime]::Now.AddSeconds(1.5)
        Set-Phase 'waitClose' 100
    } else { Stop-Run $Reason }
}
function Complete-Result([string]$State,[string]$Code) {
    $action=Get-ResultAction $State $continuous.Checked
    if ($action -eq 'pause') { Finish-Submission $State "已嘗試 $Code，單筆模式已暫停。"; return }
    if ($action -notin @('reuse','next')) { throw '無法確認兌換後的畫面，已停止。' }
    $script:queueIndex++
    if ($script:queueIndex -ge $script:queue.Count) {
        Finish-Submission $State '清單已全部嘗試。實際結果請查看遊戲與信箱。'
    } elseif ($action -eq 'reuse') {
        Write-Log '輸入框仍開著，直接換下一組序號。'
        Set-Phase 'field' 0
    } else {
        $script:lastInputLength=-1
        Set-Phase 'open' 0
    }
}
function Invoke-Tick {
    while ($null -ne $script:hotkeys) {
        $key=$script:hotkeys.Take()
        if ($key -eq 0) { break }
        if ($key -eq 119) { Stop-Run '已暫停。請先檢查遊戲目前畫面再繼續。'; return }
        if ($key -eq 117 -and $script:captureName) { Capture-Point }
        if ($key -eq 120) { Start-Run }
    }
    # Escape is the game's cancel action. F8 is the global emergency stop.
    Invoke-CaptureCountdown
    if ($script:phase -eq 'idle') { return }
    if ($script:phase -in @('arming','pointerArming')) {
        if ([RedeemNative]::GetForegroundWindow() -eq $script:target) {
            Test-Target
            if ($script:phase -eq 'pointerArming') { Set-Phase 'pointerProbe' 300; Write-Log '即將測試移動到 A，不會點擊。' }
            else { Set-Phase 'route' 300; Write-Log '即將開始；F8 隨時暫停。' }
        } elseif ([datetime]::Now -ge $script:due) { Stop-Run '等待遊戲焦點逾時；切回遊戲後按 F9。' }
        return
    }
    Test-Target
    if ([datetime]::Now -lt $script:due) { return }
    # Do not combine automated input with a modifier held by the user.
    foreach ($key in @(16,17,18,91,92)) { if ([RedeemNative]::Down($key)) { throw '偵測到修飾鍵按住，已暫停。放開按鍵並檢查畫面後再繼續。' } }
    if ($script:phase -eq 'pointerProbe') {
        $point=$script:points.open
        $trace=[RedeemNative]::MoveTo($script:target,[int]$point.x,[int]$point.y)
        Stop-Run "已送出 A 點移動，沒有點擊；請目視確認位置。$trace"
        return
    }
    if ($script:phase -eq 'waitClose') {
        $state=Get-GameScreenState -AllowUnknown
        if ($state -eq 'base') { Stop-Run $script:finishReason }
        elseif ([datetime]::Now -ge $script:closeDeadline) { Stop-Run "已按 Esc，視窗尚未確認關閉；請自行查看遊戲。$($script:finishReason)" }
        else { Set-Phase 'waitClose' 100 }
        return
    }
    $code=$script:queue[$script:queueIndex]
    switch ($script:phase) {
        'route' {
            $state=Get-GameScreenState
            if ($state -eq 'dialog') { Set-Phase 'field' 0 }
            else { Set-Phase 'open' 0 }
        }
        'open' {
            Assert-GameScreen 'base'; Invoke-Point 'open'
            $script:lastInputLength=-1
            $script:entryAttempts=1; $script:entryHits=0; $script:entryDeadline=[datetime]::Now.AddSeconds(4)
            Write-Log '已送出入口點擊，等待兌換輸入視窗。'
            Set-Phase 'waitDialog' 100
        }
        'waitDialog' {
            $state=Get-GameScreenState -AllowUnknown
            if ($state -eq 'dialog') { $script:entryHits++ } else { $script:entryHits=0 }
            $action=Get-EntryAction $state ([datetime]::Now -ge $script:entryDeadline) $script:entryAttempts $script:entryHits
            switch ($action) {
                'ready' { Set-Phase 'field' 50 }
                'wait' { Set-Phase 'waitDialog' 100 }
                'retry' {
                    Write-Log '仍停在其他頁，重試一次入口點擊。'
                    Invoke-Point 'open'; $script:entryAttempts++; $script:entryHits=0; $script:entryDeadline=[datetime]::Now.AddSeconds(4)
                    Set-Phase 'waitDialog' 100
                }
                default { throw "入口點擊後仍未確認輸入框開啟（嘗試 $($script:entryAttempts) 次），未輸入或送出序號。$($script:screenTrace)；$([RedeemNative]::LastPointerTrace)" }
            }
        }
        'field' {
            Assert-GameScreen 'dialog'; Invoke-Point 'field'
            if (!$typing.Checked) { Set-Phase 'select' 80 }
            else {
                $script:eraseRemaining=if ($script:lastInputLength -ge 0) { $script:lastInputLength+2 } else { 64 }
                Set-Phase 'clear' 80
            }
        }
        'select' {
            Assert-GameScreen 'dialog'; Test-Target
            [RedeemNative]::Chord($script:target,0x41)
            $script:typeIndex=0; Set-Phase 'type' 40
        }
        'clear' {
            Assert-GameScreen 'dialog'
            for ($i=0;$i -lt 8 -and $script:eraseRemaining -gt 0;$i++) {
                [RedeemNative]::Backspace($script:target); $script:eraseRemaining--
            }
            if ($script:eraseRemaining -gt 0) { Set-Phase 'clear' 10 }
            else { $script:typeIndex=0; Set-Phase 'type' 40 }
        }
        'type' {
            Assert-GameScreen 'dialog'; Test-Target
            if ($typing.Checked) {
                $batch=[Math]::Min(3,$code.Length-$script:typeIndex)
                [RedeemNative]::Text($script:target,$code.Substring($script:typeIndex,$batch))
                $script:typeIndex+=$batch
                if ($script:typeIndex -lt $code.Length) { Set-Phase 'type' 10; return }
            }
            else {
                if ($null -eq $script:lastClipboard) { $script:oldClipboard=Copy-ClipboardSnapshot }
                [Windows.Forms.Clipboard]::SetText($code); $script:lastClipboard=$code
                Test-Target; [RedeemNative]::Chord($script:target,0x56)
            }
            $script:lastInputLength=$code.Length
            Set-Phase 'confirm' 100
        }
        'confirm' {
            $waitMs=Get-SubmitWaitMs $script:runClock.Elapsed.TotalMilliseconds $script:lastSubmitMs ([double]$delay.Value)
            if ($waitMs -gt 0) { Set-Phase 'confirm' ([Math]::Min(100,$waitMs)); return }
            Assert-GameScreen 'dialog'
            Invoke-DialogKey 'confirm'
            $script:lastSubmitMs=$script:runClock.Elapsed.TotalMilliseconds
            $script:resultDeadlineMs=$script:lastSubmitMs+4000
            $script:resultBaseHits=0; $script:resultDialogHits=0
            Add-Attempt $code
            Write-Log "已嘗試 $($script:queueIndex+1)/$($script:queue.Count)：$code（未判定成功）"
            Set-Phase 'result' 150
        }
        'result' {
            $state=Get-GameScreenState -AllowUnknown
            if ($state -eq 'base') { $script:resultBaseHits++ } else { $script:resultBaseHits=0 }
            if ($state -eq 'dialog') { $script:resultDialogHits++ } else { $script:resultDialogHits=0 }
            $elapsedMs=$script:runClock.Elapsed.TotalMilliseconds-$script:lastSubmitMs
            $settleMs=Get-ResultSettleMs ([double]$delay.Value)
            if ($script:resultBaseHits -ge 2 -or ($script:resultDialogHits -ge 2 -and $elapsedMs -ge $settleMs)) { Complete-Result $state $code }
            elseif ($script:runClock.Elapsed.TotalMilliseconds -ge $script:resultDeadlineMs) { throw "等待兌換結果逾時；$($script:screenTrace)" }
            else { Set-Phase 'result' 100 }
        }
    }
}

try {
    if (Test-Path -LiteralPath $script:historyPath) {
        foreach ($line in [IO.File]::ReadAllLines($script:historyPath,[Text.Encoding]::UTF8)) {
            if ($line.Trim()) { $script:history+=@($line | ConvertFrom-Json) }
        }
    }
    if (!$SelfTest -and (Test-Path -LiteralPath $script:settingsPath)) {
        $settings=Get-Content -LiteralPath $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profileBox.Text=[string]$settings.profile
        if ($settings.PSObject.Properties['profiles']) { $script:profiles=@($settings.profiles) }
        if ($settings.PSObject.Properties['formatVersion'] -and $settings.formatVersion -ge 18) { $delay.Value=[Math]::Max(0.1,[Math]::Min(60,[double]$settings.delay)) }
        if ($settings.PSObject.Properties['continuous']) { $continuous.Checked=[bool]$settings.continuous }
        if ($settings.PSObject.Properties['formatVersion'] -and $settings.formatVersion -ge 16) { $typing.Checked=[bool]$settings.typing }
    }
    Refresh-ProfileNames
} catch {
    [void][Windows.Forms.MessageBox]::Show("無法讀取本機紀錄：$($_.Exception.Message)`n請先備份並修復 data 內的檔案，再啟動。",'紀錄讀取失敗')
    $form.Dispose(); exit 1
}

$timer=New-Object Windows.Forms.Timer
$timer.Interval=25
$timer.Add_Tick({ try { Invoke-Tick } catch { Stop-Run "已暫停：$($_.Exception.GetBaseException().Message)" } })
$form.Add_Shown({
    if (!$SelfTest) {
        try { Initialize-Hotkeys }
        catch { Write-Log "無法啟用全域熱鍵：$($_.Exception.GetBaseException().Message)。請使用免按鍵校準與開始按鈕。" }
    }
})
$form.Add_FormClosing({ $timer.Stop(); Stop-Run '工具已關閉。'; Clear-ScreenSamples; try { Save-Settings } catch {} })
if ($SelfTest) {
    if ($form.Controls.Count -lt 20) { throw '介面建構失敗。' }
    if ($script:phase -ne 'idle' -or $continuous.Checked) { throw '啟動狀態應為單筆、未執行。' }
    $aButton=@($form.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Tag -eq 'open' })[0]
    $clickMethod=[Windows.Forms.Button].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    $null=$clickMethod.Invoke($aButton,@([EventArgs]::Empty))
    if ($script:captureName -ne 'open') { throw '校準按鈕事件失敗。' }
    if ($script:captureDue -eq [datetime]::MaxValue) { throw '校準應預設使用免按鍵倒數。' }
    $originalCapture=(Get-Item Function:Capture-Point).ScriptBlock
    $script:testCaptures=0
    try {
        Set-Item Function:Capture-Point { $script:testCaptures++; $script:captureName='' }
        $script:captureDue=[datetime]::Now.AddSeconds(-1)
        Invoke-CaptureCountdown
        Invoke-CaptureCountdown
        if ($script:testCaptures -ne 1) { throw '倒數應只擷取一次，且不需要按鍵。' }
    } finally { Set-Item Function:Capture-Point $originalCapture }
    Stop-Run '就緒。預設每次只送出一筆，請自行查看遊戲結果。'
    Start-Run
    if ($script:phase -ne 'idle' -or $status.Text -notlike '*請先校準*') { throw '未校準時不可啟動。' }
    $script:points=@{open=@{x=10;y=10};field=@{x=20;y=20}}
    $script:targetWidth=1000
    $anchors=Get-SignatureAnchors
    if (($anchors -join ',') -ne '10,10,20,20,250,20') { throw '畫面取樣應只需要 A、B 校準。' }
    if (@($form.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Tag -in @('confirm','dismiss') }).Count) { throw '不應再要求確認／取消的滑鼠校準。' }
    if ($delay.Value -ne 1 -or $delay.Minimum -ne 0.1) { throw '預設應使用 1 秒間隔，並允許調低到 0.1 秒。' }
    if ($profileBox -isnot [Windows.Forms.ComboBox] -or $profileBox.DropDownStyle -ne 'DropDown') { throw '帳號名稱必須可以下拉選取及輸入新名稱。' }
    $profileBox.Text='測試帳號甲'; Refresh-ProfileNames
    $profileBox.Text='測試帳號乙'; Refresh-ProfileNames
    $profileBox.SelectedItem='測試帳號甲'
    if ($profileBox.Text -ne '測試帳號甲' -or !$profileBox.Items.Contains('測試帳號乙')) { throw '帳號列表應保留先前名稱，並可切回舊帳號。' }
    if ($typing.Checked) { throw '預設應直接貼上，逐字輸入只作相容模式。' }
    # Execute the real shortcut path under PowerShell 5.1, replacing only OS effects.
    $savedFunctions=@{}
    foreach ($fn in @('Assert-GameScreen','Assert-InputRights','Test-Target','Invoke-DialogBlur','Send-DialogScan')) { $savedFunctions[$fn]=(Get-Item ('Function:'+$fn)).ScriptBlock }
    $script:keyEvents=New-Object 'System.Collections.Generic.List[string]'
    try {
        Set-Item Function:Assert-GameScreen { param($Expected) }
        Set-Item Function:Assert-InputRights {}
        Set-Item Function:Test-Target {}
        Set-Item Function:Invoke-DialogBlur { $script:keyEvents.Add('blur') }
        Set-Item Function:Send-DialogScan { param([UInt16]$Scan) $script:keyEvents.Add('scan:'+$Scan) }
        Invoke-DialogKey 'confirm'
        Invoke-DialogKey 'cancel'
        if (($script:keyEvents -join ',') -ne 'blur,scan:57,blur,scan:1') { throw '確認／取消流程必須先移開焦點，並傳送 UInt16 掃描碼。' }
    } finally {
        foreach ($fn in $savedFunctions.Keys) { Set-Item ('Function:'+$fn) $savedFunctions[$fn] }
    }
    $originalDialogKey=(Get-Item Function:Invoke-DialogKey).ScriptBlock
    $script:testKeys=New-Object 'System.Collections.Generic.List[string]'
    try {
        Set-Item Function:Invoke-DialogKey { param([string]$Key) $script:testKeys.Add($Key) }
        $continuous.Checked=$true; $script:queue=@('TEST123','TEST456'); $script:queueIndex=0
        Complete-Result 'dialog' 'TEST123'
        if ($script:phase -ne 'field' -or $script:queueIndex -ne 1 -or $script:testKeys.Count -ne 0) { throw '連續模式應直接重用輸入框，不得先按 Esc。' }
        Complete-Result 'dialog' 'TEST456'
        if ($script:phase -ne 'waitClose' -or ($script:testKeys -join ',') -ne 'cancel') { throw '最後一筆才應按 Esc 關閉輸入框。' }
    } finally {
        Set-Item Function:Invoke-DialogKey $originalDialogKey
        $continuous.Checked=$false; $script:queue=@(); $script:queueIndex=0
        Stop-Run '測試完成。'
    }
    Start-Run
    if ($script:phase -ne 'idle' -or $status.Text -notlike '*畫面樣本*') { throw '沒有畫面樣本時不可啟動。' }
    $script:points=@{}
    $nativeInput=[RedeemNative].GetNestedType('INPUT',[Reflection.BindingFlags]'NonPublic')
    $expectedSize=if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
    if ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($nativeInput)) -ne $expectedSize) { throw 'SendInput 結構尺寸錯誤。' }
    if ($PreviewPath) {
        Write-Log '就緒。預設每次只送出一筆，請自行查看遊戲結果。'
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height))); $bitmap.Save($PreviewPath,[Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose(); $form.Hide() }
    }
    Write-Output "UI self-test passed: $($form.Controls.Count) controls; idle; single-code default."
    $timer.Dispose(); $form.Dispose(); exit 0
}
$timer.Start()
try { [void]$form.ShowDialog() } finally {
    $timer.Dispose()
    if ($null -ne $script:hotkeys) { $script:hotkeys.Dispose() }
    if ($null -ne $script:instanceMutex) { $script:instanceMutex.ReleaseMutex(); $script:instanceMutex.Dispose() }
    $form.Dispose()
}
