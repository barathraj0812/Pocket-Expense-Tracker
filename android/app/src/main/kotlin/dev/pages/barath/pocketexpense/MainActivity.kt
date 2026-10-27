package dev.pages.barath.pocketexpense

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingSave: PendingSave? = null
    private var pendingOpen: MethodChannel.Result? = null
    private lateinit var backupChannel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val savedPath = savedInstanceState?.getString(STATE_SAVE_PATH)
        val savedName = savedInstanceState?.getString(STATE_SAVE_NAME)
        if (!savedPath.isNullOrBlank() && !savedName.isNullOrBlank()) {
            // Keep the selected backup copy alive if Android recreates this
            // activity while its document picker is in the foreground.
            pendingSave = PendingSave(savedPath, savedName, null)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        pendingSave?.let { request ->
            outState.putString(STATE_SAVE_PATH, request.path)
            outState.putString(STATE_SAVE_NAME, request.fileName)
        }
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pocket_expense/backup_files",
        )
        backupChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveSqliteBackup" -> {
                    if (pendingSave != null || pendingOpen != null) {
                        result.error("busy", "Another file operation is active.", null)
                        return@setMethodCallHandler
                    }
                    val sourcePath = call.argument<String>("path")
                    val suggestedName = call.argument<String>("fileName")
                    if (sourcePath.isNullOrBlank() || suggestedName.isNullOrBlank()) {
                        result.error("invalid_arguments", "Backup file information is missing.", null)
                        return@setMethodCallHandler
                    }
                    pendingSave = PendingSave(sourcePath, suggestedName, result)
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/vnd.sqlite3"
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, REQUEST_CREATE_DOCUMENT)
                }
                "openSqliteBackup" -> {
                    if (pendingSave != null || pendingOpen != null) {
                        result.error("busy", "Another file operation is active.", null)
                        return@setMethodCallHandler
                    }
                    pendingOpen = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf("application/vnd.sqlite3", "application/octet-stream", "*/*"),
                        )
                    }
                    startActivityForResult(intent, REQUEST_OPEN_DOCUMENT)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("The FlutterActivity API uses the activity result callback here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CREATE_DOCUMENT) {
            completeSave(if (resultCode == RESULT_OK) data?.data else null)
        } else if (requestCode == REQUEST_OPEN_DOCUMENT) {
            completeOpen(if (resultCode == RESULT_OK) data?.data else null)
        }
    }

    private fun completeSave(uri: Uri?) {
        val request = pendingSave ?: return
        if (uri == null) {
            pendingSave = null
            request.result?.success(null)
            return
        }
        ioExecutor.execute {
            try {
                val source = File(request.path)
                if (!source.isFile || !source.canRead()) {
                    throw IllegalStateException("Backup file is unavailable.")
                }
                val copied = contentResolver.openOutputStream(uri, "w")?.use { output ->
                    FileInputStream(source).use { input -> copyAndCount(input, output) }
                } ?: throw IllegalStateException("The destination could not be opened.")
                if (copied != source.length()) {
                    throw IllegalStateException("The saved file could not be verified.")
                }
                runOnUiThread {
                    if (pendingSave === request) pendingSave = null
                    request.result?.success(
                        mapOf("fileName" to request.fileName, "bytes" to copied),
                    )
                }
            } catch (_: Exception) {
                runOnUiThread {
                    if (pendingSave === request) pendingSave = null
                    request.result?.error(
                        "save_failed",
                        "The backup could not be saved to that location.",
                        null,
                    )
                }
            }
        }
    }

    private fun completeOpen(uri: Uri?) {
        val result = pendingOpen ?: return
        if (uri == null) {
            pendingOpen = null
            result.success(null)
            return
        }
        val displayName = displayName(uri) ?: "PocketExpense_Backup.sqlite"
        ioExecutor.execute {
            val destination = File(cacheDir, "backup-import-${UUID.randomUUID()}.sqlite")
            try {
                val size = contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(destination).use { output -> copyAndCount(input, output, MAX_BACKUP_BYTES) }
                } ?: throw IllegalStateException("The selected file could not be read.")
                runOnUiThread {
                    if (pendingOpen === result) pendingOpen = null
                    result.success(mapOf("path" to destination.absolutePath, "fileName" to displayName, "bytes" to size))
                }
            } catch (_: Exception) {
                destination.delete()
                runOnUiThread {
                    if (pendingOpen === result) pendingOpen = null
                    result.error("open_failed", "The selected backup could not be read.", null)
                }
            }
        }
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    private fun copyAndCount(input: java.io.InputStream, output: java.io.OutputStream, limit: Long = MAX_BACKUP_BYTES): Long {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > limit) throw IllegalStateException("The selected file exceeds the supported size.")
            output.write(buffer, 0, read)
        }
        output.flush()
        return total
    }

    override fun onDestroy() {
        pendingSave = null
        pendingOpen = null
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private data class PendingSave(
        val path: String,
        val fileName: String,
        val result: MethodChannel.Result?,
    )

    companion object {
        private const val MAX_BACKUP_BYTES = 512L * 1024L * 1024L
        private const val REQUEST_CREATE_DOCUMENT = 801
        private const val REQUEST_OPEN_DOCUMENT = 802
        private const val STATE_SAVE_PATH = "pending_backup_save_path"
        private const val STATE_SAVE_NAME = "pending_backup_save_name"
    }
}
