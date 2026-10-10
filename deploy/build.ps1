<#
.SYNOPSIS
  Lite Arcade 生产化构建脚本（零第三方依赖，Windows PowerShell 5.1+ 可直接运行）

.DESCRIPTION
  1. 读取 config/site.json 站点配置
  2. 将 src/ 复制到 dist/ 并执行占位符替换
  3. 生成 sitemap.xml / robots.txt / llms.txt / llms-full.txt
  4. 生成带缓存指纹的 asset 引用路径
  5. 执行生产校验：内链可达性、JSON-LD 可解析、SEO 元数据完整性
  6. 输出构建报告；-Serve 时直接拉起本地静态服务

.EXAMPLE
  .\deploy\build.ps1
  .\deploy\build.ps1 -BaseUrl "https://game.example.com"
  .\deploy\build.ps1 -Serve -Port 8080
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = "",
    [string]$OutDir  = "",
    [int]   $Port    = 8080,
    [switch]$Serve
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ---------------------------------------------------------------- 路径初始化
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SrcDir   = Join-Path $RepoRoot "src"
$CfgDir   = Join-Path $RepoRoot "config"
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot "dist" }
$OutDir   = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)

if (-not (Test-Path $SrcDir)) { throw "未找到源码目录：$SrcDir" }
if (-not (Test-Path $CfgDir)) { throw "未找到配置目录：$CfgDir" }

$Sep = [System.IO.Path]::DirectorySeparatorChar

