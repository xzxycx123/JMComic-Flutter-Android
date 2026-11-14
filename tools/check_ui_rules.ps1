<#
.SYNOPSIS
    UI 规则守卫：禁止 emoji、禁止 Icons.* 图标字体、图标只允许 assets/icons/*.svg。

.DESCRIPTION
    扫描 lib/ 与 assets/，命中任一条即输出文件:行号 并以 exit 1 结束：
      1) emoji / 装饰符号字符（U+2190-21FF、U+2300-27BF、U+1F300-1FAFF、U+FE0F、U+2B00-2BFF）
      2) 代码里出现 Icons.<name>（Material 图标字体）
      3) 图标引用不是 .svg（如 Image.asset('assets/...png') 用于图标位）

    例外：注释里出现「Icons.」用于说明规则本身时，可用 `// ui-rules-ignore` 标记该行。

.EXAMPLE
    pwsh -File .\tools\check_ui_rules.ps1
    pwsh -File .\tools\check_ui_rules.ps1 -Root 'D:\data\product\JMComic'
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$emojiPatterns = @(
    '[\u2190-\u21FF\u2300-\u27BF\u2B00-\u2BFF\uFE0F]',   # 箭头 / 装饰符号 / 变体选择符
    '[\uD83C-\uD83E][\uDC00-\uDFFF]'                      # U+1F300-U+1FAFF（emoji 平面，按代理对匹配）
)
$iconsPattern = '\bIcons\.[A-Za-z_]'
$iconPngPattern = 'assets/icons/.*\.(png|jpg|jpeg|webp|gif)'

$scanRoots = @(
    (Join-Path $Root 'lib'),
    (Join-Path $Root 'assets')
)

$problems = New-Object System.Collections.Generic.List[string]

foreach ($scanRoot in $scanRoots) {
    if (-not (Test-Path -LiteralPath $scanRoot)) { continue }
    Get-ChildItem -LiteralPath $scanRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.dart', '.svg', '.yaml', '.html', '.md') } |
        ForEach-Object {
            $file = $_
            $lineNo = 0
            foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
                $lineNo++
                if ($line -cmatch 'ui-rules-ignore') { continue }

                foreach ($pattern in $emojiPatterns) {
                    if ($line -cmatch $pattern) {
                        $problems.Add(("{0}:{1}  emoji/符号字符 → 改用 assets/icons/*.svg" -f $file.FullName, $lineNo))
                        break
                    }
                }
                if ($file.Extension -eq '.dart' -and $line -match $iconsPattern) {
                    $problems.Add(("{0}:{1}  使用了 Icons.* 图标字体 → 改用 SvgIcon" -f $file.FullName, $lineNo))
                }
                if ($file.Extension -eq '.dart' -and $line -match $iconPngPattern) {
                    $problems.Add(("{0}:{1}  图标位引用了位图 → 只允许 .svg" -f $file.FullName, $lineNo))
                }
            }
        }
}

if ($problems.Count -eq 0) {
    Write-Host 'UI 规则检查通过：无 emoji、无 Icons.*、图标全为 SVG。' -ForegroundColor Green
    exit 0
}

Write-Host ("UI 规则检查失败，共 {0} 处：" -f $problems.Count) -ForegroundColor Red
$problems | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host '规则见 PLAN.md §7.0；图标清单见 assets\README.md。'
exit 1
