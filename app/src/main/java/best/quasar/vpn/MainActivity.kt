package best.quasar.vpn

import android.Manifest
import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import org.json.JSONObject

class MainActivity : AppCompatActivity() {

    private lateinit var power: FrameLayout
    private lateinit var status: TextView
    private lateinit var hint: TextView
    private lateinit var keyInfo: TextView
    private lateinit var logs: TextView
    private lateinit var logToggle: TextView

    private val listener: () -> Unit = { render() }

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (it.resultCode == Activity.RESULT_OK) startVpn()
            else toast("Без разрешения VPN не запустится")
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        power = findViewById(R.id.powerButton)
        status = findViewById(R.id.status)
        hint = findViewById(R.id.statusHint)
        keyInfo = findViewById(R.id.keyInfo)
        logs = findViewById(R.id.logs)
        logToggle = findViewById(R.id.logToggle)

        power.setOnClickListener { onPower() }
        findViewById<View>(R.id.pasteButton).setOnClickListener { pasteKey() }
        findViewById<View>(R.id.enterButton).setOnClickListener { enterKey() }
        logToggle.setOnClickListener {
            val show = logs.visibility != View.VISIBLE
            logs.visibility = if (show) View.VISIBLE else View.GONE
            logToggle.text = if (show) "Скрыть журнал" else "Показать журнал"
        }

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        handleIntent(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        VpnState.listen(listener)
        render()
    }

    override fun onStop() {
        VpnState.unlisten(listener)
        super.onStop()
    }

    private fun handleIntent(i: Intent?) {
        val data = i?.dataString ?: return
        if (data.startsWith("openflux://")) saveKey(data)
    }

    private fun onPower() {
        when (VpnState.status) {
            Status.ON, Status.CONNECTING -> stopVpn()
            else -> {
                if (Prefs.key(this).isNullOrBlank()) {
                    toast("Сначала вставьте ключ")
                    return
                }
                val prep = VpnService.prepare(this)
                if (prep != null) vpnPermission.launch(prep) else startVpn()
            }
        }
    }

    private fun startVpn() {
        val i = Intent(this, FluxVpnService::class.java).setAction(FluxVpnService.ACTION_CONNECT)
        ContextCompat.startForegroundService(this, i)
    }

    private fun stopVpn() {
        startService(Intent(this, FluxVpnService::class.java).setAction(FluxVpnService.ACTION_DISCONNECT))
    }

    private fun pasteKey() {
        val cm = getSystemService(ClipboardManager::class.java)
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(this)?.toString()?.trim()
        if (text.isNullOrEmpty()) {
            toast("Буфер обмена пуст")
            return
        }
        saveKey(text)
    }

    private fun enterKey() {
        val input = EditText(this).apply {
            hint = "openflux://…"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setText(Prefs.key(this@MainActivity) ?: "")
        }
        AlertDialog.Builder(this)
            .setTitle("Ключ")
            .setView(input)
            .setPositiveButton("Сохранить") { _, _ -> saveKey(input.text.toString().trim()) }
            .setNegativeButton("Отмена", null)
            .show()
    }

    private fun saveKey(raw: String) {
        val key = Regex("openflux://\\S+").find(raw)?.value
        if (key == null) {
            toast("Это не ключ OpenFlux")
            return
        }
        try {
            mobile.Mobile.parseShareLink(key)
        } catch (e: Throwable) {
            toast("Ключ повреждён: ${e.message}")
            return
        }
        val wasOn = VpnState.status == Status.ON || VpnState.status == Status.CONNECTING
        Prefs.setKey(this, key)
        toast("Ключ сохранён")
        if (wasOn) stopVpn()
        render()
    }

    private fun keyTitle(): String {
        val key = Prefs.key(this) ?: return "Ключ не добавлен"
        return try {
            val c = JSONObject(mobile.Mobile.parseShareLink(key))
            val name = c.optString("name").ifBlank { "Сервер" }
            val arr = c.optJSONArray("transports")
            val types = (0 until (arr?.length() ?: 0)).map { arr!!.getJSONObject(it).optString("type") }
            if (types.isEmpty()) name else "$name · ${types.joinToString(", ")}"
        } catch (_: Throwable) {
            "Ключ добавлен"
        }
    }

    private fun render() {
        keyInfo.text = keyTitle()
        when (VpnState.status) {
            Status.OFF -> {
                status.text = "Отключено"
                hint.text = "Нажмите кнопку, чтобы подключиться"
                power.setBackgroundResource(R.drawable.btn_off)
            }
            Status.CONNECTING -> {
                status.text = "Подключение…"
                hint.text = VpnState.message
                power.setBackgroundResource(R.drawable.btn_off)
            }
            Status.ON -> {
                status.text = "Подключено"
                hint.text = VpnState.message
                power.setBackgroundResource(R.drawable.btn_on)
            }
            Status.ERROR -> {
                status.text = "Ошибка"
                hint.text = VpnState.message
                power.setBackgroundResource(R.drawable.btn_off)
            }
        }
        logs.text = VpnState.logs().ifBlank { "Журнал пуст" }
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
