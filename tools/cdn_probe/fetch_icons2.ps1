# 第二批：品牌/加载/图标类资源（全部为站点 UI 资源，不含相册内容）
param(
    [string]$OutDir = 'D:\data\product\JMComic\img\_raw',
    [string]$Proxy = 'http://127.0.0.1:7890'
)
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
$hdrs = @{ 'User-Agent' = $ua; 'Accept' = 'image/avif,image/webp,image/png,image/*,*/*;q=0.8' }

$B = 'http://web.archive.org/web'
$targets = @(
    @{ n = 'loading_cat.gif';        u = "$B/20200504180053id_/https://18comic.vip/templates/frontend/airav/img/loading-cat.gif" },
    @{ n = 'logo_square_stray.png';  u = "$B/20210407172239id_/https://18comic.vip/templates/frontend/airav/img/stray/LOGO-1.png" },
    @{ n = 'logo_stray_title.png';   u = "$B/20211105181024id_/https://18comic.vip/templates/frontend/airav/img/stray/jm-title-1.png" },
    @{ n = 'logo_2019_small.png';    u = "$B/20191115072641id_/https://18comic.vip/templates/frontend/airav/img/new_logo.png?v=20191113" },
    @{ n = 'logo_new2_2020.png';     u = "$B/20200229112353id_/https://18comic.vip/templates/frontend/airav/img/new_logo_2.png?v=202000225" },
    @{ n = 'icon_jcoin.png';         u = "$B/20211003135906id_/https://18comic.vip/templates/frontend/airav/img/JCOIN-01.png" },
    @{ n = 'icon_potato.png';        u = "$B/20201213124930id_/https://18comic.vip/templates/frontend/airav/img/potato-icon.png?v=2020000806" },
    @{ n = 'icon_potato_big.png';    u = "$B/20230412112150id_/https://18comic.vip/templates/frontend/airav/img/phicon/potato.png?v=20230208" },
    @{ n = 'icon_new.png';           u = "$B/20210411131736id_/https://18comic.vip/templates/frontend/airav/img/phicon/new.png?v=2020000731" },
    @{ n = 'icon_hot.png';           u = "$B/20210411131750id_/https://18comic.vip/templates/frontend/airav/img/phicon/hot.png?v=2020000731" },
    @{ n = 'icon_week.png';          u = "$B/20210411131805id_/https://18comic.vip/templates/frontend/airav/img/phicon/week.png?v=2020000731" },
    @{ n = 'icon_day.png';           u = "$B/20210411131807id_/https://18comic.vip/templates/frontend/airav/img/phicon/day.png?v=2020000731" },
    @{ n = 'icon_theme.png';         u = "$B/20210411131808id_/https://18comic.vip/templates/frontend/airav/img/phicon/theme.png?v=2020000731" },
    @{ n = 'icon_bbs.png';           u = "$B/20201213124924id_/https://18comic.vip/templates/frontend/airav/img/phicon/bbs_icon.png?v=2020000806" },
    @{ n = 'sprite_social_media.png';u = "$B/20200503112325id_/https://18comic.vip/templates/frontend/airav/img/share/social_media_icons.png" },
    @{ n = 'qr_code.png';            u = "$B/20191115072641id_/https://18comic.vip/templates/frontend/airav/img/QR_CODE.png?v=120191113" },
    @{ n = 'icon_more.png';          u = "$B/20200317075517id_/https://18comic.vip/templates/frontend/airav/img/more.png" }
)

$results = foreach ($t in $targets) {
    $dest = Join-Path $OutDir $t.n
    $ok = $false; $msg = ''
    for ($i = 0; $i -lt 4 -and -not $ok; $i++) {
        try {
            Invoke-WebRequest -Uri $t.u -Proxy $Proxy -Headers $hdrs -TimeoutSec 150 -OutFile $dest -ErrorAction Stop
            $ok = $true
        } catch {
            $msg = $_.Exception.Message.Split([Environment]::NewLine)[0]
            Start-Sleep -Seconds 2
        }
    }
    if ($ok) { [pscustomobject]@{ name = $t.n; status = 'OK'; bytes = (Get-Item $dest).Length } }
    else { [pscustomobject]@{ name = $t.n; status = 'FAIL'; bytes = 0 } }
}
$results | Format-Table -AutoSize
