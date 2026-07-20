# agent-status 安装与本机管理（Windows PowerShell）
# 交互：irm https://raw.githubusercontent.com/ynlea/agent-status/main/scripts/install.ps1 | iex
# 非交互：
#   .\install.ps1 install -Role monitor -ServerUrl http://127.0.0.1:29125 -Key KEY -Yes
#   .\install.ps1 update  -Role all -Version v0.1.1 -Yes
#   .\install.ps1 status  -Role all
#   .\install.ps1 uninstall -Purge -Yes
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'update', 'status', 'start', 'stop', 'restart', 'enable', 'disable', 'config', 'init-agents', 'uninstall', '')]
    [string]$Command = 'install',

    [Parameter(Position = 1)]
    [ValidateSet('get', 'set', '')]
    [string]$ConfigAction = '',

    [ValidateSet('server', 'monitor', 'all', '')]
    [string]$Role = '',

    [switch]$Yes,
    [string]$Version = 'latest',
    [string]$ServerUrl = '',
    [string]$Key = '',
    [string]$Addr = ':29125',
    [switch]$NoInitAgents,
    [switch]$NoEnable,
    [string]$LocalBin = '',
    [switch]$ForceConfig,
    [switch]$Purge,
    [string[]]$Set = @()
)

$ErrorActionPreference = 'Stop'
$Repo = if ($env:AGENT_STATUS_REPO) { $env:AGENT_STATUS_REPO } else { 'ynlea/agent-status' }
$InstallRoot = if ($env:AGENT_STATUS_HOME) { $env:AGENT_STATUS_HOME } else { Join-Path $env:LOCALAPPDATA 'agent-status' }
$BinDir = Join-Path $InstallRoot 'bin'
$ConfigDir = Join-Path $InstallRoot 'config'
$DataDir = Join-Path $InstallRoot 'data'
$LogDir = Join-Path $InstallRoot 'logs'
$StateDir = Join-Path $InstallRoot 'state'

