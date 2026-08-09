package cn.openp2p

import android.content.Context
import android.util.Log
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object Logger {
    private const val LOG_TAG = "OpenP2PLogger"
    private const val MAX_VIEW_BYTES = 1024 * 1024
    private const val MAX_EXPORT_BYTES = 4 * 1024 * 1024
    private var logDir: File? = null
    private var appLogFile: File? = null
    private var bufferedWriter: BufferedWriter? = null
    private val sessionOffsets = mutableMapOf<String, Long>()

    @Synchronized
    fun init(directory: File, logFileName: String = "app.log") {
        if (!directory.exists()) directory.mkdirs()
        val target = File(directory, logFileName)
        if (appLogFile?.absolutePath == target.absolutePath && bufferedWriter != null) return

        close()
        logDir = directory
        appLogFile = target
        sessionOffsets.clear()
        sessionFiles().forEach { sessionOffsets[it.name] = it.length() }
        try {
            bufferedWriter = BufferedWriter(FileWriter(target, true))
        } catch (e: IOException) {
            Log.e(LOG_TAG, "Failed to initialize BufferedWriter: ${e.message}")
        }
    }

    @Synchronized
    fun log(level: String, tag: String, message: String, throwable: Throwable? = null) {
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        val logMessage = "$timestamp $level $tag: $message"
        when (level) {
            "ERROR" -> Log.e(tag, message, throwable)
            "WARN" -> Log.w(tag, message, throwable)
            "INFO" -> Log.i(tag, message)
            "DEBUG" -> Log.d(tag, message)
            "VERBOSE" -> Log.v(tag, message)
        }
        try {
            bufferedWriter?.apply {
                write(logMessage)
                newLine()
                throwable?.let {
                    write(Log.getStackTraceString(it))
                    newLine()
                }
                flush()
            }
        } catch (e: IOException) {
            Log.e(LOG_TAG, "Failed to write log to file: ${e.message}")
        }
    }

    @Synchronized
    fun close() {
        try {
            bufferedWriter?.close()
        } catch (e: IOException) {
            Log.e(LOG_TAG, "Failed to close BufferedWriter: ${e.message}")
        } finally {
            bufferedWriter = null
        }
    }

    fun e(tag: String, message: String, throwable: Throwable? = null) = log("ERROR", tag, message, throwable)
    fun w(tag: String, message: String, throwable: Throwable? = null) = log("WARN", tag, message, throwable)
    fun i(tag: String, message: String) = log("INFO", tag, message)
    fun d(tag: String, message: String) = log("DEBUG", tag, message)
    fun v(tag: String, message: String) = log("VERBOSE", tag, message)

    @Synchronized
    fun currentSession(): String = buildString {
        sessionFiles().forEach { file ->
            val content = readTail(file, sessionOffsets[file.name] ?: 0, MAX_VIEW_BYTES)
            if (content.isNotBlank()) {
                if (isNotEmpty()) appendLine()
                appendLine("===== ${file.name} =====")
                append(content)
            }
        }
    }

    @Synchronized
    fun createExportFile(context: Context): File {
        val exportDir = File(context.cacheDir, "log_exports").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val output = File(exportDir, "openp2p-diagnostics-$stamp.txt")
        output.bufferedWriter().use { writer ->
            writer.appendLine("OpenP2P Android diagnostics")
            writer.appendLine("Generated: ${Date()}")
            exportFiles().forEach { file ->
                if (file.exists() && file.length() > 0) {
                    writer.appendLine()
                    writer.appendLine("===== ${file.name} =====")
                    writer.append(maskSensitive(readTail(file, 0, MAX_EXPORT_BYTES)))
                }
            }
        }
        return output
    }

    private fun sessionFiles(): List<File> {
        val directory = logDir ?: return emptyList()
        val app = appLogFile ?: File(directory, "app.log")
        return listOf(app, File(directory, "openp2p.log"))
    }

    private fun exportFiles(): List<File> {
        val directory = logDir ?: return emptyList()
        return listOf(
            File(directory, "app.log"),
            File(directory, "openp2p.log"),
            File(directory, "openp2p.log.0")
        )
    }

    private fun readTail(file: File, requestedOffset: Long, maxBytes: Int): String {
        if (!file.exists()) return ""
        return try {
            val length = file.length()
            val sessionOffset = requestedOffset.coerceAtMost(length)
            val start = maxOf(sessionOffset, length - maxBytes)
            file.inputStream().use { input ->
                var remaining = start
                while (remaining > 0) {
                    val skipped = input.skip(remaining)
                    if (skipped <= 0) break
                    remaining -= skipped
                }
                input.bufferedReader().readText()
            }
        } catch (_: IOException) {
            ""
        }
    }

    private fun maskSensitive(value: String): String = value
        .replace(Regex("(?i)(token|password|authorization)(\\s*[:=]\\s*)[^\\s,;}]+"), "$1$2••••••••")
        .replace(Regex("(?i)(\\\"(?:token|password|authorization)\\\"\\s*:\\s*\\\")[^\\\"]+"), "$1••••••••")
}
