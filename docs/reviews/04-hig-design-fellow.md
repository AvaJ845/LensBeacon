# Pass 4 — HIG / Design Fellow

Reviewer lens: Human Interface Guidelines conformance for the Dashboard, Sightings,
widget and Live Activity. Dynamic Type, dark mode, colour semantics, empty states,
and — critically — whether this reads as *informative* or *alarmist*.

## Tone check (the one that matters)

The source brief demands calm, factual, non-panic UI. Current state:

- **PASS:** no full-bleed red, no siren glyphs, no "THREAT DETECTED". Confidence
  colours are muted grey → amber → clay, explicitly **never red** (`Palette
  .confidence`). A flag is a `Card` row with a badge and a sentence of evidence.
- **PASS:** the status header for a flag says "N possible cameras nearby" with a
  muted amber icon, not a red banner.
- **HIG-2 (should-fix): the empty/clear state is currently stronger than the
  detected state.** "Nothing flagged" gets a reassuring `checkmark.shield`. Good. But
  a first-time user who opens the app in a crowd and immediately sees amber cards has
  no calm baseline to compare against. *Recommendation:* the first session should
  open on a short "LensBeacon is listening…" state for ~2s before showing flags, and
  the flag list should be preceded by one plain line: "These devices broadcast
  signals used by camera glasses. A match is not proof of recording."
- **HIG-3 (nit): `eye.trianglebadge.exclamationmark`** as the "flags present" icon
  leans alarmist. Prefer `eyeglasses` or `dot.radiowaves.left.and.right` with the
  amber tint carrying the state.

## Dynamic Type

- **HIG-1 (blocker for public beta): not verified above `.xxLarge`.** Specific
  breakages predicted / observed in the simulator at `.accessibilityExtraLarge`:
  - `ConfidenceBadge` capsule: `.caption` text + fixed 8pt padding → text clips; the
    `Label` icon+text wraps badly.
  - `SightingsView` segmented `Picker` — three segments ("Glasses/All/Mine") overflow
    horizontally; needs to fall back to a `Menu` picker at AX sizes.
  - `FlagRow` header `HStack` (`Text(title)` + `Spacer` + `ConfidenceBadge`) — title
    and badge collide; should switch to a `ViewThatFits` / vertical stack.
  - `RSSISparkline` fixed `height: 64` is fine (not text) but its caption below it
    can push the row very tall.
  *Recommendation:* a dedicated Dynamic Type pass; adopt `ViewThatFits` on the two
  row headers and a size-class-aware picker style. This is table stakes for
  editorial.

## Dark mode

- **PASS:** every colour in `Palette` is defined via `UIColor { traits in … }` with
  both light and dark values, including `canvas`, `card`, `accent`, all three
  confidence colours and both proximity states. The teal accent is lifted for dark
  contrast. `.lensChrome()` hides the default scroll background and paints
  `Palette.canvas` explicitly.
- **HIG-4 (nit): `AccentColor.colorset` (asset) and `Palette.accent` (code) are
  defined twice with slightly different values.** They should match exactly or the
  tint will subtly differ between system-tinted controls and app-drawn ones. Single
  source of truth: derive one from the other, or document that the asset is
  authoritative for system controls.

## Colour semantics / accessibility

- **PASS:** confidence and proximity are always colour **+ SF Symbol + text label**.
  `ConfidenceBadge` and `ProximityChip` carry `accessibilityLabel`/`Hint`. Verified
  legible in Grayscale and Increase Contrast.
- **HIG-5 (nit): `Palette.confidence(.possible)` is plain secondary grey** — correct
  intent (de-emphasise) but on the `card` background in dark mode it's ~3.9:1, under
  the 4.5:1 AA text threshold for the small badge text. Nudge it lighter in dark.

## Empty states

- `EmptyStateView` is consistent (icon + title + one line), used in Dashboard and all
  three Sightings filters with filter-specific copy. **Good.** `LimitsNote` disclosure
  is a nice touch — honesty about limits belongs in the UI, not just the listing.

## Widget legibility

- Small/medium/accessory families all implemented. `containerBackground` set.
- **HIG-7 (should-fix): the widget's big number has no unit at a glance in the
  small size** — "3" then "camera glasses nearby" wraps to 2–3 lines at larger text
  sizes and collides with the age line. Needs `ViewThatFits` or a tighter layout.
- **HIG-8 (nit): accessory circular shows `eyeglasses` + count** — fine, but on the
  Lock Screen an unexplained "3" could read as unread-count noise. Consider the
  inline family as the recommended one and de-emphasise circular.
- Widget shows snapshot age always (`ageLine`) — **good**, prevents stale-as-live.

## Live Activity

- Content hierarchy: leading = count + `eyeglasses`, trailing = nearest band, bottom
  = one plain sentence. **Calm. Good.**
- **HIG-9 (nit): Dynamic Island compact trailing is a bare count.** If it's `0` most
  of the time, that's visual noise in the island for hours. Consider showing the
  count only when `> 0` and a small dot otherwise.
- `keylineTint` / `activitySystemActionForegroundColor` use the accent. Good.
- **HIG-10 (should-fix): there is no explicit "Stop" affordance** in the Live
  Activity. The user can long-press to end it, but a privacy tool running a
  background scan should make stopping obvious. Add a `Button` (App Intent) to end
  the scan directly from the activity.

## Verdict

**Reshape before public beta.** Tone is right — this does not read as a panic app,
and that's the hard part done. But **HIG-1 (Dynamic Type)** is a genuine blocker for
an app whose whole pitch is craft, and **HIG-7/HIG-10** (widget number, Live Activity
stop button) should land before wide release. The rest are polish.
