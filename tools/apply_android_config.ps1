<#
.SYNOPSIS
    flutter create 之后，一次性把 android/ 改成 JMComic 需要的配置（幂等）。

.DESCRIPTION
    做四件事：
      1) app/build.gradle.kts：minSdk 29 / compileSdk 36（Flutter 3.50 插件下限） / targetSdk 35；
      2) AndroidManifest.xml：补 INTERNET / POST_NOTIFICATIONS / FOREGROUND_SERVICE(_DATA_SYNC) /
         WAKE_LOCK，注册 flutter_foreground_task 的 ForegroundService，禁止明文流量；
      3) 重写 MainActivity.kt：注册 MethodChannel `jm_comic/pdf_store`，
         用 MediaStore 写公共 Documents/JMComics/（对齐 JmScript/export/DocumentsPdfStore.kt）；
      4) 打印改动摘要。

    前置：先跑过 `flutter create --org com.jmcomic --project-name jm_comic --platforms android,ios .`

.EXAMPLE
    pwsh -File .\tools\apply_android_config.ps1
    pwsh -File .\tools\apply_android_config.ps1 -Root 'D:\data\product\JMComic' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$MinSdk = 29,
    [int]$CompileSdk = 36,
    [int]$TargetSdk = 35
)

$ErrorActionPreference = 'Stop'

$androidDir = Join-Path $Root 'android'
$manifestPath = Join-Path $androidDir 'app\src\main\AndroidManifest.xml'
$gradlePath = Join-Path $androidDir 'app\build.gradle.kts'

if (-not (Test-Path -LiteralPath $androidDir)) {
    throw "找不到 android/：请先跑 flutter create --org com.jmcomic --project-name jm_comic --platforms android,ios ."
}

# ---------------------------------------------------------------- 1) build.gradle.kts
if (Test-Path -LiteralPath $gradlePath) {
    $gradle = Get-Content -LiteralPath $gradlePath -Raw -Encoding UTF8
    $original = $gradle
    # 模板初值是 flutter.compileSdkVersion；跑过一次后会变成显式数字，两种都要能覆盖。
    $gradle = $gradle -replace 'compileSdk\s*=\s*(?:flutter\.compileSdkVersion|\d+)', "compileSdk = $CompileSdk"
    $gradle = $gradle -replace 'minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)', "minSdk = $MinSdk"
    $gradle = $gradle -replace 'targetSdk\s*=\s*(?:flutter\.targetSdkVersion|\d+)', "targetSdk = $TargetSdk"
    if ($gradle -ne $original) {
        if ($PSCmdlet.ShouldProcess($gradlePath, 'patch sdk versions')) {
            Set-Content -LiteralPath $gradlePath -Value $gradle -Encoding UTF8 -NoNewline
            Write-Host "已更新 SDK 版本：minSdk=$MinSdk compileSdk=$CompileSdk targetSdk=$TargetSdk"
        }
    }
    else {
        Write-Host 'build.gradle.kts 已是显式 SDK 版本或被模板改动，请人工确认。' -ForegroundColor Yellow
    }
}
else {
    Write-Host "缺少 $gradlePath" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 2) AndroidManifest.xml
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "找不到 AndroidManifest.xml：$manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8

$permissionBlock = @'
    <!-- JMComic: 网络 / 通知 / 前台服务 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
'@

if ($manifest -notmatch 'android\.permission\.FOREGROUND_SERVICE_DATA_SYNC') {
    if ($PSCmdlet.ShouldProcess($manifestPath, 'add jm permissions')) {
        $manifest = $manifest -replace '(?m)^(\s*)<application', "$permissionBlock`n`$1<application"
        Write-Host '已补 INTERNET / POST_NOTIFICATIONS / FOREGROUND_SERVICE(_DATA_SYNC) / WAKE_LOCK'
    }
}

$serviceBlock = @'
        <!-- flutter_foreground_task：下载保活（服务名不可改） -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
'@

