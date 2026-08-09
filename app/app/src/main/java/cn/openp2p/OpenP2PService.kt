package cn.openp2p

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import cn.openp2p.security.SecureCredentialStore
import cn.openp2p.ui.MainActivity
import kotlinx.coroutines.launch
import openp2p.Openp2p
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collect
import org.json.JSONObject
import java.io.File
import java.net.InetAddress
import java.net.NetworkInterface
import kotlinx.coroutines.Dispatchers

class OpenP2PService : VpnService() {
    companion object {
        private const val LOG_TAG = "OpenP2PService"
        const val ACTION_START = "cn.openp2p.action.START"
        const val ACTION_STOP = "cn.openp2p.action.STOP"
        const val ACTION_STATUS_CHANGED = "cn.openp2p.action.STATUS_CHANGED"
        const val PREFERENCES = "openp2p_runtime"
        const val KEY_TOKEN = "token"
        const val KEY_DESIRED_RUNNING = "desired_running"
        const val KEY_STATE = "state"
        const val KEY_TUN_STATE = "tun_state"
        const val KEY_VPN_PERMISSION_REQUIRED = "vpn_permission_required"

        // getAndroidSDWANConfig() is a blocking native call and cannot be
        // cancelled by destroying a Service coroutine. Keep exactly one
        // process-wide reader and fan its results out to the active service.
        private val configReaderScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private val configEvents = MutableSharedFlow<String>(
            replay = 0,
            extraBufferCapacity = 1,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        )
        private val configReaderLock = Any()
        @Volatile private var configReaderJob: Job? = null

        private fun ensureConfigReader() {
            synchronized(configReaderLock) {
                if (configReaderJob?.isActive == true) return
                configReaderJob = configReaderScope.launch {
                    Logger.i(LOG_TAG, "Process-wide SD-WAN configuration reader started")
                    while (isActive) {
                        val configText = try {
                            val buffer = ByteArray(32 * 1024)
                            val length = Openp2p.getAndroidSDWANConfig(buffer)
                            if (length <= 0 || length > buffer.size.toLong()) {
                                Logger.w(LOG_TAG, "Ignored invalid SD-WAN config length: $length")
                                delay(1000)
                                continue
                            }
                            buffer.copyOfRange(0, length.toInt()).decodeToString()
                        } catch (error: Throwable) {
                            Logger.e(LOG_TAG, "Failed while waiting for SD-WAN config", error)
                            delay(1000)
                            continue
                        }
                        configEvents.emit(configText)
                    }
                }
            }
        }
    }

    inner class LocalBinder : Binder() {
        fun getService(): OpenP2PService = this@OpenP2PService
    }

    private val binder = LocalBinder()
    private lateinit var network: openp2p.P2PNetwork
    private var running: Boolean = false
    private var sdwanRunning: Boolean = false
    private var vpnInterface: ParcelFileDescriptor? = null
    private var sdwanJob: Job? = null
    private var tunReadJob: Job? = null
    private var configJob: Job? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var coreJob: Job? = null
    private var watchdogJob: Job? = null
    private val recoveryTimes = ArrayDeque<Long>()
    private var recoveryIndex = 0
    @Volatile private var lastSdwanConfig: JSONObject? = null

