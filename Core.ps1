Set-StrictMode -Version 2.0

function ConvertTo-CodeList {
    param([string[]]$Values)
    $seen = @{}
    foreach ($value in $Values) {
        foreach ($token in ($value -split '[\s,;，；]+')) {
            $code = $token.Trim().ToUpperInvariant()
            if (!$code) { continue }
            if ($code -notmatch '^[A-Z0-9][A-Z0-9_-]{2,63}$') {
                throw "序號格式不正確：$code（請只貼序號，不要貼網址或說明）"
            }
            if (!$seen.ContainsKey($code)) { $seen[$code] = $true; $code }
        }
    }
}

function Get-ActiveCodes {
    param($Payload, [datetimeoffset]$Now = [datetimeoffset]::UtcNow)
    if ($null -eq $Payload -or !$Payload.PSObject.Properties['active'] -or
        $Payload.active -isnot [System.Array]) { throw '網站資料格式已變更：缺少 active 清單。' }
    $values = foreach ($entry in $Payload.active) {
        if ($entry -is [string]) { $entry; continue }
        if (!$entry.PSObject.Properties['code']) { throw '網站資料格式已變更：缺少 code。' }
        if ($entry.PSObject.Properties['expiresAt'] -and $entry.expiresAt) {
            $expires = [datetimeoffset]::Parse($entry.expiresAt)
            if ($expires -le $Now) { continue }
        }
        [string]$entry.code
    }
    ConvertTo-CodeList -Values @($values)
}

function Get-PendingCodes {
    param([string[]]$Codes, [object[]]$History, [string]$Profile, [bool]$SkipAttempted)
    $seen = @{}
    if ($SkipAttempted) {
        foreach ($entry in $History) {
            if ($entry.profile -eq $Profile) { $seen[[string]$entry.code] = $true }
        }
    }
    foreach ($code in $Codes) { if (!$seen.ContainsKey($code)) { $code } }
}

function Get-DialogState {
    param([double]$BaseDistance, [double]$DialogDistance, [double]$Separation)
    if ($Separation -lt 12) { return 'unknown' }
    $limit=[Math]::Max(8,[Math]::Min(24,$Separation*0.40))
    $margin=$Separation*0.20
    if ($BaseDistance -le $limit -and $BaseDistance+$margin -lt $DialogDistance) { return 'base' }
    if ($DialogDistance -le $limit -and $DialogDistance+$margin -lt $BaseDistance) { return 'dialog' }
    return 'unknown'
}

function Get-ResultAction {
    param([string]$ScreenState, [bool]$Continuous)
    if ($ScreenState -notin @('base','dialog')) { return 'stop' }
    if (!$Continuous) { return 'pause' }
    if ($ScreenState -eq 'dialog') { return 'reuse' }
    return 'next'
}

function Get-SubmitWaitMs {
    param([double]$NowMs, [double]$LastSubmitMs, [double]$IntervalSeconds)
    return [int][Math]::Max(0,[Math]::Ceiling($LastSubmitMs+[Math]::Max(0.1,$IntervalSeconds)*1000-$NowMs))
}

function Get-ResultSettleMs {
    param([double]$IntervalSeconds)
    return [int][Math]::Max(200,[Math]::Min(900,$IntervalSeconds*300))
}

function Get-ProfileNames {
    param([string[]]$SavedProfiles, [object[]]$History, [string]$Current)
    $seen=@{}
    $values=@($Current)+@($SavedProfiles)
    foreach ($entry in $History) {
        if ($null -ne $entry -and $entry.PSObject.Properties['profile']) { $values+= [string]$entry.profile }
    }
    foreach ($value in $values) {
        if ($null -eq $value) { continue }
        $name=([string]$value).Trim()
        if ($name -and !$seen.ContainsKey($name)) { $seen[$name]=$true; $name }
    }
}

function Get-DialogBlurPoint {
    param([int]$FieldX,[int]$FieldY,[int]$Width,[int]$Height)
    if ($Width -lt 64 -or $Height -lt 64 -or $FieldX -lt 0 -or $FieldX -ge $Width -or $FieldY -lt 0 -or $FieldY -ge $Height) { throw '無法計算輸入框上方空白位置。' }
    $offset=[Math]::Max(30,[int][Math]::Round($Height*0.08))
    return @{x=[Math]::Max(8,[Math]::Min($Width-9,$FieldX));y=[Math]::Max(8,$FieldY-$offset)}
}

function Get-DialogScan {
    param([string]$Key)
    switch ($Key) {
        'confirm' { return [UInt16]0x39 }
        'cancel' { return [UInt16]0x01 }
        default { throw '未知兌換按鍵。' }
    }
}

function Test-DialogBar {
    param([double]$Current, [double]$Base, [double]$Dialog)
    $contrast=$Base-$Dialog
    if ($contrast -lt 20) { return $false }
    return ($Current -lt ($Base+$Dialog)/2 -and $Current -le $Dialog+[Math]::Max(12,[Math]::Min(25,$contrast*0.25)))
}

function Get-EntryAction {
    param([string]$Screen, [bool]$TimedOut, [int]$Attempts, [int]$DialogHits)
    if ($Screen -eq 'dialog' -and $DialogHits -ge 2) { return 'ready' }
    if (!$TimedOut) { return 'wait' }
    if ($Screen -eq 'base' -and $Attempts -lt 2) { return 'retry' }
    return 'stop'
}
