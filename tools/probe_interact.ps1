<#
.SYNOPSIS
    评论 / 点赞（互动）端点探测：确认 JM 移动端点赞与评论的真实接口形态。

.DESCRIPTION
    只读探测 + 一次「必然失败」的写请求（未登录会被服务端拒绝），用于确认：
      1) GET  /comment?id=&page=  → 评论列表结构（total / list / 字段名）
      2) POST /like  {aid}        → 点赞接口是否存在、参数名、返回体
      3) POST /comment {aid,content} → 发评论接口是否存在、参数名
    未登录时返回 code!=200 + 文案本身就是最有价值的证据（说明端点存在、缺的是 cookie）。

.PARAMETER ApiHost
    指定 API 域名（不带 https://）。

.PARAMETER AlbumId
    用于探测的车号，默认 1490702。

.PARAMETER Proxy
    显式 HTTP 代理；传 direct 强制直连。
#>
[CmdletBinding()]
param(
    [string]$ApiHost = '',
    [string]$AlbumId = '1490702',
    [string]$Proxy = ''
)

$ErrorActionPreference = 'Continue'

$TokenSecret      = '185Hcomic3PAPP7R'
$AppVersion       = '2.1.13'
$UserAgent        = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
$FallbackApiHosts = @('www.cdnutc.cc', 'www.cdngwc.net', 'www.cdngwc.cc', 'www.cdngwc.club', 'www.cdnbtd.cc', 'www.cdnhjk.net', 'www.cdnutc.me')

$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:ProxyUrl = $null

function Resolve-ProxyUrl {
    param([string]$Explicit)
    if ($Explicit) { if ($Explicit -eq 'direct') { return $null } return $Explicit }
    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
            $server = ($settings.ProxyServer -split ';' | Select-Object -First 1).Trim()
            if ($server -match '^[\w\.\-]+:\d+$') { return "http://$server" }
            if ($server -match '^https?://') { return $server }
        }
    } catch { }
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    return $null
}

$script:ProxyUrl = Resolve-ProxyUrl -Explicit $Proxy
if ($script:ProxyUrl) { Write-Host "使用代理: $script:ProxyUrl" -ForegroundColor DarkGray } else { Write-Host '直连模式' -ForegroundColor DarkGray }