function Write-Log([string]$Message) { Write-Host $Message }
function Write-Info([string]$Message) { Write-Host "  ›  $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "  ✓  $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  !  $Message" -ForegroundColor Yellow }
function Write-Hr([string]$Char = '─') {
    $line = ($Char * 54)
    Write-Host "  $line" -ForegroundColor DarkGray
}
function Write-Step([string]$Message) {
    $script:UiStepCur = [int]$script:UiStepCur + 1
    Write-Host ""
    Write-Hr
    if ([int]$script:UiStepTotal -gt 0) {
        Write-Host ("  ● 步骤 {0}/{1}  {2}" -f $script:UiStepCur, $script:UiStepTotal, $Message) -ForegroundColor Magenta
    } else {
        Write-Host "  ●  $Message" -ForegroundColor Magenta
    }
    Write-Hr
}
function Write-Banner([string]$Title = '安装向导') {
    Write-Host ""
    Write-Host '  ╭──────────────────────────────────────────────────────╮' -ForegroundColor DarkCyan
    Write-Host '  │                                                      │' -ForegroundColor DarkCyan
    Write-Host '  │    █████╗  ███████╗                                 │' -ForegroundColor Cyan
    Write-Host '  │   ██╔══██╗ ██╔════╝                                 │' -ForegroundColor Cyan
    Write-Host '  │   ███████║ ███████╗  agent-status                   │' -ForegroundColor Blue
    Write-Host '  │   ██╔══██║ ╚════██║  会话监测 · 用量统计 · 安装器     │' -ForegroundColor DarkBlue
    Write-Host '  │   ██║  ██║ ███████║                                 │' -ForegroundColor Magenta
    Write-Host '  │   ╚═╝  ╚═╝ ╚══════╝                                 │' -ForegroundColor DarkMagenta
    Write-Host '  │                                                      │' -ForegroundColor DarkCyan
    Write-Host ("  │   ▸ {0,-48} │" -f $Title) -ForegroundColor DarkCyan
    Write-Host '  ╰──────────────────────────────────────────────────────╯' -ForegroundColor DarkCyan
    Write-Host ""
}
function Write-Done([string]$Message = '完成', [string]$Dir = '') {
    Write-Host ""
    Write-Host '  ╭──────────────────────────────────────────────────────╮' -ForegroundColor Green
    Write-Host "  │  ✦  $Message" -ForegroundColor Green
    if ($Dir) { Write-Host "  │  目录  $Dir" -ForegroundColor DarkGray }
    Write-Host '  │  提示  install.ps1 status | update | restart' -ForegroundColor DarkGray
    Write-Host '  ╰──────────────────────────────────────────────────────╯' -ForegroundColor Green
    Write-Host ""
}
function Write-Kv([string]$Key, [string]$Value) {
    Write-Host ("  {0,-10} {1}" -f $Key, $Value) -ForegroundColor Gray
}
function Format-PrettyPath([string]$P) {
    if ($env:USERPROFILE -and $P.StartsWith($env:USERPROFILE, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '~' + $P.Substring($env:USERPROFILE.Length)
    }
    if ($env:LOCALAPPDATA -and $P.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '%LOCALAPPDATA%' + $P.Substring($env:LOCALAPPDATA.Length)
    }
    return $P
}
function Write-PathLine([string]$Key, [string]$P) {
    Write-Host ("  {0,-10} " -f $Key) -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-PrettyPath $P) -ForegroundColor Cyan
}
function Format-HumanSize([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}
function Write-ProgressBar([long]$Current, [long]$Total) {
    $w = 36
    $pct = 0
    if ($Total -gt 0) { $pct = [math]::Min(100, [int](100.0 * $Current / $Total)) }
    $filled = [int]($w * $pct / 100)
    $bar = ('█' * $filled) + ('░' * ($w - $filled))
    $curS = Format-HumanSize $Current
    $totS = if ($Total -gt 0) { Format-HumanSize $Total } else { '?' }
    Write-Host ("`r  [{0}] {1,3}%  {2} / {3}   " -f $bar, $pct, $curS, $totS) -NoNewline -ForegroundColor Cyan
}
function Die([string]$Message) {
    Write-Host "  ✗  $Message" -ForegroundColor Red
    throw $Message
}

function Ensure-Dirs {
    @(
        $InstallRoot, $BinDir, $ConfigDir, $DataDir, $LogDir, $StateDir
    ) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
}

function Get-RandomKey {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Test-Interactive {
    try { return [Environment]::UserInteractive -and -not $Yes } catch { return -not $Yes }
}

function Read-Prompt([string]$Message, [string]$Default = '') {
    if ($Default) {
        $ans = Read-Host "$Message [$Default]"
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        return $ans
    }
    return Read-Host $Message
}

function Get-ReleaseTag {
    if ($Version -ne 'latest') { return $Version }
    $headers = @{ 'User-Agent' = 'agent-status-installer' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    elseif ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
        if (-not $rel.tag_name) { throw "empty tag" }
        return $rel.tag_name
    } catch {
        if ("$_" -match 'rate limit') {
            Die "GitHub API 限流。请用 -Version v0.1.1 指定版本，或设置 GITHUB_TOKEN / GH_TOKEN 环境变量。"
        }
        Die "无法获取 $Repo 的最新 Release（请确认仓库已公开且已发版）"
    }
}

function Stop-RoleProcesses([string]$RoleName) {
    # 覆盖 exe 前必须释放文件锁（Windows 不允许替换正在运行的二进制）
    $procName = if ($RoleName -eq 'server') { 'agent-status-server' } else { 'agent-status-monitor' }
    $dest = Join-Path $BinDir ($procName + '.exe')
    $stopped = $false

    $pidPath = Get-PidPath $RoleName
    if (Test-Path $pidPath) {
        $old = Get-Content $pidPath -ErrorAction SilentlyContinue
        if ($old) {
            $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
            if ($p) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                $stopped = $true
            }
        }
        Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
    }

    Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }

    # 按完整路径再扫一遍（进程名被改过时）
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $dest) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped = $true
        }

    if ($stopped) {
        Write-Info "已停止运行中的 $RoleName，以便替换二进制"
        Start-Sleep -Milliseconds 500
    }
}

function Copy-BinaryWithRetry([string]$Src, [string]$Dest, [int]$Retries = 5) {
    $last = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Copy-Item $Src $Dest -Force -ErrorAction Stop
            return
        } catch {
            $last = $_
            Start-Sleep -Milliseconds (300 * $i)
        }
    }
    throw "无法写入 $Dest（文件仍被占用）。请先关闭 agent-status 进程后重试。`n$last"
}

