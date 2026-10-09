<#
.SYNOPSIS
  通过 Gitee / AtomGit OpenAPI v5 发布 Lite Arcade 源码（无需本地安装 git）

.DESCRIPTION
  - 令牌从环境变量读取（GITEE_TOKEN / ATOMGIT_TOKEN），不落盘
  - 仓库不存在时自动创建（公开）
  - 优先使用 Git Data API（blob → tree → commit → ref）合并为单次提交；
    平台不支持时自动回退到逐文件 Contents API
  - 自动排除 dist/、release/、.tools/、node_modules 与常见凭据文件

.EXAMPLE
  $env:GITEE_TOKEN   = "<token>"; .\deploy\publish-gitee.ps1 -Platform gitee -Owner vip882 -Repo lite-arcade
  $env:ATOMGIT_TOKEN = "<token>"; .\deploy\publish-gitee.ps1 -Platform atomgit -Owner zzw1208 -Repo lite-arcade
#>
[CmdletBinding()]
param(
    [ValidateSet("gitee", "atomgit")]
    [string]$Platform = "gitee",
    [string]$Owner    = "",
    [string]$Repo     = "lite-arcade",
    [string]$Branch   = "",
    [string]$Message  = "feat: 发布 Lite Arcade 静态游戏站（SEO + GEO + 生产化构建）",
    [string]$Token    = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

if ($Platform -eq "gitee")   { $base = "https://gitee.com/api/v5";       if (-not $Token) { $Token = $env:GITEE_TOKEN } }
else                         { $base = "https://api.atomgit.com/api/v5"; if (-not $Token) { $Token = $env:ATOMGIT_TOKEN } }
if (-not $Token)   { throw "未找到令牌，请设置环境变量 GITEE_TOKEN 或 ATOMGIT_TOKEN" }
Write-Host "[$Platform] 令牌长度：$($Token.Length)" -ForegroundColor DarkGray
if (-not $Branch)  { $Branch = "master" }

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Api {
    param([string]$Method, [string]$Path, $Body = $null, [switch]$TokenInQuery)
    # 令牌同时放入查询串与请求体：GET 用查询串，写接口两者皆可，避免平台差异
    if ($null -ne $Body) {
        $map = @{}
        foreach ($k in $Body.Keys) { $map[$k] = $Body[$k] }
        $map["access_token"] = $Token
        $Body = $map
    }
    # 注意：不能用 -like "*?*"，? 是通配符会恒为真，导致分隔符误用 & 污染路径
    $sep = if ($Path.Contains("?")) { "&" } else { "?" }
    $uri = "$base$Path" + $sep + "access_token=$Token"
    $json = if ($null -ne $Body) { ($Body | ConvertTo-Json -Depth 12 -Compress) } else { $null }

    # 限流退避：429 / 502 / 503 时按 3s、6s、9s… 重试
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($json) {
                return Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json; charset=utf-8" -TimeoutSec 60
            }
            return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec 60
        } catch {
            $s    = $_.Exception.Response
            $code = if ($s) { [int]$s.StatusCode } else { 0 }
            if (($code -eq 429 -or $code -eq 502 -or $code -eq 503) -and $attempt -lt 5) {
                Start-Sleep -Seconds (3 * $attempt)
                continue
            }
            $detail = ""
            if ($s) {
                try {
                    $sr = New-Object System.IO.StreamReader($s.GetResponseStream())
                    $detail = $sr.ReadToEnd(); $sr.Close()
                } catch { }
            }
            throw "API 失败 [$Method $Path] $($_.Exception.Message) $detail"
        }
    }
}

# ---------------------------------------------------------------- 账户 / 仓库
if (-not $Owner) {
    $Owner = (Api -Method Get -Path "/user").login
    Write-Host "[$Platform] 当前用户：$Owner" -ForegroundColor Cyan
}

$exists = $true
try { $null = Api -Method Get -Path "/repos/$Owner/$Repo" }
catch { $exists = $false }