    override fun onCreate() {
        val logDir = File(getExternalFilesDir(null), "log")
        Logger.init(logDir)
        Logger.i(LOG_TAG, "onCreate - Thread ID = " + Thread.currentThread().id)
        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel("openp2p_core", "OpenP2P 后台服务")
        } else {
            ""
        }
        val notificationIntent = Intent(this, MainActivity::class.java)

        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId ?: "")
            .setSmallIcon(R.drawable.icon)
            .setContentTitle("OpenP2P 正在运行")
            .setContentText("保持点对点连接与虚拟网络在线")
            .setOngoing(true).setContentIntent(pendingIntent).build()

        startForeground(1337, notification)
        super.onCreate()
        refreshSDWAN()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Logger.i(
            LOG_TAG,
            "onStartCommand - startId = " + startId + ", Thread ID = " + Thread.currentThread().id
        )
        if (intent?.action == ACTION_STOP) stopCoreByUser() else startOpenP2P()
        return START_STICKY
    }

    override fun onBind(p0: Intent?): IBinder? {
        Logger.i(LOG_TAG, "onBind")
        return binder
    }

    private fun startOpenP2P(recovery: Boolean = false) {
        if (coreJob?.isActive == true || running) {
            retryTunFromLastConfig()
            return
        }
        val preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
        val token = SecureCredentialStore.get(this)
            .migrateLegacy(preferences, KEY_TOKEN, SecureCredentialStore.CORE_TOKEN)
        if (token.isBlank()) { updateState("Token 未设置"); stopSelf(); return }
        preferences.edit().putBoolean(KEY_DESIRED_RUNNING, true).apply()
        running = true
        updateState(if (recovery) "正在恢复" else "正在启动")
        coreJob = serviceScope.launch {
            try {
                network = Openp2p.runAsModuleWithNode(
                    getExternalFilesDir(null).toString(), token, deviceNodeCandidate(), 0, 1
                )
                Logger.i(LOG_TAG, "核心登录成功，当前节点=${Openp2p.getAndroidNodeName()}")
                updateState("核心运行中")
                startWatchdog()
            } catch (e: Throwable) {
                running = false
                coreJob = null
                Logger.e(LOG_TAG, "核心启动失败", e)
                updateState("启动失败：${e.message ?: "未知错误"}")
                scheduleRecovery()
            }
        }
    }

    private fun deviceNodeCandidate(): String {
        val configuredName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } else {
            null
        }
        return configuredName?.trim().takeUnless { it.isNullOrEmpty() }
            ?: Build.MODEL?.trim().takeUnless { it.isNullOrEmpty() }
            ?: "Android-device"
    }

    private fun startWatchdog() {
        watchdogJob?.cancel()
        watchdogJob = serviceScope.launch {
            var stoppedChecks = 0
            while (isActive && getSharedPreferences(PREFERENCES, MODE_PRIVATE).getBoolean(KEY_DESIRED_RUNNING, false)) {
                delay(10_000)
                val alive = try { Openp2p.isModuleRunning() } catch (e: Throwable) {
                    Logger.e(LOG_TAG, "核心存活检查失败", e)
                    true
                }
                if (alive) {
                    stoppedChecks = 0; recoveryIndex = 0; updateState("核心运行中")
                } else if (++stoppedChecks >= 3) {
                    running = false; updateState("核心已停止，等待恢复"); scheduleRecovery(); break
                }
            }
        }
    }

    private suspend fun scheduleRecovery() {
        if (!getSharedPreferences(PREFERENCES, MODE_PRIVATE).getBoolean(KEY_DESIRED_RUNNING, false)) return
        val now = System.currentTimeMillis()
        while (recoveryTimes.isNotEmpty() && now - recoveryTimes.first() > 10 * 60_000) recoveryTimes.removeFirst()
        if (recoveryTimes.size >= 5) { updateState("10 分钟内恢复已达 5 次，请手动检查"); return }
        val delays = longArrayOf(2_000, 5_000, 15_000, 60_000)
        delay(delays[recoveryIndex.coerceAtMost(delays.lastIndex)])
        recoveryIndex = (recoveryIndex + 1).coerceAtMost(delays.lastIndex)
        recoveryTimes.addLast(System.currentTimeMillis())
        startOpenP2P(true)
    }

    private fun stopCoreByUser() {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putBoolean(KEY_DESIRED_RUNNING, false).apply()
        watchdogJob?.cancel(); coreJob?.cancel(); running = false
        closeTun("已随核心停止")
        try { Openp2p.stopModule() } catch (e: Throwable) { Logger.e(LOG_TAG, "停止核心失败", e) }
        updateState("已停止"); stopForeground(true); stopSelf()
    }

    private fun updateState(state: String) {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putString(KEY_STATE, state).apply()
        sendBroadcast(Intent(ACTION_STATUS_CHANGED).setPackage(packageName))
        Logger.i(LOG_TAG, state)
    }

    private fun refreshSDWAN() {
        if (configJob?.isActive == true) return
        configJob = serviceScope.launch(start = CoroutineStart.UNDISPATCHED) {
            Logger.i(LOG_TAG, "SD-WAN configuration listener started")
            configEvents.collect { configText ->
                val json = try {
                    JSONObject(configText)
                } catch (e: Exception) {
                    Logger.e(LOG_TAG, "Ignored malformed SD-WAN config", e)
                    return@collect
                }

                lastSdwanConfig = JSONObject(json.toString())
                stopTunAndJoin()
                // Match HarmonyOS semantics: cloud configurations do not always
                // include enable. Only an explicit zero disables TUN; otherwise
                // gateway, Nodes and local-node membership decide readiness.
                if (json.optInt("enable", 1) == 0) {
                    updateTunState("云端已关闭虚拟网络")
                    return@collect
                }
                sdwanJob = serviceScope.launch { runSDWAN(json) }
            }
        }
        ensureConfigReader()
    }

    private suspend fun stopTunAndJoin() {
        sdwanRunning = false
        vpnInterface?.close()
        vpnInterface = null
        tunReadJob?.cancelAndJoin()
        tunReadJob = null
        sdwanJob?.cancelAndJoin()
        sdwanJob = null
    }

    private fun closeTun(state: String) {
        sdwanRunning = false
        tunReadJob?.cancel()
        sdwanJob?.cancel()
        vpnInterface?.close()
        vpnInterface = null
        updateTunState(state)
    }

    private fun updateTunState(state: String) {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putString(KEY_TUN_STATE, state).apply()
        sendBroadcast(Intent(ACTION_STATUS_CHANGED).setPackage(packageName))
        Logger.i(LOG_TAG, "TUN: $state")
    }

    private fun updateVpnPermissionRequired(required: Boolean) {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit()
            .putBoolean(KEY_VPN_PERMISSION_REQUIRED, required).apply()
        sendBroadcast(Intent(ACTION_STATUS_CHANGED).setPackage(packageName))
    }

    private fun retryTunFromLastConfig() {
        if (vpnInterface != null || sdwanJob?.isActive == true) return
        val config = lastSdwanConfig ?: return
        sdwanJob = serviceScope.launch { runSDWAN(JSONObject(config.toString())) }
    }

    private suspend fun readTunLoop(descriptor: ParcelFileDescriptor) {
        val inputStream = FileInputStream(descriptor.fileDescriptor).channel
        Logger.i(LOG_TAG, "read tun loop start")
        val buffer = ByteBuffer.allocate(4096)
        val byteArrayRead = ByteArray(4096)
        while (currentCoroutineContext().isActive && sdwanRunning) {
            buffer.clear()
            val readBytes = inputStream.read(buffer)
            if (readBytes > 0) {
                buffer.flip()
                buffer.get(byteArrayRead, 0, readBytes)
                Openp2p.androidRead(byteArrayRead, readBytes.toLong())
            } else {
                delay(50)
            }
        }
        inputStream.close()
        Logger.i(LOG_TAG, "read tun loop end")
    }

    private suspend fun runSDWAN(jsonObject: JSONObject) {
//        val localIps = listOf(
//            "fe80::14b6:a0ff:fe3e:64de" to 64,
//            "192.168.100.184" to 24,
//            "10.93.158.91" to 32,
//            "192.168.3.66" to 24
//        )
//
//        // 测试用例
//        val testCases = listOf(
//            "192.168.3.11" to true,
//            "192.168.100.1" to true,
//            "192.168.101.1" to false,
//            "10.93.158.91" to true,
//            "10.93.158.90" to false,
//            "fe80::14b6:a0ff:fe3e:64de" to true,
//            "fe80::14b6:a0ff:fe3e:64dd" to true // 在同一子网
//        )
//
//        for ((ip, expected) in testCases) {
//            val result = isSameSubnet(ip, localIps)
//            println("Testing IP: $ip, Expected: $expected, Result: $result")
//        }
        Logger.i(LOG_TAG, "Applying SD-WAN config: $jsonObject")
        try {
            if (VpnService.prepare(this) != null) {
                updateVpnPermissionRequired(true)
                updateTunState("VPN 授权已失效，请返回应用重新授权")
                return
            }
            updateVpnPermissionRequired(false)
            val builder = Builder()
            // debug sdwan info
            // val jsonObject = JSONObject("""{"id":2817104318517097000,"name":"network1","gateway":"10.2.3.254/24","mode":"central","centralNode":"nanjin-192-168-0-82","enable":1,"tunnelNum":3,"mtu":1420,"Nodes":[{"name":"192-168-24-15","ip":"10.2.3.5"},{"name":"Alpine Linux-172.16","ip":"10.2.3.14","resource":"172.16.0.0/24"},{"name":"ctdeMacBook-Pro.local","ip":"10.2.3.22"},{"name":"dengjiandeMBP.sh.chaitin.net","ip":"10.2.3.32"},{"name":"DESKTOP-WIN11-ARM-self","ip":"10.2.3.19"},{"name":"eastdeMBP.sh.chaitin.net","ip":"10.2.3.3"},{"name":"FN-NAS-HP","ip":"10.2.3.1","resource":"192.168.100.0/24"},{"name":"huangruideMBP.sh.chaitin.net","ip":"10.2.3.30"},{"name":"iStoreOS-virtual-machine","ip":"10.2.3.12"},{"name":"k30s-redmi-10.2.33","ip":"10.2.3.27"},{"name":"lincheng-MacBook-Pro-3.sh.chaitin.net","ip":"10.2.3.15"},{"name":"localhost-mi-13","ip":"10.2.3.8"},{"name":"localhost-华为matepad11","ip":"10.2.3.13"},{"name":"luzhanwendeMacBook-Pro.local","ip":"10.2.3.17"},{"name":"Mi-pad2-local","ip":"10.2.3.9"},{"name":"nanjin-192-168-0-82","ip":"10.2.3.34"},{"name":"R7000P-2021","ip":"10.2.3.7"},{"name":"tanxiaolongsMBP.sh.chaitin.net","ip":"10.2.3.20"},{"name":"TUF-AX3000_V2-3804","ip":"10.2.3.25"},{"name":"WIN-CYZ-10.2.3.16","ip":"10.2.3.16"},{"name":"WODOUYAO","ip":"10.2.3.4"},{"name":"Zstrack01","ip":"10.2.3.51","resource":"192.168.24.0/22,192.168.20.0/24"},{"name":"小米14-localhost","ip":"10.2.3.23"}]}""")
            val configuredMtu = jsonObject.optInt("mtu", 1420)
            val mtu = if (configuredMtu > 0) configuredMtu else 1420
            val gateway = jsonObject.optString("gateway", "").trim()
            if (gateway.isEmpty()) {
                updateTunState("核心已连接，等待有效的 SD-WAN 网关配置")
                return
            }
            val gatewayNetwork = getNetworkAddress(gateway)
                ?: throw IllegalArgumentException("Invalid gateway: $gateway")
            val addressPrefix = gatewayNetwork.second
            val nodesArray = jsonObject.optJSONArray("Nodes")
            if (nodesArray == null) {
                updateTunState("核心已连接，等待有效的 SD-WAN 节点配置")
                return
            }

            val nodesList = mutableListOf<JSONObject>()
            for (i in 0 until nodesArray.length()) {
                nodesList.add(nodesArray.getJSONObject(i))
            }

            val myNodeName = Openp2p.getAndroidNodeName()
            // 使用本地 IP 和子网判断是否需要添加路由
            val localIps = getLocalIpAndSubnet()
            Logger.i(OpenP2PService.LOG_TAG, "getAndroidNodeName:${myNodeName}");
            var hasCurrentNodeAddress = false
            nodesList.forEach {
                val nodeName = it.optString("name", "").trim()
                val nodeIp = it.optString("ip", "").trim()
                if (nodeName.isEmpty() || nodeIp.isEmpty()) {
                    Logger.w(LOG_TAG, "Skipped malformed SD-WAN node: $it")
                    return@forEach
                }
                if (nodeName == myNodeName) {
                    try {
                        Logger.i(LOG_TAG, "Attempting to add address: $nodeIp/$addressPrefix")
                        builder.addAddress(nodeIp, addressPrefix)
                        hasCurrentNodeAddress = true
                        Logger.i(LOG_TAG, "Successfully added address")
                    } catch (e: Exception) {
                        Logger.e(LOG_TAG, "Failed to add address $nodeIp: ${e.message}")
                        throw e // or handle gracefully
                    }
                }
                val nodeResource = it.optString("resource", "")
                if (nodeResource.isNotEmpty()) {
                    // 可能是多个网段，用逗号分隔
                    val resourceList = nodeResource.split(",")
                    for (resource in resourceList) {
                        val parts = resource.split("/")
                        if (parts.size == 2) {
                            val ipAddress = parts[0].trim()
                            val subnetMask = parts[1].trim()
                            // 判断是否属于本机网段
                            if (!isSameSubnet(ipAddress, localIps)) {
                                builder.addRoute(ipAddress, subnetMask.toInt())
                                Logger.i(
                                    OpenP2PService.LOG_TAG,
                                    "sdwan addRoute:${ipAddress},${subnetMask}"
                                )
                            } else {
                                Logger.i(
                                    OpenP2PService.LOG_TAG,
                                    "Skipped adding route for ${ipAddress}, already in local subnet"
                                )
                            }
                        } else {
                            Logger.w(OpenP2PService.LOG_TAG, "Invalid resource format: $resource")
                        }
                    }
                }

            }

            if (!hasCurrentNodeAddress) {
                val cloudNodeNames = nodesList.mapNotNull {
                    it.optString("name", "").trim().takeIf(String::isNotEmpty)
                }
                Logger.w(
                    LOG_TAG,
                    "当前核心节点未加入 SD-WAN：local=$myNodeName, cloud=$cloudNodeNames"
                )
                updateTunState("当前节点 $myNodeName 未加入虚拟网络")
                return
            }
            listOf("119.29.29.29", "2400:3200::1").forEach { dnsServer ->
                try {
                    builder.addDnsServer(dnsServer)
                } catch (error: Exception) {
                    Logger.w(LOG_TAG, "Skipped unsupported DNS server $dnsServer: ${error.message}")
                }
            }
            // builder.addRoute("10.2.3.0", 24)
//            builder.addRoute("0.0.0.0", 0);
            val (netIp, prefix) = gatewayNetwork
            builder.addRoute(netIp, prefix)
            Logger.i(LOG_TAG, "Added route from gateway: $netIp/$prefix")

            builder.setSession(LOG_TAG)
            builder.setMtu(mtu)
            val descriptor = builder.establish()
                ?: throw IllegalStateException("VpnService.Builder.establish returned null")
            vpnInterface = descriptor
            sdwanRunning = true
            updateVpnPermissionRequired(false)
            updateTunState("虚拟网络运行中")

            val byteArrayWrite = ByteArray(4096)
            tunReadJob = serviceScope.launch(Dispatchers.IO) {
                try {
                    readTunLoop(descriptor)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (sdwanRunning) {
                        Logger.e(LOG_TAG, "TUN read loop failed", e)
                        sdwanRunning = false
                        descriptor.close()
                        updateTunState("虚拟网络读取失败：${e.message ?: "未知错误"}")
                    }
                }
            }

            val outputStream = FileOutputStream(descriptor.fileDescriptor).channel
            Logger.i(LOG_TAG, "write tun loop start")
            while (currentCoroutineContext().isActive && sdwanRunning) {
                val len = Openp2p.androidWrite(byteArrayWrite, 3000)
                if (len <= 0 || len > mtu || len > byteArrayWrite.size) {
                    continue
                }
                try {
                    val writeBytes = outputStream.write(ByteBuffer.wrap(byteArrayWrite, 0, len.toInt()))
                    if (writeBytes <= 0) {
                        Logger.e(LOG_TAG, "outputStream.write failed: $writeBytes")
                    }
                } catch (e: Exception) {
                    if (sdwanRunning) throw e
                    break
                }
            }
            outputStream.close()
            Logger.i(LOG_TAG, "write tun loop end")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Logger.e(LOG_TAG, "Failed to apply SD-WAN config", e)
            updateTunState("虚拟网络启动失败：${e.message ?: "未知错误"}")
        } finally {
            sdwanRunning = false
            tunReadJob?.cancel()
            tunReadJob = null
            vpnInterface?.close()
            vpnInterface = null
        }
        Logger.i(LOG_TAG, "runSDWAN end")
    }
    /**
     * 将 "10.2.3.254/16" 这样的 CIDR 转成正确对齐的网络地址，如 "10.2.0.0/16"
     */
    fun getNetworkAddress(cidr: String): Pair<String, Int>? {
        val parts = cidr.trim().split("/")
        if (parts.size != 2) return null

        val ip = parts[0]
        val prefix = parts[1].toIntOrNull() ?: return null
        if (prefix !in 0..32) return null

        val octets = ip.split(".").map { it.toInt() }
        if (octets.size != 4) return null

        // 转成整数
        val ipInt = (octets[0] shl 24) or (octets[1] shl 16) or (octets[2] shl 8) or octets[3]

        // 生成掩码并计算网络地址
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        val networkInt = ipInt and mask

        // 转回点分十进制
        val networkIp = listOf(
            (networkInt shr 24) and 0xFF,
            (networkInt shr 16) and 0xFF,
            (networkInt shr 8) and 0xFF,
            networkInt and 0xFF
        ).joinToString(".")

        return networkIp to prefix
    }
    override fun onDestroy() {
        closeTun("服务已销毁")
        super.onDestroy()
        Logger.i(LOG_TAG, "onDestroy - Canceling service scope")
        serviceScope.cancel() // 取消所有与服务相关的协程
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Logger.i(LOG_TAG, "onUnbind - Thread ID = " + Thread.currentThread().id)
        return super.onUnbind(intent)
    }

    fun isConnected(): Boolean {
        if (!::network.isInitialized) return false
        return network.connect(1000)
    }

    fun stop() {
        stopCoreByUser()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel(channelId: String, channelName: String): String? {
        val chan = NotificationChannel(
            channelId,
            channelName, NotificationManager.IMPORTANCE_NONE
        )
        chan.lightColor = Color.BLUE
        chan.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        val service = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        service.createNotificationChannel(chan)
        return channelId
    }
}

