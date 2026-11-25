package com.shoutsocial.share_handler

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

// CimBar patch (see CIMBAR_PATCH.md at the package root).
//
// A shared stream's display name is chosen by the SENDING app's content
// provider, and any installed app can send an explicit ACTION_SEND to the
// exported launcher activity. Upstream wrote `File(cacheDir, displayName)`,
// so a name like "../shared_prefs/FlutterSharedPreferences.xml" overwrote
// the receiving app's private files ("Dirty Stream" path traversal).

/**
 * The file [name] may be written to inside [dir]: only its last path segment
 * is kept, and the result must be a direct child of [dir]. Returns null for
 * names that are unusable (null, empty, ".", "..", or containing NUL), so the
 * caller can fall back to a generated name.
 */
internal fun safeCacheFile(dir: File, name: String?): File? {
    if (name == null || name.indexOf('\u0000') >= 0) return null
    val base = File(name).name
    if (base.isEmpty() || base == "." || base == "..") return null
    val file = File(dir, base)
    return try {
        if (file.canonicalFile.parentFile == dir.canonicalFile) file else null
    } catch (e: IOException) {
        null
    }
}

// CimBar patch, second fix (see CIMBAR_PATCH.md, "Second fix: size cap").
//
// The launcher accepts `*/*` and handleIntent copies every shared stream into
// cacheDir synchronously on the main thread, so a multi-GB share froze the app
// and filled the disk. Anything above the cap is refused before (or while)
// copying; the attachment's path becomes "cimbar-too-large:<size or -1>" so the
// Dart side can say "too big" instead of trying to open a file.

/** Same as CimbarSpec.maxInflatedBytes on the Dart side (a test keeps them equal). */
internal const val SHARE_SIZE_CAP: Long = 134217728L

internal const val TOO_LARGE_PREFIX = "cimbar-too-large:"

/**
 * Copies [input] to [out] and returns true, or returns false (stopping early)
 * as soon as more than [cap] bytes have been seen. The caller deletes the
 * partial output.
 */
internal fun copyCapped(input: InputStream, out: OutputStream, cap: Long): Boolean {
    val buffer = ByteArray(64 * 1024)
    var total = 0L
    while (true) {
        val n = input.read(buffer)
        if (n < 0) return true
        total += n
        if (total > cap) return false
        out.write(buffer, 0, n)
    }
}

/** The provider-reported `OpenableColumns.SIZE` of [uri], or null when absent or unknown. */
internal fun reportedSize(resolver: ContentResolver, uri: Uri): Long? {
    return try {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (!c.moveToFirst()) return@use null
            val i = c.getColumnIndex(OpenableColumns.SIZE)
            if (i == -1 || c.isNull(i)) null else c.getLong(i).takeIf { it >= 0 }
        }
    } catch (e: Exception) {
        null
    }
}
