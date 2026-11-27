package com.jmcomic.jm_comic
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * JMComic 原生能力：把 PDF 写进公共 Documents/JMComics/（MediaStore）。
 *
 * 对齐 JmScript/export/DocumentsPdfStore.kt：先 IS_PENDING=1 写入，再置 0 转正；
 * 同名文件自动追加 " (2)"、" (3)"。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "jm_comic/pdf_store"
    private val pdfReaderChannelName = "jm_comic/pdf_reader"
    private val appChannelName = "jm_comic/app"
    private val readerImageChannelName = "jm_comic/reader_image_store"
    private val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/JMComics/"

    /** 内置 PDF 阅读器：同一时刻只保留一份打开的 PdfRenderer（Dart 侧也只读一个文件）。 */
    private var pdfRenderer: PdfRenderer? = null
    private var pdfDescriptor: ParcelFileDescriptor? = null
    private var pdfUri: String? = null
    private val pdfExecutor = Executors.newSingleThreadExecutor()

    override fun onDestroy() {
        closePdf()
        pdfExecutor.shutdown()
        super.onDestroy()
    }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pdfReaderChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("bad_args", "缺少 uri", null)
                            return@setMethodCallHandler
                        }
                        pdfExecutor.execute {
                            try {
                                val info = openPdf(uri)
                                runOnUiThread { result.success(info) }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error("open_failed", error.message, null)
                                }
                            }
                        }
                    }
                    "render" -> {
                        val uri = call.argument<String>("uri")
                        val index = call.argument<Int>("index") ?: 0
                        val width = call.argument<Int>("width") ?: 1080
                        if (uri.isNullOrBlank()) {
                            result.error("bad_args", "缺少 uri", null)
                            return@setMethodCallHandler
                        }
                        pdfExecutor.execute {
                            try {
                                val bytes = renderPage(uri, index, width)
                                runOnUiThread { result.success(bytes) }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error("render_failed", error.message, null)
                                }
                            }
                        }
                    }
                    "close" -> {
                        pdfExecutor.execute {
                            closePdf()
                            runOnUiThread { result.success(true) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 自动更新的系统侧能力：读真实 versionName + 拉起浏览器 / 安装器。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionName" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            result.success(info.versionName ?: "")
                        } catch (error: Exception) {
                            result.error("version_failed", error.message, null)
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(openUrl(url))
                    }
                    else -> result.notImplemented()
                }
            }

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            readerImageChannelName,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "savePng") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name = call.argument<String>("name")
            val directory = call.argument<String>("directory")
            val bytes = call.argument<ByteArray>("bytes")
            if (name.isNullOrBlank() || directory.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
                result.error("bad_args", "缺少图片名称、保存目录或图片内容", null)
                return@setMethodCallHandler
            }
            try {
                result.success(saveReaderImage(name, directory, bytes))
            } catch (error: Exception) {
                result.error("save_failed", error.message, null)
            }
        }
    }

    /** 用系统默认应用打开链接（发布页 / 应用商店）。 */
    private fun openUrl(url: String): Boolean = try {
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setData(Uri.parse(url))
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
        true
    } catch (_: Exception) {
        false
    }

    /** 打开 PDF 并返回页数与首页尺寸（content:// 与 file:// 都支持）。 */
    private fun openPdf(uriString: String): Map<String, Any> {
        if (pdfUri == uriString && pdfRenderer != null) {
            val renderer = pdfRenderer!!
            return mapOf("pages" to renderer.pageCount)
        }
        closePdf()
        val descriptor = openDescriptor(uriString)
        val renderer = PdfRenderer(descriptor)
        pdfDescriptor = descriptor
        pdfRenderer = renderer
        pdfUri = uriString
        return mapOf("pages" to renderer.pageCount)
    }

    private fun openDescriptor(uriString: String): ParcelFileDescriptor {
        if (uriString.startsWith("content://")) {
            return contentResolver.openFileDescriptor(Uri.parse(uriString), "r")
                ?: throw IOException("无法打开 PDF（content uri 无权限）")
        }
        val path = if (uriString.startsWith("file://")) {
            Uri.parse(uriString).path ?: uriString
        } else {
            uriString
        }
        return ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    /** 渲染指定页为 PNG；按目标宽度等比缩放，白色底（PDF 透明背景在深色 UI 上会发黑）。 */
    private fun renderPage(uriString: String, index: Int, width: Int): ByteArray {
        if (pdfUri != uriString || pdfRenderer == null) openPdf(uriString)
        val renderer = pdfRenderer ?: throw IOException("PDF 未打开")
        if (index < 0 || index >= renderer.pageCount) {
            throw IOException("页码越界：$index/${renderer.pageCount}")
        }
        renderer.openPage(index).use { page ->
            val targetWidth = width.coerceIn(320, 2000)
            val ratio = page.height.toFloat() / page.width.toFloat()
            val targetHeight = (targetWidth * ratio).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)
            bitmap.recycle()
            return output.toByteArray()
        }
    }

    private fun closePdf() {
        try {
            pdfRenderer?.close()
        } catch (_: Exception) {
        }
        try {
            pdfDescriptor?.close()
        } catch (_: Exception) {
        }
        pdfRenderer = null
        pdfDescriptor = null
        pdfUri = null
    }

    private fun saveReaderImage(
        name: String,
        directory: String,
        bytes: ByteArray,
    ): Map<String, String> {
        val segments = directory.split('/')
        require(segments.none { it.isBlank() || it == "." || it == ".." }) { "图片保存目录无效" }
        val root = listOf(
            Environment.DIRECTORY_PICTURES,
            Environment.DIRECTORY_DCIM,
            Environment.DIRECTORY_DOWNLOADS,
            Environment.DIRECTORY_DOCUMENTS,
        ).firstOrNull { it.equals(segments.first(), ignoreCase = true) }
            ?: throw IOException("保存目录须以 Pictures、DCIM、Download 或 Documents 开头")
        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        val collection = when (root) {
            Environment.DIRECTORY_DOWNLOADS -> MediaStore.Downloads.getContentUri(volume)
            Environment.DIRECTORY_DOCUMENTS -> MediaStore.Files.getContentUri(volume)
            else -> MediaStore.Images.Media.getContentUri(volume)
        }
        val relativeDirectory = (listOf(root) + segments.drop(1)).joinToString("/", postfix = "/")
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDirectory)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(collection, values) ?: throw IOException("无法创建图片文件")
        try {
            resolver.openOutputStream(uri, "w")?.use { it.write(bytes) }
                ?: throw IOException("无法打开图片输出流")
            val ready = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            if (resolver.update(uri, ready, null, null) <= 0) {
                throw IOException("无法发布图片到公共存储")
            }
            // MediaStore 可能会调整目录或为同名文件追加编号，按实际位置提示。
            val columns = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.RELATIVE_PATH)
            return resolver.query(uri, columns, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) throw IOException("无法读取图片保存位置")
                val savedName = cursor.getString(0)
                val savedDirectory = cursor.getString(1)
                mapOf("name" to savedName, "path" to "${savedDirectory.trimEnd('/')}/$savedName")
            } ?: throw IOException("无法读取图片保存位置")
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
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
