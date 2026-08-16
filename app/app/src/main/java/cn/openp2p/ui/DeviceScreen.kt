package cn.openp2p.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.Menu
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.appcompat.widget.PopupMenu
import androidx.lifecycle.lifecycleScope
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import cn.openp2p.R
import cn.openp2p.management.Device
import cn.openp2p.management.ManagementSession
import cn.openp2p.management.PortMapping
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.android.material.switchmaterial.SwitchMaterial
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DeviceScreen(private val activity: MainActivity, private val session: ManagementSession) {
    val view: View
    private val swipe = SwipeRefreshLayout(activity)
    private val list = LinearLayout(activity)
    private val title = TextView(activity)
    private var devices: List<Device> = emptyList()
    private var latestVersion = ""
    private var filter = FILTER_ALL
    private var firstLoad = true
    private var errorMessage: String? = null
    private var busyDevice: String? = null
    private var currentMappings: List<PortMapping> = emptyList()
    private var refreshSequence = 0
    private var activeRefreshId = 0

    init {
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(activity.color(R.color.surface_page))
        }
        val header = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        title.apply {
            text = activity.getString(R.string.devices_title_count, 0)
            textSize = 28f
            setTextColor(activity.color(R.color.text_primary))
            setTypeface(typeface, Typeface.BOLD)
            setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(20), activity.dp(16), activity.dp(8))
        }
        header.addView(title)
        val filters = ChipGroup(activity).apply {
            isSingleSelection = true
            isSelectionRequired = true
            setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), 0, activity.dp(16), activity.dp(8))
        }
        listOf(
            FILTER_ALL to R.string.filter_all,
            FILTER_ONLINE to R.string.filter_online,
            FILTER_OFFLINE to R.string.filter_offline
        ).forEach { (id, text) ->
            filters.addView(Chip(activity).apply {
                this.id = id
                setText(text)
                isCheckable = true
                isChecked = id == filter
                minHeight = activity.dp(48)
                chipBackgroundColor = ColorStateList(
                    arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                    intArrayOf(AppearancePreferences.softColor(activity), activity.color(R.color.surface_subtle))
                )
                setTextColor(ColorStateList(
                    arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                    intArrayOf(AppearancePreferences.color(activity), activity.color(R.color.text_primary))
                ))
            })
        }
        filters.setOnCheckedChangeListener { _, checkedId -> filter = checkedId; render() }
        header.addView(filters)
        root.addView(activity.centered(header))
        list.orientation = LinearLayout.VERTICAL
        list.setPadding(activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), 0, activity.resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), activity.dp(32))
        swipe.setColorSchemeColors(activity.color(R.color.brand_primary))
        swipe.addView(ScrollView(activity).apply { addView(list) })
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
                val result = session.api.devices()
                if (activeRefreshId != refreshId) return@launch
                devices = result.nodes
                latestVersion = result.latestVersion
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
        title.text = activity.getString(R.string.devices_title_count, devices.size)
        list.removeAllViews()
        if (firstLoad) { list.loadingState(); return }
        errorMessage?.let { list.errorState(it) { load() }; return }
        val visible = devices.filter { filter == FILTER_ALL || (filter == FILTER_ONLINE && it.active) || (filter == FILTER_OFFLINE && !it.active) }
        if (visible.isEmpty()) {
            list.emptyState(activity.getString(R.string.no_devices_title), activity.getString(R.string.no_devices_message), activity.getString(R.string.open_management_console)) {
                activity.showManagementConsole()
            }
            return
        }
        val columns = if (activity.resources.configuration.screenWidthDp >= 840) 2 else 1
        var gridRow: LinearLayout? = null
        visible.forEachIndexed { index, device ->
            val card = activity.card {
                val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                header.addView(TextView(activity).apply {
                    text = device.remark.ifBlank { device.name }
                    textSize = 17f
                    maxLines = 2
                    setTextColor(activity.color(R.color.text_primary))
                    setTypeface(typeface, Typeface.BOLD)
                }, LinearLayout.LayoutParams(0, -2, 1f))
                header.addView(activity.statusChip(
                    activity.getString(if (device.active) R.string.online else R.string.offline),
                    if (device.active) AppStatus.SUCCESS else AppStatus.NEUTRAL
                ))
                if (canUpgrade(device)) header.addView(activity.statusChip(activity.getString(R.string.upgrade_available), AppStatus.WARNING), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = activity.dp(6) })
                addView(header)
                label(device.name, true).apply { typeface = Typeface.MONOSPACE }
                label(activity.getString(R.string.device_system_version, device.os.ifBlank { activity.getString(R.string.unknown_system) }, device.version.ifBlank { activity.getString(R.string.unknown_version) }), true)
                val addresses = activity.getString(R.string.device_addresses, device.lanIp.ifBlank { "--" }, device.ip.ifBlank { "--" })
                label(addresses, true).apply {
                    typeface = Typeface.MONOSPACE
                    contentDescription = "$addresses. ${activity.getString(R.string.copy_addresses)}"
                    setOnLongClickListener { copyAddresses(device); true }
                }
                if (busyDevice == device.name) {
                    val progress = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(0, activity.dp(8), 0, 0) }
                    progress.addView(android.widget.ProgressBar(activity), LinearLayout.LayoutParams(activity.dp(24), activity.dp(24)))
                    progress.addView(TextView(activity).apply { text = activity.getString(R.string.please_wait); setTextColor(activity.color(R.color.state_info)); setPadding(activity.dp(8), 0, 0, 0) })
                    addView(progress)
                }
                setOnClickListener { openMappings(device) }
                setOnLongClickListener { anchor -> showMenu(anchor, device); true }
            }
            val item = activity.swipeActions(card, deviceSwipeActions(device)) { swiping ->
                swipe.isEnabled = !swiping
            }
            if (columns == 1) {
                list.addView(item, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(12) })
            } else {
                if (index % columns == 0) {
                    gridRow = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
                    list.addView(gridRow, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = activity.dp(12) })
                }
                gridRow?.addView(item, LinearLayout.LayoutParams(0, -2, 1f).apply {
                    leftMargin = if (index % columns == 0) 0 else activity.dp(6)
                    rightMargin = if (index % columns == 0) activity.dp(6) else 0
                })
            }
        }
        if (columns == 2 && visible.size % 2 == 1) gridRow?.addView(View(activity), LinearLayout.LayoutParams(0, 1, 1f).apply {
            leftMargin = activity.dp(6)
        })
    }

    private fun copyAddresses(device: Device) {
        val value = activity.getString(R.string.device_addresses, device.lanIp.ifBlank { "--" }, device.ip.ifBlank { "--" })
        (activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("OpenP2P device addresses", value))
        view.snack(activity.getString(R.string.addresses_copied))
    }

    private fun showMenu(anchor: View, device: Device) {
        PopupMenu(activity, anchor).apply {
            if (device.active) {
                menu.add(Menu.NONE, 1, 0, R.string.port_mappings)
                menu.add(Menu.NONE, 2, 1, R.string.edit_device)
                if (canUpgrade(device)) menu.add(Menu.NONE, 3, 2, R.string.upgrade_client)
                menu.add(Menu.NONE, 4, 3, R.string.restart_device)
            }
            menu.add(Menu.NONE, 5, 4, R.string.delete_device)
            setOnMenuItemClickListener {
                when (it.itemId) {
                    1 -> openMappings(device); 2 -> editDevice(device); 3 -> upgrade(device)
                    4 -> restart(device); 5 -> delete(device)
                }
                true
            }
            show()
        }
    }

    private fun deviceSwipeActions(device: Device): LinearLayout = LinearLayout(activity).apply {
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
        if (device.active) {
            addAction(activity.getString(R.string.port_mappings), R.color.brand_primary) { openMappings(device) }
            addAction(activity.getString(R.string.edit), R.color.brand_primary) { editDevice(device) }
            if (canUpgrade(device)) {
                addAction(activity.getString(R.string.upgrade), R.color.state_warning) { upgrade(device) }
            }
            addAction(activity.getString(R.string.restart), R.color.state_warning) { restart(device) }
        }
        addAction(activity.getString(R.string.delete), R.color.state_error) { delete(device) }
    }

    private fun canUpgrade(device: Device): Boolean {
        if (!device.active || latestVersion.isBlank() || device.version.isBlank()) return false
        if (device.os.contains("android", true) || device.os.contains("ios", true) || device.os.contains("harmony", true)) return false
        return !device.updateAvailable && compareVersions(device.version, latestVersion) < 0
    }

    private fun compareVersions(left: String, right: String): Int {
        val a = Regex("\\d+").findAll(left).map { it.value.toIntOrNull() ?: 0 }.toList()
        val b = Regex("\\d+").findAll(right).map { it.value.toIntOrNull() ?: 0 }.toList()
        for (i in 0 until maxOf(a.size, b.size)) {
            val result = a.getOrElse(i) { 0 }.compareTo(b.getOrElse(i) { 0 })
            if (result != 0) return result
        }
        return 0
    }

    private fun editDevice(device: Device) {
        activity.bottomSheet(activity.getString(R.string.edit_device)) { dialog ->
            val name = field(activity.getString(R.string.device_name), device.name)
            val bandwidth = field(activity.getString(R.string.bandwidth_mbps), device.bandwidth.takeIf { it > 0 }?.toString() ?: "10", numeric = true)
            val port = field(activity.getString(R.string.public_port), device.publicIPPort.toString(), numeric = true)
            val v6 = Switch(activity).apply { text = activity.getString(R.string.force_ipv6); isChecked = device.forceV6 != 0; minHeight = activity.dp(48); AppearancePreferences.tint(this) }
            addView(v6)
            val save = action(activity.getString(R.string.save_changes)) {}
            save.setOnClickListener {
                val newName = name.text?.toString()?.trim().orEmpty()
                val publicPort = port.intValue()
                if (newName.length < 8) { name.showError(activity.getString(R.string.device_name_too_short)); return@setOnClickListener }
                if (publicPort !in 0..65535) { port.showError(activity.getString(R.string.public_port_invalid)); return@setOnClickListener }
                save.setLoading(true, activity.getString(R.string.save_changes), activity.getString(R.string.please_wait))
                val changed = device.copy(name = newName, bandwidth = bandwidth.intValue(), publicIPPort = publicPort, forceV6 = if (v6.isChecked) 1 else 0)
                runApi(device, activity.getString(R.string.save_success), { session.api.editDevice(device.name, changed) }) { dialog.dismiss(); load() }
            }
        }
    }

    private fun upgrade(device: Device) {
        if (!canUpgrade(device)) { view.snack(activity.getString(R.string.device_not_upgradeable)); return }
        activity.confirm(activity.getString(R.string.upgrade_client), activity.getString(R.string.upgrade_confirm, device.name, device.version, latestVersion), activity.getString(R.string.upgrade)) {
            runApi(device, activity.getString(R.string.upgrade_sent), { session.api.updateDevice(device) }) { load() }
        }
    }

    private fun restart(device: Device) {
        activity.confirm(activity.getString(R.string.restart_device), activity.getString(R.string.restart_confirm, device.name), activity.getString(R.string.restart), true) {
            runApi(device, activity.getString(R.string.restart_sent), { session.api.restartDevice(device) }) { load() }
        }
    }

    private fun delete(device: Device) {
        activity.confirm(activity.getString(R.string.delete_device), activity.getString(R.string.delete_confirm, device.name), activity.getString(R.string.delete), true) {
            runApi(device, activity.getString(R.string.device_deleted), { session.api.deleteDevice(device.name) }) { load() }
        }
    }

    private fun openMappings(device: Device) {
        if (!device.active) {
            view.toast(activity.getString(R.string.device_offline_mappings))
            return
        }
        activity.lifecycleScope.launch {
            try { showMappings(device, session.api.mappings(device)) }
            catch (e: Exception) { view.snack(e.message ?: activity.getString(R.string.load_failed)) }
        }
    }

    private fun mappingStatus(mapping: PortMapping): Pair<String, AppStatus> = when {
        !mapping.enabled -> activity.getString(R.string.tunnel_disabled) to AppStatus.NEUTRAL
        !mapping.active && mapping.error.isNotBlank() -> activity.getString(R.string.tunnel_failed) to AppStatus.ERROR
        !mapping.active -> activity.getString(R.string.tunnel_connecting) to AppStatus.WARNING
        mapping.relayMode == "public" -> activity.getString(R.string.tunnel_relay) to AppStatus.INFO
        mapping.relayMode == "private" -> activity.getString(R.string.tunnel_private_relay) to AppStatus.INFO
        mapping.linkMode == "ipv6" -> activity.getString(R.string.tunnel_direct_ipv6) to AppStatus.SUCCESS
        mapping.linkMode == "intranet" -> activity.getString(R.string.tunnel_direct_intranet) to AppStatus.SUCCESS
        else -> activity.getString(R.string.tunnel_direct) to AppStatus.SUCCESS
    }

    private fun formatConnectTime(value: String): String {
        val numeric = value.toLongOrNull()
        val date = if (numeric != null) {
            Date(if (numeric < 1_000_000_000_000L) numeric * 1000L else numeric)
        } else {
            listOf("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd HH:mm:ss")
                .firstNotNullOfOrNull { pattern ->
                    runCatching { SimpleDateFormat(pattern, Locale.getDefault()).parse(value) }.getOrNull()
                }
        }
        return date?.let { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(it) } ?: value
    }

    private fun showMappings(device: Device, mappings: List<PortMapping>) {
        currentMappings = mappings
        activity.bottomSheet("${device.name} · ${activity.getString(R.string.port_mappings)}") { dialog ->
            action(activity.getString(R.string.new_mapping)) { dialog.dismiss(); editMapping(device, null) }
            if (mappings.isEmpty()) emptyState(activity.getString(R.string.no_mappings), activity.getString(R.string.no_mappings))
            mappings.forEach { mapping ->
                addView(activity.card {
                    val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                    row.addView(TextView(activity).apply { text = mapping.appName.ifBlank { activity.getString(R.string.unnamed_mapping) }; setTextColor(activity.color(R.color.text_primary)); textSize = 16f; setTypeface(typeface, Typeface.BOLD) }, LinearLayout.LayoutParams(0, -2, 1f))
                    row.addView(activity.statusChip(mapping.protocol.uppercase(), AppStatus.INFO))
                    val tunnelStatus = mappingStatus(mapping)
                    row.addView(activity.statusChip(tunnelStatus.first, tunnelStatus.second), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = activity.dp(6) })
                    addView(row)
                    label(activity.getString(R.string.mapping_route, mapping.protocol.uppercase(), mapping.srcPort, mapping.peerNode, mapping.dstPort), true).apply { typeface = Typeface.MONOSPACE }
                    if (mapping.active && mapping.connectTime.isNotBlank()) {
                        keyValue(activity.getString(R.string.connect_time), formatConnectTime(mapping.connectTime))
                    }
                    if (mapping.error.isNotBlank()) label(mapping.error, true).apply { setTextColor(activity.color(R.color.state_error)) }
                    val switch = SwitchMaterial(activity).apply {
                        text = activity.getString(if (mapping.enabled) R.string.enabled else R.string.disabled)
                        isChecked = mapping.enabled
                        minHeight = activity.dp(48)
                        AppearancePreferences.tint(this)
                        setOnCheckedChangeListener { _, checked ->
                            runApi(device, activity.getString(R.string.mapping_status_updated), { session.api.switchMapping(device, mapping, checked) }) { dialog.dismiss(); openMappings(device) }
                        }
                    }
                    addView(switch)
                    val actions = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
                    actions.addView(MaterialButton(activity).apply { text = activity.getString(R.string.edit); setOnClickListener { dialog.dismiss(); editMapping(device, mapping) } }, LinearLayout.LayoutParams(0, activity.dp(48), 1f))
                    actions.addView(MaterialButton(activity).apply { text = activity.getString(R.string.delete); setTextColor(activity.color(R.color.state_error)); setOnClickListener {
                        activity.confirm(activity.getString(R.string.delete), activity.getString(R.string.mapping_delete_confirm, mapping.appName), activity.getString(R.string.delete), true) {
                            runApi(device, activity.getString(R.string.mapping_deleted), { session.api.deleteMapping(device, mapping) }) { dialog.dismiss(); openMappings(device) }
                        }
                    } }, LinearLayout.LayoutParams(0, activity.dp(48), 1f))
                    addView(actions)
                }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(12) })
            }
        }
    }

    private fun editMapping(device: Device, old: PortMapping?) {
        val value = old?.copy() ?: PortMapping(appName = activity.getString(R.string.new_mapping_default_name), srcPort = 222, dstHost = "localhost")
        activity.bottomSheet(activity.getString(if (old == null) R.string.new_mapping else R.string.edit_mapping)) { dialog ->
            val name = field(activity.getString(R.string.mapping_name), value.appName)
            var protocol = value.protocol.ifBlank { "tcp" }
            val protocolButton = secondaryAction("${activity.getString(R.string.protocol)} · ${protocol.uppercase()}") {}
            protocolButton.setOnClickListener { activity.wheelPicker(activity.getString(R.string.protocol), listOf("TCP", "UDP"), if (protocol.equals("udp", true)) 1 else 0) { protocol = if (it == 0) "tcp" else "udp"; protocolButton.text = "${activity.getString(R.string.protocol)} · ${protocol.uppercase()}" } }
            val sourcePort = field(activity.getString(R.string.local_port), value.srcPort.takeIf { it > 0 }?.toString().orEmpty(), numeric = true)
            var peer = devices.firstOrNull { it.name == value.peerNode } ?: devices.firstOrNull { it.name != device.name }
            if (old == null && value.dstPort == 0) value.dstPort = if (peer?.os?.contains("windows", true) == true) 3389 else 22
            lateinit var destinationPort: android.widget.EditText
            val peerButton = secondaryAction("${activity.getString(R.string.remote_device)} · ${peer?.name ?: activity.getString(R.string.select_value)}") {}
            peerButton.setOnClickListener {
                val options = devices.filter { it.name != device.name }
                activity.wheelPicker(activity.getString(R.string.remote_device), options.map { it.remark.ifBlank { it.name } }, options.indexOf(peer).coerceAtLeast(0)) {
                    peer = options[it]
                    if (old == null) destinationPort.setText(if (peer?.os?.contains("windows", true) == true) "3389" else "22")
                    peerButton.text = "${activity.getString(R.string.remote_device)} · ${peer?.name}"
                }
            }
            val host = field(activity.getString(R.string.remote_address), value.dstHost.ifBlank { "127.0.0.1" })
            destinationPort = field(activity.getString(R.string.remote_port), value.dstPort.takeIf { it > 0 }?.toString().orEmpty(), numeric = true)
            val whitelist = field(activity.getString(R.string.access_whitelist), value.whitelist)
            val priorities = activity.punchPriorityOptions()
            var priority = value.punchPriority.coerceIn(0, priorities.lastIndex)
            val priorityButton = secondaryAction("${activity.getString(R.string.punch_priority)} · ${priorities[priority]}") {}
            priorityButton.setOnClickListener { activity.wheelPicker(activity.getString(R.string.punch_priority), priorities, priority) { priority = it; priorityButton.text = "${activity.getString(R.string.punch_priority)} · ${priorities[it]}" } }
            val relay = field(activity.getString(R.string.relay_node), value.specRelayNode)
            val result = label("", true)
            secondaryAction(activity.getString(R.string.check_remote_service)) {
                val target = peer; val portValue = destinationPort.intValue()
                if (!protocol.equals("tcp", true)) view.toast(activity.getString(R.string.remote_check_tcp_only))
                else if (target == null || host.text.isNullOrBlank() || portValue !in 0..65535) view.toast(activity.getString(R.string.remote_check_invalid))
                else activity.lifecycleScope.launch {
                    try { session.api.checkRemote(target, host.text.toString(), portValue); view.toast(activity.getString(R.string.remote_reachable)) }
                    catch (e: Exception) { view.toast(e.message ?: activity.getString(R.string.operation_failed)) }
                }
            }
            action(activity.getString(R.string.save_changes)) {
                val target = peer; val src = sourcePort.intValue(); val dst = destinationPort.intValue()
                val mappingName = name.text?.toString()?.trim().orEmpty()
                val duplicate = currentMappings.any { it.protocol.equals(protocol, true) && it.srcPort == src && it !== old }
                if (mappingName.length !in 1..32 || target == null || src !in 0..65535 || dst !in 0..65535) { result.text = activity.getString(R.string.mapping_invalid); result.setTextColor(activity.color(R.color.state_error)); return@action }
                if (duplicate) { result.text = activity.getString(R.string.mapping_port_conflict); result.setTextColor(activity.color(R.color.state_error)); return@action }
                value.appName = mappingName; value.protocol = protocol; value.srcPort = src; value.peerNode = target.name
                value.dstHost = host.text.toString().trim(); value.dstPort = dst; value.whitelist = whitelist.text.toString().trim(); value.punchPriority = priority; value.specRelayNode = relay.text?.toString()?.trim().orEmpty()
                runApi(device, activity.getString(R.string.mapping_saved), { session.api.saveMapping(device, old, value, target.edgeServer) }) { dialog.dismiss(); openMappings(device) }
            }
        }
    }

    private fun android.widget.EditText.intValue() = text?.toString()?.toIntOrNull() ?: 0

    private fun runApi(device: Device, success: String, block: suspend () -> Unit, completed: () -> Unit) {
        if (busyDevice != null) return
        busyDevice = device.name
        render()
        activity.lifecycleScope.launch {
            try { block(); view.snack(success); completed() }
            catch (e: Exception) { view.snack(e.message ?: activity.getString(R.string.operation_failed)) }
            finally { busyDevice = null; render() }
        }
    }

    companion object {
        private const val FILTER_ALL = 1001
        private const val FILTER_ONLINE = 1002
        private const val FILTER_OFFLINE = 1003
    }
}
