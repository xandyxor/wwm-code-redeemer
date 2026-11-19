param([string]$FixturePath, [switch]$Live)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$script:assertions=0
function Assert-Equal($Actual,$Expected,[string]$Name) {
    $script:assertions++
    if (($Actual | ConvertTo-Json -Compress) -cne ($Expected | ConvertTo-Json -Compress)) {
        throw "FAIL: $Name`nActual: $Actual`nExpected: $Expected"
    }
}
Assert-Equal @(ConvertTo-CodeList @('abc123, ABC123','def456；ghi789')) @('ABC123','DEF456','GHI789') 'normalize and deduplicate'
Assert-Equal @(ConvertTo-CodeList @('','  ')) @() 'empty input'
$rejected=$false
try { $null=ConvertTo-CodeList @('https://example.com') } catch { $rejected=$true }
Assert-Equal $rejected $true 'reject instructions and URLs as codes'
$payload='{"active":[{"code":"OK123","expiresAt":"2026-12-01T00:00:00Z"},{"code":"OLD123","expiresAt":"2026-01-01T00:00:00Z"},"LEGACY123",{"code":"OK123"}],"expired":[{"code":"EXPIRED123"}]}' | ConvertFrom-Json
Assert-Equal @(Get-ActiveCodes $payload ([datetimeoffset]'2026-11-19T00:00:00Z')) @('OK123','LEGACY123') 'active only, filter expiry, deduplicate'
$rejected=$false
try { $null=Get-ActiveCodes ('{"codes":[]}' | ConvertFrom-Json) } catch { $rejected=$true }
Assert-Equal $rejected $true 'detect schema change'
$history=@([pscustomobject]@{profile='A';code='ABC123';status='attempted'},[pscustomobject]@{profile='B';code='DEF456';status='attempted'})
Assert-Equal @(Get-PendingCodes @('ABC123','DEF456') $history 'A' $true) @('DEF456') 'isolate account history'
Assert-Equal @(Get-PendingCodes @('ABC123','DEF456') $history 'A' $false) @('ABC123','DEF456') 'retry attempted codes'
Assert-Equal @(Get-PendingCodes @('ABC123') $history 'C' $true) @('ABC123') 'new account gets full queue'
Assert-Equal @(Get-PendingCodes @('ABC123') $history 'A' $true) @() 'all attempted yields empty queue'
Assert-Equal (Get-DialogState 3 58 60) 'base' 'recognize returned settings page'
Assert-Equal (Get-DialogState 58 3 60) 'dialog' 'recognize persistent dialog'
Assert-Equal (Get-DialogState 30 31 60) 'unknown' 'ambiguous screen stops'
Assert-Equal (Get-DialogState 0 5 5) 'unknown' 'reject indistinguishable calibration images'
Assert-Equal (Get-DialogState 90 100 60) 'unknown' 'unrelated screen stops'
Assert-Equal (Get-ResultAction 'base' $true) 'next' 'success closes dialog: do not cancel'
Assert-Equal (Get-ResultAction 'dialog' $true) 'reuse' 'duplicate keeps dialog: reuse without cancel and reopen'
Assert-Equal (Get-ResultAction 'base' $false) 'pause' 'single attempt pauses after auto-close'
Assert-Equal (Get-ResultAction 'dialog' $false) 'pause' 'single attempt preserves error dialog'
Assert-Equal (Get-ResultAction 'unknown' $true) 'stop' 'unknown result must not click'
Assert-Equal (Test-DialogBar 40 200 40) $true 'dark dialog footer permits confirm'
Assert-Equal (Test-DialogBar 200 200 40) $false 'settings footer must not be clicked'
Assert-Equal (Test-DialogBar 100 200 40) $false 'unrecognized footer must not be clicked'
Assert-Equal (Test-DialogBar 40 45 40) $false 'indistinguishable footer samples stop'
Assert-Equal (Get-EntryAction 'base' $false 1 0) 'wait' 'wait for game before retrying'
Assert-Equal (Get-EntryAction 'unknown' $false 1 0) 'wait' 'allow opening animation to settle'
Assert-Equal (Get-EntryAction 'dialog' $false 1 1) 'wait' 'one dialog sample is insufficient'
Assert-Equal (Get-EntryAction 'dialog' $false 1 2) 'ready' 'two consecutive dialog samples permit input'
Assert-Equal (Get-EntryAction 'base' $true 1 0) 'retry' 'retry first missed entry click'
Assert-Equal (Get-EntryAction 'base' $true 2 0) 'stop' 'stop after two failed entry clicks'
Assert-Equal (Get-EntryAction 'unknown' $true 1 0) 'stop' 'never click unknown screen after timeout'
Assert-Equal (Get-SubmitWaitMs 0 -100000 3.2) 0 'first code does not wait for cooldown'
Assert-Equal (Get-SubmitWaitMs 1000 0 3.2) 2200 'preparation counts toward submit interval'
Assert-Equal (Get-SubmitWaitMs 3199 0 3.2) 1 'wait until exact interval boundary'
Assert-Equal (Get-SubmitWaitMs 3200 0 3.2) 0 'submit immediately when cooldown elapsed'
Assert-Equal (Get-SubmitWaitMs 1000 0 5) 4000 'honor slower configured cadence'
Assert-Equal (Get-SubmitWaitMs 999 0 1) 1 'one second interval waits until its boundary'
Assert-Equal (Get-SubmitWaitMs 1000 0 1) 0 'one second setting has no hidden 3.2 second floor'
Assert-Equal (Get-SubmitWaitMs 400 0 0.5) 100 'permit half-second experiment'
Assert-Equal (Get-SubmitWaitMs 1000 0 0.1) 0 'permit configured sub-second interval'
Assert-Equal (Get-SubmitWaitMs 0 0 0) 100 'retain a 0.1 second minimum for invalid settings'
Assert-Equal (Get-ResultSettleMs 1) 300 'fast interval does not retain the old fixed 900ms result wait'
Assert-Equal (Get-ResultSettleMs 0.1) 200 'retain brief result observation for very short intervals'
Assert-Equal (Get-ResultSettleMs 5) 900 'slower mode retains longer result observation'
Assert-Equal @(Get-ProfileNames @('AccountA','小號','accounta',' ') $history ' 新帳號 ') @('新帳號','AccountA','小號','A','B') 'merge saved names, history and new profile without case duplicates'
Assert-Equal @(Get-ProfileNames @() $history '') @('A','B') 'recover old account names from existing history'
Assert-Equal @(Get-ProfileNames @('尚未兌換的帳號') @() '') @('尚未兌換的帳號') 'preserve saved accounts without redemption history'
Assert-Equal @(Get-ProfileNames @('小號') @() '主帳號') @('主帳號','小號') 'keep active account first'
Assert-Equal @(Get-PendingCodes @('ABC123','DEF456') $history 'B' $true) @('ABC123') 'switching dropdown account uses its own attempt history'
$blur=Get-DialogBlurPoint 800 450 1600 900
Assert-Equal @($blur.x,$blur.y) @(800,378) 'blur in blank area above field, no third calibration point'
$blur=Get-DialogBlurPoint 180 135 520 300
Assert-Equal @($blur.x,$blur.y) @(180,105) 'minimum blank offset on small window'
$blur=Get-DialogBlurPoint 1 20 100 100
Assert-Equal @($blur.x,$blur.y) @(8,8) 'keep blur point inside client bounds'
$rejected=$false
try { $null=Get-DialogBlurPoint 1000 450 1000 900 } catch { $rejected=$true }
Assert-Equal $rejected $true 'reject stale field coordinates before blur click'
Assert-Equal (Get-DialogScan 'confirm') ([UInt16]57) 'Space scan code resolves under Windows PowerShell'
Assert-Equal (Get-DialogScan 'cancel') ([UInt16]1) 'Escape scan code resolves under Windows PowerShell'
Assert-Equal ((Get-DialogScan 'confirm').GetType().FullName) 'System.UInt16' 'use the actual .NET UInt16 type, not a C# alias'
Write-Output "Core tests passed: $script:assertions assertions."
if ($FixturePath -or $Live) {
    if ($Live) {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $realPayload=Invoke-RestMethod -Uri 'https://codes.yar.gg/api/codes' -TimeoutSec 15 -UserAgent 'WWM-Local-Redeem-Helper/1.0'
    } else { $realPayload=Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    $realCodes=@(Get-ActiveCodes $realPayload)
    Assert-Equal ($realCodes.Count -gt 0) $true 'public API produces active codes'
    Assert-Equal (@($realCodes | Select-Object -Unique).Count) $realCodes.Count 'real payload remains unique'
    Write-Output "Public API payload parsed: $($realCodes.Count) active codes; $script:assertions total assertions passed."
}
