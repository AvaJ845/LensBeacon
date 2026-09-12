# LensBeacon — Architecture

## Principles

1. **The privacy posture is architectural, not a policy.** There is no networking
   code to misconfigure and no location framework linked. `NSAllowsArbitraryLoads` is
   `false` as belt-and-braces. If a future change tried to make a request it would
   fail loudly.
2. **Pure logic is separated from I/O.** The classification pipeline
   (`DetectionRuleTable` → `DetectionEngine` → `ProximityBand`) has no CoreBluetooth
   or UIKit dependency, lives in `Shared/`, and is unit-tested with no app host.
3. **One actor owns the mutable state.** `ScanCoordinator` is `@MainActor
   @Observable`. Bluetooth callbacks hop onto it. No locks, no shared mutable state
   outside an actor.
4. **The evidence the UI shows is the structure the decision was made from.** A flag's
   "why" screen renders the same `DetectionEvidence` the classifier produced — they
   cannot drift.

## The scan pipeline

```
CBCentralManager (private serial queue)
   │  didDiscover(peripheral, advertisementData, rssi)
   ▼
BluetoothScanner.parse()            ── extracts AdvertisementFields:
   │                                    manufacturerData, serviceUUIDs16, localName, isConnectable
   ▼  ScanEvent  (Sendable)
   │  Task { @MainActor }
   ▼
ScanCoordinator.ingest()
   ├─ DetectionEngine.classify()    ── category, tier, evidence[] (Detection)
   ├─ RSSISmoother (per device)     ── EMA → ProximityBand
   ├─ working[peripheralKey]        ── in-memory "what's nearby now", published on a debounced tick
   ├─ SightingsStore.record()       ── durable log (glasses only; debounced write, capped)
   ├─ maybeAlert()                  ── local notification if a flag appears + opted in
   └─ writeSnapshot()               ── DashboardSnapshot → App Group → widget + Live Activity
```

### Why a distilled `ScanEvent` instead of passing the advertisement dictionary

`advertisementData` is `[String: Any]` — not `Sendable`, and full of fields we do not
want and must not keep. Parsing it synchronously on the Bluetooth queue and emitting a
small value type means (a) strict concurrency is satisfied end to end, (b) the
"what we keep" surface is one struct you can read in ten seconds, (c) the engine is
trivially testable.

## The detection model

Every flag comes from one small, versioned rule table
(`Shared/DetectionRules.swift` → `DetectionRuleTable.current`, documented in
[`docs/RULES.md`](docs/RULES.md)). Three tiers, never a percentage (false precision
on noisy BLE data):

| Tier | Matched signal | Notification |
| --- | --- | --- |
| Manufacturer (High) | A manufacturer identifier registered to a camera-glasses vendor | Yes, if opted in |
| Service UUID (Medium) | A service UUID registered to a vendor | Yes, if opted in |
| Name (Low) | Advertised name matches a known pattern only | In-app badge only |

A category (`cameraGlasses`, `displayGlasses`, `headset`, `unknown`) is resolved
alongside the tier. **Category precedence beats tier when evidence merges**:
display glasses > camera glasses > headset > unknown, so a headset-only signal (a
company ID shared with that vendor's glasses, e.g. Meta's Quest and Ray-Ban Meta)
never gets upgraded to a camera flag by a stronger *headset* signal — only a
distinguishing camera/glasses signal can do that. Headsets (Quest, Vision Pro) are
shown on the Dashboard so the user knows they're there, but are never flagged and
never persisted to the Sightings log.

Rules that key on a company ID or service UUID shared across a vendor's whole
product line (not just their camera glasses) are excluded outright rather than
tuned — see the exclusion list in `docs/RULES.md`.

