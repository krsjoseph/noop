package com.noop.data

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Whole-store EXPORT / IMPORT for device migration.
 *
 * Kineva keeps everything on-device in a single Room/SQLite file ([WhoopDatabase.DB_NAME]).
 * Moving to a new phone therefore means moving exactly that one file. There is no cloud,
 * no account, nothing leaves the device except through these two explicit, user-driven
 * file operations (a SAF document the user picks).
 *
 * Export: checkpoint the WAL into the main db file, then write a single-entry ZIP
 * (the `.noopbak` format) containing the SQLite file. ZIP deflate typically reduces a
 * 100 MB+ SQLite backup to 10–20 MB — SQLite's page-aligned text data compresses very
 * well. The ZIP is a standard container: users can rename `.noopbak` → `.zip` and
 * extract the SQLite manually with any archive tool on any OS.
 *
 * Import: detect whether the picked file is a `.noopbak` ZIP (PK magic) or a legacy
 * plain `.sqlite` / `.noopdb` (SQLite magic) and handle both, so old backups keep
 * working. Validates the extracted/direct SQLite header before touching the live DB.
 * Closes the live Room singleton, snapshots the current db, overwrites it with the
 * chosen one, and drops the stale `-wal` / `-shm` sidecars. The caller then instructs
 * the user to restart the app so Room re-opens the new file fresh.
 */
object DataBackup {

    /** Entry name inside the `.noopbak` ZIP. */
    private const val ZIP_ENTRY_NAME = "noop-backup.sqlite"

    /** First 16 bytes of every SQLite 3 file: "SQLite format 3\0". */
    private val SQLITE_MAGIC: ByteArray =
        byteArrayOf(
            0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
            0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
        )

    /** First 4 bytes of every ZIP file: "PK\x03\x04". */
    private val ZIP_MAGIC: ByteArray =
        byteArrayOf(0x50, 0x4B, 0x03, 0x04)

    /** Outcome of an [importFrom] call. On success the app must be restarted. */
    sealed interface ImportResult {
        /** The new database is in place; tell the user to relaunch Kineva. */
        data object NeedsRestart : ImportResult

        /** Import failed and the original database is untouched. */
        data class Failed(val message: String) : ImportResult
    }

    /**
     * Export the live database to [uri] as a compressed `.noopbak` (single-entry ZIP).
     *
     * Runs `PRAGMA wal_checkpoint(TRUNCATE)` first so the db file is fully consistent.
     * The ZIP uses deflate compression; typical reduction is 80–90% vs the raw SQLite.
     * Throws on failure so the caller can surface the message in a toast/snackbar.
     */
    @Throws(IOException::class)
    fun exportTo(context: Context, uri: Uri) {
        val appContext = context.applicationContext

        // Fold the WAL back into the main file so the snapshot is complete.
        val db = WhoopDatabase.get(appContext)
        db.query("PRAGMA wal_checkpoint(TRUNCATE)", null).use { cursor ->
            cursor.moveToFirst()
        }

        val dbFile = appContext.getDatabasePath(WhoopDatabase.DB_NAME)
        if (!dbFile.exists()) {
            throw IOException("No database to export yet.")
        }

        val resolver = appContext.contentResolver
        val output = resolver.openOutputStream(uri)
            ?: throw IOException("Could not open the chosen file for writing.")
        output.use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(ZIP_ENTRY_NAME))
                dbFile.inputStream().use { input -> input.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    /**
     * Replace the live database with the backup at [uri].
     *
     * Accepts both the new `.noopbak` (ZIP) format and legacy plain `.sqlite`/`.noopdb`
     * files so older backups keep working after the format upgrade.
     *
     * On any error the current database is left exactly as it was. On success the caller
     * MUST instruct the user to fully restart the app.
     */
    fun importFrom(context: Context, uri: Uri): ImportResult {
        val appContext = context.applicationContext
        val resolver = appContext.contentResolver

        // 1. Peek at the first 16 bytes to distinguish ZIP from plain SQLite.
        val header = ByteArray(16)
        try {
            val read = resolver.openInputStream(uri)?.use { readFully(it, header) }
                ?: return ImportResult.Failed("Could not open the chosen file.")
            if (read < 4) return ImportResult.Failed("That file is not a Kineva backup.")
        } catch (e: IOException) {
            return ImportResult.Failed("Could not read the chosen file: ${e.message}")
        }

        // 2. If it's a ZIP (.noopbak), extract the SQLite entry to a temp file.
        //    If it's a plain SQLite (legacy), copy it to the same temp file.
        val tempSqlite = File(appContext.cacheDir, "import-extract.sqlite")
        try {
            when {
                header.startsWith(ZIP_MAGIC) -> {
                    // New .noopbak format: extract the sqlite entry.
                    var found = false
                    resolver.openInputStream(uri)?.use { input ->
                        ZipInputStream(input).use { zip ->
                            var entry = zip.nextEntry
                            while (entry != null) {
                                if (!entry.isDirectory && entry.name.endsWith(".sqlite")) {
                                    FileOutputStream(tempSqlite).use { out -> zip.copyTo(out) }
                                    found = true
                                    break
                                }
                                entry = zip.nextEntry
                            }
                        }
                    } ?: return ImportResult.Failed("Could not open the chosen file.")
                    if (!found) return ImportResult.Failed(
                        "The backup archive doesn't contain a database file."
                    )
                }
                header.startsWith(SQLITE_MAGIC) -> {
                    // Legacy plain SQLite: copy directly to temp.
                    resolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tempSqlite).use { out -> input.copyTo(out) }
                    } ?: return ImportResult.Failed("Could not open the chosen file.")
                }
                else -> return ImportResult.Failed(
                    "That file is not a Kineva backup — it doesn't look like a .noopbak archive or a SQLite database."
                )
            }
        } catch (e: IOException) {
            tempSqlite.delete()
            return ImportResult.Failed("Could not read the chosen file: ${e.message}")
        }

