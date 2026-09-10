# LensBeacon

**See the camera glasses around you — on your device, with the evidence for every
flag, and no subscription.**

LensBeacon is a fully on-device iOS app (SwiftUI, iOS 18+) that detects nearby camera
glasses — Ray-Ban Meta, Oakley Meta, Snap Spectacles and other BLE-broadcasting
wearables — by fingerprinting their Bluetooth Low Energy advertisements, and shows
each one with a confidence rating and the exact signals that matched.

> **Status:** MVP + tiered detection engine. Builds clean (0 warnings), unit tests
> pass, privacy hard-gate passes. Landing page: **[lensbeacon site](https://avaj845.github.io/LensBeacon/)**.
> See [`docs/PUNCHLIST.md`](docs/PUNCHLIST.md) for what stands between here and
> TestFlight, [`docs/RULES.md`](docs/RULES.md) for the detection rule table,
> [`AppStore/METADATA.md`](AppStore/METADATA.md) for App Store metadata, and
> [`docs/DEVICE-TESTING.md`](docs/DEVICE-TESTING.md) for how to test on a real
> iPhone.

GitHub Pages: enable Pages for this repo with **Source: Deploy from a branch →
`main` / `/docs`**. The site is `docs/index.html`; `docs/.nojekyll` keeps the
engineering `.md` files out of the published site.

---

## The two North Stars

Every build decision serves **both** of these:

1. **A calm, private, no-account utility.** 100% on-device. No account, no server, no
   analytics, no network calls of any kind. No location services — proximity is RSSI
   banding only. CoreBluetooth central role only: LensBeacon never advertises, never
   connects, never pairs, never reads or writes a characteristic.
2. **Apple editorial featuring is the only realistic path to visibility.** We have no
   audience, no following, no ad budget. Apple's editors favour calm, privacy-first,
   no-account utilities with exceptional craft. So the bar for architecture, UI, and
   the app icon is "would a Fellow ship this".

## What it does / doesn't do

| Does | Doesn't |
| --- | --- |
| Scans BLE advertisements for camera-glasses signatures | Connect to, pair with, or transmit to any device |
| Shows a confidence band (possible / likely / strong) and **why** | Use GPS or any location service |
| Estimates proximity in three coarse bands from signal strength | Claim a direction, distance, or that anyone is recording |
| Keeps a private, on-device sightings history | Send analytics or make any network request |
| Logs headsets (Quest, Vision Pro) but never flags them as covert cameras | Defeat or track around BLE address rotation |

## Free vs. LensBeacon Unlock

**Free, forever:** full scanning, live Dashboard, evidence-per-flag, 7-day history,
"mark as mine", pause/resume scanning, a Control Center control and a "scan for
camera glasses" Siri phrase, and one-tap data erase in Settings.

**LensBeacon Unlock — $9.99, one-time, non-consumable.** No subscription, no trial
countdown, no renewal: background scanning, a Live Activity, a Home Screen widget,
new-flag alerts, unlimited history, and CSV export.

The pricing wedge: competitors either charge yearly (Zuckoff, LensAware) or lock
scanning behind a paywall (AntiZuck, NoGlasshole, Nearby Lens). LensBeacon's scanning
is free and Unlock is bought once.

## Build & run

Requirements: Xcode 26+, iOS 18 SDK. [XcodeGen](https://github.com/yonyz/XcodeGen)
generates the project from `project.yml` (the `.xcodeproj` is also committed so it
opens with no tooling step).

```bash
# regenerate the project after editing project.yml
xcodegen generate

# build for the simulator (no signing needed)
xcodebuild -project LensBeacon.xcodeproj -scheme LensBeacon \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

# run the tests
xcodebuild -project LensBeacon.xcodeproj -scheme LensBeacon \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

For a device build, add your Apple ID in Xcode ▸ Settings ▸ Accounts; automatic
signing registers the two App IDs and the App Group on first run. Team:
`3L683975L8` (AVA Research), bundle prefix `com.avaresearch`.

**BLE scanning does not work in the iOS Simulator** (no radio) — the Dashboard will
show "Bluetooth isn't available". Test detection on a physical iPhone with a real or
borrowed pair of camera glasses / a Quest headset.

### QA launch arguments (Release-safe)

| Argument | Effect |
| --- | --- |
| `-skip-onboarding` | Boot straight to the Dashboard |

## Layout

```
Shared/            Pure, testable logic + types shared by app, widget, Live Activity
  ConfidenceEngine, ConfidenceLevel, DeviceSignature (+ SignatureTable),
  ProximityBand (+ RSSISmoother), DashboardSnapshot, ScanActivityAttributes,
  SharedContainer, Theme
LensBeacon/
  App/           App entry, RootView (two tabs)
  Scanner/       BluetoothScanner (CBCentralManager wrapper — the only CB code)
  Model/         Sighting, LiveSighting, ScanCoordinator (@MainActor @Observable)
  Store/         SightingsStore (durable log), MineRegistry
  Purchases/     UnlockStore (StoreKit 2 non-consumable + Restore)
  Support/       ScanActivityController, FlagNotifier, Haptics, CSVDocument
  Views/         Dashboard, Sightings, SightingDetail, Onboarding, Settings, Unlock
LensBeaconWidget/  Home Screen widget + scan Live Activity (read-only snapshot mirrors)
LensBeaconTests/   Unit tests for the pure engines
docs/
  reviews/       Phase 2 — six sequential adversarial review passes
  PUNCHLIST.md   Phase 3 — consolidated, prioritised
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`docs/BRAND.md`](docs/BRAND.md) for the design rationale and
[`PRIVACY.md`](PRIVACY.md) for the full privacy posture.

## Verifying the privacy claims

```bash
# no networking, no location, central-role only — should print only prose in comments
grep -rnE "URLSession|URLRequest|NWConnection|CoreLocation|CLLocation|startAdvertising|writeValue|\.connect\(" --include="*.swift" .
```

Or: put the phone in Airplane Mode. Every feature still works.
