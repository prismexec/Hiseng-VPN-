package best.quasar.vpn

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        handleIntent(intent)
        setContent { QuasarTheme { MainScreen() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        val data = i?.dataString ?: return
        if (data.startsWith("openflux://")) KeyStore.save(this, data)
    }
}

/** Key checks and saving, shared by the screen and deep links. */
object KeyStore {
    fun save(c: Context, raw: String): Boolean {
        val key = Regex("openflux://\\S+").find(raw)?.value
        if (key == null) {
            toast(c, "Это не ключ OpenFlux")
            return false
        }
        try {
            mobile.Mobile.parseShareLink(key)
        } catch (e: Throwable) {
            toast(c, "Ключ повреждён: ${e.message}")
            return false
        }
        val wasOn = VpnState.status == Status.ON || VpnState.status == Status.CONNECTING
        Prefs.setKey(c, key)
        toast(c, "Ключ сохранён")
        if (wasOn) stopVpn(c)
        VpnState.set(VpnState.status, VpnState.message)
        return true
    }

    fun title(c: Context): Pair<String, String>? {
        val key = Prefs.key(c) ?: return null
        return try {
            val j = JSONObject(mobile.Mobile.parseShareLink(key))
            val name = j.optString("name").ifBlank { "Сервер" }
            val arr = j.optJSONArray("transports")
            val types = (0 until (arr?.length() ?: 0)).map { arr!!.getJSONObject(it).optString("type") }
            name to types.joinToString(" · ")
        } catch (_: Throwable) {
            "Ключ добавлен" to ""
        }
    }
}

fun toast(c: Context, s: String) = Toast.makeText(c, s, Toast.LENGTH_SHORT).show()

fun startVpn(c: Context) {
    ContextCompat.startForegroundService(
        c, Intent(c, FluxVpnService::class.java).setAction(FluxVpnService.ACTION_CONNECT)
    )
}

