# seo+geo agent public bootstrap — installs private jamesserr/seo-geo-agent
# Usage: iex(irm https://raw.githubusercontent.com/jamesserr/sg/main/i.ps1)
# iex-safe: no top-level param()
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 | Out-Null } catch {}

$RepoSlug = "jamesserr/seo-geo-agent"
$InstallRoot = Join-Path $env:LOCALAPPDATA "seo-geo-agent\seo-geo-agent"
$PatSettingsUrl = "https://github.com/settings/tokens"

function Write-Banner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  seo+geo agent  ·  bootstrap (private)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "安装目录: $InstallRoot"
    Write-Host "仓库:     $RepoSlug"
    Write-Host ""
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-PathFromMachine {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machine -or $user) {
        $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ";"
    }
    foreach ($d in @(
        "${env:ProgramFiles}\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\cmd",
        "${env:ProgramFiles}\GitHub CLI",
        "${env:LOCALAPPDATA}\Programs\GitHub CLI"
    )) {
        if ((Test-Path (Join-Path $d "git.exe")) -or (Test-Path (Join-Path $d "gh.exe"))) {
            if ($env:Path -notlike "*$d*") { $env:Path = "$d;$env:Path" }
        }
    }
}

function Test-RepoComplete {
    param([string]$Path)
    if (-not $Path) { return $false }
    return (Test-Path (Join-Path $Path "server.py")) -and (Test-Path (Join-Path $Path "requirements.txt"))
}

