param([switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'Rights.cs')
if ($SelfTest) {
    if (![RedeemRights]::NeedsElevation(0x2000,0x3000)) { throw 'A normal tool must elevate for an administrator game.' }
    if ([RedeemRights]::NeedsElevation(0x3000,0x3000)) { throw 'An administrator tool must not elevate again.' }
    if ([RedeemRights]::NeedsElevation(0x2000,0x2000)) { throw 'Equal normal rights must not elevate.' }
    if ([RedeemRights]::NeedsElevation(-1,0x3000)) { throw 'Unknown rights must not cause automatic elevation.' }
    if ([RedeemRights]::ProcessIntegrity(-1) -ne -1) { throw 'Invalid process must return unknown rights.' }
    Write-Output 'Launcher tests passed: elevation decisions, no elevation loop, unknown rights handling.'
    exit 0
}
$toolPath=Join-Path $PSScriptRoot 'Redeem.ps1'
$own=[RedeemRights]::OwnIntegrity()
$elevate=$false
foreach ($game in @(Get-Process -Name wwm -ErrorAction SilentlyContinue)) {
    if ($game.MainWindowHandle -ne [IntPtr]::Zero -and [RedeemRights]::NeedsElevation($own,[RedeemRights]::ProcessIntegrity($game.Id))) {
        $elevate=$true; break
    }
}
if ($elevate) {
    Write-Host '遊戲使用管理員權限，正在以相同權限開啟工具。請自行完成 Windows 管理員確認。'
    try {
        $powershellPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments=@('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$toolPath+'"'))
        $null=Start-Process -FilePath $powershellPath -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -Verb RunAs -WindowStyle Hidden -PassThru
        exit 0
    } catch {
        Write-Host ('未能開啟管理員工具：'+$_.Exception.GetBaseException().Message) -ForegroundColor Red
        Write-Host '可關閉舊工具，再對 Start.cmd 按右鍵 → 以系統管理員身分執行。'
        exit 1
    }
}
& $toolPath