**Tier ranks specificity, not authenticity.** BLE advertisements are entirely
self-reported and unsigned — a manufacturer ID is exactly as spoofable as a name,
just less commonly bothered with (see `SECURITY.md`'s "Known, permanent
limitation"). `DetectionTier.explanation` says so at every tier; the UI never
implies a match is verified.

## Proximity and signal strength

`RSSISmoother` keeps a light EMA (α = 0.25) per device and only reports a band
change when the smoothed value genuinely crosses a threshold, so the Dashboard
doesn't strobe. Bands: `near` ≥ −55 dBm, `nearby` −55…−75, `far` < −75. The raw
smoothed dBm is also surfaced directly (`SignalDetailRow`) next to a plain-language
hint ("roughly arm's length…") — never a direction, never a distance in metres or
feet, and never an arrow. RSSI through a body and walls cannot support any of those,
and a confident arrow pointing at a stranger is the alarmist UI this app must not be.

## Persistence

| What | Where | Protection |
| --- | --- | --- |
| Sightings log | `sightings.json` in the App Group container | `.completeFileProtection`, `isExcludedFromBackup` |
| Onboarding flag, unlock mirror, "mine" keys, appearance, prefs | App Group `UserDefaults` | Container Data Protection; contents non-identifying |
| Dashboard snapshot (counts + bands only) | App Group `UserDefaults` | Overwritten at ≤1 Hz; no history, no identifiers |

The log is one record per `peripheralKey` (iOS's per-app device UUID — **not** a
MAC), keeping a strongest-detection high-water mark and a capped 60-sample signal
timeline. Only recognised camera/display glasses are persisted; a headset or an
unmatched device is shown live but never written down. Hard cap on record count with
least-recently-seen eviction; age pruning at 7 days (free) or unlimited (Unlock). A
schema-version bump migrates rather than wipes — `SightingsStore` recovers whatever
individual records still decode and only drops the ones that don't.

## Background scanning (LensBeacon Unlock)

- Opt-in toggle → `bluetooth-central` background mode.
- Background scan uses a **service-UUID filter** (derived from the rule table) with
  `allowDuplicates: false` — the only kind of scan iOS keeps servicing off-screen.
  Foreground uses `nil` services + duplicates to also catch manufacturer-only devices.
- A persistent **Live Activity** (`pushType: nil` — no token minted) keeps the scan
  visible and stoppable, with a Stop button (`PauseScanIntent`).
- `CBCentralManagerOptionRestoreIdentifierKey` + `willRestoreState` resume the scan
  after a CoreBluetooth background relaunch. Nothing to reconnect — this app never
  connects.
- **Quiet hours** (`Shared/QuietHours.swift`) mute new-flag alerts on a daily
  schedule — time only, never a place; a location-based version would be the one
  exception to "no location, ever," so it isn't on the table. Pure, wraparound-aware
  window check (`QuietHours.window(_:start:end:)`), gated in `ScanCoordinator
  .maybeAlert` alongside the existing alerts/unlock checks.

## Watch complication relay (LensBeacon Unlock)

The complication shows real counts without the watch ever scanning on its own —
relay only, never a second scanner:

- `LensBeacon/Support/WatchRelay.swift` (phone) calls `WCSession
  .updateApplicationContext(_:)` with the same `DashboardSnapshot` already written
  for the Home Screen widget, from the same ≤1 Hz debounced call site in
  `ScanCoordinator.writeSnapshot()` — no new timer. `updateApplicationContext` is
  the deliberate choice over `sendMessage`/`transferUserInfo`: it's OS-coalesced
  and latest-value-wins, so it never queues or retries if the watch is
  unreachable, matching data where only the current state is ever meaningful.
- `LensBeaconWatch/WatchRelayReceiver.swift` (watch) receives it, saves it via the
  same `DashboardSnapshot.save()` into the watch's own App Group container
  (`group.com.avaresearch.lensbeacon`, shared between `LensBeaconWatch` and
  `LensBeaconWatchWidget` only — a separate container instance from the phone's),
  and calls `WidgetCenter.shared.reloadTimelines(ofKind:)` so the complication
  redraws. watchOS's own complication-refresh budget still applies on top of
  this — "live" means "as fresh as the system allows a complication to be."
- Without Unlock, or before the first relay ever arrives, the complication falls
  back to the original honest launcher (the mark, tap to open the scanner) — see
  `LensBeaconWatchWidget/LensBeaconComplication.swift`.

## StoreKit

`UnlockStore` (`@MainActor @Observable`): one non-consumable product.
`Transaction.currentEntitlements` is the sole source of truth — the app never trusts a
flag it wrote (the App Group `unlocked` bool is only a *mirror* for the extensions,
which can't query StoreKit). `Transaction.updates` listener handles Ask-to-Buy and
cross-device purchases; `AppStore.sync()` backs Restore.

## Module / target graph

```
LensBeaconTests ──uses──▶ Shared/ (compiled in directly, no app host)

LensBeacon (app) ──▶ Shared/
        │
        ├──embeds──▶ LensBeaconWidget ──▶ Shared/         (Home Screen widget, Live Activity, Control Center control)
        │
        └──embeds──▶ LensBeaconWatch (watchOS) ──▶ Shared/{Detection, DetectionRules,
                          DetectionEngine, ProximityBand, SharedContainer,
                          DashboardSnapshot, QuietHours}.swift
                          + LensBeacon/Scanner/BluetoothScanner.swift
                          │
                          └──embeds──▶ LensBeaconWatchWidget  (complication — relayed
                                            snapshot when Unlocked, launcher otherwise)
```

`Shared/` is compiled into the iOS app, the widget and the tests. It is the reason
the pure logic has no UIKit-only dependencies — `Theme.swift` imports SwiftUI, which
is fine everywhere, but the engines import only `Foundation`.

The **watch app** compiles in only the pure engine files plus `BluetoothScanner`
(CoreBluetooth is available on watchOS; central role only, same as iOS). It does not
take `Theme.swift` (its own `WatchTheme` avoids the `UIColor` trait closures) or the
ActivityKit / StoreKit surfaces — a watch is a glance, not a record. It has its own
`WatchScanModel` (the iOS `ScanCoordinator` stripped of the durable log, Live
Activity, notifications and any background story) and scans only while its screen is
showing. The app icon and palette come from the Apple Fellow brand kit vendored in
`Icon_Source/`.

## How the rule table grows

`LiveSighting` keeps the most recent `AdvertisementFields` for whatever's
currently in range (`lastAdvertisement` — in memory only, gone the moment a
device leaves range, same lifetime as everything else in `working`). Two things
read it:

- **"Suggest what this is"** (`SightingDetailView`, ships to every user) —
  `Shared/ContributionReport.swift` turns those fields plus the user's optional
  guess (`DeviceGuess`) into a plain-text report, handed to the system Share
  Sheet. LensBeacon still makes zero network requests of its own; the user
  chooses where the text goes, identical in spirit to CSV export. This is the
  only path that can produce anything for a genuinely unmatched device — its
  `Detection.evidence` is empty by construction, so without the raw fields
  there would be nothing to report at all.
- **Dev-only tooling** — `LensBeacon/Support/CaptureLog.swift` and
  `LensBeacon/Views/CaptureView.swift`, wrapped in `#if DEBUG`. A fuller raw
  advertisement logger (every variant a device broadcasts, not just the latest)
  for confirming a rule against real hardware before it's added to
  `DetectionRuleTable`. Verified absent from Release builds by symbol and
  string inspection of the compiled binary. See `docs/DEVICE-TESTING.md`.
