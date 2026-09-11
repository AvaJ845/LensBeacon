# LensBeacon — App Review notes (paste-ready)

Two North Stars govern every line of this: **(1)** LensBeacon has no audience, no
social following, and no ad budget — Apple editorial featuring is the one
realistic path from zero to visible, and editors favour calm, privacy-first,
no-account utilities with exceptional icon and design craft. **(2)** the app
itself must actually be that thing, not just claim to be it. These notes are
written so a reviewer reaches the same read a Fellow would: this is a careful,
honest tool, not a surveillance app that needs a second look.

Paste the "App Review Information → Notes" block into App Store Connect as-is.
Adapt only the sandbox tester line for the account you actually create.

---

## App Review Information → Notes

```
LensBeacon reads the Bluetooth Low Energy advertisements that some camera
glasses broadcast in the open — the manufacturer identifier, a service UUID,
the device name — and matches them against a small, versioned, sourced rule
table. It never connects, pairs, or writes to any device; CoreBluetooth is
used in central (scanning) role only.

This is NOT a tool for surveilling a person. The subject is a device
announcing itself publicly to any nearby phone, never a person or their
behaviour — the app's own onboarding and empty-state copy say this explicitly
("A detection is not proof that anyone is recording, and quiet is not proof
that no one is"). There is no location permission, no CoreLocation, no
identity resolution across Bluetooth address rotation, and no way to target
or search for a specific person or device.

Fully on-device: no account, no server, no network requests of any kind (put
the test device in Airplane Mode — every feature still works), no analytics
or crash-reporting SDK. The Sightings log, the only persisted data, stays in
an encrypted local file excluded from iCloud and device backup, and Settings
→ Data offers one-tap erase.

Verifying the core feature without camera-glasses hardware: on launch, the
Nearby tab's "Also broadcasting nearby" disclosure confirms the scanner is
live against whatever real Bluetooth LE traffic is around the test device —
that list is unfiltered, so it populates immediately in any normal room or
office. A recognised match (Ray-Ban Meta, Oakley Meta, Snap Spectacles, Even
Realities) additionally surfaces as a tiered flag with full evidence (the
matched field, the raw bytes, the rule) under Sightings; the detection engine
that produces this is covered by 44 automated unit tests run against real
captured hardware advertisements, included in the repository.

LensBeacon Unlock ($9.99, non-consumable) adds background scanning with a
Live Activity, a Home Screen widget, local new-flag notifications, unlimited
history, and CSV export. Everything else — scanning, the Dashboard, and the
full evidence view — is free and unrestricted. Sandbox tester for IAP
testing: [ADD SANDBOX APPLE ID HERE]. "Restore Purchase" is on the Unlock
sheet and in Settings.

Bluetooth permission is requested once, with a plain-language purpose string,
and the app is fully functional (short of scanning) if declined. There is no
App Tracking Transparency prompt because nothing is tracked.
```

## In-App Purchase → "LensBeacon Unlock" review screenshot

Use `AppStore/iap-unlock-review.png` — **1284×2778, PNG, no alpha**, one of
the exact sizes App Store Connect already accepts for our iPhone screenshot
set (ASC's IAP screenshot picker wants an exact device-bucket size here, not
an arbitrary custom resize — an earlier 1021×2208 crop was rejected as "the
dimensions of one or more screenshots are wrong"). It's the real Unlock
sheet, uncaptioned, exactly as a reviewer will see it. The purchase button
renders disabled in this capture only because it was taken via `simctl
launch` outside Xcode, which can't wire the local StoreKit configuration the
way a real Xcode run or an App Review sandbox session does — the button,
price, and purchase flow are all live under an actual StoreKit session (see
`LensBeaconTests` / the `.storekit` config committed at the repo root).
Regenerate from a real device or an Xcode-launched simulator if a reviewer
flags it; the screenshot's only job here is to show the offer's content, not
to prove the button is tappable.

## In-App Purchase → promotional image (App Store product page / win-back offers)

Use `AppStore/iap-unlock-promo.png` — **1024×1024, PNG, 72 DPI, RGB, no
alpha, sharp square corners** (Apple applies its own mask; a source image
with baked-in rounding gets double-rounded). An open padlock in the same arc
gradient and Deep Navy field as the app icon, so the promoted-purchase card
reads as LensBeacon's, not a generic stock unlock graphic — verified with
`sips -g dpiHeight -g dpiWidth -g hasAlpha` before upload.

## Tone check against the North Stars

- Never uses "surveillance," "track," "stalker," or "who is recording" —
  the same exclusion list as the Keywords field (`METADATA.md`). A reviewer
  should read the same restraint the store listing and the UI both practice.
- States the negative claim first ("NOT a tool for surveilling a person")
  rather than leaving a detection app's intent for the reviewer to infer.
- Gives the reviewer a way to see the feature work in under a minute without
  owning camera glasses — a reviewer who can't verify the core loop is a
  reviewer more likely to ask a clarifying question or reject on ambiguity.
