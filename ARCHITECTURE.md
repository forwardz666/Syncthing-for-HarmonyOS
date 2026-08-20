# SyncthingHarmonyOSNext Architecture

This document records the current API 20 architecture after the HarmonyOS Next migration cleanup.

## Goals

- Keep Syncthing protocol, indexing, discovery, TLS identity, block exchange, and conflict handling inside the upstream Go core.
- Rebuild the Android app workflow with HarmonyOS Next ArkTS UI and services.
- Use Harmony platform capabilities only at the app boundary: lifecycle, storage grants, background task, notification, WebView, and QR scanning.
- Keep ordinary HAP builds independent from the patched Go toolchain by checking in the required native/core artifacts.

## Source Architecture Constraints

| Constraint | Android source | HarmonyOS Next design |
|---|---|---|
| Long running sync | Foreground service plus notification | Continuous background task with system notification |
| Core lifecycle | Android native process/library wrapper | Harmony NAPI bridge to patched Go core |
| Control plane | Syncthing REST on localhost | Same REST API on `127.0.0.1:8384` |
| UI state | Activities/fragments observing service state | ArkUI pages observing service/rest/event state |
| Settings | SharedPreferences | `@kit.ArkData` preferences |
| Storage | Direct filesystem paths | App sandbox paths only |
| Device pairing | Manual ID and QR scan | Manual ID and ScanKit guarded by syscap |

## Runtime Architecture

```text
EntryAbility
  -> pages/Index.ets
  -> SyncthingService.initialize()
  -> SyncthingProcessManager.initialize()
  -> SyncthingService.startService()
  -> SyncthingNative.startSyncthing()
  -> libsyncthing_napi.so
  -> patched Go Syncthing core
  -> REST API on 127.0.0.1:8384
  -> ArkTS RestApi/EventProcessor/pages
```

ArkTS owns UI, lifecycle, app preferences, background task management, notification integration, app-sandbox path preparation, and REST polling. The Go core owns all Syncthing protocol behavior.

## API 20 Baseline

The project targets HarmonyOS `6.0.0(20)`:

```json5
"targetSdkVersion": "6.0.0(20)",
"compatibleSdkVersion": "6.0.0(20)"
```

App source uses modern Kit imports:

| Area | API 20 import |
|---|---|
| File APIs | `@kit.CoreFileKit` |
| Network APIs | `@kit.NetworkKit` |
| Preferences | `@kit.ArkData` |
| Logging | `@kit.PerformanceAnalysisKit` |
| Ability/context/want agent | `@kit.AbilityKit` |
| Background tasks | `@kit.BackgroundTasksKit` |
| Notifications | `@kit.NotificationKit` |
| Battery and power state | `@kit.BasicServicesKit` |
| ScanKit | `@kit.ScanKit` |

There are no remaining `@ohos.*` imports in `entry/src/main/ets`.

## Native Core Integration

HarmonyOS Next cannot reuse the Android `libsyncthingnative.so` directly. This app packages a Harmony-compatible NAPI bridge and patched Syncthing core artifacts:

- `entry/src/main/cpp/syncthing_napi_bridge.cpp`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/resources/rawfile/syncthing_core`
- `entry/src/main/ets/native/SyncthingNative.ets`
- `entry/src/main/ets/types/libsyncthing_napi.d.ts`

`SyncthingProcessManager` prepares the app sandbox, local API key, log path, and Go core home directory. It starts the core through `SyncthingNative`, waits for REST health, and records diagnostics.

## Storage Architecture

The Go core scans normal filesystem paths under app storage:

```text
/data/storage/el2/base/files/<folder-id>
```

This is the only supported production storage mode after the public-folder experiments. HarmonyOS Next picker and media APIs expose URI/media abstractions, while the embedded Syncthing Go core expects regular filesystem paths. The app therefore does not expose System Folder, Gallery Folder, import/export, or mirror controls.

### Current File Sync Limitation

| User intent | Current status | Reason |
|---|---|---|
| Sync app-private files between phone and PC | Supported | Syncthing can scan app-sandbox POSIX paths |
| Sync a public phone folder | Not supported | Generic folder picker did not provide reliable usable directory access on the test phone |
| Sync a Gallery directory tree | Not supported | Public media APIs expose albums/assets, not true nested directories |
| Keep only one public copy of files | Not supported | Zero-copy requires either direct POSIX access or a full Syncthing filesystem backend |

### Evaluated Storage Approaches

| Approach | Validation performed | Final blocker |
|---|---|---|
| URI-backed Syncthing filesystem | Designed a possible Go filesystem abstraction backed by ArkTS/NAPI operations for directory listing, file open/read/write/stat/rename/delete, and change watching | The change is too broad for this baseline and would affect Syncthing's trusted filesystem, temp-file, watcher, scanner, index, and conflict paths. It also depends on stable long-lived URI access that was not validated on the device. |
| Sandbox mirror | Implemented prototype code for folder mappings, recursive import/export, manual UI actions, scheduler, status badges, and manifest planning | It creates duplicate storage and still does not produce a real Gallery directory tree. The tested generic folder picker returned an empty URI/error result on the target phone. The prototype code has been removed. |
| Gallery/media-library projection | Reviewed API 20 `photoAccessHelper` capabilities including `READ_IMAGEVIDEO`, `WRITE_IMAGEVIDEO`, album lookup, asset creation, and album asset operations | API 20 models media as albums/assets. It does not expose a public parent-folder or relative-path API for creating a real nested `Photos/<subdir>` Gallery directory tree. |

The next viable storage direction would need a new platform capability or a dedicated upstream-quality Syncthing filesystem backend. Until then, app-sandbox sync is the documented behavior.

## Background Sync Architecture

`BackgroundSyncManager` requests a continuous background task using `dataTransfer` and `multiDeviceConnection`. It uses the system-provided continuous-task notification and records diagnostics for enable, disable, heartbeat, task snapshot, cancel, suspend, and active callbacks.

All background task calls are guarded with `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask`. Devices without this syscap keep foreground sync behavior and report a clear unsupported state.

## Optional Capability Guards

| Feature | Syscap / condition | Runtime behavior when unavailable |
|---|---|---|
| Continuous background sync | `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask` | Disable background mode and keep diagnostics |
| QR scan pairing | `SystemCapability.Multimedia.Scan.ScanBarcode` | Disable/guard Scan button and keep manual input |
| Public/system folder sync | none validated | Disabled; use App Storage |
| Battery/power run conditions | `SystemCapability.PowerManager.BatteryManager.Core` and `SystemCapability.PowerManager.PowerManager.Core` | Skip unsupported checks and keep other run conditions active |

The API 20 compiler may still warn about these optional APIs. The warnings are accepted because the app needs those features on capable devices while degrading safely on unsupported device profiles.

## Current Verification

- API 20 HAP build passes with `scripts/build-hap-e.ps1`.
- Signed HAP installs on device `22N0223B15011897`.
- App starts at `pages/MainPage`.
- Go core starts and REST probe succeeds for status, connections, and config.
- A desktop Syncthing peer is visible as `Connected` in the Devices tab.
- Continuous background task starts on the test phone and reports `notificationId=300`, `continuousTaskId=323`.