function Install-Binary([string]$RoleName) {
    $destName = if ($RoleName -eq 'server') { 'agent-status-server.exe' } else { 'agent-status-monitor.exe' }
    $dest = Join-Path $BinDir $destName

    # 先停进程，避免 Windows 文件锁
    if (Test-Path $dest) {
        Stop-RoleProcesses $RoleName
    }

    if ($LocalBin) {
        $src = Join-Path $LocalBin $destName
        if (-not (Test-Path $src)) {
            $src = Join-Path $LocalBin ("agent-status-{0}-windows-amd64.exe" -f $RoleName)
        }
        if (-not (Test-Path $src)) { Die "本地二进制不存在于: $LocalBin" }
        if (Test-Path $dest) {
            Copy-Item $dest "$dest.bak" -Force -ErrorAction SilentlyContinue
            Write-Info "已备份 $(Format-PrettyPath "$dest.bak")"
        }
        Copy-BinaryWithRetry $src $dest
        Write-PathLine '安装到' $dest
        Write-Ok '二进制就绪（本地文件）'
        return
    }

    $tag = Get-ReleaseTag
    $asset = if ($RoleName -eq 'server') {
        'agent-status-server-windows-amd64.exe'
    } else {
        'agent-status-monitor-windows-amd64.exe'
    }
    $url = "https://github.com/$Repo/releases/download/$tag/$asset"
    $tmp = Join-Path $env:TEMP $asset
    Write-Host ("  {0,-10} {1}  " -f '资源', $asset) -NoNewline -ForegroundColor DarkGray
    Write-Host "($tag)" -ForegroundColor Magenta
    Write-PathLine '目标' $tmp
    Write-Host ("  {0,-10} " -f '来源') -NoNewline -ForegroundColor DarkGray
    Write-Host $url -ForegroundColor DarkGray

    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.UserAgent = 'agent-status-installer'
        $req.Method = 'GET'
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create)
        $buffer = New-Object byte[] (256KB)
        $read = 0L
        $cur = 0L
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $read)
            $cur += $read
            if ($total -gt 0) { Write-ProgressBar $cur $total }
        }
        $fs.Close(); $stream.Close(); $resp.Close()
        if ($total -gt 0) {
            Write-ProgressBar $cur $total
            Write-Host ""
        }
        Write-Ok ("下载完成  {0}" -f (Format-HumanSize $cur))
    } catch {
        Write-Info '改用 Invoke-WebRequest 下载...'
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        $cur = (Get-Item $tmp).Length
        Write-Ok ("下载完成  {0}" -f (Format-HumanSize $cur))
    }

    if (Test-Path $dest) {
        Copy-Item $dest "$dest.bak" -Force -ErrorAction SilentlyContinue
        Write-Info "已备份 $(Format-PrettyPath "$dest.bak")"
    }
    # 再次确保无锁（下载期间可能被计划任务拉起）
    Stop-RoleProcesses $RoleName
    Copy-BinaryWithRetry $tmp $dest
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-PathLine '安装到' $dest
    Write-Ok '二进制就绪'
}

function Write-ServerEnv([string]$KeyValue, [string]$AddrValue) {
    $path = Join-Path $ConfigDir 'server.env'
    if ((Test-Path $path) -and -not $ForceConfig) {
        Write-PathLine '保留配置' $path
        return
    }
    if (Test-Path $path) {
        Copy-Item $path ("$path.bak-{0:yyyyMMddHHmmss}" -f (Get-Date)) -Force
    }
    $db = Join-Path $DataDir 'agent-status.db'
    @"
AGENT_STATUS_ADDR=$AddrValue
AGENT_STATUS_KEY=$KeyValue
AGENT_STATUS_DB=$db
"@ | Set-Content -Path $path -Encoding UTF8
    Write-PathLine '写入' $path; Write-Ok '配置已就绪'
}

function Write-MonitorJson([string]$Url, [string]$KeyValue) {
    $path = Join-Path $ConfigDir 'monitor.json'
    if ((Test-Path $path) -and -not $ForceConfig) {
        Write-PathLine '保留配置' $path
        return
    }
    if (Test-Path $path) {
        Copy-Item $path ("$path.bak-{0:yyyyMMddHHmmss}" -f (Get-Date)) -Force
    }
    $machine = $env:COMPUTERNAME
    $obj = [ordered]@{
        server_url           = $Url
        key                  = $KeyValue
        machine_id           = $machine
        machine_name         = $machine
        platform             = 'windows'
        report_interval_sec  = 60
        codex_file_watch     = $true
        codex_sessions_dir   = ''
        state_file           = ''
    }
    $obj | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
    Write-PathLine '写入' $path; Write-Ok '配置已就绪'
}

function Get-PidPath([string]$RoleName) {
    Join-Path $StateDir ("$RoleName.pid")
}

function Get-TaskName([string]$RoleName) {
    if ($RoleName -eq 'server') { return 'AgentStatusServer' }
    return 'AgentStatusMonitor'
}

function Get-StartInfo([string]$RoleName) {
    if ($RoleName -eq 'server') {
        $exe = Join-Path $BinDir 'agent-status-server.exe'
        $envFile = Join-Path $ConfigDir 'server.env'
        if (-not (Test-Path $envFile)) { Die "缺少文件 $envFile" }
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
            $k, $v = $_ -split '=', 2
            Set-Item -Path "Env:$k" -Value $v
        }
        return @{ FilePath = $exe; ArgumentList = @(); Log = (Join-Path $LogDir 'server.log') }
    }
    $exe = Join-Path $BinDir 'agent-status-monitor.exe'
    $cfg = Join-Path $ConfigDir 'monitor.json'
    return @{ FilePath = $exe; ArgumentList = @('-config', $cfg); Log = (Join-Path $LogDir 'monitor.log') }
}

