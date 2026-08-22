# Syncthing for HarmonyOS

**Syncthing for HarmonyOS** is a Syncthing client for **HarmonyOS Next** (API 20, `6.0.0(20)`). It embeds the original Go Syncthing core inside the app process and ports the Android Syncthing workflow — pairing, status, device/folder management, Web GUI, logs, recent changes and continuous background sync — to Harmony tablets, PCs/2-in-1s and phones.

> **In one line:** an end-to-end encrypted file-sync client with the original Go Syncthing core embedded, supporting app-sandbox and Download/Documents public-directory sync, background keep-alive sync and real-time transfer.

## Key Features

- **Embedded original Syncthing core** — protocol, discovery, TLS identity, BEP, indexing, block exchange, conflict handling and all sync semantics are handled by the upstream Go core; ArkTS only does UI and platform integration.
- **Harmony NAPI bridge** — calls the Go core's exported `Start(homeDir, logFile, guiAddress, apiKey)` <u>inside the same app process</u> via `libsyncthing_napi.so` → `libsyncthing_core_bridge.so`; the core listens on `127.0.0.1:8384`.
- **Device & folder management** — add/edit/delete devices, QR pairing (ScanKit, syscap-guarded), dynamic addresses, Introducer, auto-accept, compression, pause, untrusted devices, folder sharing; folder type, watch-for-changes, ignore permissions, pull order, versioning, rescan and per-folder status.
- **Public-directory sync** — after user-granted `READ_WRITE_DOWNLOAD_DIRECTORY`, can sync directly to the public `Download/Syncthing/<folderId>` unified container, making files visible to the user.
- **Background keep-alive (a key enhancement over upstream)** — `dataTransfer` + `multiDeviceConnection` background continuous task + persistent progress notification + scheduled probe fallback.

## Release Notes

### v2.0.2 (2026-08-22)

Compared with v2.0.1, this release includes:

- **Loading/error screen icon**: the loading and error screens now use the app's Syncthing icon instead of the default HarmonyOS icon.
- **Synchronized tab highlight and animation**: switching between `Devices / Folders / Status` keeps the sliding animation, while the selected highlight and the new blue indicator bar move with the page instead of waiting for the animation to finish.
- **Unified grayish-white background**: removed remaining pure-white top/bottom areas so the bottom area no longer covers content after opening Settings; most screens now use the grayish-white `page_background`, while only the tab bar keeps the card white background.
- **Settings cleanup**: the language selector now shows the currently selected value just like the theme selector; each settings title uses one rounded card containing all of its options; `SYNCTHING连接` was renamed to `Syncthing连接`.
- **Aligned Devices/Folders page headers**: the `Devices, Add` row and `Folders, Add` row now use the same page background.
- **Run-condition / background sync improvements**: power source, battery saver, data, and scheduled run conditions can pause/resume the embedded Syncthing core; Status page `Follow`, `Force Start`, and `Force Stop` take effect immediately.

## Device Support & Platform Limits

**This project is currently developed and validated for Tablet and PC/2-in-1 devices (all arm64).** Public-directory sync on phones is limited by a HarmonyOS platform capability gate and is not available out of the box. See the table below:

| Capability | Tablet / PC / 2-in-1 (API 26+) | Phone (e.g. API 24) |
|---|---|---|
| App-sandbox sync (`/data/storage/el2/base/files/<id>`) | ✅ Implemented | ✅ Implemented |
| Download/Documents public-directory sync (`Download/Syncthing/<id>`) | ✅ Implemented (no picker) | ❌ Requires API 26.0.0+ HarmonyOS |
| Device/folder management, QR, Web GUI, logs, background sync | ✅ Implemented | ✅ Implemented (except public dir) |

**Why public-directory sync is restricted on phones — this is a platform capability limitation, not an app defect:**

1. **No direct access to the Download directory.** The app uses `Environment.getUserDownloadDir()` (depends on system capability `SystemCapability.FileManagement.File.Environment.FolderObtain`) to reach the public `Download` directory directly. According to the official docs this capability is **open only to 2in1 / Tablet / API 26+ devices**; on other devices it returns error `801`. `canIUse` verifies `false` on phones.
2. **The folder-picker fallback is also limited.** For phones without `FolderObtain` the app falls back to the system folder picker, but Harmony's folder-selection capability (`SystemCapability.FileManagement.UserFileService.FolderSelection`, `DocumentViewPicker` picking a folder) has **only supported phones since API 26.0.0**. On an API 24 phone it is unavailable.
3. **Dynamic authorization result.** On phones `READ_WRITE_DOWNLOAD_DIRECTORY` returns `granted=false`, so the app cannot obtain write access to the Download directory.

