<#
.SYNOPSIS
  清理 Gitee / AtomGit 仓库中因 URI 分隔符缺陷产生的脏文件名（文件名含 access_token）
#>
[CmdletBinding()]
param(
    [ValidateSet("gitee", "atomgit")][string]$Platform = "gitee",
    [string]$Owner = "",
    [string]$Repo  = "lite-arcade",
    [string]$Branch = "master",
    [string]$Token = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Platform -eq "gitee") { $base = "https://gitee.com/api/v5"; if (-not $Token) { $Token = $env:GITEE_TOKEN } }
else { $base = "https://api.atomgit.com/api/v5"; if (-not $Token) { $Token = $env:ATOMGIT_TOKEN } }
if (-not $Token) { throw "缺少令牌" }
if (-not $Owner) { $Owner = (Invoke-RestMethod -Uri "$base/user?access_token=$Token").login }

$deleted = 0
$failed  = 0

function List-Dir {
    param([string]$Path)
    $p = if ($Path) { [uri]::EscapeDataString($Path) } else { "" }
    $u = "$base/repos/$Owner/$Repo/contents" + $(if ($p) { "/$p" }) + "?access_token=$Token&ref=$Branch"
    try { return @(Invoke-RestMethod -Uri $u -TimeoutSec 40) } catch { return @() }
}

function Walk([string]$dir) {
    $items = List-Dir $dir
    foreach ($it in $items) {
        $child = if ($dir) { "$dir/$($it.name)" } else { $it.name }
        if ($it.type -eq "dir") { Walk $child; continue }
        if ($it.name -like "*access_token*") {
            $u = "$base/repos/$Owner/$Repo/contents/" + [uri]::EscapeDataString($child) + "?access_token=$Token"
            $body = @{ access_token = $Token; sha = $it.sha; message = "chore: 清理异常文件名"; branch = $Branch } | ConvertTo-Json -Compress
            try {
                $null = Invoke-WebRequest -Method Delete -Uri $u -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 40
                Write-Host "  - 已删除 $child" -ForegroundColor DarkGray
                $script:deleted++
                Start-Sleep -Milliseconds 250
            } catch {
                Write-Host "  ! 删除失败 $child" -ForegroundColor Yellow
                $script:failed++
            }
        }
    }
}

Write-Host "[$Platform] 扫描 $Owner/$Repo 的脏文件…" -ForegroundColor Cyan
Walk ""
Write-Host "[$Platform] 删除 $deleted 个，失败 $failed 个" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
