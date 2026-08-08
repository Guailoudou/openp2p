#include "napi/native_api.h"
#include <dlfcn.h>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace {

using ConfigFn = int32_t (*)(unsigned char *, int32_t);
using StartFn = int32_t (*)(char *, char *, int64_t, int64_t);
using StopFn = void (*)();
using CoreStateFn = int32_t (*)();
using CoreErrorFn = int32_t (*)(char *, int32_t);
using NodeNameFn = int32_t (*)(char *, int32_t);
using ReadTunFn = void (*)(unsigned char *, int32_t);
using WriteTunFn = int32_t (*)(unsigned char *, int32_t, int32_t);

void *coreHandle = nullptr;
std::mutex coreHandleMutex;
thread_local std::string lastCoreError;

void SetCoreError(const std::string &message) {
    lastCoreError = message;
}

void *LoadCore() {
	std::lock_guard<std::mutex> lock(coreHandleMutex);
    if (coreHandle != nullptr) {
        return coreHandle;
    }
    // libopenp2p_ohos.so is copied into entry/libs/arm64-v8a by the build
    // script and packaged beside this NAPI module in the HAP.
    coreHandle = dlopen("libopenp2p_ohos.so", RTLD_NOW | RTLD_GLOBAL);
    if (coreHandle == nullptr) {
        const char *detail = dlerror();
        if (detail == nullptr) {
            SetCoreError("Unable to load libopenp2p_ohos.so");
        } else {
            SetCoreError(std::string("Unable to load libopenp2p_ohos.so: ") + detail);
        }
    }
    return coreHandle;
}

void *FindCoreSymbol(const char *name) {
    void *handle = LoadCore();
    if (handle != nullptr) {
        dlerror();
        void *symbol = dlsym(handle, name);
        if (symbol != nullptr) {
            return symbol;
        }
        const char *detail = dlerror();
        if (detail != nullptr) {
            SetCoreError(std::string("Unable to resolve ") + name + ": " + detail);
        } else {
            SetCoreError(std::string("Symbol not found in libopenp2p_ohos.so: ") + name);
        }
    }
    // Keep RTLD_DEFAULT as a fallback for loaders that already resolved the
    // packaged library into the process.
    return dlsym(RTLD_DEFAULT, name);
}

bool ReadString(napi_env env, napi_value value, std::string &out) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    out.resize(length + 1);
    if (napi_get_value_string_utf8(env, value, &out[0], out.size(), &length) != napi_ok) {
        return false;
    }
    out.resize(length);
    return true;
}

napi_value BooleanResult(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value Int32Result(napi_env env, int32_t value) {
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value Add(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double left = 0;
    double right = 0;
    napi_get_value_double(env, args[0], &left);
    napi_get_value_double(env, args[1], &right);
    napi_value sum;
    napi_create_double(env, left + right, &sum);
    return sum;
}

static napi_value StartCore(napi_env env, napi_callback_info info) {
    lastCoreError.clear();
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 4) {
        return BooleanResult(env, false);
    }

    std::string baseDir;
    std::string token;
    int64_t shareBandwidth = 0;
    int64_t logLevel = 1;
    if (!ReadString(env, args[0], baseDir) || !ReadString(env, args[1], token) ||
        napi_get_value_int64(env, args[2], &shareBandwidth) != napi_ok ||
        napi_get_value_int64(env, args[3], &logLevel) != napi_ok) {
        SetCoreError("Invalid OpenP2PStart arguments");
        return BooleanResult(env, false);
    }

    auto start = reinterpret_cast<StartFn>(FindCoreSymbol("OpenP2PStart"));
    if (start == nullptr) {
        if (lastCoreError.empty()) {
            SetCoreError("Unable to load OpenP2PStart from libopenp2p_ohos.so");
        }
        return BooleanResult(env, false);
    }
    const int32_t started = start(const_cast<char *>(baseDir.c_str()),
                                  const_cast<char *>(token.c_str()),
                                  shareBandwidth, logLevel);
    if (started == 0) {
        SetCoreError("OpenP2PStart returned 0");
    }
    return BooleanResult(env, started != 0);
}

static napi_value GetLastError(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_string_utf8(env, lastCoreError.c_str(), lastCoreError.size(), &result);
    return result;
}

static napi_value GetCoreState(napi_env env, napi_callback_info info) {
    (void)info;
    auto getState = reinterpret_cast<CoreStateFn>(FindCoreSymbol("OpenP2PGetStatus"));
    if (getState == nullptr) {
        return Int32Result(env, -1);
    }
    return Int32Result(env, getState());
}

static napi_value IsCoreRunning(napi_env env, napi_callback_info info) {
    (void)info;
    auto isRunning = reinterpret_cast<CoreStateFn>(FindCoreSymbol("OpenP2PIsRunning"));
    if (isRunning != nullptr) {
        return BooleanResult(env, isRunning() != 0);
    }

    // Compatibility with an older core library during a staged upgrade.
    auto getState = reinterpret_cast<CoreStateFn>(FindCoreSymbol("OpenP2PGetStatus"));
    return BooleanResult(env, getState != nullptr && getState() == 2);
}

static napi_value GetCoreLastError(napi_env env, napi_callback_info info) {
    (void)info;
    std::string error = lastCoreError;
    auto getError = reinterpret_cast<CoreErrorFn>(FindCoreSymbol("OpenP2PGetLastError"));
    if (getError != nullptr) {
        std::vector<char> buffer(2048, '\0');
        const int32_t length = getError(buffer.data(), static_cast<int32_t>(buffer.size()));
        if (length > 0 && length < static_cast<int32_t>(buffer.size())) {
            error.assign(buffer.data(), static_cast<size_t>(length));
        }
    }
    napi_value result;
    napi_create_string_utf8(env, error.c_str(), error.size(), &result);
    return result;
}

static napi_value StopCore(napi_env env, napi_callback_info info) {
    (void)info;
    auto stop = reinterpret_cast<StopFn>(FindCoreSymbol("OpenP2PStop"));
    if (stop == nullptr) {
        return BooleanResult(env, false);
    }
    stop();
    return BooleanResult(env, true);
}

bool ReadCoreBuffer(ConfigFn read, std::string &value) {
    std::vector<unsigned char> buffer(64 * 1024);
    int32_t length = read(buffer.data(), static_cast<int32_t>(buffer.size()));
    if (length <= 0 || length > static_cast<int32_t>(buffer.size())) {
        return false;
    }
    value.assign(reinterpret_cast<const char *>(buffer.data()), static_cast<size_t>(length));
    return true;
}

static napi_value GetNodeName(napi_env env, napi_callback_info info) {
    (void)info;
    std::vector<char> buffer(512);
    auto getNodeName = reinterpret_cast<NodeNameFn>(FindCoreSymbol("OpenP2PGetNodeName"));
    if (getNodeName == nullptr) {
        return nullptr;
    }
    int32_t length = getNodeName(buffer.data(), static_cast<int32_t>(buffer.size()));
    if (length < 0 || length >= static_cast<int32_t>(buffer.size())) {
        return nullptr;
    }
    napi_value result;
    napi_create_string_utf8(env, buffer.data(), static_cast<size_t>(length), &result);
    return result;
}

struct ConfigWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string value;
    bool success = false;
};