Conclusion: **public-directory sync on a phone requires HarmonyOS API 26.0.0+.** On phones this version works normally with app-sandbox sync; public-directory sync and Gallery-directory-tree sync are currently unavailable. To sync a public directory on a phone, use a tablet/PC/2-in-1, or wait for an API 26+ device.

### Other Platform Limits

- **Gallery directory tree** (e.g. `Gallery/Photos/2026/Trip`) and arbitrary system-directory selection: Harmony's public media API exposes only albums/assets rather than a real nested directory tree, and the generic folder picker may return an empty URI/fail on real devices. Therefore the system Gallery cannot be used as a sync root.
- Rejected alternatives: rewriting Syncthing's filesystem backend around a URI abstraction (too invasive for the core), sandbox mirror import/export (duplicates storage and cannot satisfy directory-tree needs), and Gallery/media-library projection (API model mismatch).

## References & Acknowledgements

This project draws heavily on and reuses the following prior work and documents, **roughly in order of importance**:

### 1. Predecessor project (migration baseline)

- **[github.com/xinjinshao/SyncthingHarmonyOSNext](https://github.com/xinjinshao/SyncthingHarmonyOSNext)** — the **most important reference**. This repo uses its **c-archive + NAPI bridge architecture** as the migration baseline: the Go Syncthing core is compiled to a static library (`libsyncthingnative.a`), started via Harmony NAPI inside the same app process listening on `127.0.0.1:8384`, with a full ArkTS UI and API-20 friendliness. Pairing, status, device/folder-management UI workflows are all built on top of this architecture.

### 2. Upstream Syncthing projects

- **[github.com/syncthing/syncthing](https://github.com/syncthing/syncthing)** — the embedded Go core itself; all protocol and sync semantics come from here. Desktop sync peers use Syncthing v2.1.3 (Hafnium Hornet).
- **[github.com/syncthing/syncthing-android](https://github.com/syncthing/syncthing-android)** — the Android app, used as a UI/workflow reference; its official Chinese translations (e.g. Introducer rendered as “作为中介”) are directly referenced in this project's i18n dictionary.

### 3. GitCode adaptation Wiki and toolchain

- **[lycodestore1/thirdpartydocs Wiki](https://gitcode.com/lycodestore1/thirdpartydocs)** — its **《syncthing适配鸿蒙PC指南》** provides key insight into the Synchronization-on-Harmony permission pitfalls (public-directory `operation not permitted`, `READ_WRITE_DOWNLOAD_DIRECTORY` / `READ_WRITE_DOCUMENTS_DIRECTORY` user grants, redirecting the `HOME` env var to the Download/Documents dir); **《go应用适配鸿蒙PC指南》** explains the two ways to integrate a Go app on Harmony (hnp executable / C shared library) and the permission-interception model.
- **[openharmony-sig/ohos_golang_go](https://gitcode.com/openharmony-sig/ohos_golang_go)** — the Harmony-adapted Go toolchain (supports `GOOS=openharmony`, currently 1.24.5), used to cross-compile the Harmony aarch64 Go core/bridge artifacts.

### 4. Other references

- **[HarmonyOS Application Development Guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/application-dev-guide)** — official HarmonyOS app-development docs for permissions, background tasks, scanning and other platform capabilities.
- **Folder-level authorization approach** — the scheme of selecting a folder via `DocumentViewPicker` with `persistPermission` persisted grants is one basis for the public-directory sync implementation.
- **[github.com/xiaobaigroup/ClashBox](https://github.com/xiaobaigroup/ClashBox)** (a mihomo proxy client) — analyzed only as a reference for background keep-alive strategy. Its evasion tricks (spoofed location / picture-in-picture / fake download) were evaluated and explicitly rejected; this project's keep-alive follows the official, compliant path.

Our thanks and respect go to all of the above predecessors and open-source contributors.

## New & Adapted Features

On top of the baseline, the following is the main new/adapted work for HarmonyOS Next:

### Architecture: c-archive same-process integration

Adopts **c-archive + NAPI bridge** so the Go core starts <u>inside the same process as the app</u> rather than as a separate hnp process. The rationale: the core must read/write public directories via direct POSIX paths; same-process c-archive can directly access granted public paths such as `Environment.getUserDownloadDir()`. The artifacts `libsyncthingnative.a` (~80 MB) and `syncthing_core` (~22 MB) are committed with the source, so normal HAP builds do not require installing the patched Go toolchain.

### Public-directory sync

- Fixed the root cause of “public directory is impossible”: previously `READ_WRITE_DOCUMENTS_DIRECTORY` was mistakenly treated as a `system_grant` and was never actually requested from the user (so there was never permission).
- Request `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` (user_grant dialog) → locate the Download dir with `Environment.getUserDownloadDir()` → host all sync folders in the **unified container** `Download/Syncthing/<folderId>`; the grant persists across reboots with no need to re-pick each time.
- For phones without `FolderObtain`, falls back to the system folder picker to choose a public directory (see [Device Support & Platform Limits](#device-support--platform-limits)).
- New folders default to `ignorePerms` enabled to avoid sync failures from Harmony's Download-directory filesystem permission differences.
- Reused the baseline sandbox-sync path; small scenario-specific fixes (page-load null-guards) were merged in.

### Background keep-alive

- **Persistent progress notification:** updates the system persistent notification with **real** sync metrics (from REST connection status) roughly every 10 s so the system does not reclaim the app as idle; distinguishes “user deleted the notification” from “system cancelled it” (a user delete does not auto-restart — forming a “delete-to-stop → re-enable manually” loop).
- **Scheduled probe fallback:** registers a system scheduled job (`WorkSchedulerExtensionAbility`) that periodically wakes, probes whether the core is alive and does a REST liveness re-launch.
- Fixed the “killed after a long time without updates” issue; verified to run 4 hours without periodic kills.
- Strictly follows the official compliant route, explicitly excluding any data-spoofing evasion (spoofed location, fake downloads, picture-in-picture, etc.).

### Frontend i18n

- A self-built dictionary `L10n.ets` (~390 keys) with built-in `zh_CN` / `en_US` resources, unified lookup via `L10n.t()`.
- A language picker on the Settings page (follow system / 中文 / English); system language is detected via `@kit.LocalizationKit`, and the whole app reloads after switching.
- Supports ordered `%s/%d` formatting and `%%` escaping; maps core folder states to Chinese/English; Syncthing terms (e.g. Introducer) follow the official syncthing-android Chinese translation (“作为中介”).
- ArkUI specific handling: `TextInput` is “uncontrolled” (its printed text does not refresh with external state), so a read-only `Text` showing live value + a “Custom” button is used to make a folder label follow the input.

### Permissions & engineering adaptation

- Declared permissions: `INTERNET`, `GET_NETWORK_INFO`, `KEEP_BACKGROUND_RUNNING`, `CAMERA`, `READ_WRITE_DOCUMENTS_DIRECTORY`, `READ_WRITE_DOWNLOAD_DIRECTORY`, `FILE_ACCESS_PERSIST`.
- `backgroundModes: ["dataTransfer", "multiDeviceConnection"]`.
- All app source uses modern `@kit.*` imports with no leftover `@ohos.*`; optional capabilities (background tasks, scanning, folder picker) are guarded at runtime by syscap and degrade safely when missing.
- The C bridge layer's thread model avoids cross-thread `napi_env` access, and shared error state is protected by a mutex.

## Differences From the Original (Android)

| Android surface | HarmonyOS Next status |
|---|---|
| Main tabs, status, devices, folders | Implemented |
| Add/edit devices and QR pairing | Implemented |
| Add/edit folders, sharing, rescan, versioning, pull order | Implemented |
| Settings, Web GUI, logs, recent changes | Implemented |
| Run conditions and background sync | Partially implemented; Wi-Fi/mobile-data, metered Wi-Fi, power source, battery saver, timed schedule, force start/stop and continuous background task control are active; roaming, SSID whitelist, master sync and flight mode remain platform-gated |
| Folder picker/public-directory sync | App sandbox + Download public directory implemented; phone and Gallery directory tree limited by API (see above) |
| Share extension, camera/photo-shoot workflow, quick-settings tile | Not implemented |

## Architecture & Core Call Flow

```text
EntryAbility
  -> pages/Index.ets
  -> SyncthingService.initialize()
  -> SyncthingProcessManager.initialize()
  -> RestApi.initialize()
  -> SyncthingService.startService()
  -> SyncthingProcessManager.start()
  -> SyncthingNative.getVersion()/startSyncthing()
  -> libsyncthing_napi.so
  -> libsyncthing_core_bridge.so
  -> Go exported Start(homeDir, logFile, guiAddress, apiKey)
  -> Syncthing core starts REST on 127.0.0.1:8384
  -> ArkTS pages consume status/config/events through RestApi
```

ArkTS owns the UI, lifecycle, app preferences, background tasks, notifications, sandbox/public-directory path preparation and REST polling; the Go core owns all Syncthing protocol behavior (discovery, TLS, BEP, indexing, block exchange, conflicts, sync). Rewriting the protocol in ArkTS is explicitly out of scope for this baseline.

## Storage Model

Two sync storage modes are supported:

1. **App sandbox**: `/data/storage/el2/base/files/<folder-id>` — available on any device, but files are invisible to the system Gallery.
2. **Download public directory (unified container)**: `Download/Syncthing/<folderId>` — direct access after granting `READ_WRITE_DOWNLOAD_DIRECTORY`, files visible to the user; only Tablet/PC/2-in-1/API 26+ (see [Device Support & Platform Limits](#device-support--platform-limits)).

## Build & Run

### Build and install the HAP

A normal HAP build does **not** require the patched Go toolchain — the required native/core artifacts are committed with the repo:

- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.h`
- `entry/src/main/resources/rawfile/syncthing_core`

Use **DevEco Studio** or a configured HarmonyOS command-line environment:

- Requires DevEco Studio, Node.js, Hvigor and a matching HarmonyOS SDK (`targetSdkVersion` / `compatibleSdkVersion` = `6.0.0(20)`).
- To build a signed HAP, first configure your own `signingConfigs` in DevEco Studio (the checked-in `build-profile.json5` deliberately contains no signing material, for security).
- Build output: signed HAP `entry/build/default/outputs/default/entry-default-signed.hap`; `entry-default-unsigned.hap` when no signing config is set.
- Install onto a tablet/PC with `hdc install`, launch, and follow the wizard on first run to grant Download-directory authorization.

A ready-to-install device HAP is attached to each GitHub Release: `Syncthing-for-HarmonyOS-v2.0.2-unsigned.hap` (unsigned; sign it with DevEco Studio before installing on a real device). You can get it from the [v2.0.2 Release](https://github.com/forwardz666/Syncthing-for-HarmonyOS/releases/tag/v2.0.2).

### (Advanced) Rebuilding the Go core

Only needed when modifying the embedded core/NAPI bridge:

- Requires the Harmony Go toolchain (e.g. `ohos_golang_go`, `GOOS=openharmony`) and the Harmony clang cross-compiler.
- See `build_syncthing_harmonyos.py` and the GitCode Wiki Harmony adaptation guides (see [References & Acknowledgements](#references--acknowledgements) above).

## Validation

- ArkTS/HAP build passes (API 20); the signed HAP installs and starts on a tablet (OpenHarmony 7.0 / API 26) and on a phone.
- The embedded core starts, exposes `127.0.0.1:8384`, and the REST endpoint reports the local device ID; a desktop Syncthing and the device can add each other and show an active LAN connection.
- Folder creation, sharing, scanning and status rendering are validated via UI + REST polling; Download public-directory two-way sync is validated on a real tablet.
- Continuous background task creation, heartbeat diagnostics, run-condition decisions and pause/resume are visible in hilog.

### Validated Devices

- Tablets (OpenHarmony 7.0, API 26)
- Phones (API 24; sandbox sync and limited public-directory validation)

## Documentation

- `ARCHITECTURE.md`, `MODULE_DESIGN.md`, `CHANGELOG.md`: architecture, module design and change records.

## Repository Contents

- `entry/src/main/ets/`: ArkTS UI, services, REST client and native wrapper.
- `entry/src/main/cpp/`: Harmony NAPI bridge source.
- `entry/src/main/libs/`, `entry/src/main/resources/rawfile/`: controlled prebuilt core/bridge artifacts.
- `build_syncthing_harmonyos.py`: build script to cross-compile the Syncthing Go core into a Harmony static library.
- `Syncthing-for-HarmonyOS-v2.0.2-unsigned.hap`: the unsigned HAP attached to the GitHub Release (not checked into the repo, to keep the repository size reasonable).

## License

This project is a **HarmonyOS Next migration effort** built around **Syncthing**.

- The embedded Syncthing core follows the upstream **Mozilla Public License 2.0 (MPL-2.0)**: [github.com/syncthing/syncthing](https://github.com/syncthing/syncthing). When redistributing source or binaries, the upstream Syncthing and Syncthing Android license obligations and copyright notices must be preserved.
- Syncthing Android (workflow/UI/translation reference) is also MPL-2.0.
- **This migration repo ships no standalone LICENSE file of its own:** new ArkTS UI, Harmony NAPI bridge, background keep-alive and i18n code are treated under the same MPL-2.0-style licensing as upstream Syncthing until the maintainer explicitly publishes an independent license statement.
- **Third-party copyright ownership:** the predecessor baseline (xinjinshao), GitCode Wiki (lycodestore1) and ClashBox (xiaobaigroup) code/docs are owned by their respective authors; verify their licenses before use. The maintainer retains the relevant copyright on the new content in this repo, with the specifics deferred until an independent LICENSE file is added.
- No third-party native/front-end runtime dependencies; `oh-package` only contains unit-test dev dependencies `@ohos/hypium` (1.0.24) and `@ohos/hamock` (1.0.0), both from the official OpenHarmony ohpm repository.
