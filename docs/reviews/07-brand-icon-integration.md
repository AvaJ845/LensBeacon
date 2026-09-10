# Pass 7 — Apple Fellow: Brand + Icon Integration

Reviewer lens: did the Apple Fellow brand kit land in the project at editorial
quality, without disturbing the privacy/detection architecture the earlier passes
signed off?

## What was done

| Area | Change |
| --- | --- |
| Icon source | Vendored the brand kit into the repo: `Icon_Source/` (SVG + raster masters, Icon Composer layers, brand tokens) and `Fellow_Brief/` (brand spec, screenshot matrix). The repo is now self-contained. |
| iOS / iPadOS icon | `AppIcon.appiconset/icon-1024.png` replaced with `LensBeacon_iOS_iPadOS_1024.png` (the approved master, unaltered). Single-size asset — Xcode derives every size. |
| watchOS icon | New `LensBeaconWatch/Assets.xcassets/AppIcon.appiconset` from `LensBeacon_watchOS_1088.png`, proportionally scaled 1088→1024 (a resample, not a redraw). |
| watchOS target | New single-target watchOS app `LensBeaconWatch`, embedded in the iOS app. Reuses `Shared/` engine files and `BluetoothScanner` verbatim; its own `WatchTheme` (no UIKit) and glanceable UI. |
| Palette | `Shared/Theme.swift` re-based on the brand tokens: Beacon Blue accent (Lens Cyan on dark), `#F8FAFC` / Deep Navy canvases, lifted-navy dark cards. Confidence ramp changed from amber→clay to one calm blue ramp (never red, never green). `AccentColor.colorset` updated to match the code exactly (closes **HIG-4**). |
| In-app mark | `Mark.imageset` regenerated from the master's arc/lens geometry, flat Beacon Blue on transparent (was the old concentric-ring art — closes the repo half of **GR-5 / HIG-6**). |
| Tooling | `Tools/make_icon.py` rewritten to install the vendored masters + derive the mark (no more independent redraw). `-demo-data` launch arg seeds the Sightings log only (engine-classified, disclosed) and `-screen <name>` opens a screen — both for App Store capture, never set on a normal launch. |
| Screenshots | Real Simulator captures at App Store dimensions: iPhone 6.9″ 1320×2868, iPad 13″ 2064×2752, Apple Watch Ultra 3 422×514, under `Screenshots/AppStore/`. Flattened to opaque RGB. |

## Validation

- ✅ iOS target builds (iPhone 17 Pro Max, iOS 26.5 SDK / Xcode 26), 0 warnings.
- ✅ watchOS target builds (Apple Watch Ultra 3, watchOS 26.5 SDK), 0 warnings.
- ✅ Embedded build: iOS app + widget + watch app link together, 0 warnings.
- ✅ 16 unit tests pass (unchanged).
- ✅ Privacy hard-gate still clean: `grep` for `URLSession` / `CoreLocation` /
  `Network` / analytics / `.connect(` / `startAdvertising` across the app, watch,
  widget and Shared — nothing. No third-party dependency added.
- ✅ Icon legibility swept at 29/40/60/120/180/512/1024 px on light and dark
  grounds, square (iOS) and circular (watch) masks — the lens/beacon silhouette
  survives to 29 px; recognisable at 40 px.
- ✅ watchOS icon is navy-on-navy-lifted, not black-on-black.
- ✅ Screenshot exports are opaque PNG at the correct pixel dimensions.
- ✅ Accessibility unchanged: confidence and proximity are still colour **+ SF
  Symbol + text** everywhere, including the new watch components; Dynamic Type
  behaviour is untouched (see **BLOCKERS**).

---

## BLOCKERS

1. **Signature data is still unverified placeholder (`AF-1`).** Unchanged by this
   pass and still the top blocker. The brand work makes the app *look* finished,
   which raises the stakes: a polished app pointing confident evidence at the wrong
   manufacturer is worse than a rough one. Capture real advertisements from a
   Quest + borrowed Ray-Ban Meta / Spectacles before any wide beta.
2. **Layered Icon Composer `.icon` not produced.** The brief asks for the layered
   icon "when the project supports it" — Xcode 26 does. This pass ships the
   flattened master (App Store-valid, mark exact) because a hand-authored `.icon`
   with the brand's *gradient* foreground could not be build-verified without the
   Icon Composer GUI. **Action:** open `Icon_Source/IconComposer_Background.svg` +
   `IconComposer_Foreground.svg` in Icon Composer, export `AppIcon.icon`, drop it
   in and set `ASSETCATALOG_COMPILER_APPICON_NAME`. ~30 min for someone at a Mac;
   it unlocks the Liquid Glass layering on iOS 26 / watchOS 26.

