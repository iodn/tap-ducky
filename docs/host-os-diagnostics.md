# Host OS diagnostics — feasibility and verification

**Date:** 2026-11-22
**Scope:** TapDucky Android USB HID gadget (ConfigFS + `/dev/hidgN`)
**Recommendation:** Automatic OS identification is **unsupported** by the current USB backend. Ship connection state, an Unknown-by-default host OS, and a clearly labelled manual diagnostic value. Do not ship an inference.

## 1. Audit: what reaches Flutter

The following values are the complete host-related state surface passed from Kotlin to Flutter. There is no host OS field anywhere in the pipeline.

| Signal | Origin | What it actually means | OS evidence? |
|---|---|---|---|
| `deviceConnected` | `GadgetManager.startUdcPolling` (GadgetManager.kt:823-859) | Host-present heuristic derived from the UDC state string | No |
| `udcState` | `/sys/class/udc/<name>/state` (GadgetManager.kt:795-821) | USB Device Controller state (`not-attached`, `attached`, `powered`, `default`, `addressed`, `configured`, `suspended`, ...) | No |
| `hostConfigurationRequestCount` | Incremented on a false→true host-present transition (GadgetManager.kt:829-832) | **Not** a count of USB configuration requests. A polled host-present transition counter. | No |
| `activeProfileId`, `activeRoleType`, `keyboardWriterReady`, `mouseWriterReady` | TapDucky's own gadget and file descriptors | Local state of the emulated device | No |
| `udcList`, kernel config, root ID, paths, gadget directories | `getDiagnostics` (GadgetManager.kt:2003-2083) | Properties of the Android device | No |
| Logs | `LogBus` | Free-form native messages, including UDC transitions | No |

Flutter receives this through `MainActivity.kt` (`getStatus`, `getDiagnostics`, and the `gadget_status` event channel), `platform_gadget_service.dart` (`GadgetStatus`), and `hid_status_controller.dart` (`HidStatus`).

### Findings

1. **The counter is misnamed.** `hostConfigurationRequestCount` is reset on activation/teardown and incremented in `startUdcPolling()` when `isLikelyHostPresent(udcState)` changes from false to true. It never observes a USB `SET_CONFIGURATION` request, because the kernel HID gadget function does not expose control requests to userspace. It must not be reused as OS evidence.
2. **UDC state is not host identity.** The kernel documents these values as the current state of the USB Device Controller, with the valid values `not-attached`, `attached`, `powered`, `reconnecting`, `unauthenticated`, `default`, `addressed`, `configured`, and `suspended`; controllers need not report all of them. `configured` only means the host configured the gadget.
3. **No OS descriptors are configured.** The gadget code contains no `os_desc`, `b_vendor_code`, or `qw_sign` usage. Microsoft OS descriptors are a Windows-specific compatibility mechanism, not a general host OS detector.
4. **The HID function exposes reports, not enumeration.** Userspace can write input reports to `/dev/hidgN` and can read host output reports (for example keyboard LED state). Descriptor requests, `SET_IDLE`, descriptor ordering, and vendor requests are handled by the kernel and are not surfaced to TapDucky.
5. **Connection smoothing can outlive a physical disconnect.** `hid_status_controller.dart` may keep `deviceConnected` true for up to 15 minutes when UDC reads are ambiguous. That is a UX mechanism, not proof that the same host is still attached, and it is never used as OS evidence.

## 2. Passive inference feasibility

There is no standard USB mechanism by which a device learns the host OS. Reported techniques rely on host behavioral fingerprints during enumeration (for example `SET_IDLE` usage, `GET_DESCRIPTOR` ordering and lengths, Microsoft OS descriptor requests, or timing). Those observations are not exposed through the current configfs HID function.

An external USB analyzer was not available in this environment, and no Windows, macOS, iPhone, or second Android host was available for physical enumeration tests. The development machine is a Linux VM with no USB passthrough for the phone; the phone was reachable only over Wi-Fi ADB. Consequently no passive fingerprint dataset was collected, and no classifier is implemented. Adding one would require changing the gadget/observation architecture and validating it across at least two physical hosts per platform; even then it would remain heuristic.

