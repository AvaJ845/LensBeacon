# LensBeacon — Architecture

## Principles

1. **The privacy posture is architectural, not a policy.** There is no networking
   code to misconfigure and no location framework linked. `NSAllowsArbitraryLoads` is
   `false` as belt-and-braces. If a future change tried to make a request it would
   fail loudly.
2. **Pure logic is separated from I/O.** The classification pipeline
   (`SignatureTable` → `ConfidenceEngine` → `ProximityBand`) has no CoreBluetooth or
   UIKit dependency, lives in `Shared/`, and is unit-tested with no app host.
3. **One actor owns the mutable state.** `ScanCoordinator` is `@MainActor
   @Observable`. Bluetooth callbacks hop onto it. No locks, no shared mutable state
   outside an actor.
4. **The evidence the UI shows is the structure the decision was made from.** A flag's
   "why" screen renders the same `ConfidenceEngine.Evidence` the classifier produced —
   they cannot drift.

## The scan pipeline

```
CBCentralManager (private serial queue)
   │  didDiscover(peripheral, advertisementData, rssi)
   ▼
BluetoothScanner.parse()            ── extracts exactly 4 fields:
   │                                    companyIdentifier, serviceUUIDs, localName, isConnectable
   ▼  ScanEvent  (Sendable)
   │  Task { @MainActor }
   ▼
ScanCoordinator.ingest()
   ├─ ConfidenceEngine.classify()   ── category? confidence? evidence[]
   ├─ RSSISmoother (per device)     ── EMA → ProximityBand
   ├─ live[peripheralKey]           ── in-memory "what's nearby now"
   ├─ SightingsStore.record()       ── durable log (debounced write, capped)
   ├─ maybeAlert()                  ── local notification if likely/strong + opted in
   └─ writeSnapshot()               ── DashboardSnapshot → App Group → widget + Live Activity
```

### Why a distilled `ScanEvent` instead of passing the advertisement dictionary

`advertisementData` is `[String: Any]` — not `Sendable`, and full of fields we do not
want and must not keep. Parsing it synchronously on the Bluetooth queue and emitting a
small value type means (a) strict concurrency is satisfied end to end, (b) the
"what we keep" surface is one struct you can read in ten seconds, (c) the engine is
trivially testable.

## The confidence model

Three bands, never a percentage (false precision on noisy BLE data):

| Matched signals | Band |
| --- | --- |
| manufacturer ID only | `possible` |
| manufacturer ID + service UUID | `likely` |
| service UUID + name (no manufacturer data present) | `likely` |
| manufacturer ID + service UUID + name pattern | `strong` |

The manufacturer clause is a **filter, not a requirement**: contradictory
manufacturer data rejects a signature outright; *absent* manufacturer data lets the
other clauses carry a match (many real advertisements omit the company ID).

**Headsets never become camera flags.** A Quest / Vision Pro identified by a
*distinguishing* signal (name or headset-specific service) is classified `.headset`
and shown but never flagged. A match on only the *shared* company ID (Meta's ID covers
glasses and Quest alike) is too weak to reclassify and is dropped, so a bare Meta
advertisement can still surface as `possible` per the model above.

> ⚠️ The concrete company IDs and service UUIDs in `SignatureTable` are **placeholder
> values pending validation against real device captures** (Punch List AF-1). The
> matching *logic* is tested; the *data* is not yet trustworthy.

## Proximity

`RSSISmoother` keeps a light EMA (α = 0.25) per device and only reports a band change
when the smoothed value genuinely crosses a threshold, so the Dashboard doesn't
strobe. Bands: `near` ≥ −55 dBm, `nearby` −55…−75, `far` < −75. **No direction, no
distance, no arrows** — RSSI through a body and walls cannot support them, and a
confident arrow pointing at a stranger is the alarmist UI this app must not be.

## Persistence

| What | Where | Protection |
| --- | --- | --- |
| Sightings log | `sightings.json` in the App Group container | `.completeFileProtectionUntilFirstUserAuthentication` + `isExcludedFromBackup` (upgrade to `.completeFileProtection` — SP-1) |
| Onboarding flag, unlock mirror, "mine" keys, prefs | App Group `UserDefaults` | Container Data Protection; contents non-identifying |
| Dashboard snapshot (counts + bands only) | App Group `UserDefaults` | Overwritten constantly; no history, no identifiers |

The log is one record per `peripheralKey` (iOS's per-app device UUID — **not** a
MAC), keeping a strongest-classification high-water mark and a capped 60-sample RSSI
timeline. Hard cap 2,000 records with least-recently-seen eviction; age pruning at
7 days (free) or unlimited (Unlock).

## Background scanning (LensBeacon Unlock)

- Opt-in toggle → `bluetooth-central` background mode.
- Background scan uses a **service-UUID filter** (`knownServiceUUIDs`) with
  `allowDuplicates: false` — the only kind of scan iOS keeps servicing off-screen.
  Foreground uses `nil` services + duplicates to also catch manufacturer-only devices.
- A persistent **Live Activity** (`pushType: nil` — no token minted) keeps the scan
  visible and stoppable.
- `CBCentralManagerOptionRestoreIdentifierKey` + `willRestoreState` resume the scan
  after a CoreBluetooth background relaunch. Nothing to reconnect — this app never
  connects.

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
        └──embeds──▶ LensBeaconWidget ──▶ Shared/
```

`Shared/` is compiled into all three targets. It is the reason the pure logic has no
UIKit-only dependencies — `Theme.swift` imports SwiftUI, which is fine everywhere,
but the engines import only `Foundation`.
