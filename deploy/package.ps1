<#
.SYNOPSIS
  将 dist 打包为可直接上传到任意静态托管的分发包

.DESCRIPTION
  产出两个文件到 release/：
    lite-arcade-dist-<yyyyMMdd-HHmm>.zip   完整站点（含 .gitkeep 之外的全部产物）
    checksums.txt                           主要文件的 SHA256 清单
  上传方式：
    - GitHub Pages / Netlify / Vercel / Cloudflare Pages：直接上传 zip 或 dist 目录
    - 对象存储（S3 / OSS / COS）：解压后同步到桶根目录，并配置 index.html 为索引文档

.EXAMPLE
  .\deploy\package.ps1
#>
[CmdletBinding()]
param([string]$Root = "")

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Join-Path $RepoRoot "dist" }
if (-not (Test-Path $Root)) { throw "未找到构建产物：$Root，请先执行 deploy\build.ps1" }

$releaseDir = Join-Path $RepoRoot "release"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

$stamp = (Get-Date).ToString("yyyyMMdd-HHmm")
$zipPath = Join-Path $releaseDir ("lite-arcade-dist-" + $stamp + ".zip")
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($Root, $zipPath,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)

$sums = New-Object System.Text.StringBuilder
Get-ChildItem $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = "/" + ($_.FullName.Substring((Resolve-Path $Root).Path.Length).TrimStart("\") -replace "\\", "/")
    [void]$sums.AppendLine($hash + "  " + $rel)
}
[System.IO.File]::WriteAllText((Join-Path $releaseDir "checksums.txt"), $sums.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$sizeKB = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
$fileCount = (Get-ChildItem $Root -Recurse -File).Count
Write-Host ""
Write-Host "  分发包：$zipPath" -ForegroundColor Green
Write-Host "  压缩包：$sizeKB KB   文件数：$fileCount" -ForegroundColor Cyan
Write-Host "  校验值：$(Join-Path $releaseDir 'checksums.txt')" -ForegroundColor Cyan
