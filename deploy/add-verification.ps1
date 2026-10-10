# add-verification.ps1
# 把搜索引擎的站点验证凭据落地为根目录验证文件（随构建部署），并可选择注入 <meta> 标签。
# 用法示例（把验证码替换为你从各引擎控制台拿到的真实值）：
#   .\deploy\add-verification.ps1 `
#       -BingCode    "A1B2C3D4E5F6..." `
#       -GoogleCode  "google1a2b3c4.html" -GoogleContent "google-site-verification: 1a2b3c4..." `
#       -YandexCode  "12345678" `
#       -BaiduCode   "baidu_verify_abc123" `
#       -AddMeta
#
# 说明：
#   - Bing：写入根目录 BingSiteAuth.xml（内容 <usersiteverify site-verify-code="..."/>）
#   - Google：写入根目录 google<code>.html（内容 "google-site-verification: <code>"）
#   - Yandex：写入根目录 yandex_<code>.html（内容 "yandex-verification: <code>"）
#   - Baidu：写入根目录 baidu_verify_<code>.html（内容 "baidu-site-verification: <code>"）
#   - 验证文件会随 src/ → dist/ 构建自动发布；同时这些文件已在 robots.txt 之外可公开访问。
#   - 若使用自定义域名且 Cloudflare 托管 DNS，可用 deploy/publish-cloudflare.ps1 之外的
#     DNS TXT 方式（需 dns_records:edit 令牌），但文件方式对所有平台通用，优先用文件方式。

param(
    [string]$BingCode,
    [string]$GoogleFile,
    [string]$GoogleContent,
    [string]$YandexCode,
    [string]$BaiduCode,
    [switch]$AddMeta
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $RepoRoot 'src'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$any = $false

function Write-Verify([string]$name, [string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
    Write-Host "  [OK] 写入 $name -> $path" -ForegroundColor Green
}

if ($BingCode) {
    $any = $true
    Write-Verify 'Bing' (Join-Path $Src 'BingSiteAuth.xml') "<?xml version=""1.0""?>`n<usersiteverify site-verify-code=""$BingCode""/>"
}

if ($GoogleFile -and $GoogleContent) {
    $any = $true
    $f = if ($GoogleFile.EndsWith('.html')) { $GoogleFile } else { "google$GoogleFile.html" }
    Write-Verify 'Google' (Join-Path $Src $f) $GoogleContent
}

if ($YandexCode) {
    $any = $true
    Write-Verify 'Yandex' (Join-Path $Src "yandex_$YandexCode.html") "yandex-verification: $YandexCode"
}

if ($BaiduCode) {
    $any = $true
    $f = if ($BaiduCode.EndsWith('.html')) { $BaiduCode } else { "baidu_verify_$BaiduCode.html" }
    Write-Verify 'Baidu' (Join-Path $Src $f) "baidu-site-verification: $BaiduCode"
}

if ($AddMeta -and ($BingCode -or $GoogleContent -or $YandexCode -or $BaiduCode)) {
    $idx = Join-Path $Src 'index.html'
    $html = [System.IO.File]::ReadAllText($idx, $utf8NoBom)
    $tags = ''
    if ($BingCode)      { $tags += "`n  <meta name=""msvalidate.01"" content=""$BingCode"">" }
    if ($GoogleContent) { $tags += "`n  <meta name=""google-site-verification"" content=""$(($GoogleContent -replace '^google-site-verification:\s*',''))"">" }
    if ($YandexCode)    { $tags += "`n  <meta name=""yandex-verification"" content=""$YandexCode"">" }
    if ($BaiduCode)     { $tags += "`n  <meta name=""baidu-site-verification"" content=""$BaiduCode"">" }
    if ($html -notmatch 'msvalidate\.01|google-site-verification') {
        $html = $html -replace '(<meta name="author"[^>]*>)', ($tags.TrimStart() + "`n  $1")
        [System.IO.File]::WriteAllText($idx, $html, $utf8NoBom)
        Write-Host "  [OK] 已向 index.html <head> 注入验证 meta 标签" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] index.html 已含验证标签，跳过注入" -ForegroundColor DarkGray
    }
}

if (-not $any) {
    Write-Host "[verify] 未提供任何验证码。请在参数中至少传入一个 Code/File。" -ForegroundColor Yellow
    exit 1
}

Write-Host "[verify] 完成。下一步：运行 .\deploy\build.ps1 重新构建并部署，然后在各引擎控制台点击「验证」。" -ForegroundColor Cyan
