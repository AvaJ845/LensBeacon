# Security

## Reporting a vulnerability

Email **avaresearchLLC@gmail.com** with "SECURITY" in the subject. Please include
what you found, how to reproduce it, and the impact you see. Expect an
acknowledgement within 72 hours.

Please do **not** open a public issue for a security report.

## What is in scope

- The iOS app and widget (`LensBeacon/`, `LensBeaconWidget/`, `Shared/`).
- The signature table (`Shared/DeviceSignature.swift`) — e.g. a signature so broad it
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

## Supported versions

Only the latest App Store / TestFlight build is supported. Fixes ship in a new build.
