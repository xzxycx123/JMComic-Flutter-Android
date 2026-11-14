<#
.SYNOPSIS
    JM 移动端协议实网探测脚本（md5 token + AES-128-ECB 响应解密 + 关键端点自检）。

.DESCRIPTION
    用途：
      1) 验证本机到 JM API / 图床线路是否可用；
      2) 打印首页所需端点的真实结构与字段（/promote、/latest、/categories、/categories/filter）；
      3) 验证专辑 / 章节 / scramble_id / 封面 / 正文图四类资源的可访问性；
      4) 输出可直接抄进 Dart 单测或 fixtures 的样例。

    只读：全程 GET，不写任何站点数据；cookie 只存在于进程内 WebSession。

    代理：本机开有系统代理（如 FlClash 127.0.0.1:7890）时，PowerShell 默认不会自动用上，
    脚本会读注册表 ProxyEnable/ProxyServer 自动补 -Proxy；也可用 -Proxy 显式指定。

.PARAMETER ApiHost
    指定 API 域名（不带 https://）。默认依次尝试内置域名列表，取第一个可用的。

.PARAMETER AlbumId
    用于详情/章节/图片自检的 JM 车号，默认 1490702。

.PARAMETER Proxy
    显式 HTTP 代理，如 http://127.0.0.1:7890；传 direct 表示强制直连。

.EXAMPLE
    pwsh -File .\tools\probe_api.ps1
    pwsh -File .\tools\probe_api.ps1 -ApiHost www.cdnbtd.cc -AlbumId 350234
    pwsh -File .\tools\probe_api.ps1 -Proxy http://127.0.0.1:7890
#>
[CmdletBinding()]
param(
    [string]$ApiHost = '',
    [string]$AlbumId = '1490702',
    [string]$Proxy = '',
    [int]$Retries = 2
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- 协议常量
$TokenSecret      = '185Hcomic3PAPP7R'   # 普通接口 token / data 解密密钥前缀
$ScrambleSecret   = '18comicAPPContent'  # /chapter_view_template 专用
$AppVersion       = '2.1.13'
$UserAgent        = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
$FallbackApiHosts = @('www.cdnbtd.cc', 'www.cdnutc.cc', 'www.cdnhjk.net', 'www.cdngwc.cc', 'www.cdngwc.net', 'www.cdngwc.club')

$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:ProxyUrl = $null

# ---------------------------------------------------------------- 代理探测
function Resolve-ProxyUrl {
    param([string]$Explicit)
    if ($Explicit) {
        if ($Explicit -eq 'direct') { return $null }
        return $Explicit
    }
    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
            $server = ($settings.ProxyServer -split ';' | Select-Object -First 1).Trim()
            if ($server -match '^[\w\.\-]+:\d+$') { return "http://$server" }
            if ($server -match '^https?://') { return $server }
        }
    }
    catch { }
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    return $null
}

$script:ProxyUrl = Resolve-ProxyUrl -Explicit $Proxy
if ($script:ProxyUrl) { Write-Host "使用代理: $script:ProxyUrl" -ForegroundColor DarkGray }
else { Write-Host '直连模式（未检测到系统代理）' -ForegroundColor DarkGray }

