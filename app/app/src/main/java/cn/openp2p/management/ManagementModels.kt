package cn.openp2p.management

import java.math.BigInteger

fun punchPriorityOptionIndex(value: Int): Int = when {
    value and 2 != 0 -> 2
    value and 4 != 0 -> 3
    value == 0 -> 1
    else -> 0
}

fun punchPriorityOptionValue(index: Int): Int = when (index) {
    1 -> 0
    2 -> 2
    3 -> 4
    else -> 1
}

data class UserProfile(
    val token: String = "", val user: String = "", val email: String = "",
    val phone: String = "", val addTime: String = ""
)

data class Device(
    val id: String = "", var name: String, var remark: String = "", val os: String = "",
    val version: String = "", val ip: String = "", val ipv6: String = "", val lanIp: String = "",
    val active: Boolean = false, val updateAvailable: Boolean = false, val removed: Boolean = false,
    val activeTime: String = "", val addTime: String = "", var bandwidth: Int = 0,
    var publicIPPort: Int = 0, var forceV6: Int = 0, val natType: Int = 0,
    val hasIPv4: Int = 0, val hasUpnp: Int = 0, val edgeServer: String = ""
)

data class DeviceList(val nodes: List<Device>, val latestVersion: String)

data class PortMapping(
    var appName: String = "", var protocol: String = "tcp", var punchPriority: Int = 1,
    var srcPort: Int = 0, var peerNode: String = "", var peerUser: String = "",
    var dstHost: String = "127.0.0.1", var dstPort: Int = 0, var whitelist: String = "",
    var peerIP: String = "", var peerNatType: Int = 0, var relayNode: String = "",
    var specRelayNode: String = "", var relayMode: String = "", var linkMode: String = "",
    var active: Boolean = false, var enabled: Boolean = true, var connectTime: String = "",
    var error: String = ""
)

data class SdwanMember(
    var name: String, var ip: String, var resource: String = "", var active: Boolean = false
)

data class SdwanConfig(
    var gateway: String = "10.0.0.0/24", var mode: String = "fullmesh",
    var centralNode: String = "", var forceRelay: Int = 0, var punchPriority: Int = 1,
    val nodes: MutableList<SdwanMember> = mutableListOf(),
    val id: BigInteger? = null, val name: String? = null, val enable: Number? = null,
    val tunnelNum: Number? = null, val mtu: Number? = null
) {
    fun snapshot() = copy(nodes = nodes.map { it.copy() }.toMutableList())
}
