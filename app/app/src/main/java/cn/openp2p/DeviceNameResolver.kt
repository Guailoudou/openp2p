package cn.openp2p

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

object DeviceNameResolver {
    fun shouldRequestBluetoothPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || preferredSystemName(context) != null) return false
        if (context.getSystemService(BluetoothManager::class.java)?.adapter == null) return false
        if (readStoredBluetoothName(context) != null) return false
        return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
    }

    fun resolve(context: Context): String {
        val rawSystemName = readSystemName(context)
        return preferredSystemName(rawSystemName)
            ?: readStoredBluetoothName(context)
            ?: readBluetoothAdapterName(context)
            ?: usable(rawSystemName)
            ?: manufacturerAndModel()
            ?: usable(Build.DEVICE)
            ?: usable(Build.PRODUCT)
            ?: usable(Build.MODEL)
            ?: "Android-device"
    }

    private fun preferredSystemName(context: Context): String? = preferredSystemName(readSystemName(context))

    private fun preferredSystemName(value: String?): String? {
        val candidate = usable(value) ?: return null
        val genericValues = listOf(Build.MODEL, Build.PRODUCT, Build.DEVICE, manufacturerAndModel())
            .mapNotNull(::usable)
        return candidate.takeUnless { name -> genericValues.any { it.equals(name, true) } }
    }

    private fun readSystemName(context: Context): String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
        usable(Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME))
    } else {
        null
    }

    private fun readStoredBluetoothName(context: Context): String? = runCatching {
        usable(Settings.Secure.getString(context.contentResolver, "bluetooth_name"))
    }.getOrNull()

    private fun readBluetoothAdapterName(context: Context): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED) return null
        return runCatching {
            usable(context.getSystemService(BluetoothManager::class.java)?.adapter?.name)
        }.getOrNull()
    }

    private fun manufacturerAndModel(): String? {
        val manufacturer = usable(Build.MANUFACTURER)
        val model = usable(Build.MODEL)
        return when {
            manufacturer == null -> model
            model == null -> manufacturer
            model.startsWith(manufacturer, true) -> model
            else -> "$manufacturer $model"
        }
    }

    private fun usable(value: String?): String? {
        val candidate = value?.trim().orEmpty()
        return candidate.takeIf {
            it.isNotEmpty() && !it.equals("unknown", true) && !it.equals("generic", true) &&
                !it.equals("default", true)
        }
    }
}