# ---------------------------------------------------------------- 基础工具
function Get-Md5Hex {
    param([string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        (($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $md5.Dispose() }
}

function Get-UnixTimestamp { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() }

function Get-Token {
    param([string]$Timestamp, [string]$Secret = $TokenSecret)
    Get-Md5Hex ($Timestamp + $Secret)
}

function ConvertFrom-JmPayload {
    param([string]$Base64, [string]$Timestamp, [string]$Secret = $TokenSecret)
    $key = [Text.Encoding]::ASCII.GetBytes((Get-Md5Hex ($Timestamp + $Secret)))
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = 'ECB'
        $aes.Padding = 'PKCS7'
        $aes.Key = $key
        $raw = [Convert]::FromBase64String(($Base64 -replace '\s', ''))
        $plain = $aes.CreateDecryptor().TransformFinalBlock($raw, 0, $raw.Length)
        [Text.Encoding]::UTF8.GetString($plain)
    }
    finally { $aes.Dispose() }
}

function Invoke-JmWeb {
    <# 带代理/重试的 GET，返回原始响应文本。 #>
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 40
    )
    $attempt = 0
    $lastError = $null
    while ($attempt -le $Retries) {
        if ($attempt -gt 0) { Start-Sleep -Milliseconds (600 * $attempt) }
        $attempt++
        $params = @{
            Uri             = $Uri
            Headers         = $Headers
            WebSession      = $script:Session
            TimeoutSec      = $TimeoutSec
            UseBasicParsing = $true
        }
        if ($script:ProxyUrl) { $params['Proxy'] = $script:ProxyUrl }
        try {
            $resp = Invoke-WebRequest @params
            return [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        }
        catch {
            $lastError = $_.Exception.Message
            if ($lastError -notmatch 'SSL|handshake|EOF|超时|timed out|连接') { break }
        }
    }
    throw $lastError
}

function Invoke-JmRequest {
    <# 发一次带 token 的 GET，返回原始文本（不解密）。 #>
    param(
        [string]$Path,
        [string]$Secret = $TokenSecret,
        [hashtable]$ExtraHeaders = @{}
    )
    $ts = Get-UnixTimestamp
    $headers = @{
        token        = Get-Token -Timestamp $ts -Secret $Secret
        tokenparam   = "$ts,$AppVersion"
        'User-Agent' = $UserAgent
    }
    $headers += $ExtraHeaders
    Invoke-JmWeb -Uri "https://$script:ApiHost$Path" -Headers $headers
}

function Invoke-JmApi {
    <# 调接口并解密 data，返回 JSON 对象（失败返回 $null 并打印原因）。 #>
    param([string]$Path)
    try {
        $ts = Get-UnixTimestamp
        $text = Invoke-JmRequest -Path $Path
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -lt 0 -or $end -lt $start) { Write-Warning "$Path → 响应非 JSON"; return $null }
        $envelope = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        if ($envelope.code -ne 200) {
            Write-Warning ("$Path → code={0} msg={1}" -f $envelope.code, ($envelope.errorMsg ?? $envelope.msg))
            return $null
        }
        (ConvertFrom-JmPayload -Base64 $envelope.data -Timestamp $ts) | ConvertFrom-Json
    }
    catch {
        Write-Warning ("$Path → 请求失败: " + ($_.Exception.Message -replace "`n", ' '))
        $null
    }
}

function Show-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ("=== $Title " + ('=' * [Math]::Max(0, 58 - $Title.Length))) -ForegroundColor Cyan
}

function Format-Sample {
    param($Object, [int]$Depth = 5)
    '  ' + ($Object | ConvertTo-Json -Compress -Depth $Depth)
}

# ---------------------------------------------------------------- 线路选择
function Resolve-ApiHost {
    param([string]$Preferred)
    if ($Preferred) { return $Preferred }
    foreach ($candidate in $FallbackApiHosts) {
        try {
            $ts = Get-UnixTimestamp
            $headers = @{
                token = (Get-Token -Timestamp $ts)
                tokenparam = "$ts,$AppVersion"
                'User-Agent' = $UserAgent
            }
            $body = Invoke-JmWeb -Uri "https://$candidate/setting" -Headers $headers -TimeoutSec 20
            if ($body -match '"code"\s*:\s*200') { return $candidate }
        }
        catch { continue }
    }
    return ''
}

$script:ApiHost = Resolve-ApiHost -Preferred $ApiHost
if (-not $script:ApiHost) {
    Write-Host ''
    Write-Host '所有内置 API 域名均不可达。排查顺序：' -ForegroundColor Red
    Write-Host '  1) 本机代理是否在跑（本机常见：FlClash → 127.0.0.1:7890），必要时加 -Proxy http://127.0.0.1:7890'
    Write-Host '  2) 换 -ApiHost 指定其它线路'
    Write-Host '  3) 换网络（手机热点）再试'
    exit 1
}
Write-Host "API 线路: https://$script:ApiHost" -ForegroundColor Green

# ---------------------------------------------------------------- 1. /setting
Show-Section '1. /setting（引导：cookie + img_host + 版本）'
$setting = Invoke-JmApi '/setting'
if (-not $setting) { exit 1 }
$imageHost = ($setting.img_host -replace '^https?://', '' -replace '/$', '')
Write-Host ("jm3_version = {0}" -f $setting.jm3_version)
Write-Host ("img_host    = {0}" -f $setting.img_host)
Write-Host ("cookies     = {0} 个（会话内保留，后续请求自动携带）" -f $script:Session.Cookies.Count)

# ---------------------------------------------------------------- 2. 首页模块
Show-Section '2. /promote（首页分节横滑，App 首页主数据源）'
$promote = Invoke-JmApi '/promote'
if ($promote) {
    Write-Host ("模块数 = {0}" -f $promote.Count)
    foreach ($module in $promote) {
        Write-Host ("  id={0,-5} type={1,-20} items={2,-3} title={3}" -f $module.id, $module.type, $module.content.Count, $module.title)
    }
    Write-Host ''
    Write-Host '  首个条目字段样例:' -ForegroundColor DarkGray
    Write-Host (Format-Sample $promote[0].content[0])
}

Show-Section '3. /latest?page=1（首页「最新上架」）'
$latest = Invoke-JmApi '/latest?page=1'
if ($latest) {
    Write-Host ("返回条数 = {0}，首条 id = {1}" -f $latest.Count, $latest[0].id)
    Write-Host (Format-Sample $latest[0])
}

