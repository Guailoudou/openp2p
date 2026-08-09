package cn.openp2p.management

import android.content.Context
import cn.openp2p.security.SecureCredentialStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class ManagementSession private constructor(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("management_session", Context.MODE_PRIVATE)
    private val secureStore = SecureCredentialStore.get(context)
    private val mutex = Mutex()
    val api = ManagementApiClient()
    @Volatile var username = ""; private set
    @Volatile var profile = UserProfile(); private set
    @Volatile var lastError = ""; private set
    val authenticated get() = profile.token.isNotBlank()

    suspend fun initialize() = mutex.withLock {
        val user = preferences.getString("username", "").orEmpty()
        val password = secureStore.migrateLegacy(preferences, "password", SecureCredentialStore.MANAGEMENT_PASSWORD)
        secureStore.migrateLegacy(preferences, "authorization", SecureCredentialStore.MANAGEMENT_AUTHORIZATION)
        secureStore.migrateLegacy(preferences, "openp2p_token", SecureCredentialStore.MANAGEMENT_OPENP2P_TOKEN)
        if (user.isBlank() || password.isBlank()) return@withLock false
        loginInternal(user, password)
    }

    suspend fun login(user: String, password: String) = mutex.withLock {
        val clean = user.trim()
        if (clean.isBlank() || password.isBlank()) throw ApiException("请输入管理账号和密码")
        preferences.edit().putString("username", clean).remove("password").apply()
        secureStore.putString(SecureCredentialStore.MANAGEMENT_PASSWORD, password)
        loginInternal(clean, password)
    }

    suspend fun logout() = mutex.withLock {
        preferences.edit().clear().apply()
        secureStore.remove(SecureCredentialStore.MANAGEMENT_PASSWORD)
        secureStore.remove(SecureCredentialStore.MANAGEMENT_AUTHORIZATION)
        secureStore.remove(SecureCredentialStore.MANAGEMENT_OPENP2P_TOKEN)
        api.setToken(""); username = ""; profile = UserProfile(); lastError = ""
    }

    private suspend fun loginInternal(user: String, password: String): Boolean = try {
        val auth = api.login(user, password)
        api.setToken(auth)
        val loaded = api.profile()
        username = user; profile = loaded; lastError = ""
        secureStore.putString(SecureCredentialStore.MANAGEMENT_AUTHORIZATION, auth)
        secureStore.putString(SecureCredentialStore.MANAGEMENT_OPENP2P_TOKEN, loaded.token)
        true
    } catch (error: Exception) {
        api.setToken(""); username = user; profile = UserProfile(); lastError = error.message ?: "登录失败"
        preferences.edit().remove("authorization").remove("openp2p_token").apply()
        secureStore.remove(SecureCredentialStore.MANAGEMENT_AUTHORIZATION)
        secureStore.remove(SecureCredentialStore.MANAGEMENT_OPENP2P_TOKEN)
        false
    }

    companion object {
        @Volatile private var instance: ManagementSession? = null
        fun get(context: Context) = instance ?: synchronized(this) {
            instance ?: ManagementSession(context).also { instance = it }
        }
    }
}
