package __PACKAGE__

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coursedeep/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name") ?: "file"
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("bad_args", "No data to save", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 77)
                    result.error("permission", "Allow storage access, then tap download again.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val where = save(name, mime, bytes)
                        runOnUiThread { result.success(where) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("save_failed", e.message, null) }
                    }
                }.start()
            }
    }

    private fun save(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Could not create the file in Downloads")
            resolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Downloads/$name"
        }
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        var f = File(dir, name)
        var i = 1
        while (f.exists()) {
            val dot = name.lastIndexOf('.')
            f = File(dir, if (dot > 0) name.substring(0, dot) + " ($i)" + name.substring(dot) else "$name ($i)")
            i++
        }
        FileOutputStream(f).use { it.write(bytes) }
        MediaScannerConnection.scanFile(this, arrayOf(f.absolutePath), arrayOf(mime), null)
        return "Downloads/${f.name}"
    }
}