function Test-GhApiOk {
    try {
        & gh api user 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Ensure-Winget {
    if (-not (Test-CommandExists "winget")) {
        throw "未找到 winget，无法自动安装。请从微软商店安装「应用安装程序」后重跑。"
    }
}

function Ensure-GitInstalled {
    if (Test-CommandExists "git") {
        Write-Host "[git] 已检测到" -ForegroundColor Green
        return
    }
    Write-Host "[git] 未检测到 Git，尝试 winget 安装 Git.Git ..." -ForegroundColor Yellow
    Ensure-Winget
    & winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget 安装 Git.Git 失败。" }
    Refresh-PathFromMachine
    if (-not (Test-CommandExists "git")) {
        Write-Host "[错误] Git 已安装但当前会话找不到。请关闭窗口后重跑。" -ForegroundColor Red
        exit 1
    }
    Write-Host "[git] 安装成功" -ForegroundColor Green
}

function Ensure-GhInstalled {
    if (Test-CommandExists "gh") {
        Write-Host "[gh] 已检测到 GitHub CLI" -ForegroundColor Green
        return
    }
    Write-Host "[gh] 未检测到 GitHub CLI，尝试 winget 安装 GitHub.cli ..." -ForegroundColor Yellow
    Ensure-Winget
    & winget install -e --id GitHub.cli --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget 安装 GitHub.cli 失败。" }
    Refresh-PathFromMachine
    if (-not (Test-CommandExists "gh")) {
        Write-Host "[错误] gh 已安装但当前会话找不到。请关闭窗口后重跑。" -ForegroundColor Red
        exit 1
    }
    Write-Host "[gh] 安装成功" -ForegroundColor Green
}

function Prompt-ClassicPat {
    Write-Host ""
    Write-Host "[认证] 设备登录失败或未完成（常见于国内网络 dial tcp github.com:443）。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "请改用 classic PAT（Personal Access Token）:" -ForegroundColor Cyan
    Write-Host "  1. 浏览器打开: $PatSettingsUrl"
    Write-Host "  2. Generate new token (classic) → 勾选 repo（读私有仓）"
    Write-Host "  3. 生成后复制，粘贴到下方（仅本窗口会话，不写磁盘）"
    Write-Host ""
    try { Start-Process $PatSettingsUrl } catch {}
    $token = Read-Host "粘贴 GitHub classic PAT 后回车"
    if (-not $token -or $token.Trim().Length -lt 8) {
        throw "未提供有效 PAT，无法继续。"
    }
    $env:GH_TOKEN = $token.Trim()
    if (-not (Test-GhApiOk)) {
        $env:GH_TOKEN = $null
        throw "PAT 无效或无法访问 api.github.com。请检查 token（repo 权限）与网络后重试。"
    }
    Write-Host "[认证] PAT 已生效（GH_TOKEN 仅当前会话）" -ForegroundColor Green
}

function Ensure-GhAuth {
    if ($env:GH_TOKEN -and $env:GH_TOKEN.Trim().Length -gt 0) {
        Write-Host "[认证] 检测到 GH_TOKEN，验证中 ..."
        if (Test-GhApiOk) {
            Write-Host "[认证] GH_TOKEN 有效" -ForegroundColor Green
            return
        }
        Write-Host "[警告] 已有 GH_TOKEN 无效，将重新认证 ..." -ForegroundColor Yellow
        $env:GH_TOKEN = $null
    }

    $authOk = $false
    try {
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $authOk = $true }
    } catch { $authOk = $false }

    if ($authOk) {
        Write-Host "[认证] gh 已登录" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "[认证] gh 未登录。先尝试交互式 gh auth login（设备码）…" -ForegroundColor Yellow
    Write-Host "若国内网络 dial tcp github.com:443 失败 / 超时，登录会失败，随后可粘贴 PAT。" -ForegroundColor Cyan
    Write-Host "登录账号须为 $RepoSlug 的 owner / collaborator。"
    Write-Host ""

    $loginOk = $false
    try {
        & gh auth login
        if ($LASTEXITCODE -eq 0) {
            & gh auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $loginOk = $true }
        }
    } catch { $loginOk = $false }

    if ($loginOk) {
        Write-Host "[认证] gh 已登录" -ForegroundColor Green
        return
    }

    Prompt-ClassicPat
}

function Expand-RepoZipTo {
    param([string]$ZipPath, [string]$Dest)

    $unzip = Join-Path $env:TEMP ("seo-geo-unzip-" + [guid]::NewGuid().ToString("N"))
    try {
        if (Test-Path $unzip) { Remove-Item -LiteralPath $unzip -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $unzip -Force | Out-Null
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $unzip -Force

        $top = Get-ChildItem -LiteralPath $unzip -Force | Select-Object -First 1
        $src = $unzip
        if ($top -and $top.PSIsContainer -and -not (Test-Path (Join-Path $unzip "server.py"))) {
            $src = $top.FullName
        }

        if (-not (Test-Path $Dest)) {
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null
        }
        Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
            if ($_.Name -eq ".venv") { return }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Recurse -Force
        }
        if (-not (Test-RepoComplete $Dest)) {
            throw "解压后目录不完整: $Dest"
        }
    } finally {
        Remove-Item -LiteralPath $unzip -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-RepoViaZipFallback {
    param([string]$Dest)

    $zipFile = Join-Path $env:TEMP ("seo-geo-agent-" + [guid]::NewGuid().ToString("N") + ".zip")
    try {
        $got = $false

        if ($env:SEO_GEO_AGENT_ZIP_URL -and $env:SEO_GEO_AGENT_ZIP_URL.Trim().Length -gt 0) {
            Write-Host "[回退] 下载 SEO_GEO_AGENT_ZIP_URL ..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $env:SEO_GEO_AGENT_ZIP_URL.Trim() -OutFile $zipFile -UseBasicParsing
                if ((Test-Path $zipFile) -and ((Get-Item $zipFile).Length -gt 1000)) { $got = $true }
            } catch {
                Write-Host "[警告] 镜像 URL 下载失败: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if (-not $got) {
            Write-Host "[回退] gh api repos/$RepoSlug/zipball/main ..." -ForegroundColor Yellow
            & gh api "repos/$RepoSlug/zipball/main" --output $zipFile 2>&1 | Out-Null
            if (($LASTEXITCODE -eq 0) -and (Test-Path $zipFile) -and ((Get-Item $zipFile).Length -gt 1000)) {
                $got = $true
            }
        }

        if (-not $got -and $env:GH_TOKEN) {
            Write-Host "[回退] HTTPS zipball + GH_TOKEN ..." -ForegroundColor Yellow
            $headers = @{
                Authorization = "Bearer $($env:GH_TOKEN)"
                Accept        = "application/vnd.github+json"
            }
            try {
                Invoke-WebRequest -Uri "https://api.github.com/repos/$RepoSlug/zipball/main" -Headers $headers -OutFile $zipFile -UseBasicParsing
                if ((Test-Path $zipFile) -and ((Get-Item $zipFile).Length -gt 1000)) { $got = $true }
            } catch {
                Write-Host "[警告] zipball 下载失败: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if (-not $got) {
            throw "无法获取仓库。请确认网络、PAT(repo) 权限，或设置 SEO_GEO_AGENT_ZIP_URL。"
        }

        Expand-RepoZipTo -ZipPath $zipFile -Dest $Dest
        Write-Host "[回退] zip 获取成功: $Dest" -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-RepoViaGh {
    param([string]$Dest)

    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $gitDir = Join-Path $Dest ".git"
    if ((Test-Path $gitDir) -and (Test-RepoComplete $Dest)) {
        Write-Host "[克隆] 已有仓库，正在 pull ..."
        Push-Location $Dest
        try {
            & git pull --ff-only 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[警告] git pull 未完全成功，继续使用现有文件。" -ForegroundColor Yellow
            } else {
                Write-Host "[克隆] 已更新到最新" -ForegroundColor Green
            }
        } finally {
            Pop-Location
        }
        return
    }

    if (Test-RepoComplete $Dest) {
        Write-Host "[克隆] 使用已有本地代码: $Dest" -ForegroundColor Green
        return
    }

    if (Test-Path $Dest) {
        $items = @(Get-ChildItem -Force $Dest -ErrorAction SilentlyContinue)
        if ($items.Count -eq 0) {
            Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        } elseif (-not (Test-RepoComplete $Dest)) {
            Write-Host "[克隆] 目标目录不完整，改用临时目录克隆后覆盖 ..." -ForegroundColor Yellow
            $tmp = Join-Path $env:TEMP ("seo-geo-agent-gh-" + [guid]::NewGuid().ToString("N"))
            try {
                $cloneOk = $false
                & gh repo clone $RepoSlug $tmp -- --depth 1 2>&1 | Out-Host
                if (($LASTEXITCODE -eq 0) -and (Test-RepoComplete $tmp)) {
                    $cloneOk = $true
                } else {
                    Write-Host "[警告] gh repo clone 失败，尝试 zip / 镜像回退 ..." -ForegroundColor Yellow
                    Get-RepoViaZipFallback -Dest $tmp
                    $cloneOk = Test-RepoComplete $tmp
                }
                if (-not $cloneOk) { throw "无法获取 $RepoSlug" }
                if (-not (Test-Path $Dest)) {
                    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
                }
                Get-ChildItem -LiteralPath $tmp -Force | ForEach-Object {
                    if ($_.Name -eq ".venv") { return }
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Recurse -Force
                }
                if (-not (Test-RepoComplete $Dest)) { throw "获取后目录仍不完整: $Dest" }
                Write-Host "[克隆] 完成: $Dest" -ForegroundColor Green
                return
            } finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host "[克隆] gh repo clone $RepoSlug → $Dest ..."
    & gh repo clone $RepoSlug $Dest -- --depth 1 2>&1 | Out-Host
    if (($LASTEXITCODE -ne 0) -or -not (Test-RepoComplete $Dest)) {
        Write-Host "[警告] gh repo clone 失败，尝试 zip / 镜像回退 ..." -ForegroundColor Yellow
        if (Test-Path $Dest) {
            $partial = @(Get-ChildItem -Force $Dest -ErrorAction SilentlyContinue)
            if ($partial.Count -eq 0) {
                Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
            }
        }
        Get-RepoViaZipFallback -Dest $Dest
    }
    if (-not (Test-RepoComplete $Dest)) { throw "获取仓库失败: $Dest" }
    Write-Host "[克隆] 完成: $Dest" -ForegroundColor Green
}

function Start-App {
    param([string]$Dest)
    $startCmd = Join-Path $Dest "start.cmd"
    if (-not (Test-Path $startCmd)) {
        throw "找不到 start.cmd: $startCmd"
    }
    Write-Host ""
    Write-Host "[启动] 调用 start.cmd ..." -ForegroundColor Cyan
    Write-Host "工作台将打印可点击地址 http://127.0.0.1:端口/"
    Write-Host ""
    & cmd.exe /c "call `"$startCmd`""
}

# ---------- main ----------
Write-Banner
Refresh-PathFromMachine
Ensure-GitInstalled
Ensure-GhInstalled
Ensure-GhAuth
Ensure-RepoViaGh -Dest $InstallRoot
Start-App -Dest $InstallRoot