function Write-Step([string]$msg) { Write-Host "[build] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Bad([string]$msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

function Esc-Json([string]$v) {
    if ($null -eq $v) { return "" }
    return $v.Replace('\', '\\').Replace('"', '\"').Replace("`r", " ").Replace("`n", " ").Replace("`t", " ")
}

# ---------------------------------------------------------------- 加载配置
$site    = Get-Content (Join-Path $CfgDir "site.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$llms    = Get-Content (Join-Path $CfgDir "llms.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$games   = Get-Content (Join-Path $CfgDir "games.json") -Raw -Encoding UTF8 | ConvertFrom-Json

if ($BaseUrl) { $site.baseUrl = $BaseUrl }
$site.baseUrl = $site.baseUrl.TrimEnd("/")

$buildDate   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$buildDateIso= (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$year        = (Get-Date).ToString("yyyy")

Write-Step "站点：$($site.name)"
Write-Step "Base URL：$($site.baseUrl)"

# ---------------------------------------------------------------- 生成图片资源（封面 / 图标 / CC0 游戏配图）
Write-Step "生成图片资源"
try { & "$PSScriptRoot\gen-assets.ps1" | Out-Null } catch { Write-Warn "gen-assets.ps1 执行异常：$_" }
try { & "$PSScriptRoot\fetch-covers.ps1" -Key $env:PIXABAY_KEY | Out-Null } catch { Write-Warn "fetch-covers.ps1 执行异常：$_" }

# ---------------------------------------------------------------- 清理与复制
if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Get-ChildItem $SrcDir -Recurse -File | ForEach-Object {
    $rel  = $_.FullName.Substring($SrcDir.Length).TrimStart([char[]]'/').TrimStart([char[]]'\')
    $dest = Join-Path $OutDir $rel
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Copy-Item $_.FullName $dest -Force
}
Write-Ok "已复制 src/ → dist/"

# ---------------------------------------------------------------- 生成游戏详情页
$tplPath = Join-Path $CfgDir "game-template.html"
if ((Test-Path $tplPath) -and $games.Count -gt 0) {
    $tpl = Get-Content $tplPath -Raw -Encoding UTF8
    $bySlug = @{}
    foreach ($g in $games) { $bySlug[$g.slug] = $g }

    function Expand-GameLoops([string]$text, $game) {
        $pattern = '\{\{#(\w+)\}\}(.*?)\{\{/\1\}\}'
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $prop  = $m.Groups[1].Value
            $inner = $m.Groups[2].Value
            $node  = $game.PSObject.Properties[$prop]
            if ($null -eq $node) { return "" }
            $items = @($node.Value)
            $sb = New-Object System.Text.StringBuilder
            foreach ($it in $items) {
                $line = $inner
                if ($it -is [string]) {
                    $line = $line.Replace("{{item}}", $it)
                } else {
                    foreach ($p in $it.PSObject.Properties) {
                        $line = $line.Replace("{{item.$($p.Name)}}", [string]$p.Value)
                    }
                }
                $line = [regex]::Replace($line, '\{\{item(\.\w+)?\}\}', '')
                [void]$sb.Append($line)
            }
            return $sb.ToString()
        }
        return [regex]::Replace($text, $pattern, $evaluator, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }

    foreach ($g in $games) {
        # 关联游戏解析为完整对象
        $related = @()
        foreach ($slug in @($g.related)) {
            $t = $bySlug[$slug]
            if ($t) {
                if ($t.en -and ($t.en -ne $t.name)) { $rTitleEn = " " + $t.en }
                else { $rTitleEn = "" }
                $related += [pscustomobject]@{
                    slug = $t.slug; name = $t.name; en = $t.en; titleEn = $rTitleEn; emoji = $t.emoji; genre = $t.genre
                }
            }
        }
        $g.related = $related

        $gUrl = $site.baseUrl + "/games/" + $g.slug + "/"

        # ---- 结构化数据：VideoGame + HowTo + FAQPage + BreadcrumbList + WebPage ----
        $gName   = [string]$g.name
        $gEn     = [string]$g.en
        if ($gEn -and ($gEn -ne $gName)) { $gTitleEn = " " + $gEn; $gFullName = $gName + " " + $gEn }
        else { $gTitleEn = ""; $gFullName = $gName }
        $orgId   = $site.baseUrl + "/#organization"
        $webId   = $site.baseUrl + "/#website"
        $imgUrl  = $site.baseUrl + "/assets/img/covers/" + $g.slug + ".jpg"
        $rootUrl = $site.baseUrl + "/"
        $listUrl = $site.baseUrl + "/games/"

        $stepsJson = ""
        $n = 0
        foreach ($step in @($g.howto)) {
            $n++
            $one = '{ "@type": "HowToStep", "position": ' + $n + ', "text": "' + (Esc-Json $step) + '" }'
            if ($stepsJson) { $stepsJson += ", " }
            $stepsJson += $one
        }

        $faqJson = ""
        foreach ($f in @($g.faq)) {
            $one = '{ "@type": "Question", "name": "' + (Esc-Json $f.q) +
                   '", "acceptedAnswer": { "@type": "Answer", "text": "' + (Esc-Json $f.a) + '" } }'
            if ($faqJson) { $faqJson += ", " }
            $faqJson += $one
        }

        $jsonLdText = @"
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "VideoGame",
      "@id": "$gUrl#game",
      "name": "$gFullName",
      "alternateName": "$gEn",
      "description": "$(Esc-Json $g.summary)",
      "genre": "$(Esc-Json $g.genre)",
      "gamePlatform": "Web Browser",
      "applicationCategory": "Game",
      "operatingSystem": "Any",
      "playMode": "SinglePlayer",
      "isAccessibleForFree": true,
      "inLanguage": "$($site.lang)",
      "url": "$gUrl",
      "image": "$imgUrl",
      "datePublished": "$buildDate",
      "dateModified": "$buildDate",
      "author": { "@id": "$orgId" },
      "publisher": { "@id": "$orgId" },
      "offers": { "@type": "Offer", "price": "0", "priceCurrency": "CNY", "availability": "https://schema.org/InStock" }
    },
    {
      "@type": "HowTo",
      "@id": "$gUrl#howto",
      "name": "$gName玩法说明",
      "description": "$(Esc-Json $g.summary)",
      "step": [ $stepsJson ]
    },
    {
      "@type": "FAQPage",
      "@id": "$gUrl#faq",
      "mainEntity": [ $faqJson ]
    },
    {
      "@type": "BreadcrumbList",
      "@id": "$gUrl#breadcrumb",
      "itemListElement": [
        { "@type": "ListItem", "position": 1, "name": "首页", "item": "$rootUrl" },
        { "@type": "ListItem", "position": 2, "name": "全部游戏", "item": "$listUrl" },
        { "@type": "ListItem", "position": 3, "name": "$gName", "item": "$gUrl" }
      ]
    },
    {
      "@type": "WebPage",
      "@id": "$gUrl#webpage",
      "url": "$gUrl",
      "name": "$gFullName — 在线免费玩",
      "description": "$(Esc-Json $g.metaDescription)",
      "inLanguage": "$($site.lang)",
      "isPartOf": { "@id": "$webId" },
      "datePublished": "$buildDate",
      "dateModified": "$buildDate",
      "breadcrumb": { "@id": "$gUrl#breadcrumb" },
      "primaryImageOfPage": { "@type": "ImageObject", "url": "$imgUrl", "width": 1200, "height": 630 },
      "speakable": { "@type": "SpeakableSpecification", "cssSelector": ["#answer", "#faq"] }
    }
  ]
}
"@

        $tokens = @{
            "GAME_NAME"       = $g.name
            "GAME_EN"         = $g.en
            "GAME_TITLE_EN"   = $gTitleEn
            "GAME_EMOJI"      = $g.emoji
            "GAME_GENRE"      = $g.genre
            "GAME_SLUG"       = $g.slug
            "GAME_META"       = $g.metaDescription
            "GAME_KEYWORDS"   = (@($g.keywords) -join ",")
            "GAME_SUMMARY"    = $g.summary
            "GAME_DIFFICULTY" = $g.difficulty
            "GAME_WIDTH"      = [string]$g.width
            "GAME_HEIGHT"     = [string]$g.height
            "GAME_SCRIPT"     = $g.script
        }

        $page = Expand-GameLoops $tpl $g
        foreach ($k in $tokens.Keys) { $page = $page.Replace("{{$k}}", [string]$tokens[$k]) }
        $page = $page.Replace("{{GAME_JSONLD}}", "<script type=`"application/ld+json`">`n" + $jsonLdText + "`n</script>")

        $dir = Join-Path $OutDir ("games" + $Sep + $g.slug)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir "index.html"), $page, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Ok "已生成 $($games.Count) 个游戏详情页"
}

# ---------------------------------------------------------------- HTML 站点地图页（/sitemap/）
$tplSitemap = Join-Path $CfgDir "sitemap-template.html"
if (Test-Path $tplSitemap) {
    $stpl = Get-Content $tplSitemap -Raw -Encoding UTF8
    $spPages = @(
        [pscustomobject]@{ rel = "../";            abs = "/";                title = $site.name;      desc = $site.description }
        [pscustomobject]@{ rel = "../games/";       abs = "/games/";          title = "全部游戏";       desc = "Lite Arcade 内置的全部网页小游戏索引，可直接在浏览器游玩。" }
    )
    foreach ($g in $games) {
        $gt = if ($g.en -and ($g.en -ne $g.name)) { "$($g.name) $($g.en)" } else { $g.name }
        $spPages += [pscustomobject]@{ rel = "../games/$($g.slug)/"; abs = "/games/$($g.slug)/"; title = $gt; desc = $g.summary }
    }
    $spPages += [pscustomobject]@{ rel = "../about/"; abs = "/about/"; title = "关于与 GEO 优化"; desc = "关于 Lite Arcade 与 SEO/GEO 优化的说明。" }

    $listSb = New-Object System.Text.StringBuilder
    $partSb = New-Object System.Text.StringBuilder
    $i = 0
    foreach ($p in $spPages) {
        [void]$listSb.AppendLine("          <li><a href=`"$($p.rel)`">$(Esc-Json $p.title)</a><p>$(Esc-Json $p.desc)</p></li>")
        if ($i -gt 0) { [void]$partSb.Append(", ") }
        [void]$partSb.Append('{"@type":"WebPage","name":"' + (Esc-Json $p.title) +
            '","url":"' + $site.baseUrl + $p.abs + '","description":"' + (Esc-Json $p.desc) + '"}')
        $i++
    }

    $sitemapJsonLd = '{ "@context":"https://schema.org", "@graph":[ ' +
        '{ "@type":"WebPage", "@id":"' + $site.baseUrl + '/sitemap/#webpage", "url":"' + $site.baseUrl + '/sitemap/", ' +
        '"name":"站点地图 — ' + (Esc-Json $site.shortName) + '", "description":"Lite Arcade 全部页面的人类可读站点地图。", ' +
        '"isPartOf":{ "@id":"' + $site.baseUrl + '/#website" }, "inLanguage":"' + $site.lang + '", "dateModified":"' + $buildDate + '" }, ' +
        '{ "@type":"CollectionPage", "@id":"' + $site.baseUrl + '/sitemap/#collection", "name":"Lite Arcade 站点地图", ' +
        '"url":"' + $site.baseUrl + '/sitemap/", "isPartOf":{ "@id":"' + $site.baseUrl + '/#website" }, ' +
        '"hasPart":[ ' + $partSb.ToString() + ' ] } ] }'

    $stpl = $stpl.Replace("{{SITEMAP_LIST}}", $listSb.ToString()).Replace("{{SITEMAP_JSONLD}}", $sitemapJsonLd)
    $smapDir = Join-Path $OutDir "sitemap"
    New-Item -ItemType Directory -Path $smapDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $smapDir "index.html"), $stpl, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "已生成 HTML 站点地图 /sitemap/"
}

# ---------------------------------------------------------------- 占位符替换
$tokens = @{
    "SITE_URL"        = $site.baseUrl
    "SITE_NAME"       = $site.name
    "SITE_SHORT_NAME" = $site.shortName
    "SITE_TAGLINE"    = $site.tagline
    "SITE_DESCRIPTION"= $site.description
    "SITE_LANG"       = $site.lang
    "SITE_LOCALE"     = $site.locale
    "SITE_AUTHOR"     = $site.author
    "SITE_CONTACT"    = $site.contact
    "SITE_REPO"       = $site.repo
    "THEME_COLOR"     = $site.themeColor
    "BG_COLOR"        = $site.backgroundColor
    "BUILD_DATE"      = $buildDate
    "BUILD_DATE_ISO"  = $buildDateIso
    "YEAR"            = $year
    "KEYWORDS"        = ($site.keywords -join ",")
}

$textExt = @(".html", ".xml", ".txt", ".json", ".webmanifest", ".css", ".js", ".svg", ".md")
Get-ChildItem $OutDir -Recurse -File | Where-Object { $textExt -contains $_.Extension.ToLower() } | ForEach-Object {
    $raw = Get-Content $_.FullName -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($raw)) { return }
    $out = $raw
    foreach ($k in $tokens.Keys) {
        $out = $out.Replace("{{$k}}", [string]$tokens[$k])
    }
    if ($out -ne $raw) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($_.FullName, $out, $utf8NoBom)
    }
}
Write-Ok "占位符替换完成（$($tokens.Count) 个令牌）"

# ---------------------------------------------------------------- 页面清单
$htmlFiles = Get-ChildItem $OutDir -Recurse -File -Filter "*.html" | Sort-Object FullName
$pages = @()
foreach ($f in $htmlFiles) {
    $rel = "/" + (($f.FullName.Substring($OutDir.Length) -replace "\\", "/").TrimStart("/"))
    if ($rel -eq "/404.html") { continue }
    $raw = Get-Content $f.FullName -Raw -Encoding UTF8

    $priority = "0.5"; $changefreq = "monthly"
    if ($rel -eq "/index.html") { $priority = "1.0"; $changefreq = "daily" }
    elseif ($rel -match "^/games/") { $priority = "0.9"; $changefreq = "weekly" }
    elseif ($rel -match "^/about") { $priority = "0.6"; $changefreq = "monthly" }

    if ($rel -eq "/index.html") { $pageUrl = $site.baseUrl + "/" }
    else { $pageUrl = $site.baseUrl + ($rel -replace "/index.html$", "/") }

    $pages += [pscustomobject]@{
        File       = $rel
        Url        = $pageUrl
        Priority   = $priority
        ChangeFreq = $changefreq
        Raw        = $raw
        FullPath   = $f.FullName
    }
}
Write-Ok "发现页面 $($pages.Count) 个"

# ---------------------------------------------------------------- sitemap.xml
$sitemap = New-Object System.Text.StringBuilder
[void]$sitemap.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sitemap.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"')
[void]$sitemap.AppendLine('        xmlns:xhtml="http://www.w3.org/1999/xhtml">')
foreach ($p in $pages) {
    [void]$sitemap.AppendLine("  <url>")
    [void]$sitemap.AppendLine("    <loc>$([System.Security.SecurityElement]::Escape($p.Url))</loc>")
    [void]$sitemap.AppendLine("    <lastmod>$buildDateIso</lastmod>")
    [void]$sitemap.AppendLine("    <changefreq>$($p.ChangeFreq)</changefreq>")
    [void]$sitemap.AppendLine("    <priority>$($p.Priority)</priority>")
    [void]$sitemap.AppendLine("  </url>")
}
[void]$sitemap.AppendLine('</urlset>')
[System.IO.File]::WriteAllText((Join-Path $OutDir "sitemap.xml"), $sitemap.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "已生成 sitemap.xml"

# ---------------------------------------------------------------- robots.txt
$robots = @"
# Lite Arcade - robots.txt
# 生成时间：$buildDate
# 说明：默认开放全部内容；显式放行生成式引擎爬虫以提升 GEO 可引用性。

User-agent: *
Allow: /

# ---- 生成式引擎 / AI 搜索爬虫（GEO 关键）----
User-agent: GPTBot
Allow: /

User-agent: OAI-SearchBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: Claude-User
Allow: /

User-agent: Claude-SearchBot
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: Google-Extended
Allow: /

User-agent: Applebot-Extended
Allow: /

User-agent: Bingbot
Allow: /

User-agent: CCBot
Allow: /

User-agent: Amazonbot
Allow: /

User-agent: cohere-ai
Allow: /

User-agent: Diffbot
Allow: /

User-agent: Bytespider
Disallow: /

Sitemap: $($site.baseUrl)/sitemap.xml
Sitemap: $($site.baseUrl)/llms.txt
"@
[System.IO.File]::WriteAllText((Join-Path $OutDir "robots.txt"), $robots, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "已生成 robots.txt（含 AI 爬虫白名单）"

# ---------------------------------------------------------------- llms.txt
function Get-MetaDescription([string]$rawHtml) {
    $m = [regex]::Match($rawHtml, '<meta\s+name="description"\s+content="([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value } else { return "" }
}

$llmsSb = New-Object System.Text.StringBuilder
[void]$llmsSb.AppendLine("# $($site.shortName)")
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("> $($llms.summary)")
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("站点：$($site.name)")
[void]$llmsSb.AppendLine("主页：$($site.baseUrl)/")
[void]$llmsSb.AppendLine("语言：$($site.lang)")
[void]$llmsSb.AppendLine("最后更新：$buildDateIso")
[void]$llmsSb.AppendLine("许可：站内自研游戏代码 MIT")
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("## 关键事实")
[void]$llmsSb.AppendLine("")
foreach ($fact in $llms.facts) { [void]$llmsSb.AppendLine("- $fact") }
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("## 可游玩游戏")
[void]$llmsSb.AppendLine("")
foreach ($p in ($pages | Where-Object { $_.File -match "^/games/" })) {
    $desc = Get-MetaDescription $p.Raw
    [void]$llmsSb.AppendLine("- [$($p.Url)]($($p.Url))：$desc")
}
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("## 主题分类")
[void]$llmsSb.AppendLine("")
foreach ($t in $llms.topics) { [void]$llmsSb.AppendLine("- $t") }
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("## 常见问题")
[void]$llmsSb.AppendLine("")
foreach ($item in $llms.faq) {
    [void]$llmsSb.AppendLine("### $($item.q)")
    [void]$llmsSb.AppendLine("")
    [void]$llmsSb.AppendLine($item.a)
    [void]$llmsSb.AppendLine("")
}
[void]$llmsSb.AppendLine("## 全部页面")
[void]$llmsSb.AppendLine("")
foreach ($p in $pages) {
    [void]$llmsSb.AppendLine("- $($p.Url)：$(Get-MetaDescription $p.Raw)")
}
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("## 机器可读入口")
[void]$llmsSb.AppendLine("")
[void]$llmsSb.AppendLine("- Sitemap：$($site.baseUrl)/sitemap.xml")
[void]$llmsSb.AppendLine("- 完整上下文：$($site.baseUrl)/llms-full.txt")
[void]$llmsSb.AppendLine("- 结构化数据：各页面 <script type=`"application/ld+json`"> 区块")
[System.IO.File]::WriteAllText((Join-Path $OutDir "llms.txt"), $llmsSb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "已生成 llms.txt"

# ---------------------------------------------------------------- llms-full.txt
$fullSb = New-Object System.Text.StringBuilder
[void]$fullSb.AppendLine("# $($site.name) — 完整上下文")
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("## 摘要")
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine($site.abstract)
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("## 站点信息")
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("- 名称：$($site.name)")
[void]$fullSb.AppendLine("- 主页：$($site.baseUrl)/")
[void]$fullSb.AppendLine("- 语言：$($site.lang)")
[void]$fullSb.AppendLine("- 主题色：$($site.themeColor)")
[void]$fullSb.AppendLine("- 联系：$($site.contact)")
[void]$fullSb.AppendLine("- 关联仓库：$($site.repo)")
[void]$fullSb.AppendLine("- 构建时间：$buildDate")
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("## 事实清单")
[void]$fullSb.AppendLine("")
foreach ($fact in $llms.facts) { [void]$fullSb.AppendLine("- $fact") }
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("## 页面正文索引")
[void]$fullSb.AppendLine("")
foreach ($p in $pages) {
    $title = ([regex]::Match($p.Raw, "<title>([^<]+)</title>")).Groups[1].Value
    $desc  = Get-MetaDescription $p.Raw
    [void]$fullSb.AppendLine("### $title")
    [void]$fullSb.AppendLine("- URL：$($p.Url)")
    [void]$fullSb.AppendLine("- 描述：$desc")
    $headings = [regex]::Matches($p.Raw, "<h2[^>]*>(.*?)</h2>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($headings.Count -gt 0) {
        [void]$fullSb.AppendLine("- 章节：")
        foreach ($h in $headings) {
            $txt = (($h.Groups[1].Value -replace "<[^>]+>", "") -replace "\s+", " ").Trim()
            if ($txt) { [void]$fullSb.AppendLine("  - $txt") }
        }
    }
    [void]$fullSb.AppendLine("")
}
[void]$fullSb.AppendLine("## FAQ")
[void]$fullSb.AppendLine("")
foreach ($item in $llms.faq) {
    [void]$fullSb.AppendLine("Q: $($item.q)")
    [void]$fullSb.AppendLine("A: $($item.a)")
    [void]$fullSb.AppendLine("")
}
[System.IO.File]::WriteAllText((Join-Path $OutDir "llms-full.txt"), $fullSb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "已生成 llms-full.txt"

# ---------------------------------------------------------------- 生产校验
Write-Step "开始生产校验"
$errors = New-Object System.Collections.ArrayList

# 1. HTML 元数据完整性
foreach ($p in $pages) {
    $raw = $p.Raw
    if (-not ([regex]::IsMatch($raw, '<html[^>]+lang=')))   { [void]$errors.Add("$($p.File) 缺少 <html lang>") }
    if (-not ([regex]::IsMatch($raw, '<link[^>]+rel="canonical"'))) { [void]$errors.Add("$($p.File) 缺少 canonical") }
    if (-not ([regex]::IsMatch($raw, '<meta[^>]+name="description"'))) { [void]$errors.Add("$($p.File) 缺少 meta description") }
    if (-not ([regex]::IsMatch($raw, '<meta[^>]+property="og:title"'))) { [void]$errors.Add("$($p.File) 缺少 og:title") }
    if (-not ([regex]::IsMatch($raw, '<meta[^>]+property="og:image"'))) { [void]$errors.Add("$($p.File) 缺少 og:image") }
    if (-not ([regex]::IsMatch($raw, '<meta[^>]+name="twitter:card"'))) { [void]$errors.Add("$($p.File) 缺少 twitter:card") }
    if (-not ([regex]::IsMatch($raw, 'application/ld\+json'))) { [void]$errors.Add("$($p.File) 缺少 JSON-LD") }
    if ([regex]::IsMatch($raw, '\{\{[A-Z_]+\}\}'))            { [void]$errors.Add("$($p.File) 存在未替换占位符") }
    if (([regex]::Matches($raw, "<h1")).Count -ne 1)          { [void]$errors.Add("$($p.File) h1 数量不为 1") }

    # ---- 语义化与可访问性 ----
    if (-not ([regex]::IsMatch($raw, '<meta[^>]+property="og:image:alt"'))) { [void]$errors.Add("$($p.File) 缺少 og:image:alt") }
    if (([regex]::Matches($raw, '<main[\s>]')).Count -ne 1)   { [void]$errors.Add("$($p.File) <main> 数量不为 1") }
    if (([regex]::Matches($raw, '<header[\s>]')).Count -lt 1) { [void]$errors.Add("$($p.File) 缺少 <header>") }
    if (([regex]::Matches($raw, '<footer[\s>]')).Count -lt 1) { [void]$errors.Add("$($p.File) 缺少 <footer>") }
    if (-not ([regex]::IsMatch($raw, 'class="skip-link"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))) {
        [void]$errors.Add("$($p.File) 缺少跳转链接 skip-link")
    }
    foreach ($im in [regex]::Matches($raw, '<img\b[^>]*>')) {
        if (-not ([regex]::IsMatch($im.Value, '\balt='))) {
            $snip = $im.Value; if ($snip.Length -gt 60) { $snip = $snip.Substring(0, 60) }
            [void]$errors.Add("$($p.File) 存在缺少 alt 的 img：$snip")
        }
    }
    # 标题层级：首个 h3 不得早于首个 h2
    $firstH2 = $raw.IndexOf("<h2")
    $firstH3 = $raw.IndexOf("<h3")
    if ($firstH3 -ge 0 -and ($firstH2 -lt 0 -or $firstH3 -lt $firstH2)) {
        [void]$errors.Add("$($p.File) 标题层级异常：h3 出现在 h2 之前")
    }
}

# 2. JSON-LD 可解析
$ldCount = 0
foreach ($p in $pages) {
    foreach ($m in [regex]::Matches($p.Raw, '<script[^>]+application/ld\+json[^>]*>(.*?)</script>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $ldCount++
        try { $null = $m.Groups[1].Value | ConvertFrom-Json }
        catch { [void]$errors.Add("$($p.File) JSON-LD 解析失败：$($_.Exception.Message)") }
    }
}

# 3. 内链可达性
$linkCount = 0
foreach ($p in $pages) {
    $base = Split-Path $p.FullPath
    foreach ($m in [regex]::Matches($p.Raw, '(?:href|src)="([^"]+)"')) {
        $link = $m.Groups[1].Value
        if ($link -match '^(https?:|mailto:|tel:|data:|#|//)') { continue }
        $linkCount++
        $clean = ($link -split '[#?]')[0]
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        $target = Join-Path $base ($clean -replace "/", $Sep)
        if (-not (Test-Path $target)) { [void]$errors.Add("$($p.File) 引用了不存在的文件：$link") }
    }
}

if ($errors.Count -eq 0) {
    Write-Ok "元数据、JSON-LD($ldCount 块)、内链($linkCount 条) 全部通过"
} else {
    foreach ($e in $errors) { Write-Bad $e }
}

# ---------------------------------------------------------------- 构建报告
$totalBytes = (Get-ChildItem $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$report = [pscustomobject]@{
    Site       = $site.name
    BaseUrl    = $site.baseUrl
    BuiltAt    = $buildDate
    Pages      = $pages.Count
    JsonLdBlocks = $ldCount
    Links      = $linkCount
    TotalKB    = [math]::Round($totalBytes / 1KB, 1)
    Errors     = $errors.Count
    Output     = $OutDir
}
Write-Host ""
Write-Step "构建报告"
$report | Format-List | Out-String | Write-Host

if ($errors.Count -gt 0) {
    Write-Bad "存在 $($errors.Count) 项校验错误，请修复后再发布。"
    exit 1
}
Write-Ok "构建成功 → $OutDir"

# ---------------------------------------------------------------- 本地服务
if ($Serve) {
    Write-Step "启动本地静态服务 http://localhost:$Port"
    & (Join-Path $PSScriptRoot "serve.ps1") -Root $OutDir -Port $Port
}
