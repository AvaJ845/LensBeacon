# Pass 3 — Security / Privacy Fellow

Reviewer lens: inadvertent data leakage, at-rest protection, backup exposure, and
whether the app respects BLE identifier rotation instead of fighting it.

## Data at rest

| Store | Mechanism | Assessment |
| --- | --- | --- |
| `sightings.json` | `Data.write(options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])` in `SightingsStore.saveNow()`, plus `isExcludedFromBackup = true` | **Good.** Encrypted at rest; unreadable before first unlock after reboot; not in iCloud/iTunes backup. |
| `UserDefaults` (App Group) | onboarding flag, unlock mirror, "mine" keys, prefs, `dashboardSnapshot` | **Acceptable.** App Group defaults inherit the container's Data Protection. Contents are non-identifying (see below). |
| Keychain | not used | N/A — nothing secret to store |

**SP-1 (should-fix): `.completeFileProtectionUntilFirstUserAuthentication` is the
right *default* but the log can contain a week+ of presence history.** For a privacy
tool, `.completeFileProtection` (locked whenever the device is locked) is the more
defensible choice and the marketing claim is stronger. The only cost: a background
scan can't append to the log while the phone is locked in the pocket — but that's
arguably *correct* behaviour for this app. *Recommendation:* upgrade to
`.completeFileProtection`; have the background path buffer in memory and flush on
next unlock.

**SP-2 (nit): `dashboardSnapshot` in `UserDefaults` is a plist, not protected as
strongly as a `.complete` file.** It holds only counts + product-family names +
bands, no identifiers, and is overwritten constantly. Low sensitivity. Leave it, but
don't let it grow to hold per-device history.

## What's actually stored per device

`Sighting` stores `peripheralKey` = `CBPeripheral.identifier.uuidString`. This is
**iOS's per-app, per-device derived UUID, not a hardware MAC.** It is stable only as
long as the OS chooses; it is already anonymised by the platform. LensBeacon:

- does **not** read `CBAdvertisementDataSolicitedServiceUUIDsKey`, TX power for
  ranging math, or any pairing/bonding info;
- does **not** attempt to correlate two `peripheralKey`s as "the same device after
  rotation" — there is no re-identification code, no fuzzy matching on RSSI patterns
  or advertisement timing;
- keeps a strongest-classification high-water mark per key, which resets naturally
  when the OS rotates the key.

**SP-3 (confirm — PASS): the app does not defeat or track around BLE address
rotation.** Verified by inspection. The `Sighting.update` merge is keyed on exact
`peripheralKey` equality only. There is no heuristic that would survive a rotation.
This should be stated plainly in the privacy policy (it is, in `PrivacyDetailView`
and `PRIVACY.md`) because it is a real differentiator vs. tracking-adjacent tools.

## CSV export — does it leak more than the user expects?

`SightingsStore.exportCSV`:

- Header row names **every** column: `local_key,first_seen,last_seen,category,
  confidence,product,vendor,marked_mine,evidence`. No hidden columns.
- `local_key` is the same opaque `peripheralKey` — **SP-4 (should-fix): consider
  omitting `local_key` from the export by default**, or replacing it with a
  per-export random row index. A user who shares their CSV to get help debugging a
  flag doesn't need to hand over even the opaque key. Offer "include technical
  identifiers" as an unchecked option.
- Export is via `fileExporter` (`CSVDocument`) — user picks the destination, no
  auto-share, no default cloud target. **Good.**
- Only rows `withinRetention` are exported — matches what the user sees. **Good.**

## Live Activity / ActivityKit

- `Activity.request(..., pushType: nil)` — **no push token is ever minted.**
  Confirmed in `ScanActivityController`. ActivityKit payloads therefore never leave
  the device.
- `ContentState` carries `flaggedCount`, `strongestConfidence`, `nearestBand`,
  `updatedAt` — counts and enums, **no device identity**. Good.

## Notifications

- `FlagNotifier` posts **local** notifications only (`trigger: nil`), body text is
  the evidence bullet, `userInfo` carries the opaque `peripheralKey` for routing.
  `interruptionLevel = .active` (not `.timeSensitive`, not `.critical`). **Good** —
  no entitlement escalation, no server.

## Logging

- `os.Logger` used throughout with `privacy: .public` **only** on non-identifying
  values (background-mode bool, error `localizedDescription`). No advertisement
  contents, names, or keys are logged. **SP-5 (nit): double-check `error
  .localizedDescription` on a decode failure can't echo file contents** — Foundation's
  JSON errors include byte offsets, not payload, so this is fine, but pin it with a
  comment.

## Threats considered and dismissed

- **Pasteboard:** app never writes to `UIPasteboard`.
- **URL scheme (`lensbeacon://`):** handler only switches tabs; no parsing, no
  fetch, no write. A hostile link is inert.
- **Screenshot / app-switcher snapshot:** the Dashboard can show "N cameras nearby"
  in the app switcher. Low sensitivity (no identities), but **SP-6 (nit / v1.1):**
  consider a privacy overlay on `scenePhase == .inactive` if user testing says the
  count feels sensitive.

## Verdict

**Pass, with two upgrades before public beta:** `.completeFileProtection`
(**SP-1**) and drop `local_key` from the default CSV (**SP-4**). Everything else is
either already correct or a v1.1 nicety. The no-re-identification posture (**SP-3**)
is real and should be marketed.