function Get-Md5Hex {
    param([string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { (($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $md5.Dispose() }
}

function Get-UnixTimestamp { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() }
function Get-Token { param([string]$Timestamp) Get-Md5Hex ($Timestamp + $TokenSecret) }

function ConvertFrom-JmPayload {
    param([string]$Base64, [string]$Timestamp)
    $key = [Text.Encoding]::ASCII.GetBytes((Get-Md5Hex ($Timestamp + $TokenSecret)))
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = 'ECB'; $aes.Padding = 'PKCS7'; $aes.Key = $key
        $raw = [Convert]::FromBase64String(($Base64 -replace '\s', ''))
        $plain = $aes.CreateDecryptor().TransformFinalBlock($raw, 0, $raw.Length)
        [Text.Encoding]::UTF8.GetString($plain)
    } finally { $aes.Dispose() }
}

function Invoke-Jm {
    <# 发一次带 token 的请求，返回解密后的 JSON（失败打印 code/文案并返回 $null）。 #>
    param([string]$Path, [string]$Method = 'GET', [hashtable]$Form = $null, [switch]$Raw)
    $ts = Get-UnixTimestamp
    $headers = @{
        token        = Get-Token -Timestamp $ts
        tokenparam   = "$ts,$AppVersion"
        'User-Agent' = $UserAgent
    }
    $params = @{
        Uri = "https://$script:ApiHost$Path"; Headers = $headers
        WebSession = $script:Session; TimeoutSec = 30; UseBasicParsing = $true
        Method = $Method
    }
    if ($script:ProxyUrl) { $params['Proxy'] = $script:ProxyUrl }
    if ($Form) { $params['Body'] = $Form }
    try {
        $resp = Invoke-WebRequest @params
        $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    } catch {
        Write-Warning ("{0} {1} → HTTP 失败: {2}" -f $Method, $Path, ($_.Exception.Message -replace "`n", ' '))
        return $null
    }
    if ($Raw) { return $text }
    $start = $text.IndexOf('{'); $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt $start) { Write-Warning "$Path → 非 JSON：$($text.Substring(0, [Math]::Min(120, $text.Length)))"; return $null }
    $envelope = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
    if ($envelope.code -ne 200) {
        Write-Host ("  code={0} msg={1}" -f $envelope.code, ($envelope.errorMsg ?? $envelope.msg)) -ForegroundColor Yellow
        return @{ __code = $envelope.code; __msg = ($envelope.errorMsg ?? $envelope.msg) }
    }
    (ConvertFrom-JmPayload -Base64 $envelope.data -Timestamp $ts) | ConvertFrom-Json
}

function Show-Section { param([string]$Title) Write-Host ''; Write-Host ("=== $Title " + ('=' * [Math]::Max(0, 56 - $Title.Length))) -ForegroundColor Cyan }

# ---------------------------------------------------------------- 线路
if (-not $ApiHost) {
    foreach ($candidate in $FallbackApiHosts) {
        try {
            $ts = Get-UnixTimestamp
            $body = Invoke-WebRequest -Uri "https://$candidate/setting" -Headers @{ token = (Get-Token -Timestamp $ts); tokenparam = "$ts,$AppVersion"; 'User-Agent' = $UserAgent } -TimeoutSec 20 -UseBasicParsing -Proxy $script:ProxyUrl
            $plain = [Text.Encoding]::UTF8.GetString($body.RawContentStream.ToArray())
            if ($plain -match '"code"\s*:\s*200') { $ApiHost = $candidate; break }
        } catch { continue }
    }
}
if (-not $ApiHost) { Write-Host '所有线路不可达' -ForegroundColor Red; exit 1 }
$script:ApiHost = $ApiHost
Write-Host "API 线路: https://$script:ApiHost" -ForegroundColor Green

Show-Section '0. /setting'
$setting = Invoke-Jm '/setting'
if ($setting) { Write-Host ("img_host={0} jm3_version={1}" -f $setting.img_host, $setting.jm3_version) }

Show-Section "1. GET /comment?id=$AlbumId&page=1"
$comment = Invoke-Jm "/comment?id=$AlbumId&page=1"
if ($comment) {
    Write-Host ('顶层字段: ' + (($comment.PSObject.Properties.Name) -join ', '))
    if ($comment.total) { Write-Host ("total = {0}" -f $comment.total) }
    $list = $comment.list ?? $comment.comments ?? $comment.content
    if ($list) {
        Write-Host ("条目数 = {0}" -f @($list).Count)
        Write-Host ('首条: ' + (@($list)[0] | ConvertTo-Json -Compress -Depth 5))
    }
}

Show-Section '2. GET /comment?v=2 变体（分页参数名核对）'
foreach ($variant in @("/comment?id=$AlbumId", "/comment?aid=$AlbumId&page=1", "/comment?id=$AlbumId&page=1&order=likes")) {
    Write-Host "  试 $variant"
    $r = Invoke-Jm $variant
    if ($r -and -not $r.__code) {
        $list = $r.list ?? $r.comments ?? $r.content
        Write-Host ("    → total={0} 条目={1}" -f $r.total, $(if ($list) { @($list).Count } else { '?' }))
    }
}

Show-Section "3. POST /like {aid=$AlbumId}（未登录，期望被拒但仍能证明端点存在）"
foreach ($form in @(@{ aid = $AlbumId }, @{ id = $AlbumId })) {
    $name = ($form.Keys | Select-Object -First 1)
    Write-Host "  POST /like  $name=$($form[$name])"
    $r = Invoke-Jm '/like' -Method 'POST' -Form $form
    if ($r -and -not $r.__code) { Write-Host ('    返回: ' + ($r | ConvertTo-Json -Compress -Depth 4)) }
}

Show-Section "4. POST /comment {aid, content}（确认发评论接口与参数名）"
$r = Invoke-Jm '/comment' -Method 'POST' -Form @{ aid = $AlbumId; content = 'probe-test-only'; comment_id = '0' }
if ($r -and -not $r.__code) { Write-Host ('  返回: ' + ($r | ConvertTo-Json -Compress -Depth 4)) }

Show-Section '5. 现有 /album 里的计数字段（点赞数在详情里叫什么）'
$album = Invoke-Jm "/album?id=$AlbumId"
if ($album) {
    $names = $album.PSObject.Properties.Name | Where-Object { $_ -match 'like|comment|view|total' }
    foreach ($n in $names) { Write-Host ("  {0} = {1}" -f $n, $album.$n) }
}

Write-Host ''
Write-Host '说明：未登录时 200 才是意外；上面每条的 code/文案就是端点存在性证据。' -ForegroundColor DarkGray
