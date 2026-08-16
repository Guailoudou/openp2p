package cn.openp2p.ui

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.Menu
import android.view.View
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.appcompat.widget.PopupMenu
import androidx.lifecycle.lifecycleScope
import androidx.core.view.ViewCompat
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import cn.openp2p.R
import cn.openp2p.management.Device
import cn.openp2p.management.ManagementSession
import cn.openp2p.management.SdwanConfig
import cn.openp2p.management.SdwanMember
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import kotlinx.coroutines.launch
import org.json.JSONObject

class NetworkScreen(private val activity: MainActivity, private val session: ManagementSession) {
    val view: View
    private val swipe = SwipeRefreshLayout(activity)
    private val body = LinearLayout(activity)
    private var config = SdwanConfig()
    private var devices: List<Device> = emptyList()
    private var firstLoad = true
    private var errorMessage: String? = null
    private val memberIpViews = mutableMapOf<String, TextView>()
    private var refreshSequence = 0
    private var activeRefreshId = 0

    private fun tunnelStatus(value: JSONObject): Pair<String, AppStatus> = when {
        !value.has("isActive") -> activity.getString(R.string.tunnel_offline) to AppStatus.NEUTRAL
        value.has("enabled") && value.optInt("enabled", 1) != 1 -> activity.getString(R.string.tunnel_disabled) to AppStatus.NEUTRAL
        value.optInt("isActive") != 1 && value.optString("error").isNotBlank() -> activity.getString(R.string.tunnel_failed) to AppStatus.ERROR
        value.optInt("isActive") != 1 -> activity.getString(R.string.tunnel_connecting) to AppStatus.WARNING
        value.optString("relayMode") == "public" -> activity.getString(R.string.tunnel_relay) to AppStatus.INFO
        value.optString("relayMode") == "private" -> activity.getString(R.string.tunnel_private_relay) to AppStatus.INFO
        value.optString("linkMode") == "ipv6" -> activity.getString(R.string.tunnel_direct_ipv6) to AppStatus.SUCCESS
        value.optString("linkMode") == "intranet" -> activity.getString(R.string.tunnel_direct_intranet) to AppStatus.SUCCESS
        else -> activity.getString(R.string.tunnel_direct) to AppStatus.SUCCESS
    }

