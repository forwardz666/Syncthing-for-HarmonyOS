# SyncthingHarmonyOSNext Module Design

This document describes the current module layout and API 20 responsibilities.

## Common

| File | Responsibility | Key dependencies |
|---|---|---|
| `common/Logger.ets` | Unified hilog wrapper | `@kit.PerformanceAnalysisKit` |
| `common/ServiceLocator.ets` | Lightweight singleton registry | none |
| `common/EventBus.ets` | In-process typed event dispatch | app types |
| `common/Utils.ets` | Formatting, base64, retry helpers | `@kit.ArkTS` |

## Data

| File | Responsibility | Key dependencies |
|---|---|---|
| `data/PreferencesManager.ets` | App preference persistence and typed settings access | `@kit.ArkData` |

## Network

| File | Responsibility | Key dependencies |
|---|---|---|
| `network/ApiRequest.ets` | HTTP helper for Syncthing REST requests | `@kit.NetworkKit` |
| `network/RestApi.ets` | Syncthing REST facade for config, status, db, events, logs, stats | `ApiRequest`, models |
| `network/SyncthingTrustManager.ets` | Trust handling placeholder for local Syncthing TLS work | certificate APIs |

## Native Bridge

| File | Responsibility |
|---|---|
| `native/SyncthingNative.ets` | Typed ArkTS wrapper around `libsyncthing_napi.so` |
| `types/libsyncthing_napi.d.ts` | NAPI declaration for ArkTS compilation |
| `cpp/syncthing_napi_bridge.cpp` | C++ NAPI bridge into the patched Go core |
| `cpp/syncthing_core_bridge.cpp` | Native helper layer for bundled core startup |
| `cpp/CMakeLists.txt` | Builds native bridge and packages required artifacts |

## Services

| File | Responsibility | Notes |
|---|---|---|
| `service/Constants.ets` | Preference keys, REST constants, paths, defaults | Ported from Android concepts |
| `service/SyncthingService.ets` | Top-level runtime owner | Starts core, polling, events, and run conditions |
| `service/SyncthingProcessManager.ets` | Go core lifecycle | Starts NAPI core, waits for REST health, handles async core file installation |
| `service/EventProcessor.ets` | Syncthing event polling | Polls `/rest/events` and emits app events |
| `service/RunConditionMonitor.ets` | Run-condition evaluation | Uses `@kit.NetworkKit` and `@kit.BasicServicesKit`; network, power source, and battery saver checks are syscap guarded |
| `service/BackgroundSyncManager.ets` | Continuous background task wrapper | Guards background APIs by syscap and records diagnostics |
| `service/NotificationManager.ets` | App info/error notifications | System continuous-task notification is preferred for background sync |
| `service/BackgroundDiagnostics.ets` | Diagnostic event log | Uses `@kit.CoreFileKit` |

## File Sync Limitation

The current product module set intentionally supports app-sandbox folder sync only. Public folder, Gallery folder, generic picker folder, and mirror modules have been removed from the runtime baseline.

| Requirement | Status | Blocking point |
|---|---|---|
| Sync `/data/storage/el2/base/files/<folder-id>` | Implemented | Syncthing can scan this path directly |
| Sync a user-selected public directory | Not implemented | Folder picker did not return a usable directory URI on the test phone, and the Go core cannot scan URI paths |
| Sync a real Gallery directory tree | Not implemented | `photoAccessHelper` exposes albums/assets, not nested directory creation |
| Avoid duplicate storage while syncing public files | Not implemented | Requires direct POSIX access or a full Syncthing filesystem backend |

### Removed Prototype Modules

The following prototype modules were removed because they did not satisfy the real directory-tree requirement:

| Removed module | Previous role | Removal reason |
|---|---|---|
| `FolderLocationManager.ets` | Stored external URI to sandbox path mappings | Mapping enabled mirror behavior only |
| `FolderMirrorService.ets` | Recursive import/export between URI folders and sandbox paths | Duplicated storage and could not create a real Gallery tree |
| `FolderMirrorScheduler.ets` | Periodically ran mirror passes while the core was active | Depended on removed mirror service |

Folder UI now exposes App Storage as the supported path and shows public folder actions as unsupported.

## Pages

| File | Responsibility |
|---|---|
| `pages/Index.ets` | Startup/loading and first-run routing |
| `pages/FirstStartPage.ets` | First-run wizard |
| `pages/MainPage.ets` | Main tab shell for Devices, Folders, Status |
| `pages/DeviceListPage.ets` | Tab child component listing configured remote devices |
| `pages/FolderListPage.ets` | Tab child component listing configured folders and status |
| `pages/StatusPage.ets` | Core health, local ID, connections, pending items, logs, feature status |
| `pages/DeviceDetailPage.ets` | Add/edit device, QR scan pairing, folder sharing |
| `pages/FolderDetailPage.ets` | Add/edit folder, path selection, sharing, versioning, rescan |
| `pages/SettingsPage.ets` | App settings and Syncthing options |
| `pages/SyncConditionsPage.ets` | Background sync and run-condition controls |
| `pages/SandboxViewPage.ets` | App sandbox file viewer |
| `pages/WebGuiPage.ets` | Embedded Syncthing Web GUI |
| `pages/RecentChangesPage.ets` | Recent file changes from events |
| `pages/LogPage.ets` | Syncthing/system log view |

`DeviceListPage` and `FolderListPage` are not route pages. They are exported child components used by `MainPage`, so they are intentionally removed from `main_pages.json` and do not carry `@Entry`.

## Route Pages

`entry/src/main/resources/base/profile/main_pages.json` contains only pages that are directly navigated to by router:

- `pages/Index`
- `pages/MainPage`
- `pages/FirstStartPage`
- `pages/SandboxViewPage`
- `pages/SyncConditionsPage`
- `pages/DeviceDetailPage`
- `pages/FolderDetailPage`
- `pages/SettingsPage`
- `pages/WebGuiPage`
- `pages/RecentChangesPage`
- `pages/LogPage`

## API 20 Compatibility Rules

- App source uses `@kit.*` imports instead of legacy `@ohos.*` imports.
- Optional features are guarded by `canIUse()` before user-visible actions and before runtime calls.
- `throw err` is avoided because ArkTS API 20 restricts throwing arbitrary values; errors are wrapped in `new Error(...)`.
- File operations that may fail are kept out of page render paths and handled with explicit error reporting.
- Large synchronous file work should stay out of page render paths; new writes in `SyncthingProcessManager` use async file APIs.

## Feature Coverage

| Area | Status |
|---|---|
| Core startup through NAPI | Implemented |
| REST status/config/connections/events | Implemented |
| Device list/detail/add/delete/share | Implemented |
| QR device pairing | Implemented, syscap guarded |
| Folder list/detail/add/delete/share/rescan | Implemented |
| App sandbox folder sync | Implemented |
| System folder picker/public folder sync | Not implemented; app sandbox only |
| Sandbox viewer | Implemented |
| Web GUI/logs/recent changes | Implemented |
| Background sync | Implemented on devices with continuous-task syscap |
| Network run condition | Implemented |
| Battery/power run conditions | Implemented, syscap guarded |

## Validation Baseline

| Check | Status |
|---|---|
| API 20 HAP build | Passed |
| No `@ohos.*` imports in app source | Passed |
| HAP install on test phone | Passed |
| App starts at `pages/MainPage` | Passed |
| Go core starts | Passed |
| REST status/connections/config probe | Passed |
| Desktop peer shown connected | Passed |
| Continuous background task on test phone | Passed |
