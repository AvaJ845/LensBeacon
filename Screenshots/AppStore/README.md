# App Store screenshots

Captured from the real Xcode Simulator build (Xcode 26, iOS/watchOS 26.5 SDK) with
`Tools/screenshots.sh`. Regenerate any time:

```
xcodegen generate
Tools/screenshots.sh
```

All files are opaque PNG at current App Store Connect dimensions:

| Set | Device | Pixels |
| --- | --- | --- |
| `iphone-6.9/` | iPhone 17 Pro Max | 1320 × 2868 |
| `ipad-13/` | iPad Pro 13-inch (M5) | 2064 × 2752 |
| `watch-ultra3/` | Apple Watch Ultra 3 (49mm) | 422 × 514 |

## Honesty notes

- **Nothing is fabricated.** The Simulator has no Bluetooth LE radio, so a live scan
  cannot be shown there.
- `02-dashboard` shows the app's real state on a device with no BLE ("Bluetooth
  isn't available"). A populated **Dashboard** ("N possible cameras nearby") needs a
  device capture with real camera glasses present.
- `03-sightings` and `04-sighting-detail` are populated by the `-demo-data` launch
  argument, which seeds the **history log only**. Every record is produced by
  running a synthetic advertisement through the real `ConfidenceEngine`, so the
  bands and evidence shown are exactly what the app would display for a device
  broadcasting that advertisement. `-demo-data` is never set on a normal launch.
- `-screen <name>` opens a specific screen for capture (settings / unlock / detail).
  Screenshot tooling only.
- Watch `02-nearby` / `03-detail` use the same engine-classified demo state
  (`-demo-data`); `01-scanning` is the real empty-scan UI (`-demo-scanning`).

## Not yet captured

- Populated iPhone/iPad Dashboard (needs a device + real glasses).
- iPad three-column layout — the iPad currently renders the iPhone views at iPad
  size (single column). A real iPad layout is a separate piece of work.
- Live Activity / widget / notification frames.
- Watch wrist-raise / Smart Stack (no background scan on the watch by design).
