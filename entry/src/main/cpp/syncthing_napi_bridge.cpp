/**
 * NAPI bridge for loading and controlling the Go Syncthing core.
 *
 * ArkTS -> syncthing_napi -> libsyncthing_core_bridge.so.
 */

#include <napi/native_api.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <atomic>
#include <cstdlib>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "hilog/log.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "SyncthingNAPI"

using StartFunc = int (*)(const char*, const char*, const char*, const char*);
using IntFunc = int (*)();
using StringFunc = char* (*)();
using FreeCStringFunc = void (*)(char*);

static void* g_handle = nullptr;
static std::string g_bridgeLastError;
static std::atomic<bool> g_startInProgress(false);
static std::atomic<int> g_lastStartResult(0);

/**
 * g_bridgeLastError is written by the Start worker thread and read on the
 * JS/NAPI thread (GetLastError / StatusPage). Guarded by a mutex to avoid a
 * concurrent read/write on std::string.
 */
static std::mutex g_errorMutex;

static void SetBridgeError(const std::string& msg) {
    std::lock_guard<std::mutex> lock(g_errorMutex);
    g_bridgeLastError = msg;
}

static std::string GetBridgeError() {
    std::lock_guard<std::mutex> lock(g_errorMutex);
    return g_bridgeLastError;
}

struct StartRequest {
    StartFunc start;
    std::string homeDir;
    std::string logFile;
    std::string guiAddress;
    std::string apiKey;
};

static std::string ReadStringArg(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::vector<char> buffer(len + 1, '\0');
    napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &len);
    return std::string(buffer.data(), len);
}