## SHOULD FIX

1. **Evidence list shows near-duplicate bullets.** A real Meta camera-glasses
   advertisement matches both the `rayban-meta` and `oakley-meta` signatures
   (shared company ID + shared service UUIDs), so `SightingDetailView` renders
   "Manufacturer signal matches Meta" twice and two "Advertises a service
   identifier…" lines. Visible in `Screenshots/AppStore/*/04-sighting-detail.png`.
   Dedupe bullets, or collapse same-vendor matches, in
   `ConfidenceEngine.Classification.evidence` / the detail view. Undercuts the
   "clean evidence" pitch.
2. **Dashboard has no honest hero screenshot.** The Simulator has no BLE radio, so
   the Dashboard always renders "Bluetooth isn't available". The populated
   Dashboard (the "N possible cameras nearby" story, screenshot slot 2 in the
   matrix) needs a device capture with real glasses present, or a deliberate
   product call on a demo mode for the live view. `-demo-data` intentionally seeds
   history only.
3. **Watch app has no background story, by design — make sure the listing says
   so.** The watch scans only while its screen shows LensBeacon. That is the
   honest behaviour, but the App Store text and the watch onboarding (there is
   none yet) should state it so a reviewer doesn't expect wrist-raise alerts.
4. **Dynamic Type above `.xxLarge` still breaks (`HIG-1`).** Pre-existing, now
   inherited by the new watch `WatchConfidenceBadge` capsule (same fixed-padding
   pattern). Do the AX pass across both platforms together.
5. **iPad renders the iPhone views at iPad size** (single column). Honest and
   `TARGETED_DEVICE_FAMILY 1,2` costs nothing, but the screenshot matrix asks for
   "the real iPad three-column experience, not a stretched iPhone". The `ipad-13/`
   screenshots are captured from the real build and correctly sized; they just
   aren't an iPad-native layout yet. Separate piece of work.

## POLISH

1. `-screen` / `-demo-data` are gated only by argument presence. Fine for TestFlight
   (arguments aren't passed on a normal launch) but consider `#if DEBUG` around the
   `-screen` router hook before the App Store build if you want belt-and-braces.
2. The watch detail view's closing paragraph ("Open LensBeacon on iPhone…") assumes
   a paired iPhone. Reads slightly odd on a cellular-only excursion; minor.
3. `Mark.imageset` is still unreferenced in code. It's now on-brand so it's a safe
   asset to keep for an About screen, but if nothing uses it by v1.1, delete it and
   the `make_icon.py` branch that builds it.
4. Consider a watch complication / Smart Stack widget in v1.1 — the glance is
   already the right shape for it.

## EDITORIAL RISK

1. **The mark reads as an eye.** Two arcs around an optical centre is, at a glance,
   an eye — and an eye is the iconography of *surveillance*, the exact thing this
   app is a calm antidote to. The brand kit is explicit that this is the intended
   mark ("two opposing arcs surround a single optical center", "do not
   independently redraw"), so this pass implemented it faithfully. But an editorial
   reviewer at Apple will feel the tension between "privacy utility" and a
   watching-eye icon immediately. If there's room to push back on the brand kit,
   push here: the *lens/aperture* reading (concentric optic, no lids) is on-theme;
   the *eye* reading is not. Worth one more round with whoever owns the brand.
2. **Confidence ramp is now monochrome blue.** Calmer and on-brand, but `likely`
   and `strong` are both "blue" and lean on the SF Symbol + word to separate at a
   glance. Verified distinct in the screenshots; keep an eye on it if the palette
   is ever tuned.
3. **No alarmist visuals introduced** — no red, no shields, no warning triangles,
   no siren glyphs, on either platform. The `eye.trianglebadge.exclamationmark`
   Dashboard glyph flagged in `HIG-3` is still there (pre-existing, not touched
   this pass) and should go.
4. **Screenshot copy stays factual** — the demo seed produces "Possible / Likely /
   Strong" bands from the real engine, no invented device names beyond the product
   families already in the signature table, and the Dashboard "nearby now" is never
   faked.
