#include "hilog/log.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "SyncthingCoreBridge"

extern "C" __attribute__((visibility("default"))) int SyncthingCoreBridgePresent(void) {
    OH_LOG_INFO(LOG_APP, "Syncthing core bridge loaded");
    return 1;
}
