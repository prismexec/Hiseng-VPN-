package com.hiseng.vpn

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Over-the-air updates: newer APKs from the GitHub releases (tags build-N). */
object Updater {
    /** Public releases repo first; the main repo answers once it is public. */
    private val REPOS = listOf("prismexec/hiseng-vpn-releases", "prismexec/Hiseng-VPN-")

    data class Release(val build: Int, val apkUrl: String, val page: String)

    sealed class State {
        object Idle : State()
        object Checking : State()
        object Available : State()
        data class Downloading(val progress: Float) : State()
        data class Ready(val file: File) : State()
        data class Failed(val message: String) : State()
    }

    @Volatile var state: State = State.Idle
        private set
    @Volatile var release: Release? = null
        private set

    private val listeners = mutableSetOf<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }

    private fun set(s: State) {
        state = s
        main.post { listeners.toList().forEach { it() } }
    }

    fun currentBuild(c: Context): Int = try {
        val pi = c.packageManager.getPackageInfo(c.packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode.toInt()
        else @Suppress("DEPRECATION") pi.versionCode
    } catch (_: Throwable) {
        0
    }

    fun versionName(c: Context): String = try {
        c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: "?"
    } catch (_: Throwable) {
        "?"
    }

    /** Looks for a newer build; [onDone] gets a line for the user. */
    fun check(c: Context, onDone: ((String) -> Unit)? = null) {
        if (state is State.Checking || state is State.Downloading) return
        val app = c.applicationContext
        set(State.Checking)
        Thread({
            try {
                val arr = REPOS.firstNotNullOfOrNull { repo ->
                    try {
                        val conn = URL("https://api.github.com/repos/$repo/releases?per_page=30")
                            .openConnection() as HttpURLConnection
                        conn.setRequestProperty("Accept", "application/vnd.github+json")
                        conn.connectTimeout = 15000
                        conn.readTimeout = 15000
                        if (conn.responseCode != 200) null
                        else JSONArray(conn.inputStream.bufferedReader().use { it.readText() })
                    } catch (_: Throwable) {
                        null
                    }
                } ?: throw IllegalStateException("no releases")
                var best: Release? = null
                for (i in 0 until arr.length()) {
                    val r = arr.getJSONObject(i)
                    if (r.optBoolean("draft")) continue
                    val n = r.optString("tag_name").removePrefix("build-").toIntOrNull() ?: continue
                    if (!r.optString("tag_name").startsWith("build-")) continue
                    val cur = best
                    if (cur != null && n <= cur.build) continue
                    val assets = r.optJSONArray("assets") ?: continue
                    for (j in 0 until assets.length()) {
                        val a = assets.getJSONObject(j)
                        if (a.optString("name").endsWith(".apk")) {
                            best = Release(n, a.optString("browser_download_url"), r.optString("html_url"))
                            break
                        }
                    }
                }
                val found = best
                if (found != null && found.build > currentBuild(app)) {
                    release = found
                    set(State.Available)
                    onDone?.let { cb -> main.post { cb("Есть новая сборка ${found.build}") } }
                } else {
                    release = null
                    set(State.Idle)
                    onDone?.let { cb -> main.post { cb("Установлена последняя версия") } }
                }
            } catch (_: Throwable) {
                set(if (release != null) State.Available else State.Idle)
                onDone?.let { cb -> main.post { cb("Сервер обновлений пока недоступен") } }
            }
        }, "update-check").start()
    }

    /** Downloads the APK, then opens the system installer. */
    fun download(c: Context) {
        val rel = release ?: return
        if (state is State.Downloading) return
        val app = c.applicationContext
        set(State.Downloading(0f))
        Thread({
            try {
                val dir = File(app.cacheDir, "updates").apply { mkdirs() }
                dir.listFiles()?.forEach { it.delete() }
                val file = File(dir, "HisengVPN-${rel.build}.apk")
                val conn = URL(rel.apkUrl).openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = true
                conn.connectTimeout = 20000
                conn.readTimeout = 30000
                val total = conn.contentLengthLong
                conn.inputStream.use { input ->
                    file.outputStream().use { out ->
                        val buf = ByteArray(64 * 1024)
                        var done = 0L
                        var shown = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            done += n
                            if (total > 0 && done - shown > 256 * 1024) {
                                shown = done
                                set(State.Downloading(done.toFloat() / total))
                            }
                        }
                    }
                }
                set(State.Ready(file))
                main.post { install(app) }
            } catch (e: Throwable) {
                set(State.Failed("Не удалось скачать: ${e.message ?: e}"))
            }
        }, "update-download").start()
    }

    /** Hands the downloaded APK to the system installer. */
    fun install(c: Context) {
        val ready = state as? State.Ready ?: return
        if (!c.packageManager.canRequestPackageInstalls()) {
            c.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${c.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            toast(c, "Разрешите установку и нажмите «Установить» ещё раз")
            return
        }
        val uri = FileProvider.getUriForFile(c, "${c.packageName}.files", ready.file)
        c.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