Show-Section '4. /categories?page=1（首页分类 chips）'
$categories = Invoke-JmApi '/categories?page=1'
if ($categories) {
    Write-Host ("顶层分类 = {0}" -f $categories.categories.Count)
    foreach ($category in $categories.categories) {
        Write-Host ("  id={0,-4} total={1,-8} name={2}" -f $category.id, $category.total_albums, $category.name)
    }
    $withSubs = $categories.categories | Where-Object { $_.sub_categories } | Select-Object -First 1
    if ($withSubs) { Write-Host ('  子分类样例: ' + (($withSubs.sub_categories | ForEach-Object { "$($_.CID):$($_.name)" }) -join ', ')) }
}

Show-Section '5. /categories/filter（首页无限流，o 排序枚举）'
foreach ($order in @('mr', 'mv', 'mv_m', 'mv_w', 'mv_t', 'md', 'mp')) {
    $filter = Invoke-JmApi ("/categories/filter?page=1&order=&c=0&o=$order")
    if ($filter) {
        Write-Host ("  o={0,-5} total={1,-6} 本页={2,-3} 首条={3}" -f $order, $filter.total, $filter.content.Count, $filter.content[0].id)
    }
}

Show-Section "6. /album?id=$AlbumId（详情）"
$album = Invoke-JmApi "/album?id=$AlbumId"
if ($album) {
    Write-Host ("name         = {0}" -f $album.name)
    Write-Host ("author       = {0}" -f $album.author)
    Write-Host ("total_photos = {0}" -f $album.total_photos)
    Write-Host ("series_id    = {0} / series 章节数 = {1}" -f $album.series_id, $album.series.Count)
    if ($album.series.Count -gt 0) { Write-Host ('  series[0] = ' + ($album.series[0] | ConvertTo-Json -Compress -Depth 5)) }
}

# ---------------------------------------------------------------- 7. 章节
$chapterId = $AlbumId
if ($album -and $album.series.Count -gt 0) { $chapterId = $album.series[0].id }

Show-Section "7. /chapter?id=$chapterId（章节图片清单）"
$chapter = Invoke-JmApi "/chapter?id=$chapterId"
if ($chapter) {
    Write-Host ("images = {0} 张，首张 = {1}" -f $chapter.images.Count, $chapter.images[0])
}

# ---------------------------------------------------------------- 8. scramble_id
Show-Section '8. /chapter_view_template（scramble_id，切片阈值）'
try {
    $ts = Get-UnixTimestamp
    $path = "/chapter_view_template?id=$chapterId&mode=vertical&page=0&app_img_shunt=1&express=off&v=$ts"
    $html = Invoke-JmRequest -Path $path -Secret $ScrambleSecret
    $match = [regex]::Match($html, 'var\s+scramble_id\s*=\s*(\d+)\s*;')
    if ($match.Success) { Write-Host ("scramble_id = {0}" -f $match.Groups[1].Value) }
    else { Write-Host '未匹配到 scramble_id（回落默认 220980）' -ForegroundColor Yellow }
}
catch { Write-Warning ('scramble 请求失败: ' + ($_.Exception.Message -replace "`n", ' ')) }

# ---------------------------------------------------------------- 9. 封面 + 正文图
Show-Section '9. 图床自检（封面 / 正文图）'
$imageHeaders = @{
    'User-Agent'       = $UserAgent
    'Referer'          = "https://$script:ApiHost/"
    'Accept'           = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
    'X-Requested-With' = 'com.JMComic3.app'
}
function Test-ImageUrl {
    param([string]$Url, [string]$Label)
    $params = @{ Uri = $Url; Headers = $imageHeaders; TimeoutSec = 60; UseBasicParsing = $true }
    if ($script:ProxyUrl) { $params['Proxy'] = $script:ProxyUrl }
    try {
        $resp = Invoke-WebRequest @params
        $contentType = ($resp.Headers['Content-Type'] -join ', ')
        Write-Host ("  {0} → {1} {2} {3} B" -f $Label, $resp.StatusCode, $contentType, $resp.RawContentLength)
    }
    catch { Write-Host ("  {0} → 失败: {1}" -f $Label, ($_.Exception.Message -replace "`n", ' ')) -ForegroundColor Yellow }
}

if ($imageHost) {
    Test-ImageUrl -Url "https://$imageHost/media/albums/$AlbumId`_3x4.jpg" -Label '封面 _3x4.jpg'
    Test-ImageUrl -Url "https://$imageHost/media/albums/$AlbumId.jpg" -Label '封面 .jpg'
    if ($chapter -and $chapter.images.Count -gt 0) {
        Test-ImageUrl -Url "https://$imageHost/media/photos/$chapterId/$($chapter.images[0])" -Label "正文图 $($chapter.images[0])"
    }
}

Show-Section '完成'
Write-Host '若以上全绿：协议层可按 PLAN.md 直接实现；`TLS 握手失败` 先修代理，`code!=200` 换线路。' -ForegroundColor Green