fun stopVpn(c: Context) {
    c.startService(Intent(c, FluxVpnService::class.java).setAction(FluxVpnService.ACTION_DISCONNECT))
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun QuasarTheme(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    val dark = isSystemInDarkTheme()
    val scheme = when {
        Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        dark -> darkColorScheme(
            primary = Color(0xFFCFBCFF), onPrimary = Color(0xFF381E72),
            primaryContainer = Color(0xFF4F378B), onPrimaryContainer = Color(0xFFEADDFF),
            tertiary = Color(0xFF7FD8BE), tertiaryContainer = Color(0xFF00513F),
            onTertiaryContainer = Color(0xFF9CF5D9)
        )
        else -> lightColorScheme(
            primary = Color(0xFF6750A4), primaryContainer = Color(0xFFEADDFF),
            onPrimaryContainer = Color(0xFF21005D), tertiary = Color(0xFF006B54),
            tertiaryContainer = Color(0xFF9CF5D9), onTertiaryContainer = Color(0xFF002118)
        )
    }
    MaterialExpressiveTheme(
        colorScheme = scheme,
        motionScheme = MotionScheme.expressive(),
        content = content
    )
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun MainScreen() {
    val ctx = LocalContext.current
    var status by remember { mutableStateOf(VpnState.status) }
    var message by remember { mutableStateOf(VpnState.message) }
    var logs by remember { mutableStateOf(VpnState.logs()) }
    var keyVersion by remember { mutableIntStateOf(0) }
    var showLogs by remember { mutableStateOf(false) }
    var showDialog by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        val l: () -> Unit = {
            status = VpnState.status
            message = VpnState.message
            logs = VpnState.logs()
            keyVersion++
        }
        VpnState.listen(l)
        onDispose { VpnState.unlisten(l) }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        if (it.resultCode == android.app.Activity.RESULT_OK) startVpn(ctx)
        else toast(ctx, "Без разрешения VPN не запустится")
    }

    val keyTitle = remember(keyVersion) { KeyStore.title(ctx) }

    fun onPower() {
        when (status) {
            Status.ON, Status.CONNECTING -> stopVpn(ctx)
            else -> {
                if (Prefs.key(ctx).isNullOrBlank()) {
                    toast(ctx, "Сначала вставьте ключ")
                    return
                }
                val prep = VpnService.prepare(ctx)
                if (prep != null) permission.launch(prep) else startVpn(ctx)
            }
        }
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(20.dp))
            Text(
                "Quasar VPN",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Black,
                color = MaterialTheme.colorScheme.onSurface
            )

            Spacer(Modifier.height(44.dp))
            PowerButton(status = status, onClick = { onPower() })
            Spacer(Modifier.height(32.dp))

            AnimatedContent(
                targetState = status,
                transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(150)) },
                label = "status"
            ) { s ->
                Text(
                    when (s) {
                        Status.OFF -> "Отключено"
                        Status.CONNECTING -> "Подключение"
                        Status.ON -> "Подключено"
                        Status.ERROR -> "Ошибка"
                    },
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = if (s == Status.ON) MaterialTheme.colorScheme.tertiary
                    else MaterialTheme.colorScheme.onSurface
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                when {
                    status == Status.OFF && keyTitle == null -> "Добавьте ключ ниже"
                    status == Status.OFF -> "Нажмите, чтобы подключиться"
                    else -> message
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(36.dp))
            KeyCard(
                title = keyTitle,
                onPaste = {
                    val cm = ctx.getSystemService(ClipboardManager::class.java)
                    val text = cm.primaryClip?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim()
                    if (text.isNullOrEmpty()) toast(ctx, "Буфер обмена пуст")
                    else if (KeyStore.save(ctx, text)) keyVersion++
                },
                onEnter = { showDialog = true }
            )

            Spacer(Modifier.height(12.dp))
            TextButton(onClick = { showLogs = !showLogs }) {
                Text(if (showLogs) "Скрыть журнал" else "Журнал")
            }
            AnimatedVisibility(
                visible = showLogs,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut()
            ) {
                Surface(
                    shape = RoundedCornerShape(24.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    SelectionContainer {
                        Text(
                            logs.ifBlank { "Журнал пуст" },
                            modifier = Modifier.padding(16.dp),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            lineHeight = 15.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (showDialog) {
        var text by remember { mutableStateOf(Prefs.key(ctx) ?: "") }
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text("Ключ") },
            text = {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    placeholder = { Text("openflux://…") },
                    shape = RoundedCornerShape(16.dp),
                    maxLines = 5
                )
            },
            confirmButton = {
                Button(onClick = {
                    if (KeyStore.save(ctx, text.trim())) {
                        keyVersion++
                        showDialog = false
                    }
                }) { Text("Сохранить") }
            },
            dismissButton = { TextButton(onClick = { showDialog = false }) { Text("Отмена") } }
        )
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun PowerButton(status: Status, onClick: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scheme = MaterialTheme.colorScheme

    val container by animateColorAsState(
        when (status) {
            Status.ON -> scheme.tertiaryContainer
            Status.CONNECTING -> scheme.primaryContainer
            Status.ERROR -> scheme.errorContainer
            Status.OFF -> scheme.surfaceContainerHighest
        },
        animationSpec = tween(500), label = "container"
    )
    val content by animateColorAsState(
        when (status) {
            Status.ON -> scheme.onTertiaryContainer
            Status.CONNECTING -> scheme.onPrimaryContainer
            Status.ERROR -> scheme.onErrorContainer
            Status.OFF -> scheme.primary
        },
        animationSpec = tween(500), label = "content"
    )
    val scale by animateFloatAsState(
        if (pressed) 0.9f else 1f,
        animationSpec = spring(dampingRatio = 0.4f, stiffness = 400f), label = "scale"
    )

    val spin = rememberInfiniteTransition(label = "spin")
    val angle by spin.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(
            tween(if (status == Status.CONNECTING) 4000 else 24000, easing = LinearEasing),
            RepeatMode.Restart
        ),
        label = "angle"
    )

    val shape = when (status) {
        Status.ON -> MaterialShapes.Cookie12Sided.toShape()
        Status.CONNECTING -> MaterialShapes.SoftBurst.toShape()
        Status.ERROR -> MaterialShapes.Cookie4Sided.toShape()
        Status.OFF -> MaterialShapes.Cookie9Sided.toShape()
    }

    Box(
        modifier = Modifier
            .size(232.dp)
            .scale(scale),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(232.dp)
                .rotate(if (status == Status.OFF) 0f else angle)
                .clip(shape)
                .background(container)
                .clickable(interactionSource = interaction, indication = null) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onClick()
                }
        )
        if (status == Status.CONNECTING) {
            LoadingIndicator(modifier = Modifier.size(96.dp), color = content)
        } else {
            Icon(
                painter = painterResource(R.drawable.ic_power),
                contentDescription = "Подключить",
                tint = content,
                modifier = Modifier.size(76.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun KeyCard(title: Pair<String, String>?, onPaste: () -> Unit, onEnter: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(32.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(MaterialShapes.Cookie6Sided.toShape())
                        .background(
                            if (title != null) MaterialTheme.colorScheme.tertiaryContainer
                            else MaterialTheme.colorScheme.secondaryContainer
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        if (title != null) "✓" else "?",
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp,
                        color = if (title != null) MaterialTheme.colorScheme.onTertiaryContainer
                        else MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
                Spacer(Modifier.size(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        title?.first ?: "Ключ не добавлен",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        title?.second?.ifBlank { null } ?: "Скопируйте ключ openflux:// и вставьте",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Spacer(Modifier.height(18.dp))
            Button(
                onClick = onPaste,
                shapes = ButtonDefaults.shapes(),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 60.dp)
            ) {
                Text("Вставить ключ из буфера", style = MaterialTheme.typography.titleMedium)
            }
            Spacer(Modifier.height(10.dp))
            FilledTonalButton(
                onClick = onEnter,
                shapes = ButtonDefaults.shapes(),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
            ) {
                Text("Ввести вручную")
            }
        }
    }
}
