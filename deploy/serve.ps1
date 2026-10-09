<#
.SYNOPSIS
  零依赖本地静态文件服务器（.NET HttpListener，Windows PowerShell 5.1+）

.DESCRIPTION
  用于 Lite Arcade dist 目录的生产形态本地预览：
  - 正确的 MIME 类型
  - 静态资源长缓存 + HTML 不缓存（贴近生产 CDN 行为）
  - SPA/目录索引自动补全 index.html
  - 自定义 404 页面
  - 访问日志

.EXAMPLE
  .\deploy\serve.ps1 -Root dist -Port 8080
#>
[CmdletBinding()]
param(
    [string]$Root = "",
    [int]   $Port = 8080,
    [switch]$NoCache
)

$ErrorActionPreference = "Stop"
if (-not $Root) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) "dist" }
$Root = (Resolve-Path $Root).Path

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".mjs"  = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".webmanifest" = "application/manifest+json; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".webp" = "image/webp"
    ".gif"  = "image/gif"
    ".ico"  = "image/x-icon"
    ".woff2"= "font/woff2"
    ".txt"  = "text/plain; charset=utf-8"
    ".xml"  = "application/xml; charset=utf-8"
    ".map"  = "application/json; charset=utf-8"
}

Add-Type -AssemblyName System.Net.Http
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

try { $listener.Start() } catch {
    Write-Host "端口 $Port 启动失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Lite Arcade 本地生产预览" -ForegroundColor Cyan
Write-Host " 根目录：$Root" -ForegroundColor Cyan
Write-Host " 地址：http://localhost:$Port/" -ForegroundColor Green
Write-Host " 按 Ctrl+C 停止" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan

$notFoundPage = Join-Path $Root "404.html"

function Send-Response($ctx, [int]$code, [byte[]]$body, [string]$contentType, [hashtable]$headers) {
    $resp = $ctx.Response
    $resp.StatusCode = $code
    $resp.ContentType = $contentType
    $resp.ContentLength64 = $body.Length
    foreach ($k in $headers.Keys) { $resp.Headers.Add($k, $headers[$k]) }
    $resp.OutputStream.Write($body, 0, $body.Length)
    $resp.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $ctx  = $listener.GetContext()
        $req  = $ctx.Request
        $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)

        $rel  = $path.TrimStart("/") -replace "/", [System.IO.Path]::DirectorySeparatorChar
        if ([string]::IsNullOrEmpty($rel)) { $rel = "index.html" }
        $full = Join-Path $Root $rel

        # 目录路径安全校验
        if (-not $full.StartsWith($Root)) { Send-Response $ctx 403 @() "text/plain" @{}; continue }

        if ((Test-Path $full) -and ((Get-Item $full) -is [System.IO.DirectoryInfo])) {
            $full = Join-Path $full "index.html"
        }
        if (-not (Test-Path $full) -and -not $full.EndsWith(".html")) {
            $alt = $full + ".html"
            if (Test-Path $alt) { $full = $alt }
        }

        if (-not (Test-Path $full)) {
            $body = if (Test-Path $notFoundPage) { [System.IO.File]::ReadAllBytes($notFoundPage) }
                    else { [System.Text.Encoding]::UTF8.GetBytes("404 Not Found") }
            Send-Response $ctx 404 $body "text/html; charset=utf-8" @{"Cache-Control"="no-store"}
            Write-Host "  404 $path" -ForegroundColor DarkYellow
            continue
        }

        $ext = [System.IO.Path]::GetExtension($full).ToLower()
        $ct  = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
        $bytes = [System.IO.File]::ReadAllBytes($full)

        $headers = @{}
        if ($NoCache) {
            $headers["Cache-Control"] = "no-store"
        } elseif ($ext -eq ".html" -or $ext -eq ".webmanifest") {
            $headers["Cache-Control"] = "no-cache, must-revalidate"
        } else {
            $headers["Cache-Control"] = "public, max-age=31536000, immutable"
        }
        $headers["X-Content-Type-Options"] = "nosniff"
        $headers["Referrer-Policy"]        = "strict-origin-when-cross-origin"
        $headers["X-Frame-Options"]        = "SAMEORIGIN"

        Send-Response $ctx 200 $bytes $ct $headers
        Write-Host "  200 $path  ($([math]::Round($bytes.Length/1KB,1)) KB)" -ForegroundColor DarkGray
    }
} finally {
    if ($listener.IsListening) { $listener.Stop() }
    Write-Host "`n服务已停止。" -ForegroundColor Yellow
}