        // 3. Validate the extracted file is a real SQLite database.
        val extractedHeader = ByteArray(SQLITE_MAGIC.size)
        try {
            val read = tempSqlite.inputStream().use { readFully(it, extractedHeader) }
            if (read < SQLITE_MAGIC.size || !extractedHeader.contentEquals(SQLITE_MAGIC)) {
                tempSqlite.delete()
                return ImportResult.Failed("The backup archive doesn't contain a valid Kineva database.")
            }
        } catch (e: IOException) {
            tempSqlite.delete()
            return ImportResult.Failed("Could not validate the backup: ${e.message}")
        }

        val dbFile = appContext.getDatabasePath(WhoopDatabase.DB_NAME)
        val walFile = File(dbFile.path + "-wal")
        val shmFile = File(dbFile.path + "-shm")
        val rollbackFile = File(dbFile.path + ".import-bak")

        // 4. Close the live Room singleton so the file handles are released.
        WhoopDatabase.close()

        // 5. Snapshot the current db so a failed copy can be rolled back.
        try {
            rollbackFile.delete()
            if (dbFile.exists()) dbFile.copyTo(rollbackFile, overwrite = true)
        } catch (e: IOException) {
            tempSqlite.delete()
            return ImportResult.Failed("Could not back up the current data: ${e.message}")
        }

        // 6. Overwrite the db file with the extracted backup, then drop the stale sidecars.
        try {
            dbFile.parentFile?.mkdirs()
            tempSqlite.copyTo(dbFile, overwrite = true)
            walFile.delete()
            shmFile.delete()
        } catch (e: IOException) {
            runCatching { if (rollbackFile.exists()) rollbackFile.copyTo(dbFile, overwrite = true) }
            rollbackFile.delete()
            tempSqlite.delete()
            return ImportResult.Failed("Import failed, your data is unchanged: ${e.message}")
        }

        rollbackFile.delete()
        tempSqlite.delete()
        return ImportResult.NeedsRestart
    }

    /** Read up to [buffer].size bytes from [input], looping over short reads. Returns bytes read. */
    private fun readFully(input: java.io.InputStream, buffer: ByteArray): Int {
        var offset = 0
        while (offset < buffer.size) {
            val n = input.read(buffer, offset, buffer.size - offset)
            if (n < 0) break
            offset += n
        }
        return offset
    }

    /** True when [this] begins with every byte in [prefix]. */
    private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
        if (size < prefix.size) return false
        return prefix.indices.all { this[it] == prefix[it] }
    }
}
