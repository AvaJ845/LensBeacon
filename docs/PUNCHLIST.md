# LensBeacon — Consolidated Punch List (Phase 3)

**BLUF:** The MVP builds clean (0 warnings, strict concurrency complete), 16 unit
tests pass, and the privacy hard-gate passes (no networking, no location,
central-role only). It is **TestFlight-ready after 3 blockers**, most of which are
data/listing work rather than code. It is **not ready to pitch for Apple editorial**
until the signature data is verified and Dynamic Type is fixed.

Severity key: 🔴 blocker (before TestFlight) · 🟠 before public beta · 🟢 v1.1

| ID | Sev | Area | Finding | Fix | Source |
| --- | --- | --- | --- | --- | --- |
| AF-1 | 🔴 | Data | Signature table (company IDs, service UUIDs) is unverified placeholder data. Wrong data → false flags / silent misses, which destroys the "evidence-per-flag" premise. | Capture real advertisements from a Quest (on hand) + borrowed Ray-Ban Meta / Spectacles; correct `SignatureTable`. Until done, label the app "beta — still learning device signatures". | Fellow |
| AR-7 | 🔴 | Legal | Brand names ("Ray-Ban", "Meta", "Snap", "Oakley") appear in binary strings and copy. Nominative use is allowed but unaudited; screenshots/keywords not yet controlled. | Audit every occurrence; keep brand names to in-body prose only; no logos/trade dress; no brand ASO keywords. | App Review |
| AR-9 | 🔴 | Legal | No non-affiliation disclaimer. | Add "not affiliated with / endorsed by Meta, Ray-Ban, EssilorLuxottica, Oakley, Snap" to App Store description **and** in-app About. | App Review |
| AR-1 | 🟠 | Review | `bluetooth-central` background mode not yet justified for 2.5.4. | Write App Review notes: opt-in Unlock feature, persistent Live Activity, central-only, never connects. Attach screen recording. | App Review |
| AR-6 | 🟠 | Tooling | No `.storekit` config file → purchase/restore can't be tested locally. | Add `LensBeacon.storekit` (local only). | App Review |
| HIG-1 | 🟠 | A11y | Dynamic Type breaks above `.xxLarge`: confidence badge clips, segmented picker overflows, row headers collide. | `ViewThatFits` on row headers; size-class-aware picker; dedicated AX pass. | HIG / DE-6 |
| AF-2 | 🟠 | Product | `possible` (bare manufacturer ID) will flood the Dashboard with noise in Meta-dense areas and train users to ignore badges. | Require ≥1 corroborating signal to surface a Dashboard row; log manufacturer-only matches silently to Sightings. | Fellow |
| AF-4 | 🟠 | Perf | Dashboard degrades with 100s of devices: computed sort every render, unbounded `VStack` list. | Cache `flags`/`allInRange` as stored arrays on a debounced tick; cap "everything else" at ~50; count-summary mode above ~20 flags. | Fellow / DE |
| DE-3 | 🟠 | Perf | `writeSnapshot()` (JSON→UserDefaults + ActivityKit) fires on every advertisement. | Debounce to ~1 Hz. | DE |
| AF-3 | 🟠 | Scope | Home Screen widget adds review surface + "why is this stale" support load for marginal value (extension can't self-refresh). | Cut the widget from TestFlight build 1; ship in v1.1 with a BGTask story. | Fellow |
| SP-1 | 🟠 | Privacy | Log uses `.completeFileProtectionUntilFirstUserAuthentication`; `.completeFileProtection` is more defensible for a presence log. | Upgrade; buffer background writes in memory, flush on unlock. | Security |
| SP-4 | 🟠 | Privacy | CSV export includes the opaque `local_key` by default. | Omit by default; "include technical identifiers" as an opt-in checkbox. | Security |
| HIG-10 | 🟠 | Design | No obvious "stop scanning" control in the Live Activity. | Add an App Intent `Button` to end the background scan from the activity. | HIG |
| HIG-7 | 🟠 | Design | Widget's big number layout collides with age line at large text sizes. | `ViewThatFits` / tighter layout. | HIG |
| AR-5 | 🟠 | Review | No Terms/Privacy links on the purchase screen. | Add both to `UnlockView` footer; host `PRIVACY.md`. | App Review |
| GR-1 | 🟠 | Growth | Listing doesn't yet shout "pay once" louder than "detect glasses". | Subtitle "Spot camera glasses. Pay once."; screenshot 1 = pricing model. | Growth |
| GR-4 | 🟠 | Growth | No review-prompt gating. | Add `ReviewPrompt` (post-positive-moment, ≤1/120 days, never session 1). | Growth |
| DE-2 | 🟢 | Perf | Housekeeping `Task` polls every 5s even when not scanning. | Suspend when `state != .scanning`. | DE |
| DE-1 | 🟢 | Concurrency | `BluetoothScanner` safety rests on an unenforced `@unchecked Sendable`. | Convert to `actor` in v1.1, or add `dispatchPrecondition` guards. | DE |
| DE-5 | 🟢 | Memory | scanner ⇄ `CBCentralManager` strong cycle; harmless at app-lifetime but leaks if coordinator becomes recreatable. | Add `teardown()` niling delegate + manager. | DE |
| DE-7 | 🟢 | A11y | `RSSISparkline` exposes only a summary label to VoiceOver. | `AXChartDescriptor`, or min/max/current in the label. | DE |
| HIG-2 | 🟢 | Design | First-run in a crowd shows amber cards with no calm baseline first. | 2s "listening…" state; one plain framing line above the flag list. | HIG |
| HIG-3 | 🟢 | Design | `eye.trianglebadge.exclamationmark` icon leans alarmist. | Use `eyeglasses` / radiowaves; let the amber tint carry state. | HIG |
| HIG-4 | 🟢 | Design | `AccentColor` asset and `Palette.accent` code defined twice, values drift. | Single source of truth. | HIG |
| HIG-5 | 🟢 | A11y | `confidence(.possible)` badge text ~3.9:1 on dark card (< AA 4.5). | Lighten the dark-mode value. | HIG |
| HIG-9 | 🟢 | Design | Dynamic Island compact trailing shows a bare `0` for hours. | Show count only when `> 0`. | HIG |
| SP-6 | 🟢 | Privacy | App-switcher snapshot shows "N cameras nearby". | Optional privacy overlay on `scenePhase == .inactive`. | Security |
| GR-5 / HIG-6 | 🟢 | Brand | Icon reads as RSS/podcast at thumbnail size. | Commission a distinctive mark before pitching editorial. | Growth / HIG |
| GR-3 | 🟢 | Tooling | Screenshot automation needs a demo-seed launch arg. | Add `-demo-data` (Release-safe, seeds Sightings only). | Growth |

## Disagreements surfaced between passes

- **DE vs. Fellow:** the DE cleared the architecture; the Fellow argued the real risk
  is data trust (**AF-1**), not code. Both stand — they are about different layers.
  Resolution: AF-1 is the top blocker; the DE's perf items (DE-2/3) are real but
  secondary.
- **Fellow vs. brief:** the brief lists the widget as an Unlock feature; the Fellow
  recommends cutting it from build 1 (**AF-3**). Resolution: build it (done), ship it
  dark in TestFlight build 1, enable for public beta once DE-3 + a refresh story
  land.

## What's already done (verified this pass)

- ✅ Builds for simulator, 0 warnings, `SWIFT_STRICT_CONCURRENCY = complete` on all targets
- ✅ 16 unit tests pass (confidence engine, signature table, proximity banding)
- ✅ Privacy hard-gate: no `URLSession`/networking, no `CoreLocation`, central-role only, no `connect`/`writeValue`/`startAdvertising`
- ✅ StoreKit 2 non-consumable + Restore, entitlement is source of truth
- ✅ Data Protection on the log + excluded from backup
- ✅ Live Activity uses `pushType: nil` (no token minted)
- ✅ Confidence & proximity are colour + symbol + text with a11y labels
- ✅ Full dark-mode palette; onboarding explains detect / can't-detect / on-device
