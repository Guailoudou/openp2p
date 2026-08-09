package cn.openp2p.ui

import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import cn.openp2p.R
import cn.openp2p.management.Device
import cn.openp2p.management.ManagementSession
import cn.openp2p.management.SdwanConfig
import cn.openp2p.management.SdwanMember
import com.google.android.material.button.MaterialButton
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

    private fun tunnelStatus(value: JSONObject): Pair<String, AppStatus> = when {
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
        root.addView(TextView(activity).apply {
            text = activity.getString(R.string.nav_network)
            textSize = 28f
            setTextColor(activity.color(R.color.text_primary))
            setTypeface(typeface, Typeface.BOLD)
            setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(20), activity.dp(16), activity.dp(12))
        })
        body.orientation = LinearLayout.VERTICAL
        body.setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), 0, activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(32))
        swipe.setColorSchemeColors(activity.color(R.color.brand_primary))
        swipe.addView(ScrollView(activity).apply { addView(body) })
        swipe.setOnRefreshListener { load() }
        root.addView(swipe, LinearLayout.LayoutParams(-1, 0, 1f))
        view = root
        render()
        load()
    }

    private fun load() {
        if (!firstLoad) swipe.isRefreshing = true
        activity.lifecycleScope.launch {
            try {
                config = session.api.sdwan()
                devices = session.api.devices().nodes
                errorMessage = null
            } catch (e: Exception) {
                errorMessage = e.message ?: activity.getString(R.string.load_failed)
            } finally {
                firstLoad = false
                swipe.isRefreshing = false
                render()
            }
        }
    }

    private fun render() {
        body.removeAllViews()
        if (firstLoad) { body.loadingState(); return }
        errorMessage?.let { body.errorState(it) { load() }; return }
        body.sectionHeader(activity.getString(R.string.network_overview))
        body.addView(activity.card {
            keyValue(activity.getString(R.string.network_address), config.gateway.ifBlank { "--" }, true)
            keyValue(activity.getString(R.string.network_mode), activity.getString(if (config.mode == "central") R.string.network_mode_central else R.string.network_mode_fullmesh))
            keyValue(activity.getString(R.string.member_count), config.nodes.size.toString())
            keyValue(activity.getString(R.string.network_health), activity.getString(R.string.network_ready))
            action(activity.getString(R.string.edit_network_config)) { editNetworkConfig() }
        })

        body.sectionHeader(activity.getString(R.string.network_members), config.nodes.size.toString())
        if (config.nodes.isEmpty()) body.emptyState(activity.getString(R.string.network_members), activity.getString(R.string.no_members))
        config.nodes.forEach { member ->
            val device = devices.firstOrNull { it.name == member.name }
            body.addView(activity.card {
                val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                header.addView(TextView(activity).apply {
                    text = member.name; textSize = 16f; setTypeface(typeface, Typeface.BOLD); setTextColor(activity.color(R.color.text_primary))
                }, LinearLayout.LayoutParams(0, -2, 1f))
                header.addView(activity.statusChip(activity.getString(if (device?.active == true) R.string.online else R.string.offline), if (device?.active == true) AppStatus.SUCCESS else AppStatus.NEUTRAL))
                addView(header)
                label(member.ip, true).apply { typeface = Typeface.MONOSPACE }
                if (member.resource.isNotBlank()) label(member.resource, true)
                minimumHeight = activity.dp(72)
                setOnClickListener { editMember(member) }
            }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(12) })
        }
        body.secondaryAction(activity.getString(R.string.add_device)) { chooseAvailableDevice() }
        val save = body.action(activity.getString(R.string.save_network_config)) {}
        save.setOnClickListener {
            persistConfig(config.snapshot(), save) { load() }
        }
    }

    private fun editNetworkConfig() {
        val draft = config.copy(nodes = config.nodes.map { it.copy() }.toMutableList())
        activity.bottomSheet(activity.getString(R.string.edit_network_config)) { dialog ->
            val gateway = field(activity.getString(R.string.network_address), draft.gateway, helper = "IPv4 CIDR · 10.0.0.0/24")
            sectionHeader(activity.getString(R.string.network_mode))
            val mode = RadioGroup(activity).apply { orientation = RadioGroup.VERTICAL }
            val full = RadioButton(activity).apply { text = activity.getString(R.string.network_mode_fullmesh); id = View.generateViewId(); minHeight = activity.dp(48) }
            val central = RadioButton(activity).apply { text = activity.getString(R.string.network_mode_central); id = View.generateViewId(); minHeight = activity.dp(48) }
            mode.addView(full); mode.addView(central)
            mode.check(if (draft.mode == "central") central.id else full.id)
            addView(mode)
            var centralNode = draft.centralNode
            val centralButton = secondaryAction("") {}
            sectionHeader(activity.getString(R.string.force_relay))
            val relay = Switch(activity).apply { text = activity.getString(R.string.force_relay); textSize = 16f; isChecked = draft.forceRelay != 0; minHeight = activity.dp(48) }
            addView(relay)
            fun updateModeControls() {
                val label = activity.getString(
                    if (mode.checkedRadioButtonId == central.id) R.string.central_node else R.string.specified_relay_node
                )
                centralButton.text = "$label · ${centralNode.ifBlank { activity.getString(R.string.not_specified) }}"
                relay.visibility = if (mode.checkedRadioButtonId == central.id) View.GONE else View.VISIBLE
            }
            centralButton.setOnClickListener {
                val options = devices.filter { eligible(it) }
                val label = activity.getString(
                    if (mode.checkedRadioButtonId == central.id) R.string.central_node else R.string.specified_relay_node
                )
                activity.wheelPicker(label, options.map { it.remark.ifBlank { it.name } }, options.indexOfFirst { it.name == centralNode }.coerceAtLeast(0)) {
                    centralNode = options[it].name
                    centralButton.text = "$label · $centralNode"
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
                draft.gateway = address
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
        val existing = config.nodes.map { it.name }.toSet()
        val options = devices.filter { eligible(it) && it.name !in existing }
        if (options.isEmpty()) { view.snack(activity.getString(R.string.no_eligible_device)); return }
        activity.wheelPicker(activity.getString(R.string.add_device), options.map { it.remark.ifBlank { it.name } }) { index ->
            val device = options[index]
            val member = SdwanMember(device.name, nextAddress(config.gateway, config.nodes.size + 2))
            config.nodes += member
            editMember(member, true)
        }
    }

    private fun editMember(member: SdwanMember, isNew: Boolean = false) {
        val originalIp = member.ip
        val originalResource = member.resource
        activity.bottomSheet(activity.getString(R.string.network_member)) { dialog ->
            label(member.name)
            val ip = field(activity.getString(R.string.virtual_ip), member.ip, helper = "IPv4 · 10.0.0.2")
            val resources = field(activity.getString(R.string.resources), member.resource)
            val status = label("", true)
            val tunnels = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            addView(tunnels)
            val loadStatus: () -> Unit = {
                val device = devices.firstOrNull { it.name == member.name }
                tunnels.removeAllViews()
                if (device == null || !device.active) {
                    status.text = activity.getString(R.string.device_offline)
                    status.setTextColor(activity.color(R.color.state_warning))
                } else activity.lifecycleScope.launch {
                    try {
                        val result = session.api.memberStatus(device)
                        val error = result.optString("tunError")
                        status.text = if (error.isBlank()) activity.getString(R.string.node_healthy) else error
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
                                    val connectTime = tunnel.optString("connectTime")
                                    if (tunnel.optInt("isActive") == 1 && connectTime.isNotBlank()) {
                                        keyValue(activity.getString(R.string.connect_time), connectTime)
                                    }
                                    val tunnelError = tunnel.optString("error")
                                    if (tunnel.optInt("isActive") != 1 && tunnelError.isNotBlank()) {
                                        label(tunnelError, true).apply { setTextColor(activity.color(R.color.state_error)) }
                                    }
                                }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(8) })
                            }
                        }
                    } catch (e: Exception) {
                        status.text = e.message ?: activity.getString(R.string.check_failed)
                        status.setTextColor(activity.color(R.color.state_error))
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
                        persistConfig(config.snapshot(), save, R.string.save_member) {
                            dialog.dismiss()
                            load()
                        }
                    }
                }
            }
            destructiveAction(activity.getString(R.string.remove_from_network)) {
                activity.confirm(activity.getString(R.string.remove_from_network), activity.getString(R.string.remove_member_confirm, member.name), activity.getString(R.string.remove), true) {
                    config.nodes.remove(member)
                    dialog.dismiss()
                    persistConfig(config.snapshot(), null) { load() }
                }
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
        complete: () -> Unit
    ) {
        val idleText = activity.getString(idleTextRes)
        button?.setLoading(true, idleText, activity.getString(R.string.please_wait))
        activity.lifecycleScope.launch {
            try {
                session.api.saveSdwan(value)
                value.nodes.mapNotNull { member -> devices.firstOrNull { it.name == member.name && it.active } }
                    .forEach { session.api.refreshSdwanNode(it) }
                view.snack(activity.getString(R.string.network_saved))
                complete()
            } catch (e: Exception) {
                view.snack(e.message ?: activity.getString(R.string.operation_failed))
            } finally {
                button?.setLoading(false, idleText, activity.getString(R.string.please_wait))
            }
        }
    }

    private fun eligible(device: Device): Boolean = device.active && compareVersion(device.version, "3.13") >= 0

    private fun compareVersion(left: String, right: String): Int {
        val a = Regex("\\d+").findAll(left).map { it.value.toIntOrNull() ?: 0 }.toList()
        val b = Regex("\\d+").findAll(right).map { it.value.toIntOrNull() ?: 0 }.toList()
        for (i in 0 until maxOf(a.size, b.size)) {
            val result = a.getOrElse(i) { 0 }.compareTo(b.getOrElse(i) { 0 })
            if (result != 0) return result
        }
        return 0
    }

    private fun nextAddress(gateway: String, index: Int): String {
        val base = gateway.substringBefore('/').split('.')
        return if (base.size == 4) "${base[0]}.${base[1]}.${base[2]}.${index.coerceAtMost(254)}" else "10.0.0.${index.coerceAtMost(254)}"
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
