<#
.SYNOPSIS
    /forum（评论列表）与 /like（点赞）端点复核：打印真实结构与公开可读性。
#>
[CmdletBinding()]
param(
    [string]$ApiHost = 'www.cdnutc.cc',
    [string]$AlbumId = '1490702',
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
    param([string]$Path,[string]$Method='GET',[hashtable]$Form=$null)
    $ts = Get-UnixTimestamp
    $p = @{
        Uri="https://$ApiHost$Path"; Method=$Method; WebSession=$script:Session; TimeoutSec=30; UseBasicParsing=$true
        Headers=@{ token=(Get-Md5Hex ($ts+$TokenSecret)); tokenparam="$ts,$AppVersion"; 'User-Agent'=$UserAgent }
    }
    if ($script:Proxy) { $p['Proxy']=$script:Proxy }
    if ($Form) { $p['Body']=$Form }
    try { $resp = Invoke-WebRequest @p; $text=[Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) }
    catch { Write-Host ("  {0} {1} → HTTP {2}" -f $Method,$Path,$_.Exception.Message) -ForegroundColor Yellow; return }
    $s=$text.IndexOf('{'); $e=$text.LastIndexOf('}')
    if ($s -lt 0) { Write-Host "  → 非 JSON"; return }
    $env = $text.Substring($s,$e-$s+1) | ConvertFrom-Json
    Write-Host ("  envelope code={0}" -f $env.code)
    if ($env.code -ne 200) { Write-Host ("  msg={0}" -f ($env.errorMsg ?? $env.msg)) -ForegroundColor Yellow; return }
    $plain = ConvertFrom-JmPayload -Base64 $env.data -Timestamp $ts
    Write-Host ('  data 前 600 字: ' + $plain.Substring(0,[Math]::Min(600,$plain.Length)))
}

Write-Host "线路 $ApiHost，车号 $AlbumId" -ForegroundColor Green
Write-Host '--- GET /forum?page=1&aid=&mode=manhua ---'
Invoke-Jm "/forum?page=1&aid=$AlbumId&mode=manhua"
Write-Host '--- GET /forum?page=1&aid=（不带 mode） ---'
Invoke-Jm "/forum?page=1&aid=$AlbumId"
Write-Host '--- POST /like  id=（已点过时返回什么） ---'
Invoke-Jm '/like' -Method 'POST' -Form @{ id = $AlbumId }
Write-Host '--- POST /comment comment= aid= status=1（未登录） ---'
Invoke-Jm '/comment' -Method 'POST' -Form @{ comment='probe'; aid=$AlbumId; status='1' }
Write-Host '--- GET /album 的 liked / comment_total / likes ---'
Invoke-Jm "/album?id=$AlbumId"
