<#
.SYNOPSIS
    `/categories` + `/categories/filter` 实网探测：验证分类筛选参数到底怎么传。

.DESCRIPTION
    只读 GET。用来回答两个问题：
      1) `/categories/filter` 的 `c` 到底认什么？（结论：只认 slug，数字 id 被忽略）
      2) 每个顶层分类的 slug、真实 total、排序 `o` 是否与筛选正交。

    协议与 tools/probe_api.ps1 一致：md5(ts+secret) token、AES-256-ECB 解密 data。

.PARAMETER ApiHost
    指定 API 域名（不带 https://）。默认取 assets\data\jm_hosts.json 里 ok 的线路，再回退内置表。

.PARAMETER Proxy
    显式 HTTP 代理（如 http://127.0.0.1:7890）；传 direct 强制直连。默认读系统代理。

.PARAMETER Slug
    排序 / 子分类试探使用的分类 slug，默认 doujin（同人）。

.EXAMPLE
    pwsh -File .\tools\probe_categories.ps1
    pwsh -File .\tools\probe_categories.ps1 -Proxy direct
    pwsh -File .\tools\probe_categories.ps1 -Slug single
#>
[CmdletBinding()]
param(
    [string]$ApiHost = '',
    [string]$Proxy = '',
    [string]$Slug = 'doujin'
)

$ErrorActionPreference = 'Continue'

$TokenSecret = '185Hcomic3PAPP7R'
$AppVersion  = '2.1.13'
$UserAgent   = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
$FallbackApiHosts = @('www.cdnutc.cc', 'www.cdngwc.net', 'www.cdngwc.cc', 'www.cdngwc.club', 'www.cdnbtd.cc', 'www.cdnhjk.net', 'www.cdnutc.me')

$SeedPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\data\jm_hosts.json'
if (Test-Path $SeedPath) {
    try {
        $seed = Get-Content $SeedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $fromSeed = @($seed.api | Where-Object { $_.status -eq 'ok' } | Select-Object -ExpandProperty host)
        if ($fromSeed.Count -gt 0) { $FallbackApiHosts = @($fromSeed) + @($FallbackApiHosts | Where-Object { $_ -notin $fromSeed }) }
    }
    catch { Write-Warning "线路种子读取失败：$($_.Exception.Message)" }
}

$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:ProxyUrl = $null
if ($Proxy) {
    $script:ProxyUrl = if ($Proxy -eq 'direct') { $null } else { $Proxy }
}
else {
    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
            $server = ($settings.ProxyServer -split ';' | Select-Object -First 1).Trim()
            if ($server -match '^[\w\.\-]+:\d+$') { $script:ProxyUrl = "http://$server" }
            elseif ($server -match '^https?://') { $script:ProxyUrl = $server }
        }
    }
    catch { }
    if (-not $script:ProxyUrl -and $env:HTTPS_PROXY) { $script:ProxyUrl = $env:HTTPS_PROXY }
}
Write-Host ("代理: {0}" -f $(if ($script:ProxyUrl) { $script:ProxyUrl } else { '直连' })) -ForegroundColor DarkGray

