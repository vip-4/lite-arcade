<#
.SYNOPSIS
  通过 GitHub REST API 发布 Lite Arcade 源码（无需本地安装 git）

.DESCRIPTION
  - 读取环境变量 GITHUB_TOKEN（不要把令牌写进文件或命令行参数）
  - 仓库不存在时自动创建（默认 public，可用 -Private 改为私有）
  - 使用 Git Data API（blob → tree → commit → ref）把所有文件压缩为单次提交
  - 自动排除 dist/、release/ 与常见凭据文件

.EXAMPLE
  $env:GITHUB_TOKEN = "<your token>"
  .\deploy\publish-github.ps1 -Owner vip-4 -Repo lite-arcade
#>
[CmdletBinding()]
param(
    [string]$Owner   = "vip-4",
    [string]$Repo    = "lite-arcade",
    [string]$Branch  = "main",
    [string]$Message = "feat: 发布 Lite Arcade 静态游戏站（SEO + GEO + 生产化构建）",
    [string]$Token   = $env:GITHUB_TOKEN,
    [switch]$Private
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

if (-not $Token) { throw "未找到令牌，请先设置环境变量 GITHUB_TOKEN" }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$headers = @{
    Authorization = "Bearer $Token"
    "User-Agent"   = "lite-arcade-publish"
    Accept         = "application/vnd.github+json"
}

function Invoke-GitHub {
    param([string]$Method, [string]$Uri, $Body = $null)
    $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 12 -Compress } else { $null }
    try {
        if ($json) {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $json -ContentType "application/json; charset=utf-8"
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    } catch {
        $err = $_.Exception.Response
        $detail = ""
        if ($err) {
            $sr = New-Object System.IO.StreamReader($err.GetResponseStream())
            $detail = $sr.ReadToEnd()
            $sr.Close()
        }
        throw "GitHub API 调用失败 [$Method $Uri]：$($_.Exception.Message)`n$detail"
    }
}

# ---------------------------------------------------------------- 1. 确保仓库存在
$repoUrl = "https://api.github.com/repos/$Owner/$Repo"
$exists = $true
try { $null = Invoke-RestMethod -Uri $repoUrl -Headers $headers } catch { $exists = $false }

if (-not $exists) {
    Write-Host "[publish] 创建仓库 $Owner/$Repo" -ForegroundColor Cyan
    $created = Invoke-GitHub -Method Post -Uri "https://api.github.com/user/repos" -Body @{
        name        = $Repo
        description = "零依赖静态开源游戏站：六款原生 Canvas 小游戏 + 开源游戏目录，内置 SEO / GEO 优化"
        homepage    = "https://$Owner.github.io/$Repo/"
        private     = [bool]$Private
        auto_init   = $true
        license_template = "mit"
        has_issues  = $true
        has_wiki    = $false
    }
    Write-Host "  ✓ 已创建：$($created.html_url)" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "[publish] 复用已存在的仓库 $Owner/$Repo" -ForegroundColor Cyan
}

# ---------------------------------------------------------------- 2. 收集文件
$excludeDirs  = @("dist", "release", ".git", ".codebuddy", "node_modules")
$excludeFiles = @("*.env", ".env", "secrets.json", "*.pem", "*.key", "*.zip")

$files = Get-ChildItem $RepoRoot -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($RepoRoot.Length).TrimStart("\", "/")
    $parts = $rel -split "[\\/]"
    if ($excludeDirs -contains $parts[0]) { return $false }
    foreach ($p in $parts) { if ($excludeDirs -contains $p) { return $false } }
    foreach ($pat in $excludeFiles) { if ($_.Name -like $pat) { return $false } }
    return $true
}
Write-Host "[publish] 待提交文件：$($files.Count) 个" -ForegroundColor Cyan

# ---------------------------------------------------------------- 3. 创建 blob
$tree = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    $rel = ($f.FullName.Substring($RepoRoot.Length).TrimStart("\", "/") -replace "\\", "/")
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName))
    $blob = Invoke-GitHub -Method Post -Uri "https://api.github.com/repos/$Owner/$Repo/git/blobs" -Body @{
        content  = $b64
        encoding = "base64"
    }
    [void]$tree.Add(@{ path = $rel; mode = "100644"; type = "blob"; sha = $blob.sha })
    Write-Host "  ✓ blob $rel" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 4. 建树 → 提交 → 更新引用
$ref = Invoke-GitHub -Method Get -Uri "https://api.github.com/repos/$Owner/$Repo/git/ref/heads/$Branch"
$baseTreeSha = $ref.object.sha
$commitInfo = Invoke-GitHub -Method Get -Uri "https://api.github.com/repos/$Owner/$Repo/git/commits/$baseTreeSha"

$newTree = Invoke-GitHub -Method Post -Uri "https://api.github.com/repos/$Owner/$Repo/git/trees" -Body @{
    base_tree = $commitInfo.tree.sha
    tree      = $tree
}
Write-Host "  ✓ tree $($newTree.sha)" -ForegroundColor Green

$newCommit = Invoke-GitHub -Method Post -Uri "https://api.github.com/repos/$Owner/$Repo/git/commits" -Body @{
    message = $Message
    tree    = $newTree.sha
    parents = @($baseTreeSha)
}
Write-Host "  ✓ commit $($newCommit.sha)" -ForegroundColor Green

$null = Invoke-GitHub -Method Patch -Uri "https://api.github.com/repos/$Owner/$Repo/git/refs/heads/$Branch" -Body @{
    sha   = $newCommit.sha
    force = $false
}

Write-Host ""
Write-Host "  ✓ 已推送到 https://github.com/$Owner/$Repo/tree/$Branch" -ForegroundColor Green
Write-Host "  ✓ 提交：$($newCommit.sha.Substring(0,7)) — $Message" -ForegroundColor Green