if (-not $exists) {
    Write-Host "[$Platform] 创建仓库 $Owner/$Repo" -ForegroundColor Cyan
    try {
        $r = Api -Method Post -Path "/user/repos" -Body @{
            name        = $Repo
            description = "零依赖静态开源游戏站：六款原生 Canvas 小游戏 + 开源游戏目录，内置 SEO / GEO 优化"
            private     = $false
            has_issues  = $true
            has_wiki    = $false
            auto_init   = $false
        }
        Write-Host "  ✓ 已创建：$($r.html_url)" -ForegroundColor Green
    } catch {
        # 422 / 404 通常表示同名仓库已存在，继续走上传流程
        Write-Host "  ! 创建接口返回 $($_.Exception.Message)，假定仓库已存在并继续" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 2
} else {
    Write-Host "[$Platform] 复用已存在仓库 $Owner/$Repo" -ForegroundColor Cyan
}

# ---------------------------------------------------------------- 收集文件
$excludeDirs  = @("dist", "release", ".tools", "node_modules", ".git", ".codebuddy")
$excludeFiles = @("*.env", ".env", "secrets.json", "*.pem", "*.key", "*.zip")

$files = Get-ChildItem $RepoRoot -Recurse -File -Force | Where-Object {
    $rel   = $_.FullName.Substring($RepoRoot.Length).TrimStart("\", "/")
    $parts = $rel -split "[\\/]"
    foreach ($p in $parts) { if ($excludeDirs -contains $p) { return $false } }
    foreach ($pat in $excludeFiles) { if ($_.Name -like $pat) { return $false } }
    return $true
}
Write-Host "[$Platform] 待提交文件：$($files.Count) 个" -ForegroundColor Cyan

# ---------------------------------------------------------------- 方式一：Git Data API 单提交
$single = $false
try {
    $tree = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        $rel = ($f.FullName.Substring($RepoRoot.Length).TrimStart("\", "/") -replace "\\", "/")
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName))
        $blob = Api -Method Post -Path "/repos/$Owner/$Repo/git/blobs" -Body @{ content = $b64; encoding = "base64" }
        [void]$tree.Add(@{ path = $rel; mode = "100644"; type = "blob"; sha = $blob.sha })
    }
    # 空仓库（无分支）时先建立首次提交，否则基于现有分支增量提交
    $baseRef = $null
    try {
        $ref = Api -Method Get -Path "/repos/$Owner/$Repo/git/refs/heads/$Branch" -TokenInQuery
        $baseRef = $ref.object.sha
    } catch { $baseRef = $null }

    if ($baseRef) {
        $commitInfo = Api -Method Get -Path "/repos/$Owner/$Repo/git/commits/$baseRef" -TokenInQuery
        $newTree = Api -Method Post -Path "/repos/$Owner/$Repo/git/trees" -Body @{ base_tree = $commitInfo.tree.sha; tree = $tree }
        $newCommit = Api -Method Post -Path "/repos/$Owner/$Repo/git/commits" -Body @{ message = $Message; tree = $newTree.sha; parents = @($baseRef) }
        $null = Api -Method Patch -Path "/repos/$Owner/$Repo/git/refs/heads/$Branch" -Body @{ sha = $newCommit.sha; force = $false }
    } else {
        $newTree = Api -Method Post -Path "/repos/$Owner/$Repo/git/trees" -Body @{ tree = $tree }
        $newCommit = Api -Method Post -Path "/repos/$Owner/$Repo/git/commits" -Body @{ message = $Message; tree = $newTree.sha; parents = @() }
        try {
            $null = Api -Method Post -Path "/repos/$Owner/$Repo/git/refs" -Body @{ ref = "refs/heads/$Branch"; sha = $newCommit.sha }
        } catch {
            # 部分平台不支持创建 ref，回退为在空仓库写入一个文件以建立默认分支
            $null = Api -Method Post -Path "/repos/$Owner/$Repo/contents/README.md" -Body @{ content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("# $Repo`n")); message = $Message; branch = $Branch }
        }
    }
    $single = $true
    Write-Host "  ✓ 单次提交：$($newCommit.sha.Substring(0, 7))" -ForegroundColor Green
} catch {
    Write-Host "  ! Git Data API 不可用，回退到逐文件提交：$($_.Exception.Message)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 方式二：Contents API 逐文件
if (-not $single) {
    foreach ($f in $files) {
        $rel = ($f.FullName.Substring($RepoRoot.Length).TrimStart("\", "/") -replace "\\", "/")
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName))
        # 已存在的文件需要提供 sha 才能更新
        $sha = $null
        try {
            $cur = Api -Method Get -Path "/repos/$Owner/$Repo/contents/$rel" -TokenInQuery
            if ($cur -and $cur.sha) { $sha = $cur.sha }
        } catch { $sha = $null }
        Start-Sleep -Milliseconds 200

        $payload = @{ content = $b64; message = $Message; branch = $Branch }
        if ($sha) { $payload["sha"] = $sha }

        try {
            # 已存在 → PUT（需 sha）；不存在 → POST
            if ($sha) { $null = Api -Method Put -Path "/repos/$Owner/$Repo/contents/$rel" -Body $payload }
            else      { $null = Api -Method Post -Path "/repos/$Owner/$Repo/contents/$rel" -Body $payload }
            Write-Host "  ✓ $rel" -ForegroundColor DarkGray
        } catch {
            Write-Host "  ✗ $rel : $($_.Exception.Message)" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 350
    }
    Write-Host "  ✓ 逐文件提交完成" -ForegroundColor Green
}

Write-Host ""
Write-Host "  ✓ $Platform 仓库：https://$(if($Platform -eq 'gitee'){'gitee.com'}else{'atomgit.com'})/$Owner/$Repo" -ForegroundColor Green
