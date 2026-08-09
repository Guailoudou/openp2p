package cn.openp2p.management

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class ManagementApiClient {
    @Volatile private var authorization = ""
    fun setToken(value: String) { authorization = value }

    suspend fun login(user: String, password: String): String {
        val json = request("/api/v1/user/login", "POST", JSONObject().put("user", user).put("password", password), false)
        val token = json.optString("token")
        if (json.optInt("error", -1) != 0 || token.isBlank()) throw ApiException("管理账号或密码错误")
        return token
    }

    suspend fun profile(): UserProfile {
        val root = request("/api/v1/user/profile", "POST")
        val p = root.optJSONObject("profile") ?: JSONObject()
        val coreToken = p.optString("token").trim()
        if (root.optInt("error", 0) != 0 || !coreToken.matches(Regex("[1-9]\\d*"))) {
            throw ApiException("无法从用户信息获取 OpenP2P Token")
        }
        return UserProfile(coreToken, p.optString("user"), p.optString("email"), p.optString("phone"), p.optString("addtime"))
    }

    suspend fun devices(): DeviceList {
        val root = request("/api/v1/devices", "GET")
        val array = root.optJSONArray("nodes") ?: JSONArray()
        return DeviceList((0 until array.length()).map { parseDevice(array.getJSONObject(it)) }, root.optString("latestVer"))
    }

    suspend fun sdwan(): SdwanConfig {
        val root = request("/api/v1/sdwans/", "GET")
        val result = SdwanConfig(
            root.optString("gateway", "10.0.0.0/24"), root.optString("mode", "fullmesh"),
            root.optString("centralNode"), root.optInt("forceRelay"), root.optInt("punchPriority")
        )
        val array = root.optJSONArray("Nodes") ?: JSONArray()
        for (i in 0 until array.length()) array.optJSONObject(i)?.let {
            result.nodes += SdwanMember(it.optString("name"), it.optString("ip"), it.optString("resource"), it.optInt("isActive") != 0)
        }
        return result
    }

    suspend fun editDevice(originalName: String, device: Device) = checked(request("/api/v1/device/${enc(originalName)}/edit", "POST",
        JSONObject().put("newName", device.name).put("bandwidth", device.bandwidth).put("forcev6", device.forceV6).put("publicIPPort", device.publicIPPort)))
    suspend fun deleteDevice(name: String) = checked(request("/api/v1/device/${enc(name)}/delete", "GET"))
    suspend fun updateDevice(device: Device) = checked(push(device.name, 6, 0, device.edgeServer))
    suspend fun restartDevice(device: Device) = checked(push(device.name, 11, 0, device.edgeServer))

    suspend fun mappings(device: Device): List<PortMapping> {
        val a = push(device.name, 7, 1, device.edgeServer).optJSONArray("Apps") ?: JSONArray()
        return (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(::parseMapping) }.filter { it.srcPort > 0 }
    }

    suspend fun saveMapping(device: Device, old: PortMapping?, value: PortMapping, peerEdgeServer: String) {
        val body = mappingJson(value).put("protocol0", old?.protocol ?: "").put("srcPort0", old?.srcPort ?: 0)
        checked(request("/api/v1/device/${enc(device.name)}/push?subtype=9&edgeserver=${enc(peerEdgeServer)}", "POST", body))
    }

    suspend fun deleteMapping(device: Device, value: PortMapping) = checked(push(device.name, 9, 0, device.edgeServer,
        JSONObject().put("appName", value.appName).put("protocol0", value.protocol).put("srcPort0", value.srcPort)
            .put("peerNode", value.peerNode).put("dstHost", value.dstHost).put("dstPort", value.dstPort)))

    suspend fun switchMapping(device: Device, value: PortMapping, enabled: Boolean) = checked(request(
        "/api/v1/device/${enc(device.name)}/switchapp", "POST", JSONObject().put("appName", value.appName)
            .put("peerNode", value.peerNode).put("protocol", value.protocol).put("srcPort", value.srcPort).put("enabled", if (enabled) 1 else 0)))

    suspend fun checkRemote(peer: Device, host: String, port: Int) = checked(push(peer.name, 19, 1, peer.edgeServer,
        JSONObject().put("host", host).put("port", port)))

    suspend fun saveSdwan(value: SdwanConfig) {
        val nodes = JSONArray()
        value.nodes.forEach { nodes.put(JSONObject().put("name", it.name).put("ip", it.ip).put("resource", it.resource)) }
        checked(request("/api/v1/sdwan/edit", "POST", JSONObject().put("gateway", value.gateway).put("mode", value.mode)
            .put("centralNode", value.centralNode).put("forceRelay", value.forceRelay).put("punchPriority", value.punchPriority).put("Nodes", nodes)))
    }

    suspend fun refreshSdwanNode(device: Device) = checked(push(device.name, 22, 0, device.edgeServer))
    suspend fun memberStatus(device: Device): JSONObject = push(device.name, 17, 1, device.edgeServer)

    private suspend fun push(name: String, subtype: Int, rsp: Int, edgeServer: String, body: JSONObject? = null) =
        request("/api/v1/device/${enc(name)}/push?subtype=$subtype&rsp=$rsp&edgeserver=${enc(edgeServer)}", "POST", body)

    private suspend fun request(path: String, method: String, body: JSONObject? = null, authenticated: Boolean = true): JSONObject = withContext(Dispatchers.IO) {
        val connection = URL("https://console.openpxp.com$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.useCaches = false
            connection.setRequestProperty("Content-Type", "application/json")
            if (authenticated) {
                if (authorization.isBlank()) throw ApiException("管理账号未登录")
                connection.setRequestProperty("Authorization", authorization)
            }
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.bufferedWriter(Charsets.UTF_8).use { it.write(body.toString()) }
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw ApiException("管理服务请求失败 ($code)${if (text.isBlank()) "" else "：$text"}")
            if (text.isBlank()) JSONObject() else JSONObject(text)
        } finally { connection.disconnect() }
    }

    private fun checked(root: JSONObject) {
        if (root.has("error") && root.optInt("error") != 0) throw ApiException("操作失败 (${root.optInt("error")})")
    }
    private fun parseDevice(o: JSONObject) = Device(o.optString("id"), o.optString("name"), o.optString("remark"),
        o.optString("os"), o.optString("version"), o.optString("ip"), o.optString("ipv6"), o.optString("lanip"),
        o.optInt("isActive") != 0, o.optInt("isUpdate") != 0, o.optBoolean("removed"), o.optString("activetime"),
        o.optString("addtime"), o.optInt("bandwidth"), o.optInt("publicIPPort"), o.optInt("forcev6"), o.optInt("natType"),
        o.optInt("hasIPv4"), o.optInt("hasUPNPorNATPMP"), o.optString("edgeServer"))
    private fun parseMapping(o: JSONObject) = PortMapping(o.optString("appName"), o.optString("protocol", "tcp"),
        o.optInt("punchPriority"), o.optInt("srcPort"), o.optString("peerNode"), o.optString("peerUser"),
        o.optString("dstHost", "127.0.0.1"), o.optInt("dstPort"), o.optString("whitelist"), o.optString("peerIP"),
        o.optInt("peerNatType"), o.optString("relayNode"), o.optString("specRelayNode"), o.optString("relayMode"),
        o.optString("linkMode"), o.optInt("isActive") != 0, o.optInt("enabled", 1) != 0, o.optString("connectTime"), o.optString("error"))
    private fun mappingJson(v: PortMapping) = JSONObject().put("appName", v.appName).put("protocol", v.protocol)
        .put("punchPriority", v.punchPriority).put("srcPort", v.srcPort).put("peerNode", v.peerNode)
        .put("dstHost", v.dstHost).put("dstPort", v.dstPort).put("whitelist", v.whitelist).put("specRelayNode", v.specRelayNode)
    private fun enc(value: String) = URLEncoder.encode(value, "UTF-8")
}

class ApiException(message: String) : Exception(message)
