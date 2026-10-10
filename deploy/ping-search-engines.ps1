# ping-search-engines.ps1
# 通过搜索引擎的开放 sitemap ping 接口主动请求重新抓取（无需令牌）。
# 用法：
#   .\deploy\ping-search-engines.ps1                       # 用 config/site.json 的 baseUrl
#   .\deploy\ping-search-engines.ps1 -SitemapUrl "https://example.com/sitemap.xml"
#
# 说明：
#   - Google / Bing 的 /ping?sitemap= 接口对公网站点开放，不需要任何密钥。
#   - 若提供了 $env:BING_API_TOKEN 且该 token 在 Bing Webmaster 中已验证本站，
#     会额外调用 SubmitSitemap 做正式提交（否则仅走开放 ping，后者足以触发抓取）。

param(
    [string]$SitemapUrl,
    [string]$BaseUrl
)

$ErrorActionPreference = 'Stop'
$Sep = [System.IO.Path]::DirectorySeparatorChar
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $SitemapUrl) {
    if (-not $BaseUrl) {
        $cfg = Get-Content (Join-Path $RepoRoot 'config' 'site.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $BaseUrl = $cfg.baseUrl
    }
    $SitemapUrl = $BaseUrl.TrimEnd('/') + '/sitemap.xml'
}

$engines = @(
    @{ Name = 'Google'; Uri = "https://www.google.com/ping?sitemap=$SitemapUrl" }
    @{ Name = 'Bing';   Uri = "https://www.bing.com/ping?sitemap=$SitemapUrl" }
)

function Esc([string]$u) { return [System.Uri]::EscapeDataString($u) }

Write-Host "[ping] sitemap = $SitemapUrl" -ForegroundColor Cyan
$ok = 0
foreach ($e in $engines) {
    $url = $e.Uri
    $err = $null
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -Method Get
        $code = [int]$r.StatusCode
        if ($code -ge 200 -and $code -lt 300) {
            Write-Host "  [OK] $($e.Name) -> HTTP $code" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "  [WARN] $($e.Name) -> HTTP $code" -ForegroundColor Yellow
        }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        Write-Host "  [FAIL] $($e.Name) -> $(if($code){"HTTP $code"}else{$_.Exception.Message})" -ForegroundColor Red
    }
}

# 可选：Bing Webmaster 正式提交（需本站已在 Bing 验证，且提供 $env:BING_API_TOKEN）
if ($env:BING_API_TOKEN) {
    $site = $BaseUrl.TrimEnd('/') + '/'
    try {
        $q = Invoke-RestMethod -Uri ("https://ssl.bing.com/webmaster/api.svc/json/SubmitSitemap?apikey=$env:BING_API_TOKEN&siteUrl=$(Esc $site)&sitemapUrl=$(Esc $SitemapUrl)") -TimeoutSec 20
        Write-Host "  [OK] Bing SubmitSitemap (API) -> $($q | ConvertTo-Json -Compress)" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] Bing API 提交失败（可能本站尚未在 Bing 验证）: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

Write-Host "[ping] 完成：$ok/$($engines.Count) 开放接口成功" -ForegroundColor Cyan