static napi_value CreateInt(napi_env env, int value) {
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value CreateBool(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

static napi_value CreateString(napi_env env, const char* value) {
    napi_value result;
    napi_create_string_utf8(env, value == nullptr ? "" : value, NAPI_AUTO_LENGTH, &result);
    return result;
}

static bool LoadSyncthingLibrary(const char* libPath) {
    if (dlsym(RTLD_DEFAULT, "Start") != nullptr) {
        return true;
    }

    if (g_handle != nullptr) {
        return true;
    }

    const char* loadPath = (libPath == nullptr || libPath[0] == '\0') ? "libsyncthing_core_bridge.so" : libPath;
    g_handle = dlopen(loadPath, RTLD_NOW | RTLD_LOCAL);
    if (g_handle == nullptr) {
        const char* error = dlerror();
        SetBridgeError(error == nullptr ? "dlopen failed" : error);
        OH_LOG_ERROR(LOG_APP, "Failed to load syncthing library: %{public}s", GetBridgeError().c_str());
        return false;
    }

    OH_LOG_INFO(LOG_APP, "Syncthing library loaded from: %{public}s", loadPath);
    return true;
}

static napi_value StartSyncthing(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string homeDir = argc > 0 ? ReadStringArg(env, args[0]) : "";
    std::string logFile = argc > 1 ? ReadStringArg(env, args[1]) : "";
    std::string guiAddress = argc > 2 ? ReadStringArg(env, args[2]) : "";
    std::string apiKey = argc > 3 ? ReadStringArg(env, args[3]) : "";

    if (!LoadSyncthingLibrary("")) {
        return CreateInt(env, -1);
    }
    auto start = reinterpret_cast<StartFunc>(dlsym(RTLD_DEFAULT, "Start"));
    if (start == nullptr && g_handle != nullptr) {
        start = reinterpret_cast<StartFunc>(dlsym(g_handle, "Start"));
    }
    if (start == nullptr) {
        SetBridgeError("Start symbol not found in libsyncthing_core_bridge.so");
        OH_LOG_ERROR(LOG_APP, "Start symbol not found in libsyncthing_core_bridge.so");
        return CreateInt(env, -2);
    }

    if (g_startInProgress.exchange(true)) {
        return CreateInt(env, 1);
    }

    StartRequest request{
        start,
        homeDir,
        logFile,
        guiAddress,
        apiKey,
    };

    try {
        std::thread([request]() {
            std::string tmpDir = request.homeDir + "/tmp";
            setenv("HOME", request.homeDir.c_str(), 1);
            setenv("TMPDIR", tmpDir.c_str(), 1);
            setenv("USER", "syncthing", 1);
            setenv("LOGNAME", "syncthing", 1);
            OH_LOG_INFO(LOG_APP, "Calling bridged Syncthing Start home=%{public}s gui=%{public}s",
                request.homeDir.c_str(), request.guiAddress.c_str());
            int ret = request.start(
                request.homeDir.c_str(),
                request.logFile.c_str(),
                request.guiAddress.c_str(),
                request.apiKey.c_str());
            g_lastStartResult.store(ret);
            if (ret != 0 && ret != 1) {
                SetBridgeError("Syncthing Start returned " + std::to_string(ret));
            }
            OH_LOG_INFO(LOG_APP, "Syncthing Start returned: %{public}d", ret);
            g_startInProgress.store(false);
        }).detach();
    } catch (...) {
        g_startInProgress.store(false);
        SetBridgeError("failed to create Syncthing start thread");
        OH_LOG_ERROR(LOG_APP, "Failed to create Syncthing start thread");
        return CreateInt(env, -3);
    }

    return CreateInt(env, 0);
}

static napi_value StopSyncthing(napi_env env, napi_callback_info info) {
    auto directStop = reinterpret_cast<IntFunc>(dlsym(RTLD_DEFAULT, "Stop"));
    if (directStop != nullptr) {
        return CreateInt(env, directStop());
    }

    if (g_handle == nullptr) {
        return CreateInt(env, 0);
    }

    auto stop = reinterpret_cast<IntFunc>(dlsym(g_handle, "Stop"));
    if (stop == nullptr) {
        return CreateInt(env, -1);
    }
    return CreateInt(env, stop());
}

static std::string CallGoString(const char* symbol) {
    auto direct = reinterpret_cast<StringFunc>(dlsym(RTLD_DEFAULT, symbol));
    if (direct != nullptr) {
        char* value = direct();
        std::string result = value == nullptr ? "" : value;
        auto directFree = reinterpret_cast<FreeCStringFunc>(dlsym(RTLD_DEFAULT, "FreeCString"));
        if (directFree != nullptr && value != nullptr) {
            directFree(value);
        }
        return result;
    }

    if (g_handle == nullptr) {
        return "";
    }

    auto stringFunc = reinterpret_cast<StringFunc>(dlsym(g_handle, symbol));
    if (stringFunc == nullptr) {
        return "";
    }

    char* value = stringFunc();
    std::string result = value == nullptr ? "" : value;

    auto freeCString = reinterpret_cast<FreeCStringFunc>(dlsym(g_handle, "FreeCString"));
    if (freeCString != nullptr && value != nullptr) {
        freeCString(value);
    }
    return result;
}

static napi_value GetSyncthingVersion(napi_env env, napi_callback_info info) {
    if (!LoadSyncthingLibrary("")) {
        return CreateString(env, "unknown");
    }

    std::string version = CallGoString("Version");
    return CreateString(env, version.empty() ? "unknown" : version.c_str());
}

static napi_value GetLastError(napi_env env, napi_callback_info info) {
    std::string lastError = CallGoString("LastError");
    if (lastError.empty()) {
        lastError = GetBridgeError();
    }
    return CreateString(env, lastError.c_str());
}

static napi_value IsRunningNative(napi_env env, napi_callback_info info) {
    auto directIsRunning = reinterpret_cast<IntFunc>(dlsym(RTLD_DEFAULT, "IsRunning"));
    if (directIsRunning != nullptr) {
        return CreateBool(env, directIsRunning() != 0);
    }

    if (g_handle == nullptr) {
        return CreateBool(env, false);
    }

    auto isRunning = reinterpret_cast<IntFunc>(dlsym(g_handle, "IsRunning"));
    if (isRunning == nullptr) {
        return CreateBool(env, false);
    }
    return CreateBool(env, isRunning() != 0);
}

static napi_value Init(napi_env env, napi_value exports) {
    OH_LOG_INFO(LOG_APP, "Syncthing NAPI Init called");
    napi_property_descriptor desc[] = {
        {"startSyncthing", nullptr, StartSyncthing, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopSyncthing", nullptr, StopSyncthing, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, IsRunningNative, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, GetSyncthingVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module syncthingModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = __FILE__,
    .nm_register_func = Init,
    .nm_modname = "syncthing_napi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterSyncthingModule(void) {
    napi_module_register(&syncthingModule);
}
