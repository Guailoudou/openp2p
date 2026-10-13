package cn.openp2p.ui

import android.app.Activity
import android.Manifest
import android.content.BroadcastReceiver
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
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.lifecycle.lifecycleScope
import androidx.viewpager.widget.PagerAdapter
import androidx.viewpager.widget.ViewPager
import cn.openp2p.Logger
import cn.openp2p.DeviceNameResolver
import cn.openp2p.OpenP2PService
import cn.openp2p.R
import cn.openp2p.management.ManagementSession
import cn.openp2p.security.SecureCredentialStore
import cn.openp2p.security.tokenValidationError
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import openp2p.Openp2p

class MainActivity : AppCompatActivity() {
    private lateinit var root: FrameLayout
    private lateinit var content: FrameLayout
    private lateinit var pager: ViewPager
    private val pageHosts = mutableMapOf<Int, FrameLayout>()
    private fun tabIds() = if (managedNavigation) listOf(HOME, DEVICES, NETWORK, LOGS) else listOf(HOME, LOGS)
    private lateinit var navigation: BottomNavigationView
    private lateinit var coreButton: MaterialButton
    private lateinit var miniBar: LinearLayout
    private lateinit var miniBarHost: FrameLayout
    private lateinit var session: ManagementSession
    private lateinit var secureStore: SecureCredentialStore
    private var selected = HOME
    private var homeBusy = false
    private var managedNavigation = false
    private var rebuildingNavigation = false
    private var tokenDraft: String? = null
    private var homeScrollY = 0
    private var appearanceOpen = false
    private var receiverRegistered = false
    private var deviceScreen: DeviceScreen? = null
    private var networkScreen: NetworkScreen? = null
    private var retainedNetwork: NetworkScreen.Snapshot? = null
    private var foregroundCheckJob: Job? = null
    private val logHandler = Handler(Looper.getMainLooper())

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == OpenP2PService.ACTION_STATUS_CHANGED) homeBusy = false
            updateCoreToggle()
            if (selected == HOME) showHome()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        AppearancePreferences.applyMode(this)
        super.onCreate(savedInstanceState)
        Logger.init(getExternalFilesDir("log") ?: filesDir)
        session = ManagementSession.get(this)
        retainedNetwork = lastCustomNonConfigurationInstance as? NetworkScreen.Snapshot
        secureStore = SecureCredentialStore.get(this)
        selected = savedInstanceState?.getInt(STATE_SELECTED, HOME) ?: HOME
        tokenDraft = savedInstanceState?.getString("token_draft")

        root = FrameLayout(this).apply {
            setBackgroundColor(color(R.color.surface_page))
        }
        content = FrameLayout(this)
        pager = ViewPager(this).apply {
            id = ViewCompat.generateViewId()
            offscreenPageLimit = 3
            adapter = object : PagerAdapter() {
                override fun getCount() = tabIds().size
                override fun isViewFromObject(view: View, item: Any) = view === item
                override fun getItemPosition(item: Any) = POSITION_NONE
                override fun instantiateItem(container: android.view.ViewGroup, position: Int): Any {
                    val host = pageHosts.getOrPut(tabIds()[position]) { FrameLayout(this@MainActivity) }
                    (host.parent as? android.view.ViewGroup)?.removeView(host)
                    container.addView(host)
                    return host
                }
                override fun destroyItem(container: android.view.ViewGroup, position: Int, item: Any) {
                    container.removeView(item as View)
                }
            }
            addOnPageChangeListener(object : ViewPager.SimpleOnPageChangeListener() {
                override fun onPageSelected(position: Int) {
                    val tab = tabIds()[position]
                    if (!rebuildingNavigation && selected != tab) navigation.selectedItemId = tab
                }
            })
        }
        navigation = BottomNavigationView(this).apply {
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            ViewCompat.setElevation(this, 0f)
            itemIconTintList = AppearancePreferences.navigationTint(this@MainActivity)
            itemTextColor = AppearancePreferences.navigationTint(this@MainActivity)
            labelVisibilityMode = com.google.android.material.bottomnavigation.LabelVisibilityMode.LABEL_VISIBILITY_LABELED
            setOnNavigationItemSelectedListener { item ->
                selected = item.itemId
                pager.setCurrentItem(tabIds().indexOf(selected).coerceAtLeast(0), false)
                showSelected()
                true
            }
        }
        coreButton = MaterialButton(this).apply {
            minWidth = dp(56)
            minimumWidth = dp(56)
            minHeight = dp(56)
            cornerRadius = dp(28)
            iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
            iconPadding = 0
            iconSize = dp(24)
            setPadding(0, 0, 0, 0)
            setOnClickListener { toggleCoreFromMiniBar() }
        }
        miniBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(MaterialCardView(context).apply {
                radius = dp(28).toFloat()
                cardElevation = 0f
                maxCardElevation = 0f
                strokeWidth = dp(1)
                strokeColor = color(R.color.border_default)
                setCardBackgroundColor(color(R.color.surface_card))
                addView(navigation, FrameLayout.LayoutParams(-1, dp(56)))
            }, LinearLayout.LayoutParams(0, dp(56), 1f))
            addView(coreButton, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        }
        miniBarHost = FrameLayout(this).apply {
            addView(miniBar, FrameLayout.LayoutParams(dp(224), dp(56), Gravity.CENTER))
            setPadding(dp(16), dp(4), dp(16), dp(8))
            clipToPadding = false
        }
        root.addView(pager, FrameLayout.LayoutParams(-1, -1))
        root.addView(miniBarHost, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            root.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
            miniBarHost.setPadding(dp(16), dp(4), dp(16), dp(8) + insets.systemWindowInsetBottom)
            insets
        }

        managedNavigation = session.authenticated
        rebuildNavigation()
        updateCoreToggle()
        registerReceiver(statusReceiver, IntentFilter(OpenP2PService.ACTION_STATUS_CHANGED))
        receiverRegistered = true
        lifecycleScope.launch {
            val result = runCatching {
                (session.authenticated || session.initialize()).also { if (it) saveManagedToken(session.profile.token) }
            }
            val loggedIn = result.getOrDefault(false)
            rebuildNavigation(loggedIn)
            showSelected()
            result.exceptionOrNull()?.let { content.toast(it.message ?: getString(R.string.login_failed)) }
        }
        if (savedInstanceState?.getBoolean("appearance_open") == true) root.post { showAppearanceSettings() }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt(STATE_SELECTED, selected)
        outState.putBoolean("appearance_open", appearanceOpen)
        outState.putString("token_draft", tokenDraft)
        super.onSaveInstanceState(outState)
    }

    override fun onRetainCustomNonConfigurationInstance(): Any? = networkScreen?.snapshot() ?: retainedNetwork

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
                alive -> currentState.ifBlank { "正在连接服务器" }
                desired && transitionInProgress -> currentState
                desired -> "正在恢复核心"
                else -> "已停止"
            }
            prefs.edit().putString(OpenP2PService.KEY_STATE, state).apply()
            Logger.i("MainActivity", "前台核心状态检查：$state")
            if (desired || !homeBusy) homeBusy = false
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
        rebuildingNavigation = true
        val old = if (managed != managedNavigation) HOME else selected
        managedNavigation = managed
        pager.adapter?.notifyDataSetChanged()
        miniBar.layoutParams.width = dp(minOf(resources.configuration.screenWidthDp - 32, if (managed) 352 else 224))
        miniBar.requestLayout()
        navigation.menu.clear()
        navigation.menu.add(0, HOME, 0, R.string.nav_home).setIcon(R.drawable.ic_home)
        if (managed) {
            navigation.menu.add(0, DEVICES, 1, R.string.nav_devices).setIcon(R.drawable.ic_devices)
            navigation.menu.add(0, NETWORK, 2, R.string.nav_network).setIcon(R.drawable.ic_hotspot)
        }
        navigation.menu.add(0, LOGS, 3, R.string.nav_logs).setIcon(R.drawable.ic_logs)
        selected = if (navigation.menu.findItem(old) != null) old else HOME
        navigation.selectedItemId = selected
        pager.setCurrentItem(tabIds().indexOf(selected).coerceAtLeast(0), false)
        rebuildingNavigation = false
        navigation.itemIconTintList = AppearancePreferences.navigationTint(this)
        navigation.itemTextColor = AppearancePreferences.navigationTint(this)
    }

    private fun showSelected() {
        content = pageHosts.getOrPut(selected) { FrameLayout(this) }
        logHandler.removeCallbacksAndMessages(null)
        when (selected) {
            HOME -> showHome()
            DEVICES -> {
                val screen = deviceScreen ?: DeviceScreen(this, session).also { deviceScreen = it }
                setPage(screen.view)
            }
            NETWORK -> {
                val screen = networkScreen ?: NetworkScreen(this, session, retainedNetwork).also { networkScreen = it }
                setPage(screen.view)
            }
            LOGS -> showLogs()
        }
    }

    private fun setPage(view: View) {
        (view.parent as? android.view.ViewGroup)?.removeView(view)
        content.removeAllViews()
        content.addView(view, FrameLayout.LayoutParams(-1, -1))
    }

    private fun showHome() {
        (content.getChildAt(0)?.findViewWithTag<View>("home_scroll") as? ScrollView)?.let { homeScrollY = it.scrollY }
        val (page, body) = page(
            getString(R.string.app_name),
            R.drawable.ic_settings,
            getString(R.string.settings),
            getString(R.string.home_subtitle)
        ) { showSettings() }
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        val rawState = prefs.getString(OpenP2PService.KEY_STATE, "").orEmpty()
        val desired = prefs.getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
        val hasError = rawState.contains("error", true) || rawState.contains("fail", true) ||
            rawState.contains("异常") || rawState.contains("失败") || rawState.contains("未运行") || rawState.contains("恢复已达")
        val connected = desired && rawState == "核心运行中"
        val recovering = rawState.contains("正在恢复") || rawState.contains("等待恢复")
        val connecting = !recovering && (rawState.contains("正在启动") || rawState.contains("正在连接") ||
            (homeBusy && !desired))
        val stopping = rawState == "正在停止"
        val transitioning = connecting || recovering || stopping
        val heroStatus = when {
            hasError -> AppStatus.ERROR
            transitioning -> AppStatus.INFO
            connected -> AppStatus.SUCCESS
            else -> AppStatus.NEUTRAL
        }
        val heroTitle = getString(when {
            hasError -> R.string.status_error
            stopping -> R.string.status_stopping
            recovering -> R.string.status_recovering
            connecting -> R.string.status_connecting
            connected -> R.string.status_running
            desired -> R.string.status_connecting
            else -> R.string.status_stopped
        })
        val heroDescription = getString(when {
            hasError -> R.string.connection_failed_hint
            stopping -> R.string.connection_stopping_hint
            recovering -> R.string.connection_recovering_hint
            connecting -> R.string.connection_starting_hint
            connected -> R.string.connection_established
            desired -> R.string.connection_starting_hint
            else -> R.string.connection_stopped_hint
        })
        val statusCard = card {
            val header = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            header.addView(TextView(context).apply {
                text = if (connected) "✓" else if (hasError) "×" else "○"
                textSize = 30f
                gravity = Gravity.CENTER
                setTextColor(context.color(heroStatus.color))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(44), dp(44)).apply { rightMargin = dp(16) })
            val summary = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            summary.addView(TextView(context).apply {
                text = heroTitle
                textSize = 19f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(context.color(R.color.text_primary))
            })
            summary.label(heroDescription, true)
            header.addView(summary, LinearLayout.LayoutParams(0, -2, 1f))
            addView(header)
        }

        val configurationCard = card {
            label(getString(R.string.configuration_overview)).apply {
                textSize = 18f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }
            val token = coreToken(prefs)
            val vpnPermissionRequired = prefs.getBoolean(OpenP2PService.KEY_VPN_PERMISSION_REQUIRED, false)
            keyValue(getString(R.string.token_source), getString(when {
                session.authenticated -> R.string.token_source_account
                token.isNotBlank() -> R.string.token_source_local
                else -> R.string.token_source_missing
            }))
            keyValue(
                getString(R.string.virtual_network_status),
                getString(when {
                    hasError -> R.string.virtual_network_error
                    !desired -> R.string.status_stopped
                    prefs.getString(OpenP2PService.KEY_TUN_STATE, "") == "虚拟网络运行中" -> R.string.virtual_network_ready
                    else -> R.string.virtual_network_waiting
                })
            )
            if (vpnPermissionRequired) {
                secondaryAction(getString(R.string.reauthorize_vpn)) { requestStartCore() }
            }
        }
        if (resources.configuration.screenWidthDp >= 840) {
            body.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(statusCard, LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = dp(8) })
                addView(configurationCard, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
            })
        } else {
            body.addView(statusCard)
            body.addView(configurationCard, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        }

        if (!session.authenticated) {
            body.addView(card {
                label("Token").textSize = 16f
                label(getString(R.string.token_help), true)
                val saved = tokenDraft ?: coreToken(prefs)
                val token = field(getString(R.string.token_label), saved, numeric = true, password = true)
                (token.parent.parent as? com.google.android.material.textfield.TextInputLayout)?.isEnabled = !desired && !homeBusy
                token.addTextChangedListener(object : android.text.TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { tokenDraft = s?.toString() }
                    override fun afterTextChanged(s: android.text.Editable?) = Unit
                })
                secondaryAction(getString(R.string.save_token)) {
                    val value = token.text?.toString()?.trim().orEmpty()
                    val error = tokenValidationError(value)
                    if (error.isNotEmpty()) token.showError(error)
                    else {
                        token.showError(null)
                        saveManagedToken(value)
                        tokenDraft = value
                        page.snack(getString(R.string.token_saved))
                        showHome()
                    }
                }.isEnabled = !desired && !homeBusy
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(18) })
            body.secondaryAction(getString(R.string.login_management_account)) { showManagementAccount() }
        }
        val scroll = page.getChildAt(0) as ScrollView
        scroll.tag = "home_scroll"
        scroll.post { scroll.scrollTo(0, homeScrollY) }
        setPage(page)
        updateCoreToggle()
    }

    private fun toggleCoreFromMiniBar() {
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        val desired = prefs.getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
        if (homeBusy && !desired) return
        homeBusy = true
        if (desired) stopCore() else requestStartCore()
        updateCoreToggle()
        if (selected == HOME) showHome()
    }

    private fun updateCoreToggle(desiredOverride: Boolean? = null) {
        if (!::coreButton.isInitialized) return
        val running = desiredOverride ?: getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
            .getBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
        coreButton.icon = ContextCompat.getDrawable(this, if (running) R.drawable.ic_pause else R.drawable.ic_play)
        coreButton.iconTint = android.content.res.ColorStateList.valueOf(
            color(if (running) R.color.brand_on_primary else R.color.text_primary)
        )
        coreButton.backgroundTintList = android.content.res.ColorStateList.valueOf(
            if (running) AppearancePreferences.color(this) else color(R.color.surface_card)
        )
        coreButton.strokeWidth = 0
        coreButton.strokeColor = android.content.res.ColorStateList.valueOf(color(R.color.border_default))
        coreButton.contentDescription = getString(if (running) R.string.stop_openp2p else R.string.start_openp2p)
        coreButton.isEnabled = !homeBusy || running
    }

    private fun requestStartCore() {
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        val token = if (session.authenticated) coreToken(prefs) else tokenDraft ?: coreToken(prefs)
        val error = tokenValidationError(token)
        if (error.isNotEmpty()) {
            homeBusy = false
            content.snack(error)
            if (selected == HOME) showHome()
            return
        }
        saveManagedToken(token)
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
                updateCoreToggle()
                if (selected == HOME) showHome()
            }
        }
    }

    private fun startCore() {
        getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE).edit()
            .putBoolean(OpenP2PService.KEY_DESIRED_RUNNING, true)
            .putString(OpenP2PService.KEY_STATE, "正在启动核心")
            .apply()
        updateCoreToggle(true)
        ContextCompat.startForegroundService(this, Intent(this, OpenP2PService::class.java).setAction(OpenP2PService.ACTION_START))
    }

    private fun stopCore() {
        getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE).edit()
            .putBoolean(OpenP2PService.KEY_DESIRED_RUNNING, false)
            .putString(OpenP2PService.KEY_STATE, "正在停止")
            .apply()
        updateCoreToggle(false)
        startService(Intent(this, OpenP2PService::class.java).setAction(OpenP2PService.ACTION_STOP))
    }

    private fun saveManagedToken(token: String) {
        val prefs = getSharedPreferences(OpenP2PService.PREFERENCES, MODE_PRIVATE)
        secureStore.putString(SecureCredentialStore.CORE_TOKEN, token)
        tokenDraft = token
        if (prefs.contains(OpenP2PService.KEY_TOKEN)) prefs.edit().remove(OpenP2PService.KEY_TOKEN).apply()
    }

    private fun coreToken(preferences: android.content.SharedPreferences): String =
        secureStore.migrateLegacy(preferences, OpenP2PService.KEY_TOKEN, SecureCredentialStore.CORE_TOKEN)

    private fun showLogs() {
        val (page, body) = page(getString(R.string.nav_logs), subtitle = getString(R.string.logs_subtitle), scrollHeader = false)
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val export = MaterialButton(this).apply { text = getString(R.string.export_logs); minWidth = 0 }
        controls.addView(export); body.addView(controls)
        val logScroll = ScrollView(this)
        val text = TextView(this).apply {
            textSize = 12f
            setTextColor(color(R.color.log_text))
            setBackgroundColor(color(R.color.log_surface))
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        logScroll.addView(text)
        val logHeight = (resources.configuration.screenHeightDp - 260).coerceAtLeast(120)
        body.addView(logScroll, LinearLayout.LayoutParams(-1, dp(logHeight)))
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
                val latest = Logger.currentSession().lineSequence().filter { it.isNotBlank() }.toList().takeLast(500).joinToString("\n")
                if (latest != previous) {
                    val styled = android.text.SpannableString(latest)
                    Regex("(?im)^.*error.*$").findAll(latest).forEach { match ->
                        styled.setSpan(android.text.style.ForegroundColorSpan(color(R.color.log_error)),
                            match.range.first, match.range.last + 1, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                    text.text = styled
                    previous = latest
                    logScroll.post { logScroll.fullScroll(View.FOCUS_DOWN) }
                }
                if (latest.isBlank()) {
                    text.text = "${getString(R.string.logs_empty)}\n\n${getString(R.string.logs_empty_description)}"
                    text.setTextColor(color(R.color.text_secondary))
                    text.setBackgroundColor(color(R.color.surface_page))
                    text.gravity = Gravity.CENTER_HORIZONTAL
                } else {
                    text.setTextColor(color(R.color.log_text))
                    text.setBackgroundColor(color(R.color.log_surface))
                    text.gravity = Gravity.START
                }
                logHandler.postDelayed(this, 1000)
            }
        }
        update.run()
        setPage(page)
    }

    private fun showSettings() {
        bottomSheet(getString(R.string.settings), large = true) { _ ->
            fun settingsCard(title: String, subtitle: String? = null, icon: Int = R.drawable.ic_settings, action: () -> Unit): MaterialCardView = card {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(androidx.appcompat.widget.AppCompatImageView(context).apply {
                    setImageResource(icon)
                    setColorFilter(AppearancePreferences.color(context))
                    setPadding(dp(10), dp(10), dp(10), dp(10))
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(AppearancePreferences.softColor(context)); cornerRadius = dp(12).toFloat()
                    }
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(44), dp(44)).apply { rightMargin = dp(14) })
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    label(title).textSize = 17f
                    if (!subtitle.isNullOrBlank()) label(subtitle, true)
                }, LinearLayout.LayoutParams(0, -2, 1f))
                addView(TextView(context).apply { text = "›"; textSize = 24f; setTextColor(color(R.color.text_secondary)) })
                setOnClickListener { action() }
            }
            addView(settingsCard(
                getString(R.string.management_account),
                if (session.username.isNotBlank()) "${session.username} · ${getString(if (session.authenticated) R.string.account_signed_in else R.string.account_signed_out)}" else getString(R.string.account_description),
                android.R.drawable.ic_menu_myplaces
            ) { showManagementAccount() })
            addView(settingsCard(
                getString(R.string.background_keep_alive),
                getString(R.string.android_background_keep_alive_description), android.R.drawable.ic_lock_lock
            ) { showBackgroundHelp() }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
            addView(settingsCard(getString(R.string.appearance_settings)) {
                showAppearanceSettings()
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
            addView(settingsCard(getString(R.string.about), getString(R.string.about_information), android.R.drawable.ic_dialog_info) {
                showAbout()
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        }
    }

    private fun showManagementAccount() {
        bottomSheet(getString(R.string.management_account)) { dialog ->
            if (session.authenticated) {
                keyValue(getString(R.string.account_label), session.profile.user.ifBlank { session.username })
                val emailValue = session.profile.email.trim()
                keyValue(getString(R.string.email), maskedEmail(emailValue)).apply {
                    if (emailValue.isNotBlank()) setOnClickListener {
                        (getChildAt(1) as? TextView)?.text = emailValue
                    }
                }
                val phoneValue = session.profile.phone.trim()
                keyValue(getString(R.string.phone), maskedContact(phoneValue)).apply {
                    if (phoneValue.isNotBlank()) setOnClickListener {
                        (getChildAt(1) as? TextView)?.text = phoneValue
                    }
                }
                keyValue(getString(R.string.registration_time), session.profile.addTime.ifBlank { getString(R.string.unknown_value) })
                label(getString(R.string.token_locked_by_login), true)
                destructiveAction(getString(R.string.sign_out)) {
                    context.confirm(getString(R.string.sign_out), getString(R.string.sign_out_confirm), getString(R.string.sign_out), true) {
                        lifecycleScope.launch {
                            session.logout()
                            deviceScreen = null
                            networkScreen = null
                            retainedNetwork = null
                            selected = HOME
                            rebuildNavigation(false)
                            dialog.dismiss()
                            showHome()
                        }
                    }
                }
            } else {
                val user = field(getString(R.string.username), session.username)
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
                            showHome()
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
        bottomSheet(getString(R.string.register_title), large = true) { dialog ->
            label(getString(R.string.register_description), true)
            val user = field(getString(R.string.username_minimum))
            val password = field(getString(R.string.password_minimum), password = true)
            val confirmation = field(getString(R.string.confirm_password), password = true)
            val phone = field(getString(R.string.phone_optional)).apply { inputType = android.text.InputType.TYPE_CLASS_PHONE }
            val email = field(getString(R.string.email_recovery_hint)).apply {
                inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            }
            val agreement = CheckBox(context).apply {
                text = getString(R.string.agree_user_agreement)
                setTextColor(color(R.color.text_primary))
                AppearancePreferences.tint(this)
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
                        showHome()
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

    private fun maskedEmail(value: String): String {
        if (value.isBlank()) return getString(R.string.not_provided)
        val at = value.indexOf('@')
        if (at < 0) return maskedContact(value)
        val local = value.substring(0, at)
        val domain = value.substring(at)
        return when (local.length) {
            0, 1 -> "***$domain"
            2 -> "${local.take(1)}***$domain"
            else -> "${local.take(1)}***${local.takeLast(1)}$domain"
        }
    }

    private fun maskedContact(value: String): String = when {
        value.isBlank() -> getString(R.string.not_provided)
        value.length <= 4 -> "****"
        value.length <= 7 -> "${value.take(2)}***${value.takeLast(2)}"
        else -> "${value.take(3)}****${value.takeLast(4)}"
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

    private fun showAppearanceSettings() {
        appearanceOpen = true
        bottomSheet(getString(R.string.appearance_settings), large = true) { _ ->
            sectionHeader(getString(R.string.dark_mode))
            val modeLabels = listOf(getString(R.string.follow_system), getString(R.string.always_dark), getString(R.string.always_light))
            val modeValues = listOf(AppearancePreferences.MODE_SYSTEM, AppearancePreferences.MODE_DARK, AppearancePreferences.MODE_LIGHT)
            modeValues.forEachIndexed { index, mode ->
                addView(android.widget.RadioButton(context).apply {
                    text = modeLabels[index]
                    isChecked = mode == AppearancePreferences.mode(context)
                    minHeight = dp(48)
                    AppearancePreferences.tint(this)
                    setOnClickListener {
                        appearanceOpen = true
                        AppearancePreferences.setMode(this@MainActivity, modeValues[index])
                    }
                })
            }
            sectionHeader(getString(R.string.theme_color))
            val colors = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
            AppearancePreferences.colors.forEach { hex ->
                colors.addView(MaterialButton(context).apply {
                    minWidth = dp(48); minimumWidth = dp(48); minHeight = dp(48)
                    cornerRadius = dp(24); text = ""
                    setPadding(0, 0, 0, 0)
                    backgroundTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.parseColor(hex))
                    strokeWidth = if (AppearancePreferences.colorHex(context) == hex) dp(3) else 0
                    strokeColor = android.content.res.ColorStateList.valueOf(color(R.color.surface_card))
                    contentDescription = hex
                    setOnClickListener {
                        AppearancePreferences.setColor(this@MainActivity, hex)
                        appearanceOpen = true
                        recreate()
                    }
                }, LinearLayout.LayoutParams(dp(48), dp(48)).apply { leftMargin = dp(3); rightMargin = dp(3) })
            }
            addView(android.widget.HorizontalScrollView(context).apply {
                isHorizontalScrollBarEnabled = false
                isFillViewport = true
                addView(colors)
            }, LinearLayout.LayoutParams(-1, dp(48)))
        }.setOnDismissListener { appearanceOpen = false }
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
        bottomSheet(getString(R.string.about), large = true) { _ ->
            addView(android.widget.ImageView(context).apply { setImageResource(R.mipmap.ic_launcher); contentDescription = null },
                LinearLayout.LayoutParams(dp(80), dp(80)).apply { gravity = Gravity.CENTER_HORIZONTAL })
            label(getString(R.string.app_name)).apply { gravity = Gravity.CENTER; textSize = 24f }
            label(getString(R.string.android_native_client), true).gravity = Gravity.CENTER
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            keyValue(getString(R.string.app_version), packageInfo.versionName ?: getString(R.string.unknown_value))
            keyValue(getString(R.string.device_display_name), DeviceNameResolver.resolve(this@MainActivity))
            keyValue(getString(R.string.software_source), "OpenP2P").setOnClickListener { openAgreement("https://github.com/openp2p-cn/openp2p") }
            keyValue(getString(R.string.harmony_author), "Guailoudou").setOnClickListener { openAgreement("https://github.com/Guailoudou") }
            label(getString(R.string.open_source_description), true)
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
