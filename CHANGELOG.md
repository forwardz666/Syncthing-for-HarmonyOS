# Changelog

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

## Unreleased


### Added

- Added Syncthing REST pause/resume wrappers used by run-condition enforcement.
- Added run-condition enforcement in `SyncthingService` so Wi-Fi/mobile data, metered Wi-Fi, power source, battery saver, timed schedule, and force start/stop can pause or resume the embedded Syncthing core instead of stopping the service.
- Added immediate Status page force-mode execution so `Follow`, `Force Start`, and `Force Stop` apply without waiting for the next background interval.

### Changed

- Enabled the Power Source and Respect Battery Saver controls in Sync Conditions.
- Kept platform-gated run conditions visibly disabled for roaming, SSID whitelist, master sync, and flight mode.
- Updated README feature status and validation notes for run conditions and continuous background sync.

### Validated

- Built the signed HAP with `scripts/build-hap-e.ps1`.
- Installed and started the HAP on a HarmonyOS Next phone.
- Verified the embedded Syncthing REST health endpoint, peer connection status, continuous background task snapshot, and pause/resume behavior through local port forwarding.
