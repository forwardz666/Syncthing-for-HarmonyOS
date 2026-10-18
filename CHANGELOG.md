# Changelog

## Unreleased

### Added

- Added phone public-directory sync through `DocumentPickerMode.DOWNLOAD`: the persistent `Download/<package>/` root hosts each folder at `Download/<package>/<folderId>`, with no `READ_WRITE_DOWNLOAD_DIRECTORY` and no repeated folder authorization. Tablet/PC/2-in-1 keep `Download/Syncthing/<folderId>`.

### Fixed

- Fixed background sync on phones and tablets by selecting `dataTransfer` on non-PC/2-in-1 devices and publishing Live View progress updates; `taskKeeping` is now only requested on PC/2-in-1.
- Fixed the Background Sync switch reverting after leaving the page: a failed task request now surfaces the error instead of silently clearing the setting, and a system cancellation no longer rewrites the user's saved preference.
- Fixed continuous-task detection to recognize the configured background mode, including `taskKeeping`, so an existing task is adopted after a process restart.
- Replaced the removed `AxisEvent.hasAxis`/`AxisType` wheel checks with `getVerticalAxisValue()` so the project builds with the HarmonyOS 6.0.1 (API 21) SDK while still targeting API 20.
- Removed the duplicate start/end notification on phone/tablet `dataTransfer` tasks and added the missing `notification_start_*`/`notification_end_*` localization keys.
- Silenced Live View progress updates by keeping the progress value below 100 and stopping the periodic `updateBackgroundRunning` calls that re-posted the system notification.

## 2.0.1 - 2026-08-21

### Added

- Added long-running background support on PC/2-in-1 via `taskKeeping` continuous task mode; Syncthing can now stay alive in the background for long periods without being canceled after 10 minutes.
- Added silent start/end notifications (`后台同步已开始` / `后台同步已结束`) so users hear only when background sync starts and stops, not on every progress update.

### Changed

- Switched the continuous-task mode from `dataTransfer`/`multiDeviceConnection` to `taskKeeping` on supported PC/2-in-1 devices to avoid system cancellation caused by missing Live View progress updates (`detailedReason=12`) or missing distributed multi-device business (`detailedReason=10`).
- Stopped publishing Live View progress notifications during sync; progress is still tracked internally and used to refresh the continuous task without repeated ringing.
- Corrected cancel-callback classification: when the detailed cancel reason is available, only `USER_CANCEL_REMOVE_NOTIFICATION` is treated as a user removal; other system cancel reasons now trigger automatic re-enable instead of being mistaken for user cancellation.

### Validated

- Real-device validation on HarmonyOS PC: `taskKeeping` continuous task remained alive beyond the previous 10-minute data-transfer cancel window, with no repeated notification sounds.
- Unsigned HAP built as `Syncthing-for-HarmonyOS-v2.0.1-unsigned.hap`.

## 2.0.2 - 2026-08-22

### Added

- Added Syncthing REST pause/resume wrappers used by run-condition enforcement.
- Added run-condition enforcement in `SyncthingService` so Wi-Fi/mobile data, metered Wi-Fi, power source, battery saver, timed schedule, and force start/stop can pause or resume the embedded Syncthing core instead of stopping the service.
- Added immediate Status page force-mode execution so `Follow`, `Force Start`, and `Force Stop` apply without waiting for the next background interval.
- Replaced the loading/error icon with the app's Syncthing icon instead of the default HarmonyOS icon.
- Added a blue moving indicator under the selected `设备/文件夹/状态` tab; the selected text and indicator now stay in sync during tab animations and swipe/wheel switching.

### Changed

- Enabled the Power Source and Respect Battery Saver controls in Sync Conditions.
- Kept platform-gated run conditions visibly disabled for roaming, SSID whitelist, master sync, and flight mode.
- Unified the app background to the grayish-white `page_background`; removed remaining pure-white top/bottom areas and prevented the bottom area from covering content after opening Settings.
- Aligned the `设备、添加` header row background on the Devices page with the `文件夹、添加` header row on the Folders page (both now use the page background).
- Reworked Settings list sections so each title uses one rounded card containing all options with inner dividers, instead of several independently rounded text boxes stacked together.
- Language selector in Settings now displays the currently selected language value, consistent with the theme selector.
- Renamed `SYNCTHING连接` to `Syncthing连接`.
- Updated README feature status and validation notes for run conditions and continuous background sync.

### Validated

- Built the unsigned HAP with DevEco/Hvigor as `Syncthing-for-HarmonyOS-v2.0.2-unsigned.hap`.
- Installed and started the HAP on a HarmonyOS Next phone.
- Verified the embedded Syncthing REST health endpoint, peer connection status, continuous background task snapshot, and pause/resume behavior through local port forwarding.
- Verified tab animation/indicator sync, settings grouping/language display, and background alignment on device.
