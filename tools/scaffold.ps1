<#
.SYNOPSIS
    幂等创建 JMComic Flutter 客户端工程目录骨架。

.DESCRIPTION
    只建目录，不写业务文件；重复执行安全。
    Flutter SDK 与 flutter create 会在后续步骤补齐 android/、ios/ 与平台文件。

.EXAMPLE
    pwsh -File .\tools\scaffold.ps1
    pwsh -File .\tools\scaffold.ps1 -Root 'D:\data\product\JMComic'
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Root)) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Host "创建工程根目录: $Root"
}

$directories = @(
    # core：主题 / 路由 / 网络 / 图片算法 / 工具
    'lib\core\config'
    'lib\core\constants'
    'lib\core\theme'
    'lib\core\router'
    'lib\core\network'
    'lib\core\image'
    'lib\core\utils'

    # data：模型 / 协议源 / 本地存储 / 仓储
    'lib\data\models'
    'lib\data\sources'
    'lib\data\local'
    'lib\data\repositories'

    # features：三 tab + 详情 + 阅读器 + 下载引擎
    'lib\features\shell'
    'lib\features\home\widgets'
    'lib\features\album\widgets'
    'lib\features\reader'
    'lib\features\mine'
    'lib\features\download\widgets'
    'lib\features\download\engine'

    # 资源与测试
    'assets\images'
    'test\core'
    'test\data'
    'test\download'
    'test\features'
    'test\fixtures'
    'test\helpers'

    # 工具与文档
    'tools'
    'docs'
)

$created = 0
foreach ($relative in $directories) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        $created++
    }
}

Write-Host ("目录就绪: 共 {0} 项，新建 {1} 项" -f $directories.Count, $created)
