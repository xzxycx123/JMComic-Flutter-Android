<#
.SYNOPSIS
    JM 线路发现 + 连通性实测，产出可打进 APK 的 `assets/data/jm_hosts.json` 与留档报告。

.DESCRIPTION
    发现源（全部失败也能跑，后面的源只是覆盖更全）：
      1) 官方域名服务：3 个 TOS 上的 newsvr-2025.txt（AES 解密，含 Setting / Server / jm3_Server 三张表）；
      2) 发布页：jmcomictt.site、jmcomicgo.org（后者 302 到前者），解析「國際通用 / 東南亞 / 內地 / 分流」四栏；
      3) 开源项目镜像：JMComic-Crawler-Python 的 jm_config.py（DOMAIN_API_LIST / DOMAIN_IMAGE_LIST）；
      4) 已有产物：assets/data/jm_hosts.json（增量复测，保留 firstSeen）。

    实测项（每台主机三件事，任一成功即算该主机在该用途上可用）：
      api   : GET /setting（带 token）+ AES 解密，必须拿到 jm3_version / img_host；
      image : GET /media/albums/<AlbumId>_3x4.jpg，必须 content-type=image/*；
      web   : GET /，必须 text/html（网页兜底抓取用）。

    输出：
      - assets/data/jm_hosts.json   App 冷启动的内置线路种子（含状态、延迟、时间戳）
      - docs/NETWORK_DOMAINS_<date>.md  人读报告（表格 + 本次判定理由）

.PARAMETER Proxy
    '' 自动读注册表系统代理（本机 FlClash 127.0.0.1:7890）；'direct' 强制直连；也可显式给 URL。

.PARAMETER AlbumId
    用于图床自检的车号（默认 1490702，实测有 19 张图）。

.PARAMETER Concurrency
    并发探测数（默认 6；线路多时调大，别超过 12 免得被 CDN 限速）。

.EXAMPLE
    pwsh -File .\tools\probe_hosts.ps1
    pwsh -File .\tools\probe_hosts.ps1 -Proxy direct -Concurrency 8
    pwsh -File .\tools\probe_hosts.ps1 -Proxy http://127.0.0.1:7890 -TimeoutSec 20
#>
[CmdletBinding()]
param(
    [string]$Proxy = '',
    [string]$AlbumId = '1490702',
    [int]$TimeoutSec = 15,
    [int]$Concurrency = 6,
    [string]$OutFile = '',
    [string]$ReportFile = '',
    [switch]$SkipProbe
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- 协议常量
$TokenSecret      = '185Hcomic3PAPP7R'
$DomainSecret     = 'diosfjckwpqpdfjkvnqQjsik'
$AppVersion       = '2.1.13'
$UserAgent        = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
$BrowserUa        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

$DomainServerUrls = @(
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt'
)
$PublicationUrls = @('https://jmcomictt.site/', 'https://jmcomicgo.org/')
$MirrorConfigUrls = @(
    'https://raw.githubusercontent.com/hect0x7/JMComic-Crawler-Python/master/src/jmcomic/jm_config.py'
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutFile)    { $OutFile = Join-Path $ProjectRoot 'assets\data\jm_hosts.json' }
if (-not $ReportFile) { $ReportFile = Join-Path $ProjectRoot ('docs\NETWORK_DOMAINS_' + (Get-Date -Format 'yyyy-MM-dd') + '.md') }

# ---------------------------------------------------------------- 代理
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
    } catch { }
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    return $null
}

$script:ProxyUrl = Resolve-ProxyUrl -Explicit $Proxy
if ($script:ProxyUrl) { Write-Host "网络路径：代理 $script:ProxyUrl" -ForegroundColor DarkGray }
else { Write-Host '网络路径：直连（无代理）' -ForegroundColor DarkGray }

# ---------------------------------------------------------------- 基础工具
function Get-Md5Hex {
    param([string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    [Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
}

function ConvertFrom-JmPayload {
    param([string]$Base64, [string]$Timestamp, [string]$Secret)
    $key = [Text.Encoding]::ASCII.GetBytes((Get-Md5Hex ($Timestamp + $Secret)))
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = 'ECB'
        $aes.Padding = 'PKCS7'
        $aes.Key = $key
        $clean = ($Base64 -replace '\s', '') -replace '\\/', '/'
        while ($clean.Length % 4 -ne 0) { $clean += '=' }
        $raw = [Convert]::FromBase64String($clean)
        [Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($raw, 0, $raw.Length))
    }
    finally { $aes.Dispose() }
}

function Invoke-HttpText {
    <# 发一次 GET，返回 @{ Ok; Status; Text; Ms; Error }，非 2xx 不抛异常。 #>
    param(
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$ProxyUrl = $script:ProxyUrl,
        [int]$Timeout = $script:TimeoutSec,
        [switch]$FollowRedirect
    )
    $params = @{
        Uri                = $Uri
        Headers            = $Headers
        TimeoutSec         = $Timeout
        SkipHttpErrorCheck = $true
        UseBasicParsing    = $true
    }
    if ($ProxyUrl) { $params['Proxy'] = $ProxyUrl }
    if (-not $FollowRedirect) { $params['MaximumRedirection'] = 0 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest @params
        $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        [pscustomobject]@{
            Ok = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
            Status = [int]$resp.StatusCode
            Text = $text
            Ms = [int]$sw.ElapsedMilliseconds
            Error = ''
        }
    }
    catch {
        [pscustomobject]@{
            Ok = $false
            Status = 0
            Text = ''
            Ms = [int]$sw.ElapsedMilliseconds
            Error = ($_.Exception.Message -split "`n")[0]
        }
    }
    finally { $sw.Stop() }
}

# ---------------------------------------------------------------- 发现源 1：官方域名服务
function Get-DomainServerHosts {
    $rows = @()
    foreach ($url in $DomainServerUrls) {
        $r = Invoke-HttpText -Uri $url -Headers @{ 'User-Agent' = $UserAgent } -Timeout 12
        if (-not $r.Ok -or [string]::IsNullOrWhiteSpace($r.Text)) {
            Write-Host ("  TOS 不可用 {0}：{1}" -f $url, ($(if ($r.Error) { $r.Error } else { "HTTP $($r.Status)" }))) -ForegroundColor Yellow
            continue
        }
        # 去掉开头的非 ASCII 字符（服务端会在文件头塞进一段中文水印）
        $clean = -join ($r.Text.ToCharArray() | Where-Object { [int]$_ -le 0x7f })
        $clean = $clean.Trim()
        try {
            $plain = ConvertFrom-JmPayload -Base64 $clean -Timestamp '' -Secret $DomainSecret
            $obj = $plain | ConvertFrom-Json
        }
        catch {
            Write-Host ("  TOS 解密失败 {0}：{1}" -f $url, $_.Exception.Message) -ForegroundColor Yellow
            continue
        }
        $ms = $r.Ms
        foreach ($hostName in @($obj.Setting)) {
            if ($hostName) { $rows += [pscustomobject]@{ Host = [string]$hostName; Label = ''; Source = 'tos:Setting'; Ms = $ms } }
        }
        foreach ($hostName in @($obj.Server)) {
            if ($hostName) { $rows += [pscustomobject]@{ Host = [string]$hostName; Label = ''; Source = 'tos:Server'; Ms = $ms } }
        }
        foreach ($pair in @($obj.jm3_Server)) {
            if ($pair -and $pair.Count -ge 1) {
                $rows += [pscustomobject]@{ Host = [string]$pair[0]; Label = [string]$pair[1]; Source = 'tos:jm3_Server'; Ms = $ms }
            }
        }
    }
    $rows
}

# ---------------------------------------------------------------- 发现源 2：发布页
function Get-PublicationHosts {
    $rows = @()
    $seen = @{}
    foreach ($url in $PublicationUrls) {
        $r = Invoke-HttpText -Uri $url -Headers @{ 'User-Agent' = $BrowserUa; 'Accept' = 'text/html' } -Timeout 20 -FollowRedirect
        if (-not $r.Ok -or $r.Text -notmatch '<html|<!DOCTYPE|<main') {
            Write-Host ("  发布页不可用 {0}：{1}" -f $url, ($(if ($r.Error) { $r.Error } else { "HTTP $($r.Status)" }))) -ForegroundColor Yellow
            continue
        }
        $html = $r.Text
        $sections = [ordered]@{
            international     = '國際通用'
            southeast_asia    = '東南亞'
            china             = '內地'
            first_line        = '分流1'
            second_line       = '分流2'
        }
        foreach ($key in $sections.Keys) {
            # <div class="china"><span>comic18j-susu.com</span></div>
            $pattern = '<div class="{0}"[^>]*>(.*?)</div>' -f [regex]::Escape($key)
            $block = [regex]::Match($html, $pattern, 'Singleline')
            if (-not $block.Success) { continue }
            foreach ($span in [regex]::Matches($block.Groups[1].Value, '<span>(.*?)</span>', 'Singleline')) {
                $raw = ($span.Groups[1].Value -replace '<[^>]+>', '').Trim()
                $hostName = ($raw -replace '^\s*https?://', '' -replace '/.*$', '').Trim()
                if ($hostName -notmatch '^[a-z0-9][a-z0-9\.\-]+\.[a-z]{2,}$') { continue }
                if ($seen.ContainsKey($hostName)) { continue }
                $seen[$hostName] = $true
                $rows += [pscustomobject]@{
                    Host   = $hostName
                    Label  = $sections[$key]
                    Source = "pub:$($url.TrimEnd('/'))"
                    Ms     = $r.Ms
                }
            }
        }
        Write-Host ("  发布页 {0}：{1} 个域名" -f $url, $rows.Count) -ForegroundColor DarkGray
    }
    $rows
}

# ---------------------------------------------------------------- 发现源 3：GitHub 镜像项目
function Get-MirrorConfigHosts {
    $rows = @()
    foreach ($url in $MirrorConfigUrls) {
        $r = Invoke-HttpText -Uri $url -Headers @{ 'User-Agent' = $BrowserUa } -Timeout 20 -FollowRedirect
        if (-not $r.Ok) {
            Write-Host ("  镜像配置不可用 {0}：{1}" -f $url, ($(if ($r.Error) { $r.Error } else { "HTTP $($r.Status)" }))) -ForegroundColor Yellow
            continue
        }
        $blocks = @(
            @{ Key = 'DOMAIN_API_LIST'; Kind = 'api' },
            @{ Key = 'DOMAIN_IMAGE_LIST'; Kind = 'image' }
        )
        foreach ($block in $blocks) {
            $pattern = 'DOMAIN_' + ($(if ($block.Kind -eq 'api') { 'API' } else { 'IMAGE' })) + '_LIST\s*=\s*shuffled\(''(.+?)''\)'
            $match = [regex]::Match($r.Text, $pattern, 'Singleline')
            if (-not $match.Success) { continue }
            foreach ($line in ($match.Groups[1].Value -split "`n")) {
                $hostName = $line.Trim()
                if ($hostName -notmatch '^[a-z0-9][a-z0-9\.\-]+\.[a-z]{2,}$') { continue }
                $rows += [pscustomobject]@{
                    Host   = $hostName
                    Label  = ''
                    Source = "github:$($block.Kind)List"
                    Ms     = $r.Ms
                    Kind   = $block.Kind
                }
            }
        }
        Write-Host ("  镜像 {0}：{1} 条" -f $url, $rows.Count) -ForegroundColor DarkGray
    }
    $rows
}

# ---------------------------------------------------------------- 探测
function Invoke-Probes {
    param(
        [object[]]$Hosts,
        [string]$ProxyUrl,
        [string]$Album,
        [int]$Timeout,
        [int]$Throttle
    )
    $results = $Hosts | ForEach-Object -ThrottleLimit $Throttle -Parallel {
        $hostName = $_
        $tokenSecret = '185Hcomic3PAPP7R'
        $ua = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
        $browserUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
        $appVersion = '2.1.13'
        $probeProxy = $using:ProxyUrl
        $album = $using:Album
        $timeout = $using:Timeout

        function ConvertFrom-Payload([string]$b64, [string]$ts) {
            $keyHex = [Convert]::ToHexString([Security.Cryptography.MD5]::HashData(
                [Text.Encoding]::UTF8.GetBytes($ts + $tokenSecret))).ToLowerInvariant()
            $aes = [Security.Cryptography.Aes]::Create()
            try {
                $aes.Mode = 'ECB'; $aes.Padding = 'PKCS7'
                $aes.Key = [Text.Encoding]::ASCII.GetBytes($keyHex)
                $clean = ($b64 -replace '\s', '') -replace '\\/', '/'
                while ($clean.Length % 4 -ne 0) { $clean += '=' }
                $raw = [Convert]::FromBase64String($clean)
                [Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($raw, 0, $raw.Length))
            }
            finally { $aes.Dispose() }
        }

        $proxyParams = @{}
        if ($probeProxy) { $proxyParams['Proxy'] = $probeProxy }
        $entry = [ordered]@{
            host = $hostName
            api = [ordered]@{ status = 'skipped'; httpStatus = 0; latencyMs = 0; detail = '' }
            image = [ordered]@{ status = 'skipped'; httpStatus = 0; latencyMs = 0; detail = '' }
            web = [ordered]@{ status = 'skipped'; httpStatus = 0; latencyMs = 0; detail = '' }
            imgHost = ''
            appVersion = ''
        }

        # api
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        $token = [Convert]::ToHexString([Security.Cryptography.MD5]::HashData(
            [Text.Encoding]::UTF8.GetBytes($ts + $tokenSecret))).ToLowerInvariant()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri "https://$hostName/setting" -TimeoutSec $timeout -SkipHttpErrorCheck -UseBasicParsing `
                -Headers @{ token = $token; tokenparam = "$ts,$appVersion"; 'User-Agent' = $ua } @proxyParams
            $entry.api.httpStatus = [int]$resp.StatusCode
            $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
            if ($resp.StatusCode -ne 200) { $entry.api.status = "http_$($resp.StatusCode)" }
            elseif ($text -notmatch '"code"\s*:\s*200') { $entry.api.status = 'code_not_200' }
            else {
                $envelope = $text.Substring($text.IndexOf('{'), $text.LastIndexOf('}') - $text.IndexOf('{') + 1) | ConvertFrom-Json
                $setting = (ConvertFrom-Payload $envelope.data $ts) | ConvertFrom-Json
                $entry.imgHost = [string]$setting.img_host
                $entry.appVersion = [string]$setting.jm3_version
                if ($entry.appVersion -or $entry.imgHost) { $entry.api.status = 'ok' } else { $entry.api.status = 'payload_unexpected' }
            }
        }
        catch {
            $message = ($_.Exception.Message -split "`n")[0]
            $entry.api.status = if ($message -match 'SSL|TLS|handshake|certificate') { 'tls_error' }
                                elseif ($message -match 'timed out|timeout|已过期') { 'timeout' }
                                else { 'error' }
            $entry.api.detail = $message
        }
        finally { $sw.Stop(); $entry.api.latencyMs = [int]$sw.ElapsedMilliseconds }

        # image
        $sw.Restart()
        try {
            $resp = Invoke-WebRequest -Uri "https://$hostName/media/albums/$($album)_3x4.jpg" -TimeoutSec $timeout -SkipHttpErrorCheck -UseBasicParsing `
                -Headers @{ 'User-Agent' = $ua; 'Accept' = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'; 'X-Requested-With' = 'com.JMComic3.app' } @proxyParams
            $entry.image.httpStatus = [int]$resp.StatusCode
            $contentType = ($resp.Headers['Content-Type'] -join ',')
            if ($resp.StatusCode -eq 200 -and $contentType -match 'image/') {
                $entry.image.status = 'ok'; $entry.image.detail = "$([int]($resp.RawContentStream.Length / 1024))KB"
            }
            else { $entry.image.status = "http_$($resp.StatusCode)"; $entry.image.detail = $contentType }
        }
        catch {
            $message = ($_.Exception.Message -split "`n")[0]
            $entry.image.status = if ($message -match 'SSL|TLS|handshake') { 'tls_error' }
                                  elseif ($message -match 'timed out|timeout') { 'timeout' }
                                  else { 'error' }
            $entry.image.detail = $message
        }
        finally { $sw.Stop(); $entry.image.latencyMs = [int]$sw.ElapsedMilliseconds }

        # web
        $sw.Restart()
        try {
            $resp = Invoke-WebRequest -Uri "https://$hostName/" -TimeoutSec $timeout -SkipHttpErrorCheck -UseBasicParsing -MaximumRedirection 2 `
                -Headers @{ 'User-Agent' = $browserUa; 'Accept' = 'text/html,application/xhtml+xml'; 'Accept-Language' = 'zh-CN,zh;q=0.9' } @proxyParams
            $entry.web.httpStatus = [int]$resp.StatusCode
            $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
            if ($resp.StatusCode -eq 200 -and $text -match '<html|<!DOCTYPE') { $entry.web.status = 'ok' }
            elseif ($text -match 'Just a moment|cf-chl|challenge-platform') { $entry.web.status = 'cloudflare_challenge' }
            else { $entry.web.status = "http_$($resp.StatusCode)" }
        }
        catch {
            $message = ($_.Exception.Message -split "`n")[0]
            $entry.web.status = if ($message -match 'SSL|TLS|handshake') { 'tls_error' }
                                elseif ($message -match 'timed out|timeout') { 'timeout' }
                                else { 'error' }
            $entry.web.detail = $message
        }
        finally { $sw.Stop(); $entry.web.latencyMs = [int]$sw.ElapsedMilliseconds }

        [pscustomobject]$entry
    }
    return @($results)
}

# ---------------------------------------------------------------- 合并 + 分类
function Get-SeedEntries {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return @() }
    $list = @()
    foreach ($group in @('api', 'image', 'web')) {
        foreach ($item in @($json.$group)) {
            if (-not $item -or -not $item.host) { continue }
            $list += [pscustomobject]@{
                Host   = [string]$item.host
                Group  = $group
                Label  = [string]$item.label
                Source = 'seed'
                First  = [string]$item.firstSeen
            }
        }
    }
    $list
}

$domesticKeywords = @('comic18j', 'susu', 'nico', 'neo')

function Test-Domestic {
    param([string]$HostName, [string]$Label, [string]$Group)
    if ($Group -eq 'api' -and $HostName -match '^www\.cdn') { return $false }
    if ($HostName -match 'comic18j') { return $true }
    if ($Label -match '內地|内地|china') { return $true }
    return $false
}

# ---------------------------------------------------------------- 主流程
$all = [ordered]@{}
function Add-Candidate {
    param([string]$HostName, [string]$Group, [string]$Label, [string]$Source)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $key = "$Group|$HostName"
    if (-not $all.Contains($key)) {
        $all[$key] = [pscustomobject]@{
            host = $HostName
            group = $Group
            labels = New-Object System.Collections.Generic.List[string]
            sources = New-Object System.Collections.Generic.List[string]
            firstSeen = (Get-Date).ToString('yyyy-MM-dd')
        }
    }
    if ($Label -and -not $all[$key].labels.Contains($Label)) { $all[$key].labels.Add($Label) }
    if ($Source -and -not $all[$key].sources.Contains($Source)) { $all[$key].sources.Add($Source) }
}

Write-Host ''
Write-Host '=== 1/4 域名服务（TOS）' -ForegroundColor Cyan
$tosRows = @()
try { $tosRows = Get-DomainServerHosts } catch { Write-Host "  TOS 整体失败：$($_.Exception.Message)" -ForegroundColor Yellow }
foreach ($row in $tosRows) { Add-Candidate -HostName $row.Host -Group 'api' -Label $row.Label -Source $row.Source }
Write-Host ("  → {0} 条 API 候选" -f $tosRows.Count) -ForegroundColor DarkGray

Write-Host '=== 2/4 发布页（国内域名来源）' -ForegroundColor Cyan
$pubRows = @()
try { $pubRows = Get-PublicationHosts } catch { Write-Host "  发布页整体失败：$($_.Exception.Message)" -ForegroundColor Yellow }
foreach ($row in $pubRows) {
    $group = if ($row.Host -match 'comic18j') { 'web' } else { 'web' }
    Add-Candidate -HostName $row.Host -Group $group -Label $row.Label -Source $row.Source
}

Write-Host '=== 3/4 开源镜像配置' -ForegroundColor Cyan
$mirrorRows = @()
try { $mirrorRows = Get-MirrorConfigHosts } catch { Write-Host "  镜像整体失败：$($_.Exception.Message)" -ForegroundColor Yellow }
foreach ($row in $mirrorRows) {
    $group = if ($row.Kind -eq 'image') { 'image' } else { 'api' }
    Add-Candidate -HostName $row.Host -Group $group -Label $row.Label -Source $row.Source
}

Write-Host '=== 4/4 已有产物增量' -ForegroundColor Cyan
foreach ($entry in Get-SeedEntries -Path $OutFile) {
    Add-Candidate -HostName $entry.Host -Group $entry.Group -Label $entry.Label -Source $entry.Source
}

# 兜底：内置常量里的老线路也纳入（保证第一次跑不会漏）
foreach ($hostName in @('www.cdnbtd.cc', 'www.cdnutc.cc', 'www.cdngwc.net', 'www.cdngwc.club', 'www.cdnutc.me', 'www.cdnhjk.net', 'www.cdngwc.cc')) {
    Add-Candidate -HostName $hostName -Group 'api' -Label '' -Source 'builtin'
}
foreach ($hostName in @('cdn-msp.jmapiproxy1.cc', 'cdn-msp.jmapiproxy2.cc', 'cdn-msp2.jmapiproxy2.cc', 'cdn-msp3.jmapiproxy2.cc', 'cdn-msp.jmapinodeudzn.net', 'cdn-msp3.jmapinodeudzn.net')) {
    Add-Candidate -HostName $hostName -Group 'image' -Label '' -Source 'builtin'
}

$candidates = @($all.Values)
Write-Host ("候选合计：{0} 台（api={1} image={2} web={3}）" -f $candidates.Count,
    @($candidates | Where-Object { $_.group -eq 'api' }).Count,
    @($candidates | Where-Object { $_.group -eq 'image' }).Count,
    @($candidates | Where-Object { $_.group -eq 'web' }).Count) -ForegroundColor Green

$probeMap = @{}
if (-not $SkipProbe) {
    Write-Host ''
    $hostsToProbe = @($candidates | Select-Object -ExpandProperty host -Unique)
    Write-Host ("开始实测 {0} 台主机（并发 {1}，单台超时 {2}s）..." -f $hostsToProbe.Count, $Concurrency, $TimeoutSec) -ForegroundColor Cyan
    $results = Invoke-Probes -Hosts $hostsToProbe -ProxyUrl $script:ProxyUrl -Album $AlbumId -Timeout $TimeoutSec -Throttle $Concurrency
    foreach ($item in $results) { $probeMap[$item.host] = $item }

    # /setting 下发的 img_host 当天就会变（cdn-msp / cdn-msp2 / cdn-msp12 / tencent 前缀轮换），
    # 必须反向收编成图床候选再测一次，否则内置表永远是过期的。
    $extra = @()
    foreach ($item in $results) {
        if (-not $item.imgHost) { continue }
        $normalized = ([string]$item.imgHost) -replace '^\s*https?://', '' -replace '/.*$', ''
        if ($normalized -notmatch '^[a-z0-9][a-z0-9\.\-]+\.[a-z]{2,}$') { continue }
        if ($all.Contains("image|$normalized")) { continue }
        Add-Candidate -HostName $normalized -Group 'image' -Label 'setting:img_host' -Source 'setting:img_host'
        $extra += $normalized
    }
    $extra = @($extra | Select-Object -Unique)
    if ($extra.Count -gt 0) {
        Write-Host ("补充实测 /setting.img_host：{0} 台" -f $extra.Count) -ForegroundColor DarkGray
        foreach ($item in (Invoke-Probes -Hosts $extra -ProxyUrl $script:ProxyUrl -Album $AlbumId -Timeout $TimeoutSec -Throttle $Concurrency)) {
            $probeMap[$item.host] = $item
        }
    }

    $candidates = @($all.Values)
    $okApi = @($results | Where-Object { $_.api.status -eq 'ok' }).Count
    $okImg = @($probeMap.Values | Where-Object { $_.image.status -eq 'ok' }).Count
    Write-Host ("实测完成：API 可用 {0} 台 / 图床可用 {1} 台" -f $okApi, $okImg) -ForegroundColor Green
}

# 网页域名只要 /media 能出图，也当图床用（国内域名 comic18j-* 的价值就在这里）
foreach ($candidate in @($all.Values)) {
    if ($candidate.group -eq 'image') { continue }
    $probe = $probeMap[$candidate.host]
    if ($probe -and $probe.image.status -eq 'ok') {
        Add-Candidate -HostName $candidate.host -Group 'image' -Label ($candidate.labels -join ' / ') -Source ('media-from:' + $candidate.group)
    }
}
$candidates = @($all.Values)

# ---------------------------------------------------------------- 汇总输出
$generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$output = [ordered]@{
    schema = 2
    generatedAt = $generatedAt
    network = if ($script:ProxyUrl) { "proxy:$script:ProxyUrl" } else { 'direct' }
    sampleAlbum = $AlbumId
    api = @()
    image = @()
    web = @()
}

function Get-Status {
    param($Probe, [string]$Group)
    if (-not $Probe) { return 'unknown' }
    return [string]$Probe.$Group.status
}

foreach ($candidate in ($candidates | Sort-Object group, host)) {
    $probe = $probeMap[$candidate.host]
    $status = Get-Status -Probe $probe -Group $candidate.group
    $row = [ordered]@{
        host = $candidate.host
        label = ($candidate.labels -join ' / ')
        status = $status
        latencyMs = if ($probe) { [int]$probe.($candidate.group).latencyMs } else { 0 }
        httpStatus = if ($probe) { [int]$probe.($candidate.group).httpStatus } else { 0 }
        domestic = (Test-Domestic -HostName $candidate.host -Label ($candidate.labels -join ' ') -Group $candidate.group)
        sources = @($candidate.sources)
        firstSeen = $candidate.firstSeen
        checkedAt = $generatedAt
    }
    if ($probe -and $probe.imgHost) { $row['settingImgHost'] = $probe.imgHost }
    if ($probe -and $probe.appVersion) { $row['appVersion'] = $probe.appVersion }
    if ($probe -and $probe.($candidate.group).detail) { $row['detail'] = [string]$probe.($candidate.group).detail }
    $output[$candidate.group] += [pscustomobject]$row
}

# api 组：可用的按延迟升序，失败的按名字留在尾部
$output.api = @($output.api | Sort-Object @{ Expression = { if ($_.status -eq 'ok') { 0 } else { 1 } } }, latencyMs, host)
$output.image = @($output.image | Sort-Object @{ Expression = { if ($_.status -eq 'ok') { 0 } else { 1 } } }, latencyMs, host)
$output.web = @($output.web | Sort-Object @{ Expression = { if ($_.status -eq 'ok') { 0 } else { 1 } } }, latencyMs, host)

$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$json = $output | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($OutFile, $json, [Text.UTF8Encoding]::new($false))
Write-Host ("已写入 {0}" -f $OutFile) -ForegroundColor Green

# ---------------------------------------------------------------- 报告
$lines = @()
$lines += '# JM 线路实测留档'
$lines += ''
$lines += "- 生成时间：$generatedAt"
$lines += "- 网络路径：$($output.network)"
$lines += "- 采样车号：$AlbumId（封面 `/media/albums/${AlbumId}_3x4.jpg`）"
$lines += "- 判定：api = `/setting` + token + AES 解密拿得到 `jm3_version`/`img_host`；image = 封面 200 且 `content-type: image/*`；web = 首页 200 HTML"
$lines += ''
function Format-Table2 {
    param([object[]]$Rows, [string]$Title)
    $out = @('', "## $Title", '', '| 主机 | 标签 | 状态 | 延迟 | 国内 | 来源 |', '|---|---|---|---|---|---|')
    foreach ($row in $Rows) {
        $out += ("| `{0}` | {1} | {2} | {3}ms | {4} | {5} |" -f $row.host, $row.label, $row.status, $row.latencyMs,
            $(if ($row.domestic) { '是' } else { '' }), (($row.sources) -join ', '))
    }
    $out
}
$lines += Format-Table2 -Rows @($output.api) -Title 'API 线路（APP 接口）'
$lines += Format-Table2 -Rows @($output.image) -Title '图床线路（/media）'
$lines += Format-Table2 -Rows @($output.web) -Title '网页域名（HTML 兜底 / 发布页）'
$lines += ''
$lines += '## 结论'
$lines += ''
$apiOk = @($output.api | Where-Object { $_.status -eq 'ok' })
$imgOk = @($output.image | Where-Object { $_.status -eq 'ok' })
$webOk = @($output.web | Where-Object { $_.status -eq 'ok' })
$lines += "- 可用 API：$(if ($apiOk) { ($apiOk | ForEach-Object { $_.host }) -join '、' } else { '本次全部失败（网络路径问题优先排查）' })"
$lines += "- 可用图床：$(if ($imgOk) { ($imgOk | ForEach-Object { $_.host }) -join '、' } else { '无' })"
$lines += "- 可用网页：$(if ($webOk) { ($webOk | ForEach-Object { $_.host }) -join '、' } else { '无（可能被 Cloudflare 挑战拦住）' })"
$lines += ''
$lines += '> 本文件由 `tools\probe_hosts.ps1` 生成，重新跑一遍即可刷新；`assets\data\jm_hosts.json` 会被打进 APK 作为内置种子。'
[IO.File]::WriteAllText($ReportFile, ($lines -join "`n"), [Text.UTF8Encoding]::new($false))
Write-Host ("已写入 {0}" -f $ReportFile) -ForegroundColor Green

Write-Host ''
Write-Host '=== 结果速览 ===' -ForegroundColor Cyan
$output.api | Select-Object host, status, latencyMs, imgHost, appVersion | Format-Table -AutoSize | Out-String | Write-Host
$output.web | Select-Object host, status, latencyMs | Format-Table -AutoSize | Out-String | Write-Host
