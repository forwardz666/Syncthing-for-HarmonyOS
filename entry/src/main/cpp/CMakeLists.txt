cmake_minimum_required(VERSION 3.16)
project(SyncthingHarmonyNative LANGUAGES C CXX)

# the compiler to use for C/C++ code
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# NAPI library
add_library(syncthing_napi SHARED syncthing_napi_bridge.cpp)
add_library(syncthing_core_bridge SHARED syncthing_core_bridge.cpp)

# Find NAPI headers (provided by HarmonyOS SDK)
# The SDK path is automatically provided by hvigor
target_include_directories(syncthing_napi PRIVATE
    ${OHOS_SDK_NATIVE}/sysroot/usr/include
    ${OHOS_SDK_NATIVE}/sysroot/usr/include/napi
)
target_include_directories(syncthing_core_bridge PRIVATE
    ${OHOS_SDK_NATIVE}/sysroot/usr/include
)

# Link against required system libraries
target_link_libraries(syncthing_napi PUBLIC
    ace_napi.z
    hilog_ndk.z
    dl
)

if(DEFINED OHOS_ARCH)
    set(SYNCTHING_NATIVE_ABI ${OHOS_ARCH})
elseif(DEFINED CMAKE_OHOS_ARCH_ABI)
    set(SYNCTHING_NATIVE_ABI ${CMAKE_OHOS_ARCH_ABI})
else()
    set(SYNCTHING_NATIVE_ABI arm64-v8a)
endif()

set(SYNCTHING_NATIVE_ARCHIVE
    ${CMAKE_CURRENT_SOURCE_DIR}/../libs/${SYNCTHING_NATIVE_ABI}/libsyncthingnative.a
)

if(EXISTS ${SYNCTHING_NATIVE_ARCHIVE})
    target_link_libraries(syncthing_core_bridge PUBLIC
        -Wl,--whole-archive
        ${SYNCTHING_NATIVE_ARCHIVE}
        -Wl,--no-whole-archive
        pthread
        dl
        hilog_ndk.z
    )
else()
    message(WARNING "libsyncthingnative.a not found for ${SYNCTHING_NATIVE_ABI}: ${SYNCTHING_NATIVE_ARCHIVE}")
endif()
