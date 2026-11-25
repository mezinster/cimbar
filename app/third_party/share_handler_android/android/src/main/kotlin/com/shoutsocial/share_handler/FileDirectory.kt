package com.shoutsocial.share_handler

import android.content.Context
import android.database.Cursor
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.util.*
import android.webkit.MimeTypeMap
import android.util.Log


object FileDirectory {

    /**
     * The cache copy of a shared [uri]'s stream, or null when it can't be copied.
     *
     * CimBar patch, third fix (see CIMBAR_PATCH.md): every `content://` URI is
     * copied through the capped stream copy. Upstream resolved document
     * URIs (Storage Access Framework) to paths instead: `primary:` documents to
     * the app's own external files dir + the relative path, which doesn't exist,
     * and media documents to the MediaStore data column under
     * /storage/emulated/0, which an app holding only CAMERA can't read, so a
     * PDF shared from the system Files app arrived unreadable. A `file://` (or any other non-content)
     * URI is refused: a modern sender can't send one (FileUriExposedException),
     * and the only files it could name that CimBar can read are CimBar's own.
     */
    internal fun getAbsolutePath(context: Context, uri: Uri, budget: CopyBudget): String? {
        if (!isContentScheme(uri.scheme)) return null
        return try {
            getDataColumn(context, uri, budget)
        } catch (e: Exception) {
            // A provider that refuses the read (revoked grant, missing
            // document) makes this one attachment unreadable, not the app crash.
            Log.w("FileDirectory", "Copy failed: $e")
            null
        }
    }

    /**
     * Copies [uri]'s stream into the cache under its sanitised display name
     * (or a generated one) and returns the copy's path, or the too-large marker.
     */
    private fun getDataColumn(context: Context, uri: Uri, budget: CopyBudget): String? {
        if (uri.authority == null) return null
        var cursor: Cursor? = null
        val column = "_display_name"
        val projection = arrayOf(column)
        var targetFile: File? = null
        try {
            cursor = context.contentResolver.query(uri, projection, null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndexOrThrow(column)
                val fileName = cursor.getString(columnIndex)
                Log.i("FileDirectory", "File name: $fileName")
                // CimBar patch: never trust the sender's display name as a path.
                targetFile = safeCacheFile(context.cacheDir, fileName)
            }
        } finally {
            cursor?.close()
        }

        if (targetFile == null) {
            val mimeType = context.contentResolver.getType(uri)
            val prefix = with(mimeType ?: "") {
                when {
                    startsWith("image") -> "IMG"
                    startsWith("video") -> "VID"
                    else -> "FILE"
                }
            }
            val type = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
            targetFile = File(context.cacheDir, "${prefix}_${Date().time}.$type")
        }
        // CimBar patch: refuse shares above the cap instead of copying them on the
        // main thread. The marker string travels back through the path result and
        // ShareHandlerPlugin.attachmentForUri turns it into the attachment's path.
        val size = reportedSize(context.contentResolver, uri)
        if (shouldSkipCopy(size, budget.remaining)) return "$TOO_LARGE_PREFIX${size ?: -1}"
        var tooLarge = false
        try {
            val input = context.contentResolver.openInputStream(uri) ?: return null
            input.use {
                FileOutputStream(targetFile).use { fileOut ->
                    tooLarge = !copyCapped(input, fileOut, budget.remaining)
                }
            }
        } catch (e: Exception) {
            targetFile.delete()
            throw e
        }
        if (tooLarge) {
            targetFile.delete()
            budget.consume(budget.remaining)
            return "$TOO_LARGE_PREFIX${size ?: -1}"
        }
        budget.consume(targetFile.length())
        return targetFile.path
    }
}
