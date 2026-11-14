# 从 Wayback 归档 / 可达 API 主机抓取 JM 品牌图标资源
param(
    [string]$OutDir = 'D:\data\product\JMComic\img\_raw',
    [string]$Proxy = 'http://127.0.0.1:7890'
)
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
$hdrs = @{ 'User-Agent' = $ua; 'Accept' = 'image/avif,image/webp,image/png,image/*,*/*;q=0.8' }

# name, url  —— 全部为品牌 logo / favicon，无相册内容
$targets = @(
    @{ n = 'favicon_api_cdnutc.ico';       u = 'https://www.cdnutc.cc/favicon.ico' },
    @{ n = 'logo_18comic_2021_hi.png';     u = 'http://web.archive.org/web/20210303023428id_/https://18comic.vip/media/logo/new_logo.png' },
    @{ n = 'logo_18comic_2023_30208.png';  u = 'http://web.archive.org/web/20230310054152id_/https://18comic.vip/media/logo/new_logo.png?v=20230208' },
    @{ n = 'logo_18comic_2023_30521.png';  u = 'http://web.archive.org/web/20230523140956id_/https://18comic.vip/media/logo/new_logo.png?v=20230521' },
    @{ n = 'logo_jmcomic_2023_0928.png';   u = 'http://web.archive.org/web/20231207151223id_/https://jmcomic.me/media/logo/new_logo.png?v=20220928' },
    @{ n = 'logo_jmcomic_2022.png';        u = 'http://web.archive.org/web/20221120054349id_/https://jmcomic.me/media/logo/new_logo.png' },
    @{ n = 'favicon_18comic_2019.ico';     u = 'http://web.archive.org/web/20191115072644id_/https://18comic.vip/favicon.ico' }
)

$results = foreach ($t in $targets) {
    $dest = Join-Path $OutDir $t.n
    $ok = $false; $msg = ''
    for ($i = 0; $i -lt 4 -and -not $ok; $i++) {
        try {
            Invoke-WebRequest -Uri $t.u -Proxy $Proxy -Headers $hdrs -TimeoutSec 120 -OutFile $dest -ErrorAction Stop
            $ok = $true
        } catch {
            $msg = $_.Exception.Message.Split([Environment]::NewLine)[0]
            Start-Sleep -Seconds 2
        }
    }
    if ($ok) {
        $len = (Get-Item $dest).Length
        [pscustomobject]@{ name = $t.n; status = 'OK'; bytes = $len; note = '' }
    } else {
        [pscustomobject]@{ name = $t.n; status = 'FAIL'; bytes = 0; note = $msg }
    }
}
$results | Format-Table -AutoSize
