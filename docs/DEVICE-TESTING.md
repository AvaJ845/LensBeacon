# Physical device testing

The iOS Simulator has no Bluetooth LE radio, so every detection path has to be
tested on a real iPhone. This is the checklist, plus the one job that needs your
own hardware: confirming the detection rules against real advertisements.

## Setup

1. Open `LensBeacon.xcodeproj` in Xcode 26+.
2. Xcode ▸ Settings ▸ Accounts — add the Apple ID for your development team.
3. Select the **LensBeacon** scheme, pick your iPhone (iOS 18+), `⌘R`, tap **Allow**
   on the Bluetooth prompt. Automatic signing registers the App IDs + App Group.
4. The scheme has a StoreKit config (`LensBeacon.storekit`), so Unlock is testable
   without a sandbox account.

## Smoke test (any iPhone)

| Check | Expected |
| --- | --- |
| Onboarding | 3 panels, Bluetooth ask in context, "awareness not accusation" framing, no account |
| Empty dashboard | brief "Listening…", then "Nothing flagged" with the not-proof line; calm pulse, no red |
| Also broadcasting nearby | expand it — AirPods / watch / TV appear live, labelled anonymous, and are **not** written to the log |
| Listening toggle | Settings ▸ Scanning ▸ "Listen for camera glasses" off → header shows "Scanning paused", nothing detected or logged; survives relaunch |
| Pause button | toolbar pause / header Resume does the same thing |
| Settings ▸ Data | record count + size; clear history / reset mine / erase all; kill the app right after "clear" → stays cleared |
| Dynamic Type → AX5 | flag row stacks title/badge, evidence bytes wrap, Sightings filter becomes a menu — no truncation |
| VoiceOver | tier badge reads "Signal strength: High confidence…", each evidence row reads its AD type + value + raw bytes, sparkline reads a trend sentence |
| Reduce Motion | the scanning pulse stops |
| Airplane Mode | every feature still works |
| Control Centre / Siri | "Scan for camera glasses" control and phrase open the app scanning |

### With Unlock

| Check | Expected |
| --- | --- |
| Background scanning | Live Activity on the Lock Screen; its **Stop** button ends the scan and flips the app to paused |
| Widget | shows the last count + "as of …" age; refreshes within ~1 s of a dashboard change |
| Alert | Tier 1 / Tier 2 camera flag posts one notification with "This is mine" / "Show evidence" actions; a Tier 3 name-only match posts nothing |

## Confirming the detection rules

Every flag comes from `Shared/DetectionRules.swift` (see `RULES.md`).

**Confirmed on hardware (2026-09-10):**
- Meta Quest 2 — `0x058E` + service `0xFEB8` + name `"Quest 2"`
- Even Realities G2 — prefix `0x5245` ("ER") + name `Even G2_32_L_5EFC69`
- Samsung TV — `0x0075` (the reason it is excluded)

**Still sourced only** (SIG registry + a competitor): `0x0D53` (Luxottica), `0x03C2`
(Snap), `0xFD5F` (Oculus), and the camera-glasses name patterns — no real
Ray-Ban / Oakley Meta or Snap Spectacles has been captured.

### The tool — BLE capture (dev only)

A **Debug build** has **Settings ▸ About ▸ BLE capture (dev only)**. It is inside
`#if DEBUG`, so it is **not in the Release / TestFlight / App Store binary** —
nothing to hide from App Review.

It is a full advertisement logger. For every nearby peripheral it records:

- every **distinct advertisement variant** it broadcasts (devices change their
  payload between idle / pairing / connected — you want all of them)
- **manufacturer data** in full hex + the parsed company ID
- **service UUIDs** (16- and 128-bit), **service data**, overflow / solicited UUIDs
- **local name**, `peripheral.name`, Tx power, connectable
- **RSSI**, packet count, first/last seen
- **what the shipping engine currently makes of it**

Central-role scan only — it never connects, pairs, or writes. Nothing is stored or
sent; the only way data leaves the phone is the **Export** button (a Share sheet →
AirDrop / Messages / Files).

### Per device

1. Put the device in pairing mode / take it out of its case; hold the phone ~20 cm
   away. Candidates (anything with manufacturer data or a glasses-ish name) float to
   the top and get an eyeglasses icon.
2. Open each one, and set **"This device is"** to the right tag (Ray-Ban Meta,
   Even Realities G1 — left, …). The tag annotates the export.
3. Tap **Export capture** and send the text.

| Device | Confirm |
| --- | --- |
| **Meta Quest** | `0x058E` seen already. Check whether `0xFD5F` and/or `0x00E0` (Google) also appear, and the exact name. |
| **Even Realities G1 / G2** | ✓ confirmed on a G2: company prefix `0x5245` ("ER") + name `Even G<1|2>_<ch>_<L|R>_<id>`. Capture a **G1** and the **right arm** to confirm the pattern holds. |
| **Ray-Ban / Oakley Meta** | does `0x0D53` or `0x058E` actually appear? The exact advertised name. **Any service UUID at all, in either "Service UUIDs" or "Service data" — not just `0xFD5F`.** This rule is manufacturer-ID-only today, which means it currently cannot be included in the background-scan filter (`ARCHITECTURE.md` → "Background scanning"), so **Unlock's background scanning cannot detect this product at all while backgrounded** until some service UUID is confirmed to add. Also capture with the glasses **connected to their owner's phone, worn normally** — not just powered on and idle — since that's the state that actually matters and it's unconfirmed whether they keep advertising once connected. |
| **Snap Spectacles** | is it `0x03C2`? Exact name. Same service-UUID gap and same connected-state check as above. |

After a table change: `⌘U` (tests stay green — add one for the new signature), then
re-capture to confirm the engine verdict.

### Excluded on purpose

`0x00E0` (Google) and `0x0075` (Samsung) are deliberately **not** matched — every
Pixel and Fast Pair accessory broadcasts the Google ID. If you see one of these in
a capture next to a real pair of glasses, that is the reason we gate on the vendor
company ID, not Google's.
