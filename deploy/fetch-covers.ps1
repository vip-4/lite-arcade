# fetch-covers.ps1
# 构建期获取 CC0 游戏主题配图并本地内置（零运行时外链，性能不退化）。
# 优先用 Pixabay API（需 -Key 或 $env:PIXABAY_KEY）；任何失败均回退到本地占位图，
# 保证每个 slug 必有文件，游戏页 <img> 与 JSON-LD 永不 404。
#
# 用法：
#   .\deploy\fetch-covers.ps1 -Key "你的PixabayKey"
#   $env:PIXABAY_KEY="..."; .\deploy\fetch-covers.ps1

param(
    [string]$Key = ($env:PIXABAY_KEY),
    [string]$ImgDir = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ImgDir) { $ImgDir = Join-Path $RepoRoot "src\assets\img" }
$CoverDir = Join-Path $ImgDir "covers"
New-Item -ItemType Directory -Path $CoverDir -Force | Out-Null

Add-Type -AssemblyName System.Drawing

# slug -> 查询词（CC0 游戏主题）
$queries = @{
    "snake"    = @("snake game", "retro arcade")
    "2048"     = @("number puzzle", "wooden blocks")
    "breakout" = @("brick wall", "arcade game")
    "tetris"   = @("color blocks", "tetris blocks")
    "memory"   = @("playing cards", "memory game")
    "bird"     = @("pixel bird", "small bird")
    "slot-classic" = @("slot machine", "casino chips")
    "slot-fruit"   = @("fruit slot machine", "casino fruit")
    "slot-egypt"   = @("egyptian casino", "pyramid treasure")
    "slot-panda"   = @("panda casino", "bamboo luck")
    "slot-diamond" = @("diamond casino", "luxury jewels")
}

function Resize-Crop([string]$srcPath, [string]$destPath, [int]$tw, [int]$th, [int]$quality) {
    $src = [System.Drawing.Image]::FromFile($srcPath)
    try {
        $ratio = [math]::Max($tw / $src.Width, $th / $src.Height)
        $dw = [int]($src.Width * $ratio); $dh = [int]($src.Height * $ratio)
        $dx = [int](($dw - $tw) / 2); $dy = [int](($dh - $th) / 2)
        $tmp = New-Object System.Drawing.Bitmap($dw, $dh)
        $g = [System.Drawing.Graphics]::FromImage($tmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($src, 0, 0, $dw, $dh)
        $out = New-Object System.Drawing.Bitmap($tw, $th)
        $g2 = [System.Drawing.Graphics]::FromImage($out)
        $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g2.DrawImage($tmp, (New-Object System.Drawing.Rectangle(0, 0, $tw, $th)), (New-Object System.Drawing.Rectangle($dx, $dy, $tw, $th)), [System.Drawing.GraphicsUnit]::Pixel)
        $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
        $q = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $q.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $quality)
        $out.Save($destPath, $enc, $q)
        $g.Dispose(); $g2.Dispose(); $tmp.Dispose(); $out.Dispose()
    } finally { $src.Dispose() }
}

function Make-Placeholder([string]$destPath, [int]$tw, [int]$th, [string]$label) {
    $bmp = New-Object System.Drawing.Bitmap($tw, $th)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 17, 22, 40))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 110, 231, 255), 4)
    $g.DrawRectangle($pen, 20, 20, $tw - 40, $th - 40)
    $f = New-Object System.Drawing.Font("Microsoft YaHei", 36, [System.Drawing.FontStyle]::Bold)
    $sf = $g.MeasureString($label, $f)
    $g.DrawString($label, $f, [System.Drawing.Brushes]::White, [int](($tw - $sf.Width) / 2), [int](($th - $sf.Height) / 2))
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $g.Dispose(); $bmp.Dispose()
}

function Fetch-First([string]$q) {
    $u = "https://pixabay.com/api/?key=$Key&q=$([uri]::EscapeDataString($q))&image_type=photo&orientation=horizontal&safesearch=true&per_page=5&min_width=640"
    try {
        $j = Invoke-RestMethod -Uri $u -TimeoutSec 25 -UseBasicParsing
        if ($j.totalHits -gt 0 -and $j.hits.Count -gt 0) { return $j.hits[0].webformatURL }
    } catch { }
    return $null
}

$ProgressPreference = "SilentlyContinue"
$tmpRoot = Join-Path $env:TEMP "lite-covers"
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$ok = 0; $fallback = 0

foreach ($slug in $queries.Keys) {
    $dest = Join-Path $CoverDir ($slug + ".jpg")
    $url = $null
    if ($Key) {
        foreach ($q in $queries[$slug]) { $url = Fetch-First $q; if ($url) { break } }
    }
    if ($url) {
        try {
            $tmp = Join-Path $tmpRoot ($slug + ".jpg")
            Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 40 -UseBasicParsing
            Resize-Crop $tmp $dest 800 450 82
            Write-Host "  ✓ covers/$slug.jpg (Pixabay)" -ForegroundColor Green
            $ok++
            continue
        } catch { }
    }
    Make-Placeholder $dest 800 450 $slug
    Write-Host "  • covers/$slug.jpg (本地占位)" -ForegroundColor DarkGray
    $fallback++
}

Write-Host "[covers] 完成：Pixabay $ok / 占位 $fallback / 共 $($queries.Count)" -ForegroundColor Cyan
