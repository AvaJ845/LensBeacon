# Pass 1 — Apple Distinguished Engineer: Correctness & Craft

Reviewer lens: architecture, concurrency, CoreBluetooth lifecycle, memory, performance,
platform idioms, accessibility, and — as a hard gate — privacy egress.

## Hard gate: network egress

```
grep -rnE "URLSession|URLRequest|NWConnection|\.dataTask|https?://[a-z]|CoreLocation|CLLocation" --include=*.swift
```

Result: **no hits in code.** The only matches are prose in `BluetoothScanner.swift`
describing capabilities the app deliberately does not use. `NSAllowsArbitraryLoads`
is `false`; `CoreLocation` is not linked; `Info.plist` declares no location keys.
`ITSAppUsesNonExemptEncryption = false`. **Gate passes.**

## Architecture

| Area | Finding | Verdict |
| --- | --- | --- |
| Layering | Pure logic (`SignatureTable`, `ConfidenceEngine`, `ProximityBand`, `RSSISmoother`) is isolated in `Shared/` with no UIKit/CoreBluetooth imports and is unit-tested (16 tests) with no host app. | Good |
| Ownership | `SightingsStore` / `MineRegistry` created in `App.init`, passed to `ScanCoordinator` as `unowned`. Single owner each, lifetime == app. No retain cycle: the coordinator does not own its owners. | Good |
| Scanner boundary | `BluetoothScanner` emits a `Sendable` `ScanEvent`; no `CB` type escapes. Advertisement parsing (`parse(_:)`) extracts exactly four fields. | Good — this is the right seam |
| Coordinator | `@MainActor @Observable`. All observable state mutates on the main actor; scanner callbacks hop via `Task { @MainActor in }`. No locks. | Good |

## Concurrency

- `BluetoothScanner` runs its `CBCentralManager` on a dedicated `DispatchQueue`
  (`qos: .utility`). All mutable scanner state (`central`, `wantsBackgroundMode`) is
  touched only on that queue. The class is `@unchecked Sendable` with a comment
  explaining the discipline. **Acceptable**, but see finding **DE-1**.
- `onEvent` / `onStateChange` are `@Sendable` closures. The coordinator sets them to
  hop to `@MainActor`. Correct.
- `SWIFT_STRICT_CONCURRENCY = complete` on every target. Clean build, **zero
  warnings** after the ActivityKit `nonisolated` split in `ScanActivityController`.
- `UnlockStore.Transaction.updates` listener loop uses `[weak self]`; no `deinit`
  cancellation because lifetime is the whole process (documented).

### Findings

**DE-1 (should-fix): `@unchecked Sendable` on `BluetoothScanner` is load-bearing and
unenforced.** The safety argument ("everything on `queue`") is correct today but a
future edit could add a property touched from `onEvent`'s caller. *Recommendation:*
convert to an `actor` in v1.1, or add a debug `dispatchPrecondition(condition:
.onQueue(queue))` at the top of each queue-isolated method so a violation traps in
testing. Low risk for the beta.

**DE-2 (should-fix): housekeeping `Task` in `ScanCoordinator` polls every 5s for the
life of the app.** It is cheap (a dictionary filter) but it runs even when not
scanning. *Recommendation:* suspend it when `state != .scanning`. Minor battery /
wake hygiene.

**DE-3 (nit): `ScanCoordinator.ingest` calls `writeSnapshot()` on every
advertisement.** With `allowDuplicates` on in the foreground this can be dozens/sec
in a dense room; each call re-encodes JSON to `UserDefaults` and pokes ActivityKit.
*Recommendation:* debounce `writeSnapshot()` to ~1 Hz (a `Task` + timestamp guard,
same pattern as `SightingsStore.scheduleSave`). See also **AF-2** from Pass 2.

## CoreBluetooth lifecycle

- `CBCentralManagerOptionRestoreIdentifierKey` set; `willRestoreState` implemented.
  There is nothing to restore (no connections) so it just re-arms background mode.
  **Correct and minimal.**
- `bootstrap()` is called from `App.task` before any scan, so a CoreBluetooth
  background relaunch has a manager to restore into. **Correct.**
- Background scan uses a service-UUID filter (`knownServiceUUIDs`) and
  `allowDuplicates: false`; foreground uses `nil` services + duplicates. This is the
  correct split — a `nil`-services scan is not serviced in the background. **Good**,
  but note the real limitation in **DE-4**.

**DE-4 (accept / document): manufacturer-data-only devices are invisible to the
background scan.** iOS only delivers advertisements matching the service-UUID filter
while backgrounded, and it strips/relocates manufacturer data and the local name into
the `overflow` area. A Ray-Ban Meta that advertises *only* Meta's company ID (no
service UUID) will be seen in the foreground but not in the background. This is an
OS constraint, not a bug. It is disclosed in `LimitsNote` and should be disclosed in
the Unlock copy too. See **AR-3**, **GR-2**.

## Memory

- No delegate retain cycles: `BluetoothScanner` is owned by `ScanCoordinator`
  (a `let`); it holds the manager, the manager holds the scanner as `delegate`
  (a strong ref by CB convention) — this is a 2-node cycle **scanner ⇄ manager**
  that lives as long as the coordinator, which is fine (app lifetime), but see
  **DE-5**.

**DE-5 (nit): scanner ⇄ CBCentralManager strong cycle.** Harmless given app-lifetime
ownership, but if `ScanCoordinator` ever becomes recreatable (e.g. multi-window on
iPad, or tests), the manager leaks. *Recommendation:* nil the delegate and the
manager in a `teardown()` and call it if the coordinator is deinited.

## Performance / battery

- Foreground continuous scan with `allowDuplicates` is the biggest draw. Mitigated
  by: the scan only runs while the app is foreground *and* (per `applyScenePhase`)
  stops on background unless Unlock + toggle. RSSI smoothing keeps UI churn down.
- `SightingsStore` write is debounced 2s and capped at 2,000 records with LRU
  eviction and a 60-sample timeline cap. **Bounded. Good.**
- **DE-3** debounce would materially cut foreground CPU in a crowded space.

## Accessibility

- `ConfidenceBadge` and `ProximityChip` are colour + SF Symbol + text, with explicit
  `accessibilityLabel` / `accessibilityHint`. **Good — meets the "not colour alone"
  bar.**
- `StatusHeader` combines children and provides a spoken label. Good.
- **DE-6 (should-fix): Dynamic Type not verified above XXL.** The `Card` layouts use
  fixed `padding(16)` and some `.caption2` text that will clip at AX sizes. Needs a
  pass at `.accessibility3+` with the `RSSISparkline` and the segmented picker. See
  **HIG-1**.
- **DE-7 (nit): `RSSISparkline` has a combined a11y label but no data.** A
  VoiceOver user gets "Signal strength trend over N readings" and nothing else.
  Consider an `AXChartDescriptor` in v1.1, or at least min/max/current values in the
  label.

## API surface / testability

- Engine API is small, value-typed, and documented. `ConfidenceEngine.classify` takes
  an injectable `table:` parameter — good for tests.
- `SightingsStore` / `MineRegistry` / `UnlockStore` are not protocol-abstracted, so a
  UI test can't inject fakes. Acceptable for MVP; revisit if UI tests are added.

## Verdict

**Ship the beta.** Architecture is sound, the concurrency model is clean under strict
checking, and the privacy gate passes unambiguously. Address **DE-2/DE-3** (battery)
and **DE-6** (Dynamic Type) before public beta; **DE-1/DE-5** are v1.1 hardening.