    init {
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(activity.color(R.color.surface_page))
        }
        val header = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        header.addView(TextView(activity).apply {
            text = activity.getString(R.string.nav_network)
            textSize = 28f
            setTextColor(activity.color(R.color.text_primary))
            setTypeface(typeface, Typeface.BOLD)
            setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(20), activity.dp(16), 0)
        })
        header.addView(TextView(activity).apply {
            text = activity.getString(R.string.network_subtitle)
            textSize = 14f
            setTextColor(activity.color(R.color.text_secondary))
            setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(4), activity.dp(16), activity.dp(12))
        })
        root.addView(activity.centered(header))
        body.orientation = LinearLayout.VERTICAL
        body.setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), 0, activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(32))
        swipe.setColorSchemeColors(activity.color(R.color.brand_primary))
        swipe.addView(ScrollView(activity).apply { addView(body) })
        swipe.setOnRefreshListener { load() }
        root.addView(activity.centered(swipe, fillHeight = true), LinearLayout.LayoutParams(-1, 0, 1f))
        view = root
        render()
        load()
    }

    private fun load() {
        val manualRefresh = !firstLoad
        if (manualRefresh) swipe.isRefreshing = true
        val refreshId = ++refreshSequence
        activeRefreshId = refreshId
        swipe.postDelayed({
            if (activeRefreshId != refreshId) return@postDelayed
            activeRefreshId = 0
            firstLoad = false
            if (!manualRefresh) errorMessage = activity.getString(R.string.refresh_timeout)
            swipe.isRefreshing = false
            render()
            swipe.snack(activity.getString(R.string.refresh_timeout))
        }, 5_000)
        activity.lifecycleScope.launch {
            try {
                val loadedConfig = session.api.sdwan()
                val loadedDevices = session.api.devices().nodes
                if (activeRefreshId != refreshId) return@launch
                config = loadedConfig
                devices = loadedDevices
                errorMessage = null
                swipe.isRefreshing = false
            } catch (e: Exception) {
                if (activeRefreshId != refreshId) return@launch
                errorMessage = e.message ?: activity.getString(R.string.load_failed)
                if (!manualRefresh) swipe.isRefreshing = false
            }
            if (activeRefreshId != refreshId) return@launch
            activeRefreshId = 0
            firstLoad = false
            render()
        }
    }

    private fun render() {
        body.removeAllViews()
        memberIpViews.clear()
        if (firstLoad) { body.loadingState(); return }
        errorMessage?.let { body.errorState(it) { load() }; return }
        var gatewayInput: TextInputEditText? = null
        val settingsCard = activity.card {
            label(activity.getString(R.string.network_settings)).apply {
                textSize = 18f
                setTypeface(typeface, Typeface.BOLD)
            }
            gatewayInput = field(activity.getString(R.string.network_address), config.gateway)
            gatewayInput?.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
                override fun afterTextChanged(s: Editable?) {
                    updateMemberGateway(config, s?.toString()?.trim().orEmpty())
                }
            })

            val modeRow = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
            fun modeButton(text: String, value: String): MaterialButton = MaterialButton(activity).apply {
                this.text = text
                minHeight = activity.dp(48)
                cornerRadius = activity.dp(12)
                val selected = config.mode == value
                setTextColor(activity.color(if (selected) R.color.brand_on_primary else R.color.text_primary))
                backgroundTintList = ColorStateList.valueOf(activity.color(if (selected) R.color.brand_primary else R.color.surface_subtle))
                setOnClickListener {
                    if (config.mode != value) {
                        config.mode = value
                        render()
                    }
                }
            }
            modeRow.addView(modeButton(activity.getString(R.string.network_mode_fullmesh), "fullmesh"),
                LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = activity.dp(4) })
            modeRow.addView(modeButton(activity.getString(R.string.network_mode_central), "central"),
                LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = activity.dp(4) })
            addView(modeRow, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(12) })

            val nodeLabel = activity.getString(if (config.mode == "central") R.string.central_node else R.string.specified_relay_node)
            secondaryAction("$nodeLabel · ${config.centralNode.ifBlank { activity.getString(R.string.not_specified) }}") {
                val options = listOf<String?>(null) + config.nodes.map { it.name }.distinct()
                activity.wheelPicker(nodeLabel, options.map { it ?: activity.getString(R.string.not_specified) },
                    options.indexOf(config.centralNode.ifBlank { null }).coerceAtLeast(0)) { index ->
                    config.centralNode = options[index].orEmpty()
                    render()
                }
            }
            if (config.mode != "central") {
                addView(Switch(activity).apply {
                    text = activity.getString(R.string.force_relay)
                    textSize = 16f
                    isChecked = config.forceRelay == 1
                    minHeight = activity.dp(48)
                    AppearancePreferences.tint(this)
                    setOnCheckedChangeListener { _, checked -> config.forceRelay = if (checked) 1 else 0 }
                })
            }
            val priorities = activity.punchPriorityOptions()
            val selectedPriority = config.punchPriority.coerceIn(0, priorities.lastIndex)
            secondaryAction("${activity.getString(R.string.punch_priority)} · ${priorities[selectedPriority]}") {
                activity.wheelPicker(activity.getString(R.string.punch_priority), priorities, selectedPriority) { index ->
                    config.punchPriority = index
                    render()
                }
            }
        }

        val membersCard = activity.card {
            label(activity.getString(R.string.network_members)).apply {
                textSize = 18f
                setTypeface(typeface, Typeface.BOLD)
            }
            if (config.nodes.isEmpty()) {
                label(activity.getString(R.string.no_members), true).apply {
                    setPadding(0, activity.dp(12), 0, activity.dp(12))
                }
            }
            config.nodes.forEach { member ->
                val device = devices.firstOrNull { it.name == member.name }
                val memberCard = activity.card {
                    val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                    header.addView(TextView(activity).apply {
                        text = member.name; textSize = 16f; setTypeface(typeface, Typeface.BOLD); setTextColor(activity.color(R.color.text_primary))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                    header.addView(activity.statusChip(activity.getString(if (device?.active == true) R.string.online else R.string.offline), if (device?.active == true) AppStatus.SUCCESS else AppStatus.NEUTRAL))
                    addView(header)
                    label(member.ip, true).apply {
                        typeface = Typeface.MONOSPACE
                        memberIpViews[member.name] = this
                    }
                    if (member.resource.isNotBlank()) label(member.resource, true)
                    minimumHeight = activity.dp(72)
                    setOnClickListener { editMember(member) }
                    setOnLongClickListener { anchor -> showMemberMenu(anchor, member); true }
                }
                addView(activity.swipeActions(memberCard, memberSwipeActions(member)) { swiping ->
                    swipe.isEnabled = !swiping
                }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(8) })
            }
        }
        if (activity.resources.configuration.screenWidthDp >= 840) {
            body.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(settingsCard, LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = activity.dp(8) })
                addView(membersCard, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = activity.dp(8) })
            }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(16) })
        } else {
            body.addView(settingsCard, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(16) })
            body.addView(membersCard, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(16) })
        }

        val available = availableDevices()
        if (available.isNotEmpty()) {
            body.addView(activity.card {
                label(activity.getString(R.string.available_devices)).apply {
                    textSize = 18f
                    setTypeface(typeface, Typeface.BOLD)
                }
                label(activity.resources.getQuantityString(R.plurals.available_device_count, available.size, available.size), true)
                action(activity.getString(R.string.select_device)) { chooseAvailableDevice() }
            }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(16) })
        }
        val save = body.action(activity.getString(R.string.save_network_config)) {}
        save.setOnClickListener {
            when {
                !isCidr(config.gateway) -> gatewayInput?.showError(activity.getString(R.string.network_address_invalid))
                config.mode == "central" && config.centralNode.isBlank() -> view.snack(activity.getString(R.string.central_node_required))
                else -> persistConfig(config.snapshot(), save) { load() }
            }
        }
    }

    private fun memberSwipeActions(member: SdwanMember): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        fun addAction(label: String, color: Int, action: () -> Unit) {
            addView(MaterialButton(activity).apply {
                text = label
                minWidth = activity.dp(72)
                minimumWidth = activity.dp(72)
                setTextColor(Color.WHITE)
                backgroundTintList = ColorStateList.valueOf(activity.color(color))
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(activity.dp(76), -1))
        }
        addAction(activity.getString(R.string.edit), R.color.brand_primary) { editMember(member) }
        addAction(activity.getString(R.string.remove), R.color.state_error) { requestRemoveMember(member) }
    }

    private fun showMemberMenu(anchor: View, member: SdwanMember) {
        PopupMenu(activity, anchor).apply {
            menu.add(Menu.NONE, 1, 0, R.string.edit)
            menu.add(Menu.NONE, 2, 1, R.string.remove_from_network)
            setOnMenuItemClickListener {
                when (it.itemId) {
                    1 -> editMember(member)
                    2 -> requestRemoveMember(member)
                }
                true
            }
            show()
        }
    }

    private fun requestRemoveMember(member: SdwanMember) {
        activity.confirm(activity.getString(R.string.remove_from_network),
            activity.getString(R.string.remove_member_confirm, member.name), activity.getString(R.string.remove), true) {
            val previous = config.snapshot()
            config.nodes.removeAll { it.name == member.name }
            if (config.centralNode == member.name) config.centralNode = ""
            render()
            persistConfig(config.snapshot(), null, failed = {
                config = previous
                render()
            }) { load() }
        }
    }

    private fun editNetworkConfig() {
        val draft = config.copy(nodes = config.nodes.map { it.copy() }.toMutableList())
        activity.bottomSheet(activity.getString(R.string.edit_network_config)) { dialog ->
            val gateway = field(activity.getString(R.string.network_address), draft.gateway)
            sectionHeader(activity.getString(R.string.network_mode))
            val mode = RadioGroup(activity).apply { orientation = RadioGroup.VERTICAL }
            val full = RadioButton(activity).apply { text = activity.getString(R.string.network_mode_fullmesh); id = ViewCompat.generateViewId(); minHeight = activity.dp(48); AppearancePreferences.tint(this) }
            val central = RadioButton(activity).apply { text = activity.getString(R.string.network_mode_central); id = ViewCompat.generateViewId(); minHeight = activity.dp(48); AppearancePreferences.tint(this) }
            mode.addView(full); mode.addView(central)
            mode.check(if (draft.mode == "central") central.id else full.id)
            addView(mode)
            var centralNode = draft.centralNode
            val centralButton = secondaryAction("") {}
            sectionHeader(activity.getString(R.string.force_relay))
            val relay = Switch(activity).apply { text = activity.getString(R.string.force_relay); textSize = 16f; isChecked = draft.forceRelay != 0; minHeight = activity.dp(48); AppearancePreferences.tint(this) }
            addView(relay)
            fun updateModeControls() {
                val label = activity.getString(
                    if (mode.checkedRadioButtonId == central.id) R.string.central_node else R.string.specified_relay_node
                )
                centralButton.text = "$label · ${centralNode.ifBlank { activity.getString(R.string.not_specified) }}"
                relay.visibility = if (mode.checkedRadioButtonId == central.id) View.GONE else View.VISIBLE
            }
            centralButton.setOnClickListener {
                val options = listOf<String?>(null) + draft.nodes.map { it.name }.distinct()
                val label = activity.getString(
                    if (mode.checkedRadioButtonId == central.id) R.string.central_node else R.string.specified_relay_node
                )
                activity.wheelPicker(label, options.map { it ?: activity.getString(R.string.not_specified) }, options.indexOf(centralNode.ifBlank { null }).coerceAtLeast(0)) {
                    centralNode = options[it].orEmpty()
                    centralButton.text = "$label · ${centralNode.ifBlank { activity.getString(R.string.not_specified) }}"
                }
            }
            mode.setOnCheckedChangeListener { _, _ -> updateModeControls() }
            updateModeControls()
            val priorities = activity.punchPriorityOptions()
            var priority = draft.punchPriority.coerceIn(0, priorities.lastIndex)
            val priorityButton = secondaryAction("${activity.getString(R.string.punch_priority)} · ${priorities[priority]}") {}
            priorityButton.setOnClickListener { activity.wheelPicker(activity.getString(R.string.punch_priority), priorities, priority) { priority = it; priorityButton.text = "${activity.getString(R.string.punch_priority)} · ${priorities[it]}" } }
            val save = action(activity.getString(R.string.save_network_config)) {}
            save.setOnClickListener {
                val address = gateway.text?.toString()?.trim().orEmpty()
                if (address.isBlank()) { gateway.showError(activity.getString(R.string.network_address_required)); return@setOnClickListener }
                if (!isCidr(address)) { gateway.showError(activity.getString(R.string.network_address_invalid)); return@setOnClickListener }
                val centralMode = mode.checkedRadioButtonId == central.id
                if (centralMode && centralNode.isBlank()) { view.snack(activity.getString(R.string.central_node_required)); return@setOnClickListener }
                updateMemberGateway(draft, address)
                draft.mode = if (centralMode) "central" else "fullmesh"
                draft.centralNode = centralNode
                draft.forceRelay = if (relay.isChecked) 1 else 0
                draft.punchPriority = priority
                persistConfig(draft.snapshot(), save) {
                    config = draft
                    dialog.dismiss()
                    load()
                }
            }
        }
    }

    private fun chooseAvailableDevice() {
        val options = availableDevices()
        if (options.isEmpty()) { view.snack(activity.getString(R.string.no_eligible_device)); return }
        activity.wheelPicker(activity.getString(R.string.add_device), options.map { it.remark.ifBlank { it.name } }) { index ->
            val device = options[index]
            val address = nextAvailableAddress(config)
            if (address.isBlank()) { view.toast(activity.getString(R.string.no_available_virtual_ip)); return@wheelPicker }
            val member = SdwanMember(device.name, address, active = device.active)
            config.nodes += member
            editMember(member, true)
        }
    }

    private fun editMember(member: SdwanMember, isNew: Boolean = false) {
        val originalIp = member.ip
        val originalResource = member.resource
        activity.bottomSheet(activity.getString(R.string.network_member)) { dialog ->
            label(member.name)
            val ip = field(activity.getString(R.string.virtual_ip), member.ip)
            val resources = field(activity.getString(R.string.resources), member.resource)
            val status = label("", true)
            val tunnels = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            addView(tunnels)
            val loadStatus: () -> Unit = {
                val device = devices.firstOrNull { it.name == member.name }
                tunnels.removeAllViews()
                if (device == null) {
                    status.text = activity.getString(R.string.device_offline)
                    status.setTextColor(activity.color(R.color.state_warning))
                } else activity.lifecycleScope.launch {
                    try {
                        val result = session.api.memberStatus(device)
                        val error = result.optString("tunError")
                        status.text = if (error.isBlank()) activity.getString(R.string.node_healthy)
                        else activity.getString(R.string.tun_error, error)
                        status.setTextColor(activity.color(if (error.isBlank()) R.color.state_success else R.color.state_error))
                        val apps = result.optJSONArray("Apps")
                        if (apps != null && apps.length() > 0) {
                            tunnels.sectionHeader(activity.getString(R.string.member_tunnels), apps.length().toString())
                            for (index in 0 until apps.length()) {
                                val tunnel = apps.optJSONObject(index) ?: continue
                                tunnels.addView(activity.card {
                                    val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                                    header.addView(TextView(activity).apply {
                                        text = tunnel.optString("peerNode").ifBlank { activity.getString(R.string.unknown_device) }
                                        textSize = 15f
                                        setTypeface(typeface, Typeface.BOLD)
                                        setTextColor(activity.color(R.color.text_primary))
                                    }, LinearLayout.LayoutParams(0, -2, 1f))
                                    val state = tunnelStatus(tunnel)
                                    header.addView(activity.statusChip(state.first, state.second))
                                    addView(header)
                                    val tunnelError = tunnel.optString("error")
                                    if (tunnel.optInt("isActive") != 1 && tunnelError.isNotBlank()) {
                                        label(tunnelError, true).apply { setTextColor(activity.color(R.color.state_error)) }
                                    }
                                }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(8) })
                            }
                        }
                    } catch (e: Exception) {
                        status.text = if (device.active) {
                            e.message ?: activity.getString(R.string.check_failed)
                        } else {
                            activity.getString(R.string.device_offline)
                        }
                        status.setTextColor(activity.color(if (device.active) R.color.state_error else R.color.state_warning))
                    }
                }
            }
            secondaryAction(activity.getString(R.string.check_status)) { loadStatus() }
            val save = action(activity.getString(R.string.save_member)) {}
            save.setOnClickListener {
                val address = ip.text?.toString()?.trim().orEmpty()
                when {
                    !isIpv4(address) -> ip.showError(activity.getString(R.string.virtual_ip_invalid))
                    !isIpInCidr(address, config.gateway) -> ip.showError(activity.getString(R.string.virtual_ip_outside_network))
                    config.nodes.any { it !== member && it.ip == address } -> ip.showError(activity.getString(R.string.virtual_ip_conflict))
                    else -> {
                        member.ip = address
                        member.resource = resources.text?.toString()?.trim().orEmpty()
                        persistConfig(config.snapshot(), save, R.string.save_member, failed = {
                            member.ip = originalIp
                            member.resource = originalResource
                            if (isNew) config.nodes.remove(member)
                            render()
                        }) {
                            dialog.dismiss()
                            load()
                        }
                    }
                }
            }
            destructiveAction(activity.getString(R.string.remove_from_network)) {
                dialog.dismiss()
                requestRemoveMember(member)
            }
            dialog.setOnCancelListener {
                member.ip = originalIp
                member.resource = originalResource
                if (isNew) config.nodes.remove(member)
                render()
            }
            loadStatus()
        }
    }

    private fun SdwanConfig.snapshot() = copy(nodes = nodes.map { it.copy() }.toMutableList())

    private fun persistConfig(
        value: SdwanConfig,
        button: MaterialButton?,
        idleTextRes: Int = R.string.save_network_config,
        failed: (() -> Unit)? = null,
        complete: () -> Unit
    ) {
        val idleText = activity.getString(idleTextRes)
        button?.setLoading(true, idleText, activity.getString(R.string.please_wait))
        activity.lifecycleScope.launch {
            try {
                session.api.saveSdwan(value)
                value.nodes.mapNotNull { member ->
                    devices.firstOrNull { it.name == member.name && it.active && it.edgeServer.isNotBlank() }
                }
                    .forEach { session.api.refreshSdwanNode(it) }
                view.toast(activity.getString(R.string.network_saved))
                complete()
            } catch (e: Exception) {
                view.toast(e.message ?: activity.getString(R.string.operation_failed))
                failed?.invoke()
            } finally {
                button?.setLoading(false, idleText, activity.getString(R.string.please_wait))
            }
        }
    }

    private fun eligible(device: Device): Boolean = device.active && compareVersion(device.version, "3.13") >= 0

    private fun availableDevices(): List<Device> {
        val existing = config.nodes.map { it.name }.toSet()
        return devices.filter { eligible(it) && it.name !in existing }
    }

    private fun compareVersion(left: String, right: String): Int {
        val a = Regex("\\d+").findAll(left).map { it.value.toIntOrNull() ?: 0 }.toList()
        val b = Regex("\\d+").findAll(right).map { it.value.toIntOrNull() ?: 0 }.toList()
        for (i in 0 until maxOf(a.size, b.size)) {
            val result = a.getOrElse(i) { 0 }.compareTo(b.getOrElse(i) { 0 })
            if (result != 0) return result
        }
        return 0
    }

    private fun nextAvailableAddress(value: SdwanConfig): String {
        val base = value.gateway.substringBefore('/').split('.')
        if (base.size != 4) return ""
        val prefix = "${base[0]}.${base[1]}.${base[2]}"
        return (1..254).map { "$prefix.$it" }.firstOrNull { candidate -> value.nodes.none { it.ip == candidate } }.orEmpty()
    }

    private fun updateMemberGateway(value: SdwanConfig, gateway: String) {
        val base = gateway.substringBefore('/').split('.')
        if (base.size == 4) {
            val prefix = "${base[0]}.${base[1]}.${base[2]}"
            value.nodes.forEach { member ->
                member.ip.substringAfterLast('.', "").takeIf { it.isNotBlank() }?.let {
                    member.ip = "$prefix.$it"
                    memberIpViews[member.name]?.text = member.ip
                }
            }
        }
        value.gateway = gateway
    }

    private fun isIpv4(value: String): Boolean {
        val parts = value.split('.')
        return parts.size == 4 && parts.all {
            val number = it.toIntOrNull()
            number != null && number in 0..255
        }
    }

    private fun isCidr(value: String): Boolean {
        val parts = value.split('/')
        val prefix = parts.getOrNull(1)?.toIntOrNull()
        return parts.size == 2 && isIpv4(parts[0]) && prefix != null && prefix in 0..32
    }

    private fun isIpInCidr(ip: String, cidr: String): Boolean {
        if (!isIpv4(ip) || !isCidr(cidr)) return false
        val prefix = cidr.substringAfter('/').toInt()
        if (prefix == 0) return true
        fun ipv4Number(value: String): Long = value.split('.').fold(0L) { result, part ->
            (result shl 8) or part.toLong()
        }
        val mask = (0xffffffffL shl (32 - prefix)) and 0xffffffffL
        return (ipv4Number(ip) and mask) == (ipv4Number(cidr.substringBefore('/')) and mask)
    }

}
