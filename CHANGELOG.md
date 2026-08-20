# Changelog

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
