<#
.SYNOPSIS
  生成站点图片资源：og-cover.png(1200x630) 与 PWA 图标 icon-180/512.png
  使用 .NET System.Drawing，无需任何第三方库。
#>
[CmdletBinding()]
param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot "src\assets\img" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Add-Type -AssemblyName System.Drawing

function New-RoundedRectPath([int]$w, [int]$h, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($w - $d, 0, $d, $d, 270, 90)
    $p.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $p.AddArc(0, $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Write-Cover {
    $w = 1200; $h = 630
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # 背景
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point($w, $h)),
        [System.Drawing.Color]::FromArgb(255, 11, 16, 32),
        [System.Drawing.Color]::FromArgb(255, 7, 10, 22))
    $g.FillRectangle($bg, 0, 0, $w, $h)

    # 装饰光斑
    $glow = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(80, 40)),
        (New-Object System.Drawing.Point(620, 480)),
        [System.Drawing.Color]::FromArgb(90, 110, 231, 255),
        [System.Drawing.Color]::FromArgb(0, 110, 231, 255))
    $g.FillEllipse($glow, -120, -160, 780, 700)
    $glow2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(760, 60)),
        (New-Object System.Drawing.Point(1180, 520)),
        [System.Drawing.Color]::FromArgb(80, 167, 139, 250),
        [System.Drawing.Color]::FromArgb(0, 167, 139, 250))
    $g.FillEllipse($glow2, 640, -140, 720, 660)

    # 顶部品牌块
    $brand = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(80, 96)),
        (New-Object System.Drawing.Point(230, 168)),
        [System.Drawing.Color]::FromArgb(255, 110, 231, 255),
        [System.Drawing.Color]::FromArgb(255, 167, 139, 250))
    $g.FillRectangle($brand, 80, 96, 72, 72)
    $markFont = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Bold)
    $g.DrawString("LA", $markFont, [System.Drawing.Brushes]::Black, 88, 108)

    $font1 = New-Object System.Drawing.Font("Microsoft YaHei", 74, [System.Drawing.FontStyle]::Bold)
    $g.DrawString("Lite Arcade", $font1, [System.Drawing.Brushes]::White, 172, 92)

    $font2 = New-Object System.Drawing.Font("Microsoft YaHei", 34, [System.Drawing.FontStyle]::Regular)
    $g.DrawString("轻量开源游戏站", $font2, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 154, 168, 199))), 82, 196)

    $font3 = New-Object System.Drawing.Font("Microsoft YaHei", 40, [System.Drawing.FontStyle]::Bold)
    $g.DrawString("零依赖 · 免安装 · 可离线 · MIT 许可", $font3, [System.Drawing.Brushes]::White, 82, 300)

    $font4 = New-Object System.Drawing.Font("Microsoft YaHei", 28, [System.Drawing.FontStyle]::Regular)
    $g.DrawString("贪吃蛇 · 2048 · 打砖块 · 俄罗斯方块 · 记忆翻牌 · 像素飞鸟", $font4,
        (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 110, 231, 255))), 82, 382)

    # 底部强调条
    $bar = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(82, 0)),
        (New-Object System.Drawing.Point(1118, 0)),
        [System.Drawing.Color]::FromArgb(255, 110, 231, 255),
        [System.Drawing.Color]::FromArgb(255, 167, 139, 250))
    $g.FillRectangle($bar, 82, 470, 1036, 8)

    $font5 = New-Object System.Drawing.Font("Microsoft YaHei", 24, [System.Drawing.FontStyle]::Regular)
    $g.DrawString("lite-arcade.pages.dev", $font5,
        (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 111, 127, 159))), 82, 512)

    $bmp.Save((Join-Path $OutDir "og-cover.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "  ✓ og-cover.png (1200x630)"
}

function Write-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $r = [int]($size * 0.22)
    $path = New-RoundedRectPath $size $size $r
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point($size, $size)),
        [System.Drawing.Color]::FromArgb(255, 110, 231, 255),
        [System.Drawing.Color]::FromArgb(255, 167, 139, 250))
    $g.FillPath($bg, $path)

    $inner = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pad = [int]($size * 0.06)
    $ir = [int]($size * 0.18)
    $inner.AddArc($pad, $pad, $ir * 2, $ir * 2, 180, 90)
    $inner.AddArc($size - $pad - $ir * 2, $pad, $ir * 2, $ir * 2, 270, 90)
    $inner.AddArc($size - $pad - $ir * 2, $size - $pad - $ir * 2, $ir * 2, $ir * 2, 0, 90)
    $inner.AddArc($pad, $size - $pad - $ir * 2, $ir * 2, $ir * 2, 90, 90)
    $inner.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 7, 10, 22))), $inner)

    $f = New-Object System.Drawing.Font("Segoe UI", [single]($size * 0.32), [System.Drawing.FontStyle]::Bold)
    $sf = $g.MeasureString("LA", $f)
    $g.DrawString("LA", $f, [System.Drawing.Brushes]::White,
        [single](($size - $sf.Width) / 2), [single](($size - $sf.Height) / 2 - $size * 0.02))

    # 装饰点
    $dot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 209, 102))
    $ds = [int]($size * 0.09)
    $g.FillEllipse($dot, [int]($size * 0.66), [int]($size * 0.24), $ds, $ds)

    $bmp.Save((Join-Path $OutDir ("icon-" + $size + ".png")), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "  ✓ icon-$size.png"
}

Write-Cover
Write-Icon 180
Write-Icon 512
