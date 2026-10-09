<#
.SYNOPSIS
  通过 Cloudflare Pages Direct Upload API 部署 dist（无需 wrangler / Node）

.DESCRIPTION
  - 读取环境变量 CLOUDFLARE_API_TOKEN（令牌不落盘、不进参数）
  - 项目不存在时自动创建
  - 以 SHA-1 清单 + multipart/form-data 一次性上传全部文件
  - 部署后自动轮询状态并校验线上可访问性

.EXAMPLE
  $env:CLOUDFLARE_API_TOKEN = "<token>"
  .\deploy\publish-cloudflare.ps1 -Project lite-arcade -BaseUrl "https://lite-arcade.pages.dev"
#>
[CmdletBinding()]
param(
    [string]$Project    = "lite-arcade",
    [string]$AccountId  = "",
    [string]$BaseUrl    = "https://lite-arcade.pages.dev",
    [string]$DistDir    = "",
    [string]$Branch     = "main",
    [string]$Token      = $env:CLOUDFLARE_API_TOKEN
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

if (-not $Token) { throw "未找到令牌，请先设置环境变量 CLOUDFLARE_API_TOKEN" }

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DistDir) { $DistDir = Join-Path $RepoRoot "dist" }
if (-not (Test-Path $DistDir)) { throw "未找到构建产物：$DistDir，请先执行 deploy\build.ps1" }

Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Security

$headers = @{ Authorization = "Bearer $Token"; "User-Agent" = "lite-arcade-publish" }
$api = "https://api.cloudflare.com/client/v4"

# ---------------------------------------------------------------- 账户
if (-not $AccountId) {
    $accts = (Invoke-RestMethod -Uri "$api/accounts" -Headers $headers).result
    if (@($accts).Count -eq 1) { $AccountId = $accts[0].id } else {
        throw "请通过 -AccountId 指定账户；可选：" + ((@($accts) | ForEach-Object { $_.id + '(' + $_.name + ')' }) -join ', ')
    }
}
Write-Host "[pages] 账户 $AccountId / 项目 $Project" -ForegroundColor Cyan

# ---------------------------------------------------------------- 确保项目存在
$projUrl = "$api/accounts/$AccountId/pages/projects/$Project"
$exists = $true
try { $null = Invoke-RestMethod -Uri $projUrl -Headers $headers } catch { $exists = $false }

if (-not $exists) {
    Write-Host "[pages] 创建项目 $Project" -ForegroundColor Cyan
    $created = Invoke-RestMethod -Method Post -Uri "$api/accounts/$AccountId/pages/projects" -Headers $headers `
        -ContentType "application/json" -Body (@{ name = $Project; production_branch = $Branch } | ConvertTo-Json -Compress)
    Write-Host "  ✓ 已创建：$($created.result.subdomain)" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "[pages] 复用已存在项目" -ForegroundColor Cyan
}

# ---------------------------------------------------------------- 构建清单（SHA-1）
$files = Get-ChildItem $DistDir -Recurse -File
$manifest = @{}
$sha1 = [System.Security.Cryptography.SHA1]::Create()
foreach ($f in $files) {
    $rel = ($f.FullName.Substring((Resolve-Path $DistDir).Path.Length).TrimStart("\") -replace "\\", "/")
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hash = -join ($sha1.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
    $manifest[$rel] = $hash
}
Write-Host "[pages] 待上传文件：$($files.Count) 个" -ForegroundColor Cyan

# ---------------------------------------------------------------- multipart 上传
$content = New-Object System.Net.Http.MultipartFormDataContent
$manifestJson = $manifest | ConvertTo-Json -Compress
$manifestPart = New-Object System.Net.Http.StringContent($manifestJson, [System.Text.Encoding]::UTF8)
$manifestPart.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/json")
$content.Add($manifestPart, "manifest")

foreach ($f in $files) {
    $rel = ($f.FullName.Substring((Resolve-Path $DistDir).Path.Length).TrimStart("\") -replace "\\", "/")
    $hash = $manifest[$rel]
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $bc = New-Object System.Net.Http.ByteArrayContent(, $bytes)
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
    $content.Add($bc, $hash, $hash)
}

$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", "Bearer $Token") | Out-Null
$client.Timeout = [TimeSpan]::FromMinutes(10)

$deployUrl = "$api/accounts/$AccountId/pages/projects/$Project/deployments"
Write-Host "[pages] 上传部署产物…" -ForegroundColor Cyan
$resp = $client.PostAsync($deployUrl, $content).Result
$body = $resp.Content.ReadAsStringAsync().Result

if (-not $resp.IsSuccessStatusCode) {
    throw "部署失败 [$([int]$resp.StatusCode)]：$body"
}

$deploy = ($body | ConvertFrom-Json).result
Write-Host "  ✓ deployment $($deploy.id) → $($deploy.url)" -ForegroundColor Green

# ---------------------------------------------------------------- 轮询部署状态
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 5
    $d = (Invoke-RestMethod -Uri "$deployUrl/$($deploy.id)" -Headers $headers).result
    $stage = $d.latest_stage
    Write-Host "  [$(($i + 1) * 5)s] $($stage.name) = $($stage.status)" -ForegroundColor DarkGray
    if ($stage.name -eq "deploy") {
        if ($stage.status -eq "success") { Write-Host "  ✓ 部署成功" -ForegroundColor Green; break }
        if ($stage.status -eq "failure" -or $stage.status -eq "canceled") { throw "部署失败：$($stage.name)=$($stage.status)" }
    }
}

# ---------------------------------------------------------------- 线上校验
$site = $BaseUrl.TrimEnd("/") + "/"
Write-Host ""
Write-Host "[pages] 线上校验：$site" -ForegroundColor Cyan
Start-Sleep -Seconds 5
foreach ($u in @("", "games/", "games/snake/", "about/", "robots.txt", "sitemap.xml", "llms.txt")) {
    try {
        $r = Invoke-WebRequest -Uri ($site + $u) -UseBasicParsing -TimeoutSec 25
        Write-Host ("  ✓ {0,-22} {1}" -f ("/" + $u), $r.StatusCode) -ForegroundColor Green
    } catch {
        Write-Host ("  ✗ {0,-22} {1}" -f ("/" + $u), $_.Exception.Message) -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "  ✓ 线上地址：$site" -ForegroundColor Green