## 3. Implemented diagnostics

- `HostOs` (`unknown`, `windows`, `macos`, `linux`, `android`, `ios`) and `HostOsSource` (`none`, `manual`, `verified`, `inferred`).
- `HostOsDiagnostic` defaults to Unknown/none. Labels are always qualified:
  - Unknown → `Unknown`
  - manual → `Windows (Manually selected)`
  - inferred → `Likely Windows`
  - verified → `Windows (Verified by companion)`
- Manual selection is stored in app settings. It is diagnostic-only and is never read by the DuckyScript parser, executor, scheduler, or HID code.
- Device Information now shows **Host connected** and **Host OS** as separate rows, plus the manual selector.
- Inferred/verified values are session-scoped and are cleared on session end, connection loss, or a new host-present transition. The transition counter is used only as a session-change trigger, never as OS evidence. A manual label persists and remains labelled manual.
- No automatic inference and no companion integration are shipped. No companion is required for HID use.

## 4. Verification matrix

| Case | Result | Notes |
|---|---|---|
| Windows, macOS, Linux (each separately, direct, hub, reconnects, sleep/wake) | **Not tested** | No Windows/macOS hosts; the phone has no USB passthrough to the Linux development VM. |
| Android (second phone as host and not host) | **Not tested** | No second Android host available. A non-enumerating host remains Unknown by design. |
| iPhone (unlocked/locked, approval, USB-C/Lightning) | **Not tested** | No iPhone or Lightning/USB-C accessory path available. Blocked communication cannot produce a label because no inference exists. |
| No host, no cable, charge-only cable, unsupported instrumentation | **Not tested** | Physical cable/instrumentation changes were not available. There is no inference code, so none of these conditions can produce an OS guess. |
| Missing or incomplete observations with a connected host | **Pass (device + automated)** | On-device with an enumerated host (UDC state `CONFIGURED`), the app showed `Host connected: Connected` and `Host OS: Unknown`; it did not invent a label. Automated tests cover the default Unknown state and the absence of an inference path. |
| Switching hosts | **Not tested physically** | Automated test covers clearing on disconnect and on a new host-present transition; no two-host physical test was possible. |
| Manual selection | **Pass (device + automated)** | On-device selection of Windows displayed `Windows (Manually selected)` and the manual-only explanation; it was reset to Unknown afterward. Widget tests cover the selector and the `Likely ...` label used for inference. |
| USB regressions (arm/disarm, host readiness, Stop/Panic Stop, restoration, Wi-Fi ADB) | **Not tested (live)** | Live arm/disarm/Stop/Panic/restoration were skipped to avoid changing the user's armed composite session. Those code paths (binding, restoration, Stop, Panic Stop) were not modified. Wi-Fi ADB remained active through build, install, and diagnostics. |
| Flutter tests | **Pass** | 72 tests pass, including new model, controller, settings, and widget tests. |
| Release build + install | **Pass** | Release APK built, re-signed with the installed app's debug key, installed with data preserved. |

## 5. Recommendation

Automatic detection is **unsupported**, not experimental, for this architecture. The app should continue to return Unknown unless the user selects a manual label. Revisit only if a future design can expose controlled enumeration observations and is validated on at least two physical hosts per OS family; even then the UI must say `Likely <OS>` and the value must never feed payload selection or execution.

## Sources

- Linux kernel ABI, `/sys/class/udc/<udc>/state`: <https://mjmwired.net/kernel/Documentation/ABI/stable/sysfs-class-udc>
- Linux USB HID gadget driver: <https://docs.kernel.org/usb/gadget_hid.html>
- Kernel HID gadget implementation (`f_hid.c`): <https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/usb/gadget/function/f_hid.c>
- Linux USB gadget ConfigFS documentation: <https://docs.kernel.org/usb/gadget_configfs.html>
- Microsoft OS 1.0 descriptors (Windows-specific compatibility descriptors): <https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/microsoft-os-1-0-descriptors-specification>
- No standard host-OS identification from a HID device: <https://stackoverflow.com/questions/15874601/detect-os-by-hid-device>
