<#
.SYNOPSIS
    评论字段与搜索排序探测：确认 `spoiler` 真实取值，以及 `/search?o=` 各排序是否生效。
#>
[CmdletBinding()]
param(
    [string]$ApiHost = 'www.cdnutc.cc',
    [string[]]$Albums = @('350234', '1490663', '422378', '1490702'),
    [string]$Keyword = 'futa',
    [string]$Proxy = ''
)

$TokenSecret = '185Hcomic3PAPP7R'
$AppVersion  = '2.1.13'
$UserAgent   = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36'
$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

if (-not $Proxy) {
    $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) { $Proxy = 'http://' + (($settings.ProxyServer -split ';')[0].Trim()) }
}
$script:Proxy = if ($Proxy -and $Proxy -ne 'direct') { $Proxy } else { $null }

function Get-Md5Hex { param([string]$Text) $m=[System.Security.Cryptography.MD5]::Create(); try { (($m.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $m.Dispose() } }
function Get-UnixTimestamp { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() }

function ConvertFrom-JmPayload {
    param([string]$Base64, [string]$Timestamp)
    $key = [Text.Encoding]::ASCII.GetBytes((Get-Md5Hex ($Timestamp + $TokenSecret)))
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode='ECB'; $aes.Padding='PKCS7'; $aes.Key=$key
        $raw=[Convert]::FromBase64String(($Base64 -replace '\s',''))
        [Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($raw,0,$raw.Length))
    } finally { $aes.Dispose() }
}

function Invoke-Jm {
    param([string]$Path)
    $ts = Get-UnixTimestamp
    $p = @{
        Uri="https://$ApiHost$Path"; WebSession=$script:Session; TimeoutSec=30; UseBasicParsing=$true
        Headers=@{ token=(Get-Md5Hex ($ts+$TokenSecret)); tokenparam="$ts,$AppVersion"; 'User-Agent'=$UserAgent }
    }
    if ($script:Proxy) { $p['Proxy']=$script:Proxy }
    try { $resp = Invoke-WebRequest @p; $text=[Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) }
    catch { Write-Host ("  {0} → HTTP {1}" -f $Path, $_.Exception.Message) -ForegroundColor Yellow; return $null }
    $s=$text.IndexOf('{'); $e=$text.LastIndexOf('}')
    if ($s -lt 0) { Write-Host '  非 JSON'; return $null }
    $env = $text.Substring($s,$e-$s+1) | ConvertFrom-Json
    if ($env.code -ne 200) { Write-Host ("  code={0} msg={1}" -f $env.code, ($env.errorMsg ?? $env.msg)) -ForegroundColor Yellow; return $null }
    ConvertFrom-JmPayload -Base64 $env.data -Timestamp $ts | ConvertFrom-Json
}

Write-Host "=== 1. /forum 的 spoiler 真实取值 ===" -ForegroundColor Cyan
foreach ($album in $Albums) {
    $forum = Invoke-Jm "/forum?page=1&aid=$album&mode=manhua"
    if (-not $forum) { continue }
    Write-Host ("album {0} total={1} 条目={2}" -f $album, $forum.total, @($forum.list).Count)
    $first = @($forum.list) | Select-Object -First 1
    if ($first) {
        Write-Host ('  首条: ' + ($first | Select-Object CID,spoiler,likes,parent_CID,addtime,nickname | ConvertTo-Json -Compress))
        $spoilers = @($forum.list | ForEach-Object { $_.spoiler }) -join ','
        Write-Host ("  spoiler 取值集合: {0}" -f $spoilers)
    }
}

Write-Host ''
Write-Host "=== 2. /search?o= 是否真的改变排序（关键词 $Keyword）===" -ForegroundColor Cyan
foreach ($order in @('mr', 'mv', 'mv_m', 'mv_w', 'mv_t', 'md', 'mp')) {
    $page = Invoke-Jm ("/search?main_tag=0&search_query=$([uri]::EscapeDataString($Keyword))&page=1&o=$order&t=a")
    if ($page) {
        $ids = @($page.content | Select-Object -First 3 | ForEach-Object { $_.id }) -join ','
        Write-Host ("  o={0,-5} total={1,-6} 前三条={2}" -f $order, $page.total, $ids)
    }
}

Write-Host ''
Write-Host '说明：若各 o 的前三条不同，说明服务端排序生效；相同则只能前端排序。' -ForegroundColor DarkGray