// 获取本机所有IP地址和对应的子网信息
fun getLocalIpAndSubnet(): List<Pair<String, Int>> {
    val localIps = mutableListOf<Pair<String, Int>>()
    val networkInterfaces = NetworkInterface.getNetworkInterfaces()
    // 手动添加测试数据
    //localIps.add(Pair("192.168.3.33", 24))
    while (networkInterfaces.hasMoreElements()) {
        val networkInterface = networkInterfaces.nextElement()
        if (networkInterface.isUp && !networkInterface.isLoopback) {
            val interfaceAddresses = networkInterface.interfaceAddresses
            for (interfaceAddress in interfaceAddresses) {
                val address = interfaceAddress.address
                val prefixLength = interfaceAddress.networkPrefixLength
                if (address is InetAddress) {
                    address.hostAddress?.let { host ->
                        localIps.add(Pair(host, prefixLength.toInt()))
                    }
                }
            }
        }
    }
    return localIps
}

// 判断某个IP是否与本机某网段匹配
fun isSameSubnet(ipAddress: String, localIps: List<Pair<String, Int>>): Boolean {
    val targetIp = InetAddress.getByName(ipAddress).address
    for ((localIp, prefixLength) in localIps) {
        val localIpBytes = InetAddress.getByName(localIp).address
        val mask = createSubnetMask(prefixLength, localIpBytes.size) // 动态生成掩码

        // 比较目标 IP 和本地 IP 的网络部分
        if (targetIp.indices.all { i ->
                (targetIp[i].toInt() and mask[i].toInt()) == (localIpBytes[i].toInt() and mask[i].toInt())
            }) {
            return true
        }
    }
    return false
}

// 根据前缀长度动态生成子网掩码
fun createSubnetMask(prefixLength: Int, addressLength: Int): ByteArray {
    val mask = ByteArray(addressLength)
    for (i in 0 until prefixLength / 8) {
        mask[i] = 0xFF.toByte()
    }
    if (prefixLength % 8 != 0) {
        mask[prefixLength / 8] = (0xFF shl (8 - (prefixLength % 8))).toByte()
    }
    return mask
}