function Start-Role([string]$RoleName) {
    $pidPath = Get-PidPath $RoleName
    if (Test-Path $pidPath) {
        $old = Get-Content $pidPath -ErrorAction SilentlyContinue
        if ($old) {
            $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
            if ($p) {
                Write-Log "$RoleName 已在运行 pid=$old"
                return
            }
        }
    }
    $info = Get-StartInfo $RoleName
    # PowerShell 不允许 stdout/stderr 重定向到同一文件，因此拆成 .log / .err.log
    $logOut = $info.Log
    $logErr = [System.IO.Path]::ChangeExtension($logOut, '.err.log')
    if ($logOut -eq $logErr) { $logErr = "$logOut.err" }
    New-Item -ItemType Directory -Force -Path (Split-Path $logOut) | Out-Null
    $p = Start-Process -FilePath $info.FilePath -ArgumentList $info.ArgumentList -WorkingDirectory $InstallRoot `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    Set-Content -Path $pidPath -Value $p.Id -Encoding ascii
    Write-Log "已启动 $RoleName pid=$($p.Id)"
}

function Stop-Role([string]$RoleName) {
    $pidPath = Get-PidPath $RoleName
    if (Test-Path $pidPath) {
        $old = Get-Content $pidPath -ErrorAction SilentlyContinue
        if ($old) {
            Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
    }
    # fallback by name
    $name = if ($RoleName -eq 'server') { 'agent-status-server' } else { 'agent-status-monitor' }
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Log "已停止 $RoleName"
}

function Enable-Role([string]$RoleName) {
    $task = Get-TaskName $RoleName
    $info = Get-StartInfo $RoleName
    $arg = ($info.ArgumentList -join ' ')
    $action = New-ScheduledTaskAction -Execute $info.FilePath -Argument $arg -WorkingDirectory $InstallRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Log "已启用开机任务 $task"
}

function Disable-Role([string]$RoleName) {
    $task = Get-TaskName $RoleName
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "已关闭开机任务 $task"
}

function Expand-Roles([string]$R) {
    if ([string]::IsNullOrWhiteSpace($R) -or $R -eq 'all') {
        $list = @()
        if (Test-Path (Join-Path $BinDir 'agent-status-server.exe')) { $list += 'server' }
        if (Test-Path (Join-Path $BinDir 'agent-status-monitor.exe')) { $list += 'monitor' }
        if ($list.Count -eq 0) { Die '尚未安装，请指定 -Role server|monitor' }
        return $list
    }
    return @($R)
}

function Detect-Claude {
    if (Get-Command claude -ErrorAction SilentlyContinue) { return $true }
    $p = Join-Path $env:USERPROFILE '.claude'
    return (Test-Path $p)
}

function Detect-Codex {
    if (Get-Command codex -ErrorAction SilentlyContinue) { return $true }
    $p = Join-Path $env:USERPROFILE '.codex'
    return (Test-Path $p)
}

function Init-Agents {
    $mon = Join-Path $BinDir 'agent-status-monitor.exe'
    $cfg = Join-Path $ConfigDir 'monitor.json'
    if (-not (Test-Path $mon)) { Die '监测端二进制不存在' }
    if (-not (Test-Path $cfg)) { Die "监测端配置不存在: $cfg" }

    $claudeOk = Detect-Claude
    $codexOk = Detect-Codex
    $claudeDir = Join-Path $env:USERPROFILE '.claude'
    $codexDir = Join-Path $env:USERPROFILE '.codex'

    Write-Host ''
    Write-Host '  ╭─ Agent 探测 ──────────────────────────────────────────╮' -ForegroundColor Magenta
    if ($claudeOk) {
        $p = if (Test-Path $claudeDir) { '  ' + (Format-PrettyPath $claudeDir) } else { '' }
        Write-Host ("  │  ●  Claude Code    已发现{0}" -f $p) -ForegroundColor Green
    } else {
        Write-Host '  │  ○  Claude Code    未发现' -ForegroundColor DarkGray
    }
    if ($codexOk) {
        $p = if (Test-Path $codexDir) { '  ' + (Format-PrettyPath $codexDir) } else { '' }
        Write-Host ("  │  ●  Codex          已发现{0}" -f $p) -ForegroundColor Green
    } else {
        Write-Host '  │  ○  Codex          未发现' -ForegroundColor DarkGray
    }
    Write-Host '  ╰──────────────────────────────────────────────────────╯' -ForegroundColor Magenta

    if ($claudeOk) {
        Write-Info '初始化 Claude Code hooks...'
        try {
            $out = & $mon --init --claude --config $cfg 2>&1 | Out-String
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw $out }
            $settings = Join-Path $claudeDir 'settings.json'
            if ($out -match '设置文件=([^\s]+)') { $settings = $Matches[1] }
            $added = if ($out -match '新增事件数=(\d+)') { $Matches[1] } else { '0' }
            $updated = if ($out -match '更新事件数=(\d+)') { $Matches[1] } else { '0' }
            Write-PathLine '设置文件' $settings
            Write-Ok ("Claude hooks 已配置  新增 {0} · 更新 {1}" -f $added, $updated)
        } catch {
            Write-Warn "Claude hooks 初始化失败: $_"
        }
    } else {
        Write-Info '跳过 Claude hooks（未检测到 Claude Code）'
    }
    if ($codexOk) {
        Write-Info 'Codex 走文件监听，无需额外 hooks'
    }
}

function Show-Status {
    Write-Host ""
    Write-Host '  ╭──────────────────────────────────────────────────────╮' -ForegroundColor DarkCyan
    Write-Host '  │  系统状态                                             │' -ForegroundColor DarkCyan
    Write-Host '  ╰──────────────────────────────────────────────────────╯' -ForegroundColor DarkCyan
    foreach ($r in Expand-Roles $Role) {
        Write-Host ""
        Write-Host "  ◆ $r" -ForegroundColor Magenta
        Write-Hr '·'
        $exe = Join-Path $BinDir ("agent-status-{0}.exe" -f $r)
        if (Test-Path $exe) {
            Write-Kv '二进制' $exe
            if ($r -eq 'monitor') {
                try {
                    $ver = & $exe -version 2>$null
                    if ($ver) { Write-Kv '版本' "$ver" }
                } catch {}
            }
        } else {
            Write-Kv '二进制' '缺失'
        }
        $pidPath = Get-PidPath $r
        if (Test-Path $pidPath) {
            $id = Get-Content $pidPath
            $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
            if ($p) { Write-Kv '进程' "● running  pid=$id" }
            else { Write-Kv '进程' "○ stale pid=$id" }
        } else {
            Write-Kv '进程' '○ stopped'
        }
        if ($r -eq 'server' -and (Test-Path (Join-Path $ConfigDir 'server.env'))) {
            Get-Content (Join-Path $ConfigDir 'server.env') | ForEach-Object {
                if ($_ -match '^AGENT_STATUS_KEY=') { Write-Kv 'KEY' '****' }
                elseif ($_ -match '^AGENT_STATUS_ADDR=(.*)$') { Write-Kv 'ADDR' $Matches[1] }
                elseif ($_ -match '^AGENT_STATUS_DB=(.*)$') { Write-Kv 'DB' $Matches[1] }
            }
        }
        if ($r -eq 'monitor' -and (Test-Path (Join-Path $ConfigDir 'monitor.json'))) {
            $j = Get-Content (Join-Path $ConfigDir 'monitor.json') -Raw | ConvertFrom-Json
            if ($j.server_url) { Write-Kv 'URL' $j.server_url }
            $hostName = if ($j.machine_name) { $j.machine_name } else { $j.machine_id }
            if ($hostName) { Write-Kv '机器' $hostName }
            if ($j.platform) { Write-Kv '平台' $j.platform }
            Write-Kv 'KEY' '****'
        }
    }
    Write-Host ""
}

function Get-ExistingMonitorConfig {
    $path = Join-Path $ConfigDir 'monitor.json'
    if (-not (Test-Path $path)) { return $null }
    try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-ExistingServerKey {
    $envPath = Join-Path $ConfigDir 'server.env'
    if (-not (Test-Path $envPath)) { return '' }
    $line = Get-Content $envPath | Where-Object { $_ -match '^AGENT_STATUS_KEY=' } | Select-Object -First 1
    if ($line) { return $line.Substring('AGENT_STATUS_KEY='.Length) }
    return ''
}

function Fill-Interactive {
    if ([string]::IsNullOrWhiteSpace($Role)) {
        if (-not (Test-Interactive)) { Die '非交互安装请指定 -Role 与 -Yes' }
        Write-Host '  选择要安装的角色' -ForegroundColor White
        Write-Host '  ┌────────────────────────────────────────────────────┐' -ForegroundColor DarkGray
        Write-Host '  │  1  服务端 server     接收上报、WebSocket、API      │' -ForegroundColor DarkGray
        Write-Host '  │  2  监测端 monitor    扫描会话 / 用量并上报         │' -ForegroundColor DarkGray
        Write-Host '  │  3  两者都装 all      本机完整部署                  │' -ForegroundColor DarkGray
        Write-Host '  └────────────────────────────────────────────────────┘' -ForegroundColor DarkGray
        $c = Read-Prompt '请输入序号' '2'
        switch ($c) {
            '1' { $script:Role = 'server' }
            '2' { $script:Role = 'monitor' }
            '3' { $script:Role = 'all' }
            default { Die '无效选项' }
        }
    }

    $wantServer = $Role -eq 'server' -or $Role -eq 'all'
    $wantMonitor = $Role -eq 'monitor' -or $Role -eq 'all'
    $existingMon = Get-ExistingMonitorConfig
    $existingKey = Get-ExistingServerKey
    $keepMonitorCfg = $wantMonitor -and $existingMon -and -not $ForceConfig
    $keepServerCfg = $wantServer -and (Test-Path (Join-Path $ConfigDir 'server.env')) -and -not $ForceConfig

    if ($wantServer) {
        if ($keepServerCfg) {
            Write-Log "复用已有服务端配置"
            if (-not $Key -and $existingKey) { $script:Key = $existingKey }
        } else {
            if (-not $Key) {
                if ($existingKey) {
                    if (Test-Interactive) {
                        $script:Key = Read-Prompt '服务端密钥（留空沿用已有）' $existingKey
                    } else {
                        $script:Key = $existingKey
                    }
                } elseif (Test-Interactive) {
                    $script:Key = Read-Prompt '服务端密钥（留空则自动生成）' ''
                }
                if (-not $script:Key) { $script:Key = Get-RandomKey }
            }
            if (Test-Interactive -and -not $Yes) {
                $script:Addr = Read-Prompt '监听地址' $Addr
            }
        }
    }

    if ($wantMonitor) {
        $defaultUrl = if ($existingMon -and $existingMon.server_url) { [string]$existingMon.server_url } else { 'http://127.0.0.1:29125' }
        $defaultKey = ''
        if ($existingMon -and $existingMon.key) { $defaultKey = [string]$existingMon.key }
        if (-not $defaultKey -and $existingKey) { $defaultKey = $existingKey }
        if (-not $defaultKey -and $Key) { $defaultKey = $Key }

        if ($keepMonitorCfg) {
            Write-Log "复用已有监测端配置（$defaultUrl）"
            if (-not $ServerUrl) { $script:ServerUrl = $defaultUrl }
            if (-not $Key) { $script:Key = $defaultKey }
        } else {
            if (-not $ServerUrl) {
                if (Test-Interactive) {
                    $script:ServerUrl = Read-Prompt '服务端地址' $defaultUrl
                } else {
                    $script:ServerUrl = $defaultUrl
                }
            }
            if (-not $Key) {
                if (Test-Interactive) {
                    if ($defaultKey) {
                        $script:Key = Read-Prompt '共享密钥（留空沿用已有）' $defaultKey
                    } else {
                        $script:Key = Read-Prompt '共享密钥' ''
                    }
                } else {
                    $script:Key = $defaultKey
                }
            }
            if (-not $Key) { Die '安装监测端需要 -Key' }
        }
    }
}

function Invoke-Install {
    Write-Banner '安装向导'
    Ensure-Dirs
    Fill-Interactive
    $wantServer = $Role -eq 'server' -or $Role -eq 'all'
    $wantMonitor = $Role -eq 'monitor' -or $Role -eq 'all'

    $script:UiStepCur = 0
    $script:UiStepTotal = 1
    if ($wantServer) { $script:UiStepTotal++ }
    if ($wantMonitor) { $script:UiStepTotal++ }
    if ($wantMonitor -and -not $NoInitAgents) { $script:UiStepTotal++ }

    if ($wantServer) {
        Write-Step '安装服务端'
        Install-Binary server
        Write-ServerEnv $Key $Addr
        Write-Ok '服务端就绪'
    }
    if ($wantMonitor) {
        Write-Step '安装监测端'
        Install-Binary monitor
        Write-MonitorJson $ServerUrl $Key
        Write-Ok '监测端就绪'
    }

    Write-Step '启用并启动'
    if (-not $NoEnable) {
        if ($wantServer) { Enable-Role server; Start-Role server }
        if ($wantMonitor) { Enable-Role monitor; Start-Role monitor }
    } else {
        if ($wantServer) { Start-Role server }
        if ($wantMonitor) { Start-Role monitor }
    }
    Write-Ok '服务已启动'

    if ($wantMonitor -and -not $NoInitAgents) {
        Write-Step '初始化 Agent'
        try { Init-Agents } catch { Write-Warn "init-agents: $_" }
    }

    # Persist manager script for later status/start/stop
    try {
        $dest = Join-Path $InstallRoot 'install.ps1'
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            Copy-Item $PSCommandPath $dest -Force
        } else {
            $url = "https://raw.githubusercontent.com/$Repo/main/scripts/install.ps1"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        }
        Write-Ok "管理脚本: $dest"
    } catch {
        Write-Warn "无法保存 install.ps1: $_"
    }

    Write-Done '安装完成' $InstallRoot
    Show-Status
}

function Invoke-Config {
    if (-not $ConfigAction) { $ConfigAction = 'get' }
    if ($ConfigAction -eq 'get') {
        foreach ($r in Expand-Roles $(if ($Role) { $Role } else { 'all' })) {
            if ($r -eq 'server') {
                $p = Join-Path $ConfigDir 'server.env'
                if (Test-Path $p) {
                    Get-Content $p | ForEach-Object {
                        if ($_ -match '^AGENT_STATUS_KEY=') { 'AGENT_STATUS_KEY=****' } else { $_ }
                    }
                }
            } else {
                $p = Join-Path $ConfigDir 'monitor.json'
                if (Test-Path $p) {
                    $j = Get-Content $p -Raw | ConvertFrom-Json
                    $j.key = '****'
                    $j | ConvertTo-Json
                }
            }
        }
        return
    }

    if (-not $Role -or $Role -eq 'all') { Die 'config set 需要 -Role server|monitor' }
    if (-not $Set -or $Set.Count -eq 0) { Die 'config set 需要 -Set KEY=VALUE' }
    foreach ($pair in $Set) {
        $k, $v = $pair -split '=', 2
        if (-not $v -and $pair -notmatch '=') { Die "参数格式错误: $pair" }
        if ($Role -eq 'server') {
            $p = Join-Path $ConfigDir 'server.env'
            if (-not (Test-Path $p)) { Die "缺少文件 $p" }
            Copy-Item $p ("$p.bak-{0:yyyyMMddHHmmss}" -f (Get-Date)) -Force
            switch ($k) {
                'key' { $k = 'AGENT_STATUS_KEY' }
                'addr' { $k = 'AGENT_STATUS_ADDR' }
                'db' { $k = 'AGENT_STATUS_DB' }
            }
            $lines = Get-Content $p
            $found = $false
            $lines = $lines | ForEach-Object {
                if ($_ -match "^$k=") { $found = $true; "$k=$v" } else { $_ }
            }
            if (-not $found) { $lines += "$k=$v" }
            $lines | Set-Content $p -Encoding UTF8
            Write-Log "已更新 $p 的 $k"
        } else {
            $p = Join-Path $ConfigDir 'monitor.json'
            if (-not (Test-Path $p)) { Die "缺少文件 $p" }
            Copy-Item $p ("$p.bak-{0:yyyyMMddHHmmss}" -f (Get-Date)) -Force
            switch ($k) {
                'server-url' { $k = 'server_url' }
                'machine-id' { $k = 'machine_id' }
                'machine-name' { $k = 'machine_name' }
            }
            $j = Get-Content $p -Raw | ConvertFrom-Json
            $j | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force
            $j | ConvertTo-Json | Set-Content $p -Encoding UTF8
            Write-Log "已更新 $p 的 $k"
        }
    }
}

function Remove-ClaudeHooks {
    $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
    if (-not (Test-Path $settings)) {
        Write-Info '未找到 Claude settings，跳过 hooks 清理'
        return
    }
    try {
        $doc = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "无法解析 Claude settings: $_"
        return
    }
    if (-not $doc.hooks) {
        Write-Info 'Claude settings 中无 hooks'
        return
    }
    $changed = 0
    $hookObj = $doc.hooks
    $props = @($hookObj.PSObject.Properties.Name)
    foreach ($event in $props) {
        $groups = @($hookObj.$event)
        if ($groups.Count -eq 0) { continue }
        $newGroups = @()
        foreach ($g in $groups) {
            if (-not $g.hooks) { $newGroups += $g; continue }
            $kept = @()
            foreach ($h in @($g.hooks)) {
                $cmd = [string]$h.command
                if ($cmd -match 'agent-status-monitor' -and $cmd -match 'claude-hook') {
                    $changed++
                    continue
                }
                $kept += $h
            }
            if ($kept.Count -gt 0) {
                $g.hooks = $kept
                $newGroups += $g
            }
        }
        if ($newGroups.Count -gt 0) {
            $hookObj | Add-Member -NotePropertyName $event -NotePropertyValue $newGroups -Force
        } else {
            $hookObj.PSObject.Properties.Remove($event)
        }
    }
    if ($changed -eq 0) {
        Write-Info 'Claude settings 中无 agent-status hooks'
        return
    }
    $bak = "$settings.agent-status.uninstall.bak"
    Copy-Item $settings $bak -Force
    $doc.hooks = $hookObj
    $doc | ConvertTo-Json -Depth 20 | Set-Content -Path $settings -Encoding UTF8
    Write-PathLine '设置文件' $settings
    Write-PathLine '备份' $bak
    Write-Ok "已移除 $changed 条 agent-status hooks"
}

function Invoke-Uninstall {
    Write-Banner '卸载'
    $roles = @()
    if ([string]::IsNullOrWhiteSpace($Role) -or $Role -eq 'all') {
        if (Test-Path (Join-Path $BinDir 'agent-status-server.exe')) { $roles += 'server' }
        if (Test-Path (Join-Path $BinDir 'agent-status-monitor.exe')) { $roles += 'monitor' }
        # 计划任务也可能还在
        if (-not $roles) {
            $roles = @('server', 'monitor')
        }
    } else {
        $roles = @($Role)
    }

    if ($Purge) {
        Write-Host '  ╭──────────────────────────────────────────────────────╮' -ForegroundColor Yellow
        Write-Host '  │  将彻底删除：服务进程 / 计划任务 / 安装目录           │' -ForegroundColor Yellow
        Write-Host '  │  以及用量游标与 Claude hooks                          │' -ForegroundColor Yellow
        Write-Host '  ╰──────────────────────────────────────────────────────╯' -ForegroundColor Yellow
        if (-not $Yes) {
            $ans = Read-Host '  确认彻底卸载并清理全部数据? [y/N]'
            if ($ans -notmatch '^(y|yes|Y)$') {
                Write-Info '已取消卸载'
                return
            }
        }
    } else {
        Write-Info '标准卸载：停止服务并移除开机任务，保留安装目录'
        Write-Info '彻底清理请加：-Purge -Yes'
    }

    $script:UiStepCur = 0
    $script:UiStepTotal = if ($Purge) { 5 } else { 2 }

    Write-Step '停止进程'
    foreach ($r in $roles) {
        Stop-RoleProcesses $r
        Stop-Role $r
        Write-Ok "已停止 $r"
    }

    Write-Step '移除开机任务'
    foreach ($r in $roles) {
        Disable-Role $r
        Write-Ok "已移除任务 $(Get-TaskName $r)"
    }

    if ($Purge) {
        Write-Step '删除安装目录'
        if (Test-Path $InstallRoot) {
            # 再确保无残留锁
            foreach ($r in $roles) { Stop-RoleProcesses $r }
            Start-Sleep -Milliseconds 300
            Remove-Item -Recurse -Force $InstallRoot -ErrorAction SilentlyContinue
            if (Test-Path $InstallRoot) {
                Write-Warn "部分文件未能删除（可能仍被占用）：$InstallRoot"
            } else {
                Write-PathLine '已删除' $InstallRoot
                Write-Ok '安装目录已清理'
            }
        } else {
            Write-Info '安装目录不存在，跳过'
        }

        Write-Step '清理用量游标'
        $asHome = Join-Path $env:USERPROFILE '.agent-status'
        if (Test-Path $asHome) {
            Remove-Item -Recurse -Force $asHome -ErrorAction SilentlyContinue
            Write-PathLine '已删除' $asHome
            Write-Ok '用量游标目录已清理'
        } else {
            Write-Info '无 ~/.agent-status，跳过'
        }

        Write-Step '清理 Claude Code hooks'
        Remove-ClaudeHooks
    } else {
        Write-Info "已保留安装目录：$(Format-PrettyPath $InstallRoot)"
    }

    Write-Done '卸载完成'
}

function Invoke-Update {
    Write-Banner '更新二进制'
    $roles = Expand-Roles $(if ($Role) { $Role } else { 'all' })
    $script:UiStepCur = 0
    $script:UiStepTotal = @($roles).Count
    foreach ($r in $roles) {
        Write-Step "更新 $r"
        Stop-Role $r
        Install-Binary $r
        Start-Role $r
        Write-Ok "已更新 $r"
    }
    Write-Done '更新完成' $InstallRoot
    Show-Status
}

# When piped via irm | iex, $PSCommandPath may be empty; still allow running as function-like
if ([string]::IsNullOrWhiteSpace($Command)) { $Command = 'install' }

switch ($Command) {
    'install' { Invoke-Install }
    'update'   { Invoke-Update }
    'status'   { Show-Status }
    'start' { foreach ($r in Expand-Roles $Role) { Start-Role $r } }
    'stop' { foreach ($r in Expand-Roles $Role) { Stop-Role $r } }
    'restart' { foreach ($r in Expand-Roles $Role) { Stop-Role $r; Start-Role $r } }
    'enable' { foreach ($r in Expand-Roles $Role) { Enable-Role $r } }
    'disable' { foreach ($r in Expand-Roles $Role) { Disable-Role $r } }
    'config' { Invoke-Config }
    'init-agents' { Init-Agents }
    'uninstall' { Invoke-Uninstall }
    default { Die "未知命令: $Command" }
}
