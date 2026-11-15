<#
.SYNOPSIS
    用 GitHub REST API 创建/更新 Release 并上传 APK。

.DESCRIPTION
    凭证来源（按顺序）：
      1) 环境变量 GITHUB_TOKEN / GH_TOKEN；
      2) 本机 git credential helper（`git credential fill`，GCM 存过的 PAT / OAuth token）。
    只读 token、不落盘、不打印。

.PARAMETER Tag
    Release tag，例如 v0.2.0。tag 不存在时 GitHub 会按 target 自动创建。

.EXAMPLE
    pwsh -File .\tools\publish_release.ps1 -Tag v0.2.0 -Apk dist\JMComic-0.2.0-release.apk -NotesFile docs\RELEASE_NOTES_0.2.0.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [Parameter(Mandatory = $true)][string]$Apk,
    [string]$NotesFile = '',
    [string]$Owner = 'xzxycx123',
    [string]$Repo = 'JMComic-Flutter-Android',
    [string]$Name = '',
    [string]$Target = 'main',
    [switch]$Draft,
    [switch]$Prerelease
)

$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'

function Get-Token {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    $filled = "protocol=https`nhost=github.com`n`n" | & git credential fill 2>$null
    $line = ($filled | Select-String '^password=' | Select-Object -First 1)
    if (-not $line) { throw '找不到 GitHub 凭证：请设置 GITHUB_TOKEN，或先用 git 登录一次。' }
    return ($line.ToString() -replace '^password=', '')
}

$token = Get-Token
$headers = @{
    Authorization          = "token $token"
    'User-Agent'           = 'JMComic-Release'
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$api = "https://api.github.com/repos/$Owner/$Repo"

if (-not (Test-Path -LiteralPath $Apk)) { throw "APK 不存在：$Apk" }
$apkItem = Get-Item -LiteralPath $Apk
$revision = (& git -C (Split-Path -Parent $PSScriptRoot) rev-parse --short HEAD) -join ''
$hash = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash

$body = ''
if ($NotesFile -and (Test-Path -LiteralPath $NotesFile)) {
    $body = Get-Content -LiteralPath $NotesFile -Raw -Encoding UTF8
}

$payload = @{
    tag_name         = $Tag
    target_commitish = $Target
    name             = if ($Name) { $Name } else { "JMComic $Tag" }
    body             = $body
    draft            = [bool]$Draft
    prerelease       = [bool]$Prerelease
} | ConvertTo-Json -Depth 4

# 1) 已有同 tag Release 就复用，否则创建
$release = $null
try {
    $release = Invoke-RestMethod -Uri "$api/releases/tags/$Tag" -Headers $headers -TimeoutSec 60
    Write-Host "复用已有 Release: $($release.html_url)"
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -ne 404) { throw }
}

if (-not $release) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $release = Invoke-RestMethod -Method Post -Uri "$api/releases" -Headers $headers `
        -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 120
    Write-Host "已创建 Release: $($release.html_url)"
}

# 2) 上传 APK（同名资产先删）
$existing = Invoke-RestMethod -Uri "$api/releases/$($release.id)/assets" -Headers $headers -TimeoutSec 60
foreach ($asset in $existing) {
    if ($asset.name -eq $apkItem.Name) {
        Invoke-RestMethod -Method Delete -Uri "$api/releases/assets/$($asset.id)" -Headers $headers -TimeoutSec 60
        Write-Host "已删除同名旧资产: $($asset.name)"
    }
}

$uploadUrl = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($release.id)/assets?name=$($apkItem.Name)"
$asset = Invoke-RestMethod -Method Post -Uri $uploadUrl -Headers $headers -InFile $apkItem.FullName `
    -ContentType 'application/vnd.android.package-archive' -TimeoutSec 600
Write-Host "上传完成: $($asset.browser_download_url)"

Write-Host ''
Write-Host "Release : $($release.html_url)"
Write-Host "Commit  : $revision"
Write-Host "APK     : $($apkItem.Name)  $([math]::Round($apkItem.Length / 1MB, 2)) MB"
Write-Host "SHA256  : $hash"
