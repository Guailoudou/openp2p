package cn.openp2p.security

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores credentials with an app-private Android Keystore key. Android versions below API 23
 * keep secrets in process memory only instead of writing recoverable plaintext to disk.
 */
class SecureCredentialStore private constructor(context: Context) {
    private val preferences = context.applicationContext
        .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val memory = ConcurrentHashMap<String, String>()

    @Synchronized
    fun putString(key: String, value: String) {
        if (value.isEmpty()) {
            remove(key)
            return
        }
        memory[key] = value
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        runCatching { preferences.edit().putString(key, encrypt(value)).apply() }
            .onFailure { Log.e(TAG, "Unable to encrypt credential $key", it) }
    }

    @Synchronized
    fun getString(key: String): String {
        memory[key]?.let { return it }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return ""
        val encoded = preferences.getString(key, null) ?: return ""
        return runCatching { decrypt(encoded) }
            .onSuccess { memory[key] = it }
            .onFailure {
                Log.e(TAG, "Unable to decrypt credential $key; removing invalid value", it)
                preferences.edit().remove(key).apply()
            }
            .getOrDefault("")
    }

    @Synchronized
    fun migrateLegacy(legacy: SharedPreferences, legacyKey: String, secureKey: String): String {
        val current = getString(secureKey)
        val legacyValue = legacy.getString(legacyKey, "").orEmpty()
        if (current.isEmpty() && legacyValue.isNotEmpty()) putString(secureKey, legacyValue)
        if (legacy.contains(legacyKey)) legacy.edit().remove(legacyKey).apply()
        return if (current.isNotEmpty()) current else legacyValue
    }

    @Synchronized
    fun remove(key: String) {
        memory.remove(key)
        preferences.edit().remove(key).apply()
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun decrypt(value: String): String {
        val pieces = value.split(':', limit = 2)
        require(pieces.size == 2) { "Invalid encrypted credential" }
        val iv = Base64.decode(pieces[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(pieces[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE).run {
            init(KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
            generateKey()
        }
    }

    companion object {
        const val CORE_TOKEN = "core.openp2p_token"
        const val MANAGEMENT_PASSWORD = "management.password"
        const val MANAGEMENT_AUTHORIZATION = "management.authorization"
        const val MANAGEMENT_OPENP2P_TOKEN = "management.openp2p_token"

        private const val TAG = "SecureCredentialStore"
        private const val PREFERENCES = "secure_credentials"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "cn.openp2p.credentials.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"

        @Volatile private var instance: SecureCredentialStore? = null
        fun get(context: Context): SecureCredentialStore = instance ?: synchronized(this) {
            instance ?: SecureCredentialStore(context).also { instance = it }
        }
    }
}
