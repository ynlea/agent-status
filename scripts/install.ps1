# agent-status 安装与本机管理（Windows PowerShell）
# 交互：irm https://raw.githubusercontent.com/ynlea/agent-status/main/scripts/install.ps1 | iex
# 非交互：
#   .\install.ps1 install -Role monitor -ServerUrl http://127.0.0.1:29125 -Key KEY -Yes
#   .\install.ps1 update  -Role all -Version v0.1.1 -Yes
#   .\install.ps1 status  -Role all
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
function Die([string]$Message) { throw $Message }

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

function Install-Binary([string]$RoleName) {
    $destName = if ($RoleName -eq 'server') { 'agent-status-server.exe' } else { 'agent-status-monitor.exe' }
    $dest = Join-Path $BinDir $destName

    if ($LocalBin) {
        $src = Join-Path $LocalBin $destName
        if (-not (Test-Path $src)) {
            $src = Join-Path $LocalBin ("agent-status-{0}-windows-amd64.exe" -f $RoleName)
        }
        if (-not (Test-Path $src)) { Die "本地二进制不存在于: $LocalBin" }
        if (Test-Path $dest) { Copy-Item $dest "$dest.bak" -Force }
        Copy-Item $src $dest -Force
        Write-Log "已安装 $dest（本地文件）"
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
    Write-Log "正在下载 $asset（$tag）"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    if (Test-Path $dest) { Copy-Item $dest "$dest.bak" -Force }
    Copy-Item $tmp $dest -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log "已安装 $dest"
}

function Write-ServerEnv([string]$KeyValue, [string]$AddrValue) {
    $path = Join-Path $ConfigDir 'server.env'
    if ((Test-Path $path) -and -not $ForceConfig) {
        Write-Log "保留已有配置 $path"
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
    Write-Log "已写入 $path"
}

function Write-MonitorJson([string]$Url, [string]$KeyValue) {
    $path = Join-Path $ConfigDir 'monitor.json'
    if ((Test-Path $path) -and -not $ForceConfig) {
        Write-Log "保留已有配置 $path"
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
    Write-Log "已写入 $path"
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
    $log = $info.Log
    $p = Start-Process -FilePath $info.FilePath -ArgumentList $info.ArgumentList -WorkingDirectory $InstallRoot `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $log
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
    Write-Log 'Agent 探测：'
    if (Detect-Claude) { Write-Log '  Claude Code：已发现' } else { Write-Log '  Claude Code：未发现' }
    if (Detect-Codex) { Write-Log '  Codex：已发现' } else { Write-Log '  Codex：未发现' }
    if (Detect-Claude) {
        Write-Log '正在初始化 Claude Code hooks...'
        & $mon --init --claude --config $cfg
    } else {
        Write-Log '跳过 Claude hooks（未检测到 Claude）'
    }
}

function Show-Status {
    foreach ($r in Expand-Roles $Role) {
        Write-Log "---- $r ----"
        $exe = Join-Path $BinDir ("agent-status-{0}.exe" -f $r)
        if (Test-Path $exe) { Write-Log "二进制: $exe" } else { Write-Log '二进制: 缺失' }
        $pidPath = Get-PidPath $r
        if (Test-Path $pidPath) {
            $id = Get-Content $pidPath
            $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
            if ($p) { Write-Log "运行中: pid=$id" } else { Write-Log "失效的 pid 文件: $id" }
        } else {
            Write-Log '运行中: 否'
        }
        if ($r -eq 'server' -and (Test-Path (Join-Path $ConfigDir 'server.env'))) {
            Get-Content (Join-Path $ConfigDir 'server.env') | ForEach-Object {
                if ($_ -match '^AGENT_STATUS_KEY=') { 'AGENT_STATUS_KEY=****' } else { $_ }
            }
        }
        if ($r -eq 'monitor' -and (Test-Path (Join-Path $ConfigDir 'monitor.json'))) {
            $j = Get-Content (Join-Path $ConfigDir 'monitor.json') -Raw | ConvertFrom-Json
            $j.key = '****'
            $j | ConvertTo-Json
        }
    }
}

function Fill-Interactive {
    if ([string]::IsNullOrWhiteSpace($Role)) {
        if (-not (Test-Interactive)) { Die '非交互安装请指定 -Role 与 -Yes' }
        Write-Log '请选择角色：'
        Write-Log '  1) 服务端 server'
        Write-Log '  2) 监测端 monitor'
        Write-Log '  3) 两者都装'
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

    if ($wantServer) {
        if (-not $Key) {
            if (Test-Interactive) {
                $script:Key = Read-Prompt '服务端密钥（留空则自动生成）' ''
            }
            if (-not $script:Key) { $script:Key = Get-RandomKey }
        }
        if (Test-Interactive -and -not $Yes) {
            $script:Addr = Read-Prompt '监听地址' $Addr
        }
    }

    if ($wantMonitor) {
        if (-not $ServerUrl) {
            if (Test-Interactive) {
                $script:ServerUrl = Read-Prompt '服务端地址' 'http://127.0.0.1:29125'
            } else {
                $script:ServerUrl = 'http://127.0.0.1:29125'
            }
        }
        if (-not $Key) {
            $envPath = Join-Path $ConfigDir 'server.env'
            if (Test-Path $envPath) {
                $line = Get-Content $envPath | Where-Object { $_ -match '^AGENT_STATUS_KEY=' } | Select-Object -First 1
                if ($line) { $script:Key = $line.Substring('AGENT_STATUS_KEY='.Length) }
            }
        }
        if (-not $Key) {
            if (Test-Interactive) {
                $script:Key = Read-Prompt '共享密钥' ''
            }
        }
        if (-not $Key) { Die '安装监测端需要 -Key' }
    }
}

function Invoke-Install {
    Ensure-Dirs
    Fill-Interactive
    $wantServer = $Role -eq 'server' -or $Role -eq 'all'
    $wantMonitor = $Role -eq 'monitor' -or $Role -eq 'all'

    if ($wantServer) {
        Install-Binary server
        Write-ServerEnv $Key $Addr
    }
    if ($wantMonitor) {
        Install-Binary monitor
        Write-MonitorJson $ServerUrl $Key
    }

    if (-not $NoEnable) {
        if ($wantServer) { Enable-Role server; Start-Role server }
        if ($wantMonitor) { Enable-Role monitor; Start-Role monitor }
    } else {
        if ($wantServer) { Start-Role server }
        if ($wantMonitor) { Start-Role monitor }
    }

    if ($wantMonitor -and -not $NoInitAgents) {
        try { Init-Agents } catch { Write-Log "init-agents: $_" }
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
        Write-Log "管理脚本: $dest"
    } catch {
        Write-Log "警告：无法保存 install.ps1: $_"
    }

    Write-Log "安装完成，目录：$InstallRoot"
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

function Invoke-Uninstall {
    $roles = Expand-Roles $(if ($Role) { $Role } else { 'all' })
    foreach ($r in $roles) {
        Stop-Role $r
        Disable-Role $r
    }
    if ($Purge) {
        Remove-Item -Recurse -Force $InstallRoot -ErrorAction SilentlyContinue
        Write-Log "已删除安装目录 $InstallRoot"
    } else {
        Write-Log "已保留 $InstallRoot（加 -Purge 可删除）"
    }
}

function Invoke-Update {
    $roles = Expand-Roles $(if ($Role) { $Role } else { 'all' })
    foreach ($r in $roles) {
        Write-Log "---- 更新 $r ----"
        Stop-Role $r
        Install-Binary $r
        Start-Role $r
        Write-Log "已更新 $r"
    }
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
