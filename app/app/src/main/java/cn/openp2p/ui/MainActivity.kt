package cn.openp2p.ui

import android.app.Activity
import android.Manifest
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import cn.openp2p.Logger
import cn.openp2p.DeviceNameResolver
import cn.openp2p.OpenP2PService
import cn.openp2p.R
import cn.openp2p.management.ManagementSession
import cn.openp2p.security.SecureCredentialStore
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import openp2p.Openp2p

class MainActivity : AppCompatActivity() {
    private lateinit var root: LinearLayout
    private lateinit var content: FrameLayout
    private lateinit var navigation: BottomNavigationView
    private lateinit var session: ManagementSession
    private lateinit var secureStore: SecureCredentialStore
    private var selected = HOME
    private var homeBusy = false
    private var receiverRegistered = false
    private var deviceScreen: DeviceScreen? = null
    private var networkScreen: NetworkScreen? = null
    private var foregroundCheckJob: Job? = null
    private val logHandler = Handler(Looper.getMainLooper())

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            homeBusy = false
            if (selected == HOME) showHome()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Logger.init(getExternalFilesDir("log") ?: filesDir)
        session = ManagementSession.get(this)
        secureStore = SecureCredentialStore.get(this)
        selected = savedInstanceState?.getInt(STATE_SELECTED, HOME) ?: HOME

        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(R.color.surface_page))
        }
        content = FrameLayout(this)
        navigation = BottomNavigationView(this).apply {
            setBackgroundColor(color(R.color.surface_card))
            itemIconTintList = ContextCompat.getColorStateList(this@MainActivity, R.color.navigation_item_tint)
            itemTextColor = ContextCompat.getColorStateList(this@MainActivity, R.color.navigation_item_tint)
            labelVisibilityMode = com.google.android.material.bottomnavigation.LabelVisibilityMode.LABEL_VISIBILITY_LABELED
            setOnNavigationItemSelectedListener { item ->
                selected = item.itemId
                showSelected()
                true
            }
        }
        root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(navigation, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            root.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
            navigation.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
            insets
        }

        rebuildNavigation(false)
        registerReceiver(statusReceiver, IntentFilter(OpenP2PService.ACTION_STATUS_CHANGED))
        receiverRegistered = true
        lifecycleScope.launch {
            val loggedIn = session.initialize()
            if (loggedIn) saveManagedToken(session.profile.token)
            rebuildNavigation(loggedIn)
            showSelected()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt(STATE_SELECTED, selected)
        super.onSaveInstanceState(outState)
    }

    override fun onResume() {
        super.onResume()
        checkCoreOnForeground()
    }

    private fun checkCoreOnForeground() {
        foregroundCheckJob?.cancel()
        foregroundCheckJob = lifecycleScope.launch {
            val alive = try {
                withContext(Dispatchers.IO) { Openp2p.isModuleRunning() }
            } catch (e: Throwable) {
                Logger.e("MainActivity", "前台核心状态检查失败", e)
                return@launch
            }

            val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
            val desired = prefs.getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
            val currentState = prefs.getString(OpenP2PService.KEY_STATE, "").orEmpty()
            val transitionInProgress = currentState.contains("正在启动") ||
                currentState.contains("正在连接") || currentState.contains("正在恢复")
            if (!alive && desired && !transitionInProgress) {
                prefs.edit().putString(OpenP2PService.KEY_STATE, "正在恢复核心").apply()
                ContextCompat.startForegroundService(
                    this@MainActivity,
                    Intent(this@MainActivity, OpenP2PService::class.java)
                        .setAction(OpenP2PService.ACTION_START)
                )
            }
            val state = when {
                alive -> "核心运行中"
                desired && transitionInProgress -> currentState
                desired -> "正在恢复核心"
                else -> "已停止"
            }
            prefs.edit().putString(OpenP2PService.KEY_STATE, state).apply()
            Logger.i("MainActivity", "前台核心状态检查：$state")
            homeBusy = false
            if (selected == HOME) showHome()
        }
    }

    override fun onDestroy() {
        foregroundCheckJob?.cancel()
        if (receiverRegistered) unregisterReceiver(statusReceiver)
        logHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun rebuildNavigation(managed: Boolean = session.authenticated) {
        val old = selected
        navigation.menu.clear()
        navigation.menu.add(0, HOME, 0, R.string.nav_home).setIcon(R.drawable.ic_home)
        if (managed) {
            navigation.menu.add(0, DEVICES, 1, R.string.nav_devices).setIcon(R.drawable.ic_devices)
            navigation.menu.add(0, NETWORK, 2, R.string.nav_network).setIcon(R.drawable.ic_hotspot)
        }
        navigation.menu.add(0, LOGS, 3, R.string.nav_logs).setIcon(R.drawable.ic_logs)
        navigation.menu.add(0, PROFILE, 4, R.string.nav_profile).setIcon(R.drawable.ic_profile)
        selected = if (navigation.menu.findItem(old) != null) old else PROFILE
        navigation.selectedItemId = selected
    }

    private fun showSelected() {
        logHandler.removeCallbacksAndMessages(null)
        when (selected) {
            HOME -> showHome()
            DEVICES -> {
                val screen = deviceScreen ?: DeviceScreen(this, session).also { deviceScreen = it }
                setPage(screen.view)
            }
            NETWORK -> {
                val screen = networkScreen ?: NetworkScreen(this, session).also { networkScreen = it }
                setPage(screen.view)
            }
            LOGS -> showLogs()
            PROFILE -> showProfile()
        }
    }

    private fun setPage(view: View) {
        (view.parent as? android.view.ViewGroup)?.removeView(view)
        content.removeAllViews()
        content.addView(view, FrameLayout.LayoutParams(-1, -1))
    }

    private fun showHome() {
        val (page, body) = page(getString(R.string.app_name))
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        val rawState = prefs.getString(OpenP2PService.KEY_STATE, "").orEmpty()
        val desired = prefs.getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
        val hasError = rawState.contains("error", true) || rawState.contains("fail", true) ||
            rawState.contains("异常") || rawState.contains("失败") || rawState.contains("未运行")
        val recovering = rawState.contains("正在恢复") || rawState.contains("等待恢复")
        val connecting = !recovering && (rawState.contains("正在启动") || rawState.contains("正在连接") ||
            (homeBusy && !desired))
        val stopping = homeBusy && desired
        val transitioning = connecting || recovering || stopping
        val heroStatus = when {
            hasError -> AppStatus.ERROR
            transitioning -> AppStatus.INFO
            desired -> AppStatus.SUCCESS
            else -> AppStatus.NEUTRAL
        }
        val heroTitle = getString(when {
            hasError -> R.string.status_error
            stopping -> R.string.status_stopping
            recovering -> R.string.status_recovering
            connecting -> R.string.status_connecting
            desired -> R.string.status_running
            else -> R.string.status_stopped
        })
        val heroDescription = getString(when {
            hasError -> R.string.status_error
            stopping -> R.string.connection_stopping_hint
            recovering -> R.string.connection_recovering_hint
            connecting -> R.string.connection_starting_hint
            desired -> R.string.connection_established
            else -> R.string.connection_stopped_hint
        })
        body.addView(card {
            val header = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            header.addView(TextView(context).apply {
                text = heroTitle
                textSize = 22f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(context.color(R.color.text_primary))
            }, LinearLayout.LayoutParams(0, -2, 1f))
            header.addView(context.statusChip(heroTitle, heroStatus))
            addView(header)
            label(heroDescription, true).apply { setPadding(0, context.dp(8), 0, context.dp(8)) }
            if (rawState.isNotBlank() && hasError) label(rawState, true)
            val buttonText = getString(if (desired) R.string.stop_openp2p else R.string.start_openp2p)
            action(buttonText) {
                homeBusy = true
                showHome()
                if (desired) stopCore() else requestStartCore()
            }.setLoading(transitioning, buttonText, getString(R.string.please_wait))
        })

        body.sectionHeader(getString(R.string.configuration_overview))
        body.addView(card {
            val token = coreToken(prefs)
            val vpnPermissionRequired = prefs.getBoolean(OpenP2PService.KEY_VPN_PERMISSION_REQUIRED, false)
            keyValue(getString(R.string.token_source), getString(when {
                session.authenticated -> R.string.token_source_account
                token.isNotBlank() -> R.string.token_source_local
                else -> R.string.token_source_missing
            }))
            keyValue(getString(R.string.vpn_permission), getString(if (vpnPermissionRequired) {
                R.string.vpn_permission_required
            } else {
                R.string.vpn_permission_ready
            }))
            keyValue(
                getString(R.string.virtual_network_status),
                prefs.getString(OpenP2PService.KEY_TUN_STATE, getString(R.string.virtual_network_waiting))
                    ?: getString(R.string.virtual_network_waiting)
            )
            keyValue(getString(R.string.management_account), getString(if (session.authenticated) R.string.account_signed_in else R.string.account_signed_out))
            if (vpnPermissionRequired) {
                secondaryAction(getString(R.string.reauthorize_vpn)) { requestStartCore() }
            }
        })

        if (!session.authenticated) {
            body.sectionHeader(getString(R.string.configure_token))
            body.addView(card {
                label(getString(R.string.token_help), true)
                val saved = coreToken(prefs)
                val token = field(getString(R.string.token_label), saved, numeric = true, password = true)
                action(getString(R.string.save_token)) {
                    val value = token.text?.toString()?.trim().orEmpty()
                    if (!value.matches(Regex("[1-9]\\d*"))) token.showError(getString(R.string.invalid_token))
                    else {
                        token.showError(null)
                        saveManagedToken(value)
                        page.snack(getString(R.string.token_saved))
                        showHome()
                    }
                }
                secondaryAction(getString(R.string.login_management_account)) { showManagementAccount() }
            })
        }
        body.secondaryAction(getString(R.string.common_questions)) { showBackgroundHelp() }
        setPage(page)
    }

    private fun requestStartCore() {
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        val token = coreToken(prefs)
        if (token.isBlank()) {
            homeBusy = false
            content.snack(getString(R.string.token_required))
            showHome()
            return
        }
        val bluetoothPermissionAsked = prefs.getBoolean(KEY_BLUETOOTH_PERMISSION_ASKED, false)
        if (!bluetoothPermissionAsked && DeviceNameResolver.shouldRequestBluetoothPermission(this)) {
            prefs.edit().putBoolean(KEY_BLUETOOTH_PERMISSION_ASKED, true).apply()
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                BLUETOOTH_NAME_REQUEST
            )
            return
        }
        requestVpnAndStartCore(prefs)
    }

    private fun requestVpnAndStartCore(prefs: android.content.SharedPreferences =
        getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)) {
        val prepare = VpnService.prepare(this)
        prefs.edit().putBoolean(OpenP2PService.KEY_VPN_PERMISSION_REQUIRED, prepare != null).apply()
        if (prepare != null) startActivityForResult(prepare, VPN_REQUEST) else startCore()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BLUETOOTH_NAME_REQUEST) requestVpnAndStartCore()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST) {
            val granted = resultCode == Activity.RESULT_OK
            getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE).edit()
                .putBoolean(OpenP2PService.KEY_VPN_PERMISSION_REQUIRED, !granted).apply()
            if (granted) startCore() else {
                homeBusy = false
                showHome()
            }
        }
    }

    private fun startCore() {
        ContextCompat.startForegroundService(this, Intent(this, OpenP2PService::class.java).setAction(OpenP2PService.ACTION_START))
    }

    private fun stopCore() {
        startService(Intent(this, OpenP2PService::class.java).setAction(OpenP2PService.ACTION_STOP))
    }

    private fun saveManagedToken(token: String) {
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        secureStore.putString(SecureCredentialStore.CORE_TOKEN, token)
        if (prefs.contains(OpenP2PService.KEY_TOKEN)) prefs.edit().remove(OpenP2PService.KEY_TOKEN).apply()
    }

    private fun coreToken(preferences: android.content.SharedPreferences): String =
        secureStore.migrateLegacy(preferences, OpenP2PService.KEY_TOKEN, SecureCredentialStore.CORE_TOKEN)

    private fun showLogs() {
        val (page, body) = page(getString(R.string.nav_logs))
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val autoScroll = Switch(this).apply { text = getString(R.string.auto_scroll); isChecked = true }
        controls.addView(autoScroll, LinearLayout.LayoutParams(0, -2, 1f))
        val export = MaterialButton(this).apply { text = getString(R.string.export_logs); minWidth = 0 }
        controls.addView(export); body.addView(controls)
        val logScroll = ScrollView(this)
        val text = TextView(this).apply {
            textSize = 12f
            setTextColor(color(R.color.text_primary))
            setBackgroundColor(color(R.color.log_surface))
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        logScroll.addView(text)
        body.addView(logScroll, LinearLayout.LayoutParams(-1, dp(440)))
        export.setOnClickListener {
            runCatching {
                val file = Logger.createExportFile(this)
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, getString(R.string.logs_export_subject))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }, getString(R.string.export_logs)))
            }.onFailure {
                Logger.e("MainActivity", "Failed to export logs", it)
                page.snack(getString(R.string.logs_export_failed))
            }
        }
        var previous = ""
        val update = object : Runnable {
            override fun run() {
                val latest = Logger.currentSession()
                if (latest != previous) {
                    if (previous.isNotEmpty() && latest.startsWith(previous)) text.append(latest.substring(previous.length))
                    else text.text = latest
                    previous = latest
                    if (autoScroll.isChecked) logScroll.post { logScroll.fullScroll(View.FOCUS_DOWN) }
                }
                if (text.text.isBlank()) text.hint = getString(R.string.logs_empty)
                logHandler.postDelayed(this, 1000)
            }
        }
        update.run()
        setPage(page)
    }

    private fun showProfile() {
        val (page, body) = page(getString(R.string.nav_profile))
        body.addView(card {
            label(getString(R.string.management_account))
            label(if (session.authenticated) session.profile.user.ifBlank { session.username } else getString(R.string.account_description), true)
            setOnClickListener { showManagementAccount() }
        })
        body.sectionHeader(getString(R.string.services_support))
        body.addView(card {
            label(getString(R.string.management_console))
            label(getString(R.string.management_console_description), true)
            setOnClickListener { showManagementConsole() }
        })
        body.addView(card {
            label(getString(R.string.background_keep_alive))
            label(getString(R.string.android_background_keep_alive_description), true)
            setOnClickListener { showBackgroundHelp() }
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        body.sectionHeader(getString(R.string.about))
        body.addView(card {
            label(getString(R.string.about))
            label(getString(R.string.about_description), true)
            setOnClickListener { showAbout() }
        })
        setPage(page)
    }

    private fun showManagementAccount() {
        bottomSheet(getString(R.string.management_account)) { dialog ->
            if (session.authenticated) {
                keyValue(getString(R.string.username), session.profile.user.ifBlank { session.username })
                if (session.profile.email.isNotBlank()) keyValue(getString(R.string.email), session.profile.email)
                if (session.profile.phone.isNotBlank()) keyValue(getString(R.string.phone), session.profile.phone)
                if (session.profile.addTime.isNotBlank()) keyValue(getString(R.string.registration_time), session.profile.addTime)
                val token = session.profile.token
                keyValue(getString(R.string.token_label), getString(R.string.masked_token, token.takeLast(4)), mono = true)
                label(getString(R.string.token_locked_by_login), true)
                secondaryAction(getString(R.string.copy_token)) {
                    copySensitive(getString(R.string.token_label), token)
                    content.snack(getString(R.string.token_copied_warning))
                }
                destructiveAction(getString(R.string.sign_out)) {
                    context.confirm(getString(R.string.sign_out), getString(R.string.sign_out_confirm), getString(R.string.sign_out), true) {
                        lifecycleScope.launch {
                            session.logout()
                            deviceScreen = null
                            networkScreen = null
                            selected = PROFILE
                            rebuildNavigation(false)
                            dialog.dismiss()
                            showProfile()
                        }
                    }
                }
            } else {
                val user = field(getString(R.string.username))
                val password = field(getString(R.string.password), password = true)
                val loginButton = action(getString(R.string.sign_in_save)) {}
                loginButton.setOnClickListener {
                    val username = user.text?.toString()?.trim().orEmpty()
                    val passwordValue = password.text?.toString().orEmpty()
                    if (username.isBlank()) { user.showError(getString(R.string.username)); return@setOnClickListener }
                    if (passwordValue.isBlank()) { password.showError(getString(R.string.password)); return@setOnClickListener }
                    loginButton.setLoading(true, getString(R.string.sign_in_save), getString(R.string.signing_in))
                    lifecycleScope.launch {
                        val ok = session.login(username, passwordValue)
                        loginButton.setLoading(false, getString(R.string.sign_in_save), getString(R.string.signing_in))
                        if (ok) {
                            saveManagedToken(session.profile.token)
                            rebuildNavigation(true)
                            dialog.dismiss()
                            showProfile()
                            content.snack(getString(R.string.login_success))
                        } else password.showError(session.lastError.ifBlank { getString(R.string.login_failed) })
                    }
                }
                secondaryAction(getString(R.string.register_account)) {
                    dialog.dismiss()
                    showRegistration()
                }
            }
        }
    }

    private fun showRegistration() {
        bottomSheet(getString(R.string.register_title)) { dialog ->
            label(getString(R.string.register_description), true)
            val user = field(getString(R.string.username_minimum))
            val password = field(getString(R.string.password_minimum), password = true)
            val confirmation = field(getString(R.string.confirm_password), password = true)
            val phone = field(getString(R.string.phone_optional))
            val email = field(getString(R.string.email_recovery_hint))
            val agreement = CheckBox(context).apply {
                text = getString(R.string.agree_user_agreement)
                setTextColor(color(R.color.text_primary))
            }
            addView(agreement, LinearLayout.LayoutParams(-1, -2))
            val agreementLinks = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(agreementLink(getString(R.string.view_user_agreement)) {
                    openAgreement(AGREEMENT_URL)
                }, LinearLayout.LayoutParams(0, dp(48), 1f))
                addView(agreementLink(getString(R.string.view_privacy_agreement)) {
                    openAgreement(PRIVACY_AGREEMENT_URL)
                }, LinearLayout.LayoutParams(0, dp(48), 1f))
            }
            addView(agreementLinks, LinearLayout.LayoutParams(-1, -2))
            val registerButton = action(getString(R.string.register_and_sign_in)) {}
            registerButton.setOnClickListener {
                val username = user.text?.toString()?.trim().orEmpty()
                val passwordValue = password.text?.toString().orEmpty()
                val confirmationValue = confirmation.text?.toString().orEmpty()
                if (username.length < 8 || passwordValue.length < 8) {
                    user.showError(getString(R.string.username_password_minimum_error))
                    return@setOnClickListener
                }
                if (passwordValue != confirmationValue) {
                    confirmation.showError(getString(R.string.passwords_do_not_match))
                    return@setOnClickListener
                }
                if (!agreement.isChecked) {
                    content.snack(getString(R.string.agreement_required))
                    return@setOnClickListener
                }
                registerButton.setLoading(true, getString(R.string.register_and_sign_in), getString(R.string.registering))
                lifecycleScope.launch {
                    val ok = session.register(
                        username, passwordValue, phone.text?.toString().orEmpty(), email.text?.toString().orEmpty()
                    )
                    registerButton.setLoading(false, getString(R.string.register_and_sign_in), getString(R.string.registering))
                    if (ok) {
                        saveManagedToken(session.profile.token)
                        rebuildNavigation(true)
                        dialog.dismiss()
                        showProfile()
                        content.snack(getString(R.string.registration_success))
                    } else confirmation.showError(session.lastError.ifBlank { getString(R.string.registration_failed) })
                }
            }
        }
    }

    private fun agreementLink(label: String, action: () -> Unit) = TextView(this).apply {
        text = label
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(color(R.color.brand_primary))
        setOnClickListener { action() }
    }

    private fun openAgreement(url: String) {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
            .onFailure { content.snack(getString(R.string.no_browser_available)) }
    }

    private fun copySensitive(label: String, value: String) {
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(label, value))
    }

    private fun showBackgroundHelp() {
        bottomSheet(getString(R.string.background_keep_alive)) { dialog ->
            label(getString(R.string.phone_setting), true)
            action(getString(R.string.request_battery_exemption)) { openBatteryOptimizationSettings() }
            secondaryAction(getString(R.string.open_autostart_settings)) { openAutoStartSettings() }
            secondaryAction(getString(R.string.open_app_settings)) { openAppSettings() }
            action(getString(R.string.done)) { dialog.dismiss() }
        }
    }

    private fun openBatteryOptimizationSettings() {
        val direct = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        } else null
        val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        } else null
        openFirstAvailable(listOfNotNull(direct, list), ::openAppSettings)
    }

    private fun openAutoStartSettings() {
        val candidates = listOf(
            Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.oplus.safecenter", "com.oplus.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        )
        openFirstAvailable(candidates, ::openAppSettings)
    }

    private fun openAppSettings() {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
    }

    private fun openFirstAvailable(candidates: List<Intent>, fallback: () -> Unit) {
        val intent = candidates.firstOrNull { it.resolveActivity(packageManager) != null }
        if (intent == null) fallback() else runCatching { startActivity(intent) }.onFailure { fallback() }
    }

    private fun showAbout() {
        bottomSheet(getString(R.string.about)) { dialog ->
            label(getString(R.string.app_name))
            label(getString(R.string.open_source_description), true)
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            keyValue(getString(R.string.about), getString(R.string.version_format, packageInfo.versionName ?: "--", packageInfo.versionCode))
            keyValue(getString(R.string.runtime_platform), "Android")
            val architecture = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                Build.SUPPORTED_ABIS.firstOrNull() ?: Build.CPU_ABI
            } else {
                Build.CPU_ABI
            }
            keyValue(getString(R.string.core_architecture), architecture)
            keyValue(getString(R.string.core_type), "OpenP2P Go Native")
            action(getString(R.string.done)) { dialog.dismiss() }
        }
    }

    fun showManagementConsole() {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(CONSOLE_URL))) }
            .onFailure { content.snack(getString(R.string.no_browser_available)) }
    }

    companion object {
        private const val HOME = 1
        private const val DEVICES = 2
        private const val NETWORK = 3
        private const val LOGS = 4
        private const val PROFILE = 5
        private const val VPN_REQUEST = 100
        private const val BLUETOOTH_NAME_REQUEST = 101
        private const val KEY_BLUETOOTH_PERMISSION_ASKED = "bluetooth_name_permission_asked"
        private const val STATE_SELECTED = "selected_navigation"
        private const val CONSOLE_URL = "https://console.openpxp.com/"
        private const val AGREEMENT_URL = "https://console.openpxp.com/agreement"
        private const val PRIVACY_AGREEMENT_URL =
            "https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2013507738654513472"
    }
}