if ($manifest -notmatch 'flutter_foreground_task\.service\.ForegroundService') {
    if ($PSCmdlet.ShouldProcess($manifestPath, 'register foreground service')) {
        $manifest = $manifest -replace '(?m)^(\s*)</application>', "$serviceBlock`$1</application>"
        Write-Host '已注册 ForegroundService（dataSync）'
    }
}

if ($manifest -notmatch 'android:usesCleartextTraffic') {
    if ($PSCmdlet.ShouldProcess($manifestPath, 'disable cleartext traffic')) {
        $cleartextAttr = '$1' + "`n        android:usesCleartextTraffic=`"false`""
        $manifest = $manifest -replace '(<application\b)', $cleartextAttr
        Write-Host '已关闭明文流量（usesCleartextTraffic=false）'
    }
}

Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding UTF8 -NoNewline

# ---------------------------------------------------------------- 3) MainActivity.kt
$mainActivity = Get-ChildItem -LiteralPath (Join-Path $androidDir 'app\src\main') -Recurse -Filter 'MainActivity.kt' -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $mainActivity) {
    Write-Host '找不到 MainActivity.kt，跳过通道注册（请先 flutter create）。' -ForegroundColor Yellow
    return
}

$packageLine = (Get-Content -LiteralPath $mainActivity.FullName -Encoding UTF8 |
        Where-Object { $_ -match '^\s*package\s+' } |
        Select-Object -First 1)
if (-not $packageLine) {
    throw "无法从 $($mainActivity.FullName) 读取 package 声明"
}
$packageName = ($packageLine -replace '^\s*package\s+', '').Trim()

# 单引号 here-string：Kotlin 的 $ 模板原样保留
$kotlinBody = @'
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.IOException

/**
 * JMComic 原生能力：把 PDF 写进公共 Documents/JMComics/（MediaStore）。
 *
 * 对齐 JmScript/export/DocumentsPdfStore.kt：先 IS_PENDING=1 写入，再置 0 转正；
 * 同名文件自动追加 " (2)"、" (3)"。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "jm_comic/pdf_store"
    private val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/JMComics/"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePdf" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name.isNullOrBlank() || bytes == null) {
                            result.error("bad_args", "缺少 name / bytes", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(savePdf(name, bytes))
                        } catch (error: Exception) {
                            result.error("save_failed", error.message, null)
                        }
                    }
                    "openPdf" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(Uri.parse(uri), "application/pdf")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    "documentsDir" -> result.success(relativePath.trimEnd('/'))
                    else -> result.notImplemented()
                }
            }
    }

    private fun savePdf(requestedName: String, bytes: ByteArray): Map<String, Any?> {
        val displayName = nextAvailableName(requestedName)
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("在 Documents 中创建 PDF 失败")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                ByteArrayInputStream(bytes).use { input -> input.copyTo(output) }
            } ?: throw IOException("打开 PDF 输出流失败")
            val ready = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            val updated = contentResolver.update(uri, ready, null, null)
            if (updated <= 0) throw IOException("PDF 写入完成状态更新失败")
            return mapOf(
                "name" to displayName,
                "uri" to uri.toString(),
                "path" to null,
            )
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun nextAvailableName(requestedName: String): String {
        val existing = mutableSetOf<String>()
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        contentResolver.query(
            collection,
            projection,
            selection,
            arrayOf(relativePath, "${requestedName.substringBeforeLast('.')}%"),
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                cursor.getString(index)?.let { existing += it }
            }
        }
        if (requestedName !in existing) return requestedName
        val base = requestedName.removeSuffix(".pdf")
        var suffix = 2
        while ("$base ($suffix).pdf" in existing) suffix++
        return "$base ($suffix).pdf"
    }
}
'@

$kotlin = (@($packageLine, $kotlinBody) -join "`n")

if ($PSCmdlet.ShouldProcess($mainActivity.FullName, 'write MediaStore channel')) {
    Set-Content -LiteralPath $mainActivity.FullName -Value $kotlin -Encoding UTF8 -NoNewline
    Write-Host "已重写 MainActivity.kt（package $packageName，通道 jm_comic/pdf_store）"
}

Write-Host ''
Write-Host 'android 配置完成：flutter pub get 后再 flutter run / flutter build apk。' -ForegroundColor Green
