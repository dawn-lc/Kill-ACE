::BATCH_START
@ECHO off
SETLOCAL EnableDelayedExpansion
SET RequiresRunAdmin=yes
TITLE Initializing Script...
CD /d %~dp0
SET ScriptPath=\^"%~f0\^"
SET ScriptRoot=%~dp0
SET ScriptRoot=\^"!ScriptRoot:~0,-1!\^"
SET Args=%*
IF DEFINED Args ( SET Args=!Args:"=\"! )
SET "PSSH=PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass"
<NUL SET /p="Checking powershell ... "
WHERE /q PowerShell 
IF !ERRORLEVEL! NEQ 0 ( ECHO Fail & ECHO PowerShell is not installed. & PAUSE & EXIT )
ECHO OK
IF /I !RequiresRunAdmin!=="no" ( GOTO NotRunAdmin )
<NUL SET /p="Checking execute permissions ... "
!PSSH! -Command "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 1 }"
IF !ERRORLEVEL! NEQ 0 ( ECHO Fail & ECHO Restart with administrator & !PSSH! -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList '/k CD /d !ScriptRoot! && !ScriptPath! !Args!'" & EXIT )
ECHO OK
:NotRunAdmin
<NUL SET /p="Checking powershell version ... "
!PSSH! -Command "if ($PSVersionTable.PSVersion.Major -lt 3) { exit 1 }"
IF !ERRORLEVEL! NEQ 0 ( ECHO Fail & ECHO Requires PowerShell 3 or later. & PAUSE & EXIT )
ECHO OK
<NUL SET /p="Extract embedded script ... "
!PSSH! -Command "$START = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('OjpCQVRDSF9TVEFSVA==')); $END = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('OjpCQVRDSF9FTkQ=')); $content = ((Get-Content -Path '%~f0' -Raw -Encoding UTF8) -replace '(?s)' + $START + '.*?' + $END).Trim(); if ($content.Length -cle 0) { exit 1 } else { Set-Content -Path '%~f0.ps1' -Value $content -Encoding UTF8 }"
IF !ERRORLEVEL! NEQ 0 ( ECHO Fail & ECHO Embedded script section not found. & PAUSE & EXIT )
ECHO OK
ECHO Execute script
!PSSH! -File "%~f0.ps1" %*
ECHO Delete the execution cache
DEL /f /q "%~f0.ps1"
EXIT
::BATCH_END
# 参数定义
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("stop-service", "limit-process", "all")]
    [string]$Action,
    [Parameter(Mandatory = $false)]
    [switch]$NoMenu
)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("zh-CN")
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo("zh-CN")
function Show-Pause {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Text = "按任意键继续...",
        [string]$Color = "Cyan"
    )
    Write-Host "$Text" -ForegroundColor $Color
    [System.Console]::ReadKey($true) > $null
}
function Clear-CurrentLine {
    $width = [Console]::WindowWidth
    Write-Host ("`r" + (" " * $width) + "`r") -NoNewline
}
function Invoke-Timeout {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Seconds,
        [string]$Template = "剩余 {0} 秒. {1}",
        [string]$Text = "按任意键继续...",
        [switch]$NoBreak
    )
    if ($NoBreak) { $Text = "" }
    $line = "`r$($Template -f $Seconds, $Text)"
    while ($Host.UI.RawUI.KeyAvailable) {
        [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    for ($i = $Seconds; $i -gt 0; $i--) {
        $line = "`r$($Template -f $i, $Text)"
        Write-Host -NoNewline $line
        for ($j = 0; $j -lt 10; $j++) {
            Start-Sleep -Milliseconds 100
            if (-not $NoBreak -and $Host.UI.RawUI.KeyAvailable) {
                [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                return
            }
        }
    }
    Clear-CurrentLine
}
function Show-MultipleChoicePrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Options,
        [string[]]$Helps = @(),
        [string]$Title = "",
        [int]$DefaultIndex = 0
    )
    if ($Helps.Count -eq 0) {
        $Helps = @("")
        for ($i = 1; $i -lt $Options.Count; $i++) {
            $Helps += ""
        }
    }
    if ($Options.Count -ne $Helps.Count) {
        throw "Options 和 Helps 的数量必须相同。"
    }
    if ($DefaultIndex -ge $Options.Count) {
        $DefaultIndex = $Options.Count - 1
    }
    $currentSelection = $DefaultIndex
    function Show-Menu {
        param(
            [int]$highlightIndex,
            [string]$title,
            [string]$message,
            [string[]]$options,
            [string[]]$helps,
            [int]$prevIndex = -1
        )
        try {
            # 首次显示时绘制完整菜单
            if ($prevIndex -eq -1) {
                Clear-Host
                if (-not [string]::IsNullOrEmpty($title)) {
                    Write-Host "`n$title`n" -ForegroundColor Blue
                }
                Write-Host "$message" -ForegroundColor Yellow
                # 保存初始光标位置
                $script:menuTop = [Console]::CursorTop
                # 首次绘制所有选项
                for ($i = 0; $i -lt $options.Count; $i++) {
                    $prefix = if ($i -eq $highlightIndex) { "[>]" } else { "[ ]" }
                    $color = if ($i -eq $highlightIndex) { "Green" } else { "Gray" }
                    Write-Host "$prefix $($options[$i])" -ForegroundColor $color -NoNewline
                    Write-Host $(if (-not [string]::IsNullOrEmpty($helps[$i])) { " - $($helps[$i])" } else { "" }) -ForegroundColor DarkGray
                }
            }
            # 只更新变化的选项
            if ($prevIndex -ne -1) {
                $safePrevPos = [Math]::Min([Console]::WindowHeight - 1, $menuTop + $prevIndex)
                [Console]::SetCursorPosition(0, $safePrevPos)
                Write-Host "[ ] $($options[$prevIndex])" -ForegroundColor Gray -NoNewline
                Write-Host $(if (-not [string]::IsNullOrEmpty($helps[$prevIndex])) { " - $($helps[$prevIndex])" } else { "" }) -ForegroundColor DarkGray
            }
            $safeHighlightPos = [Math]::Min([Console]::WindowHeight - 1, $menuTop + $highlightIndex)
            [Console]::SetCursorPosition(0, $safeHighlightPos)
            Write-Host "[>] $($options[$highlightIndex])" -ForegroundColor Green -NoNewline
            Write-Host $(if (-not [string]::IsNullOrEmpty($helps[$highlightIndex])) { " - $($helps[$highlightIndex])" } else { "" }) -ForegroundColor DarkGray
            # 首次显示时绘制操作提示
            if ($prevIndex -eq -1) {
                $safePos = [Math]::Min([Console]::WindowHeight - 2, $menuTop + $options.Count)
                [Console]::SetCursorPosition(0, $safePos)
                Write-Host "操作: 使用 ↑ / ↓ 移动 | Enter - 确认"
            }
        }
        finally {
            # 将光标移动到操作提示下方等待位置
            $waitPos = [Math]::Min([Console]::WindowHeight - 1, $menuTop + $options.Count + 1)
            [Console]::SetCursorPosition(0, $waitPos)
        }
    }
    $prevSelection = -1
    while ($true) {
        Show-Menu -highlightIndex $currentSelection -title $Title -message $Message -options $Options -helps $Helps -prevIndex $prevSelection
        $prevSelection = $currentSelection
        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            { $_ -eq [ConsoleKey]::UpArrow } {
                $currentSelection = [Math]::Max(0, $currentSelection - 1)
            }
            { $_ -eq [ConsoleKey]::DownArrow } {
                $currentSelection = [Math]::Min($Options.Count - 1, $currentSelection + 1)
            }
            { $_ -eq [ConsoleKey]::Enter } {
                Clear-Host
                return $currentSelection
            }
        }
    }
}
function New-Shortcut {
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut("$env:USERPROFILE\Desktop\ACE Kill.lnk")
        $Shortcut.Arguments = "-Action all -NoMenu"
        $Shortcut.TargetPath = "$($pwd.Path)\main.cmd"
        $Shortcut.IconLocation = "$env:ProgramFiles\AntiCheatExpert\Uninstaller.exe"
        $Shortcut.WorkingDirectory = $pwd.Path
        $Shortcut.Save()
        Write-Host "快捷方式创建成功！" -ForegroundColor Green
    }
    catch {
        Write-Host "无法创建快捷方式`n错误： $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Stop-ACEProcesses {
    [CmdletBinding()]
    param()
    # 目标进程名称（白名单进程不终止）
    $processNames = @(
        "SGuardSvc64",
        "SGuard64",
        "ACE-Tray", 
        "browser", 
        "delta_force_launcher"
    )
    $whitelist = @(
        "delta_force_launcher",
        "browser",
        "AclosGameProxy",
        "CrossProxy", 
        "无畏契约登录器"
    )
    # 检查 wmic 可用性
    $wmicAvailable = $true
    try {
        & wmic /? | Out-Null
    }
    catch {
        $wmicAvailable = $false
        Write-Host "警告：wmic 不可用，I/O 优先级设置和部分终止方法可能受限。" -ForegroundColor Yellow
    }
    # 获取 CPU 核数量
    $cpuCount = [Environment]::ProcessorCount
    $lastCpuMask = [IntPtr] (1 -shl ($cpuCount - 1))
    Write-Host "CPU 核数量: $cpuCount, 最后一个 CPU 核: $($cpuCount - 1), 掩码: $lastCpuMask" -ForegroundColor White
    foreach ($name in $processNames) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $processes) {
            Write-Host "未找到进程: $name" -ForegroundColor Yellow
            continue
        }
        foreach ($process in $processes) {
            Write-Host "找到进程: $($process.Name), PID: $($process.Id)" -ForegroundColor White
            # 设置 CPU 亲和性
            try {
                $process.ProcessorAffinity = $lastCpuMask
                Write-Host "已将 $($process.Name) 的 CPU 亲和性设置为 CPU $($cpuCount - 1)" -ForegroundColor Green
            }
            catch {
                Write-Host "无法设置 $($process.Name) 的 CPU 亲和性: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            # 设置进程优先级
            try {
                $process.PriorityClass = "Idle"
                Write-Host "已将 $($process.Name) 的优先级设置为低 (Idle)" -ForegroundColor Green
            }
            catch {
                Write-Host "无法设置 $($process.Name) 的优先级: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            # 设置 I/O 优先级
            try {
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    Set-ProcessIoPriority -Id $process.Id -Priority VeryLow -ErrorAction Stop
                    Write-Host "已将 $($process.Name) 的 I/O 优先级设置为非常低 (Very Low)" -ForegroundColor Green
                }
                elseif ($wmicAvailable) {
                    & wmic process where processid=$($process.Id) call setpriority 1
                    Write-Host "已将 $($process.Name) 的 I/O 优先级设置为非常低 (Very Low, via wmic)" -ForegroundColor Green
                }
                else {
                    Write-Host "无法设置 $($process.Name) 的 I/O 优先级：系统不支持" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "无法设置 $($process.Name) 的 I/O 优先级: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            # 终止非白名单进程
            if ($whitelist -notcontains $name) {
                Write-Host "尝试终止进程: $($process.Name), PID: $($process.Id)" -ForegroundColor White
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Write-Host "已通过 Stop-Process 成功终止 $($process.Name)" -ForegroundColor Green
                    continue
                }
                catch {
                    Write-Host "Stop-Process 无法终止 $($process.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
                try {
                    & taskkill /PID $($process.Id) /F
                    Write-Host "已通过 taskkill 成功终止 $($process.Name)" -ForegroundColor Green
                    continue
                }
                catch {
                    Write-Host "taskkill 无法终止 $($process.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
                if ($wmicAvailable) {
                    try {
                        & wmic process where processid=$($process.Id) call terminate
                        Write-Host "已通过 wmic 成功终止 $($process.Name)" -ForegroundColor Green
                        continue
                    }
                    catch {
                        Write-Host "wmic 无法终止 $($process.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
            else {
                Write-Host "进程 $($process.Name) 在白名单中，仅限制运行，不终止" -ForegroundColor Cyan
            }
        }
    }
}
function Set-ACEServices {
    [CmdletBinding()]
    param()
    $serviceNames = @("AntiCheatExpert Service", "AntiCheatExpert Protection")
    foreach ($service in $serviceNames) {
        Write-Host "查找服务: $service" -ForegroundColor White
        $svc = Get-Service -DisplayName $service -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq "Running") {
                try {
                    Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                    Write-Host "已停止服务: $service" -ForegroundColor Green
                }
                catch {
                    Write-Host "无法停止服务 ${service}: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            try {
                Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
                Write-Host "已将服务 ${service} 的启动类型设置为手动" -ForegroundColor Green
            }
            catch {
                Write-Host "无法设置服务 ${service} 的启动类型: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "未找到服务: $service" -ForegroundColor Yellow
        }
    }
}
function Show-MainMenu {
    [CmdletBinding()]
    param()
    $options = @(
        "1. 停止 ACE 服务",
        "2. 限制 ACE 进程", 
        "3. 创建快捷方式",
        "4. 退出"
    )
    $helps = @(
        "停止 AntiCheatExpert 相关服务并设置为手动启动",
        "限制 ACE 进程的 CPU、内存和 I/O 优先级",
        "在桌面创建ACE Kill快捷方式",
        "退出本程序"
    )
    $choice = Show-MultipleChoicePrompt -Title "ACE Kill" -Message "请选择操作:" -Options $options -Helps $helps
    switch ($choice) {
        0 { 
            Set-ACEServices
        }
        1 { 
            Stop-ACEProcesses
        }
        2 {
            New-Shortcut
        }
        3 {
            exit
        }
    }
    Show-Pause -Text "按任意键返回主菜单..."
    Show-MainMenu
}
# 主程序入口
$host.ui.rawui.WindowTitle = "ACE Kill"
Clear-Host
# 参数处理逻辑
if ($Action) {
    switch ($Action) {
        "stop-service" { Set-ACEServices }
        "limit-process" { Stop-ACEProcesses }
        "all" { 
            Set-ACEServices
            Stop-ACEProcesses
        }
    }
    if (-not $NoMenu) {
        Show-Pause -Text "按任意键返回主菜单..."
        Show-MainMenu
    } 
    else {
        Invoke-Timeout -Seconds 2 -Text "按任意键退出..."
        exit
    }
}
else {
    Show-MainMenu
}
