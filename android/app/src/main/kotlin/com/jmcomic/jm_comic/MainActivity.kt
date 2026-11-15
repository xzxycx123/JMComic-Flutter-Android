package com.jmcomic.jm_comic
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