# Security

## Reporting a vulnerability

Email **avaresearchLLC@gmail.com** with "SECURITY" in the subject. Please include
what you found, how to reproduce it, and the impact you see. Expect an
acknowledgement within 72 hours.

Please do **not** open a public issue for a security report.

## What is in scope

- The iOS app, widget, and watch app (`LensBeacon/`, `LensBeaconWidget/`,
  `LensBeaconWatch/`, `Shared/`).
- The detection rule table (`Shared/DetectionRules.swift`) — e.g. a rule so broad it
  false-flags unrelated common hardware, or so wrong it points evidence at the wrong
  manufacturer.
- The Sightings log persistence and CSV export — e.g. anything that persists or
  exports more than the user expects.

## Design facts that bound the attack surface

These are enforced by architecture, not policy (see `ARCHITECTURE.md`,
`PRIVACY.md`):

- **No backend.** There is no server owned by this project. There is no endpoint that
  accepts input.
- **No network code at all.** The binary makes zero network connections. App
  Transport Security is strict (`NSAllowsArbitraryLoads = false`) purely as
  belt-and-braces.
- **No account, no analytics, no third-party SDK, no Swift package dependencies.**
  The Privacy Nutrition Label is *Data Not Collected*.
- **CoreBluetooth central role only.** The app never advertises, never connects,
  never pairs, never reads or writes a characteristic. It cannot be used to attack a
  nearby device because it never talks to one.
- **No location.** CoreLocation is not linked; no location Info.plist keys.
- **The Sightings log** is written with Data Protection and excluded from backup. It
  contains iOS's rotating per-app device identifiers (not MACs) and no attempt is
  made to re-identify a device across rotation.
- **No dynamic code, no remote config, no push.** Background behaviour is limited to
  a user-opted-in `bluetooth-central` scan with a visible, stoppable Live Activity.
- **No secrets in the repo or the binary.** There is nothing to embed.

## Known, permanent limitation: BLE advertisements are unauthenticated

**This is disclosed, not undiscovered — please don't file it as a fresh report.**
Every field a detection rule can match — manufacturer ID, service UUID, advertised
name — is self-reported by the broadcasting device. Bluetooth LE advertising has no
signing or authentication for any of it. Any device with a BLE radio and a
general-purpose advertiser/cloner tool can broadcast a fabricated payload that
matches a rule in `DetectionRuleTable`, including the "manufacturer ID" tier —
confirmed directly: a real capture showed a stock BLE advertiser tool cloning Meta's
company ID (`0x058E`) onto a custom name in under a minute, with no special
hardware.

This is a property of BLE advertising itself, not a bug in LensBeacon, and there is
no verification layer a passive scanner could add — the only fix would be Bluetooth
itself gaining signed advertisements. It's why:

- every tier's on-screen explanation says the matched field is self-reported, never
  that the broadcaster is verified (`DetectionTier.explanation`, `Copy.selfReported`);
- "confidence" tiers rank match *specificity*, not authenticity — a manufacturer-ID
  match is exactly as spoofable as a name match, just less commonly bothered with;
- LensBeacon never shows alarmist copy at any tier, high or low — a wrong flag from
  a spoofed signal is exactly as consequential as a wrong flag from a coincidence,
  and the UI is built assuming both happen.

## Supported versions

Only the latest App Store / TestFlight build is supported. Fixes ship in a new build.
