<#
.SYNOPSIS
  通过 IndexNow 协议向 Bing / Yandex / Seznam / Naver 等搜索引擎主动推送 URL

.DESCRIPTION
  - IndexNow 是开放的即时收录协议，无需任何账号或 API 密钥
  - 密钥文件必须放在站点根目录：https://<host>/<key>.txt，内容仅含密钥本身
  - 密钥从 config/indexnow-key.txt 读取（IndexNow 密钥设计为可公开）
  - 只对 canonical 主站提交，镜像站不提交（避免重复内容信号）

.EXAMPLE
  .\deploy\submit-indexnow.ps1
  .\deploy\submit-indexnow.ps1 -Host "your-domain.com"
#>
[CmdletBinding()]
param(
    [string]$Host = "lite-arcade.pages.dev",
    [string]$KeyFile = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $KeyFile) { $KeyFile = Join-Path $RepoRoot "config/indexnow-key.txt" }
if (-not (Test-Path $KeyFile)) { throw "未找到密钥文件：$KeyFile" }

$key = (Get-Content $KeyFile -Raw -Encoding UTF8).Trim()
if ($key.Length -lt 8 -or $key.Length -gt 128) { throw "密钥长度不符合 IndexNow 要求（8-128）" }

$keyLocation = "https://$Host/$key.txt"

# 密钥文件必须可公开访问，否则推送会被拒绝
try {
    $probe = Invoke-WebRequest -Uri $keyLocation -UseBasicParsing -TimeoutSec 20
    if ($probe.Content.Trim() -ne $key) { throw "密钥文件内容不匹配" }
    Write-Host "[indexnow] 密钥文件校验通过：$keyLocation" -ForegroundColor Green
} catch {
    throw "密钥文件不可访问或内容不匹配：$keyLocation —— $($_.Exception.Message)"
}

$paths = @(
    "/", "/games/", "/games/snake/", "/games/2048/", "/games/breakout/",
    "/games/tetris/", "/games/memory/", "/games/bird/", "/about/"
)
$urlList = $paths | ForEach-Object { "https://$Host$_" }

$body = @{
    host         = $Host
    key          = $key
    keyLocation  = $keyLocation
    urlList      = $urlList
} | ConvertTo-Json -Depth 5 -Compress

Write-Host "[indexnow] 提交 $($urlList.Count) 条 URL 到 https://api.indexnow.org/indexnow" -ForegroundColor Cyan

try {
    $resp = Invoke-WebRequest -Method Post -Uri "https://api.indexnow.org/indexnow" `
        -Body $body -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 40
    Write-Host "  ✓ 推送成功：HTTP $($resp.StatusCode)" -ForegroundColor Green
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "ERR" }
    # 200 / 202 均表示已接收；429 为限流
    if ($code -eq 200 -or $code -eq 202) {
        Write-Host "  ✓ 推送成功：HTTP $code（无响应体）" -ForegroundColor Green
    } elseif ($code -eq 429) {
        Write-Warning "  ! 被限流（429），请稍后重试"
    } else {
        $s = $_.Exception.Response
        $detail = ""
        if ($s) {
            $sr = New-Object System.IO.StreamReader($s.GetResponseStream())
            $detail = $sr.ReadToEnd(); $sr.Close()
        }
        Write-Host "  ✗ 推送失败：HTTP $code $detail" -ForegroundColor Red
    }
}

$urlList | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
