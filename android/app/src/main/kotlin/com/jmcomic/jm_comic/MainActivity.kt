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