function Get-Md5Hex([string]$Text) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { (($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $md5.Dispose() }
}
function Get-Ts { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() }

function ConvertFrom-JmPayload {
    param([string]$Base64, [string]$Timestamp)
    $key = [Text.Encoding]::ASCII.GetBytes((Get-Md5Hex ($Timestamp + $TokenSecret)))
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

function Invoke-JmApi {
    param([string]$Path)
    try {
        $ts = Get-Ts
        $headers = @{
            token        = (Get-Md5Hex ($ts + $TokenSecret))
            tokenparam   = "$ts,$AppVersion"
            'User-Agent' = $UserAgent
        }
        $params = @{
            Uri             = "https://$script:ApiHost$Path"
            Headers         = $headers
            WebSession      = $script:Session
            TimeoutSec      = 30
            UseBasicParsing = $true
        }
        if ($script:ProxyUrl) { $params['Proxy'] = $script:ProxyUrl }
        $resp = Invoke-WebRequest @params
        $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -lt 0 -or $end -lt $start) { Write-Warning "$Path → 非 JSON"; return $null }
        $envelope = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        if ($envelope.code -ne 200) {
            Write-Warning ("$Path → code={0} msg={1}" -f $envelope.code, ($envelope.errorMsg + $envelope.msg))
            return $null
        }
        (ConvertFrom-JmPayload -Base64 $envelope.data -Timestamp $ts) | ConvertFrom-Json
    }
    catch {
        Write-Warning ("$Path → 请求失败: " + ($_.Exception.Message -replace "`n", ' '))
        $null
    }
}

function Resolve-ApiHost {
    foreach ($candidate in $FallbackApiHosts) {
        try {
            $ts = Get-Ts
            $headers = @{
                token        = (Get-Md5Hex ($ts + $TokenSecret))
                tokenparam   = "$ts,$AppVersion"
                'User-Agent' = $UserAgent
            }
            $params = @{ Uri = "https://$candidate/setting"; Headers = $headers; TimeoutSec = 15; UseBasicParsing = $true }
            if ($script:ProxyUrl) { $params['Proxy'] = $script:ProxyUrl }
            $body = [Text.Encoding]::UTF8.GetString((Invoke-WebRequest @params).RawContentStream.ToArray())
            if ($body -match '"code"\s*:\s*200') { return $candidate }
        }
        catch { continue }
    }
    ''
}

$script:ApiHost = if ($ApiHost) { $ApiHost } else { Resolve-ApiHost }
if (-not $script:ApiHost) {
    Write-Host '所有线路均不可达：先检查代理（-Proxy http://127.0.0.1:7890）或换 -ApiHost。' -ForegroundColor Red
    exit 1
}
Write-Host "API 线路: https://$script:ApiHost" -ForegroundColor Green

function Show-FilterLine {
    param([string]$Label, [string]$Query)
    $r = Invoke-JmApi "/categories/filter?$Query"
    if (-not $r) { Write-Host ("  {0,-34} -> (失败/空)" -f $Label); return }
    $cats = @($r.content | Select-Object -First 40 | ForEach-Object { $_.category.title } | Sort-Object -Unique) -join '|'
    $ids = ($r.content | Select-Object -First 4 | ForEach-Object { $_.id }) -join ','
    Write-Host ("  {0,-34} total={1,-6} n={2,-3} cats=[{3}] ids={4}" -f $Label, $r.total, $r.content.Count, $cats, $ids)
}

# ------------------------------------------------------------------ 1. /categories
Write-Host ''
Write-Host '=== 1. /categories（顶层分类 + slug）===' -ForegroundColor Cyan
$categories = Invoke-JmApi '/categories?page=1'
if (-not $categories) { exit 1 }
$slugs = @()
foreach ($c in $categories.categories) {
    $slugs += [string]$c.slug
    Write-Host ("  id={0,-3} slug={1,-18} type={2,-7} total={3,-8} {4}" -f $c.id, $c.slug, $c.type, $c.total_albums, $c.name)
}

# ------------------------------------------------------------------ 2. 数字 id vs slug
Write-Host ''
Write-Host '=== 2. c=数字 id 会被忽略（对照组）===' -ForegroundColor Cyan
foreach ($c in @('0', '1', '2', '3')) {
    Show-FilterLine "c=$c" "page=1&order=&c=$c&o=mr"
}

Write-Host ''
Write-Host '=== 3. c=slug 才真的过滤 ===' -ForegroundColor Cyan
foreach ($s in ($slugs | Where-Object { $_ })) {
    Show-FilterLine "c=$s" ("page=1&order=&c={0}&o=mr" -f [uri]::EscapeDataString($s))
}

# ------------------------------------------------------------------ 4. 排序
Write-Host ''
Write-Host ("=== 4. 排序 o 与筛选正交（c={0}）===" -f $Slug) -ForegroundColor Cyan
foreach ($o in @('mr', 'mv', 'mv_m', 'mv_w', 'mv_t', 'md', 'mp')) {
    Show-FilterLine "o=$o" "page=1&order=&c=$Slug&o=$o"
}

# ------------------------------------------------------------------ 5. 子分类
Write-Host ''
Write-Host '=== 5. 子分类：必须拼 父slug_子slug（单独传子 slug / o= / filter= 都无效）===' -ForegroundColor Cyan
foreach ($q in @("c=$Slug&o=chinese", "c=$Slug&filter=chinese", "c=$Slug&sub_category=chinese", 'c=chinese')) {
    Show-FilterLine $q "page=1&order=&$q"
}
$parent = $categories.categories | Where-Object { $_.slug -eq $Slug } | Select-Object -First 1
if ($parent -and $parent.sub_categories) {
    foreach ($sub in ($parent.sub_categories | Select-Object -First 3)) {
        if (-not $sub.slug) { continue }
        $composed = "${Slug}_$($sub.slug)"
        Show-FilterLine "c=$composed" ("page=1&order=&c={0}&o=mr" -f [uri]::EscapeDataString($composed))
    }
}

Write-Host ''
Write-Host '结论：c 只认 slug；二级筛选用 父slug_子slug；数字 id 与子类单参数都会被服务端静默忽略。' -ForegroundColor Green
