package best.quasar.vpn

import android.content.Context
import android.os.Handler
import android.os.Looper

enum class Status { OFF, CONNECTING, ON, ERROR }

/** Shared state between the VPN service and the screen. */
object VpnState {
    @Volatile var status: Status = Status.OFF
        private set
    @Volatile var message: String = ""
        private set

    private val logLines = ArrayDeque<String>()
    private val listeners = mutableSetOf<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun set(s: Status, msg: String = "") {
        status = s
        message = msg
        notifyListeners()
    }

    fun addLogs(text: String) {
        if (text.isBlank()) return
        synchronized(logLines) {
            text.lines().filter { it.isNotBlank() }.forEach {
                logLines.addLast(it)
                while (logLines.size > 300) logLines.removeFirst()
            }
        }
        notifyListeners()
    }

    fun logs(): String = synchronized(logLines) { logLines.joinToString("\n") }

    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }

    private fun notifyListeners() {
        main.post { listeners.toList().forEach { it() } }
    }
}

object Prefs {
    private fun p(c: Context) = c.getSharedPreferences("quasar", Context.MODE_PRIVATE)
    fun key(c: Context): String? = p(c).getString("key", null)
    fun setKey(c: Context, k: String) = p(c).edit().putString("key", k).apply()
}