static void ExecuteGetConfig(napi_env env, void *data) {
    (void)env;
    auto *work = static_cast<ConfigWork *>(data);
    auto getConfig = reinterpret_cast<ConfigFn>(FindCoreSymbol("OpenP2PGetSDWANConfig"));
    work->success = getConfig != nullptr && ReadCoreBuffer(getConfig, work->value);
}

static void CompleteGetConfig(napi_env env, napi_status status, void *data) {
    auto *work = static_cast<ConfigWork *>(data);
    if (status == napi_ok && work->success) {
        napi_value result;
        napi_create_string_utf8(env, work->value.data(), work->value.size(), &result);
        napi_resolve_deferred(env, work->deferred, result);
    } else {
        napi_value error;
        napi_create_string_utf8(env, "OpenP2P SD-WAN configuration is unavailable", NAPI_AUTO_LENGTH, &error);
        napi_reject_deferred(env, work->deferred, error);
    }
    napi_delete_async_work(env, work->work);
    delete work;
}

static napi_value GetSDWANConfig(napi_env env, napi_callback_info info) {
    (void)info;
    napi_deferred deferred;
    napi_value promise;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return nullptr;
    }

    auto *work = new ConfigWork();
    work->deferred = deferred;
    napi_value resourceName;
    napi_create_string_utf8(env, "OpenP2PGetSDWANConfig", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteGetConfig, CompleteGetConfig,
                               work, &work->work) != napi_ok ||
        napi_queue_async_work(env, work->work) != napi_ok) {
        delete work;
        return nullptr;
    }
    return promise;
}

static napi_value ReadTun(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 1) {
        return BooleanResult(env, false);
    }
    void *data = nullptr;
    size_t length = 0;
    if (napi_get_arraybuffer_info(env, args[0], &data, &length) != napi_ok || data == nullptr || length == 0) {
        return BooleanResult(env, false);
    }
    if (length > INT32_MAX) {
        return BooleanResult(env, false);
    }
    auto readTun = reinterpret_cast<ReadTunFn>(FindCoreSymbol("OpenP2PReadTun"));
    if (readTun == nullptr) {
        return BooleanResult(env, false);
    }
    readTun(static_cast<unsigned char *>(data), static_cast<int32_t>(length));
    return BooleanResult(env, true);
}

static napi_value WriteTun(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 2) {
        return nullptr;
    }
    void *data = nullptr;
    size_t length = 0;
    int64_t timeoutMs = 100;
    if (napi_get_arraybuffer_info(env, args[0], &data, &length) != napi_ok || data == nullptr || length == 0 ||
        length > INT32_MAX || napi_get_value_int64(env, args[1], &timeoutMs) != napi_ok) {
        return nullptr;
    }
    auto writeTun = reinterpret_cast<WriteTunFn>(FindCoreSymbol("OpenP2PWriteTun"));
    if (writeTun == nullptr) {
        return Int32Result(env, -1);
    }
    int32_t written = writeTun(static_cast<unsigned char *>(data), static_cast<int32_t>(length),
                               static_cast<int32_t>(timeoutMs));
    napi_value result;
    napi_create_int32(env, written, &result);
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startCore", nullptr, StartCore, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCoreState", nullptr, GetCoreState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isCoreRunning", nullptr, IsCoreRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCoreLastError", nullptr, GetCoreLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopCore", nullptr, StopCore, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getNodeName", nullptr, GetNodeName, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSdwanConfig", nullptr, GetSDWANConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readTun", nullptr, ReadTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"writeTun", nullptr, WriteTun, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
