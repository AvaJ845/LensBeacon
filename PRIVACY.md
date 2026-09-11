# LensBeacon — Privacy

LensBeacon is built so that its privacy claims are *verifiable from this source
tree*, not taken on trust.

## The claims

1. **Everything happens on your device.** There is no LensBeacon account and no
   LensBeacon server. The app makes **no network connections of any kind.** Put your
   iPhone in Airplane Mode — every feature still works.
2. **LensBeacon listens; it never speaks.** It uses CoreBluetooth in *central* role
   only, to scan for the advertisements nearby devices broadcast. It never connects,
   never pairs, never reads or writes a device's data, and never advertises itself.
3. **No location, ever.** Proximity is estimated only from Bluetooth signal strength,
   in three coarse bands. LensBeacon requests no location permission and does not link
   CoreLocation.
4. **Your history stays on your iPhone.** The Sightings log is a single file,
   encrypted at rest and excluded from iCloud and device backups.
5. **LensBeacon does not track devices or people.** Bluetooth identifiers are rotated
   by iOS on both ends. LensBeacon stores the rotating identifier as an opaque local
   key and makes **no attempt** to re-identify a device across that rotation — there
   is no fuzzy matching on signal patterns, timing, or anything else.
6. **A detection is not an accusation.** A flag means a Bluetooth signature resembles
   camera glasses. It is not evidence that any device is recording, and LensBeacon
   never says it is.

## How to verify

```bash
# 1. No networking, no location, no peripheral/connect APIs.
#    Prints only prose inside code comments.
grep -rnE "URLSession|URLRequest|URLConnection|NWConnection|CFStream|Network\.framework|CoreLocation|CLLocationManager|startAdvertising|CBPeripheralManager|writeValue|readValue|\.connect\(" --include="*.swift" .

# 2. No analytics / crash SDKs.
grep -rniE "firebase|amplitude|mixpanel|sentry|bugsnag|segment|appsflyer|adjust|facebook|googleanalytics" --include="*.swift" .
cat project.yml            # no packages / dependencies section

# 3. App Transport Security blocks arbitrary loads anyway.
plutil -p LensBeacon/Info.plist | grep -A2 NSAppTransportSecurity
```

## Data, by the App Store privacy taxonomy

**Data Not Collected.** LensBeacon collects no data and transmits no data. The
following stay on the device and are never sent anywhere:

| On-device only | Notes |
| --- | --- |
| Sightings log | Opaque per-app device keys, timestamps, matched-signature evidence, capped RSSI samples. Encrypted at rest, excluded from backup. |
| "Mine" list | Opaque keys you chose to suppress. |
| Preferences | Onboarding done, scan toggles, purchase state mirror. |
| CSV export | Only when *you* export, to a location *you* pick. Every column is named in the header. |
| "Suggest what this is" report | Only when *you* share it, to a destination *you* pick (Mail, Messages, AirDrop, ...). Contains a device's advertisement fields and your optional guess at what it is — never your name, location, or anything else about your phone. |
| Session report | Only when *you* share it, same as CSV export — a plain-language summary of the recognised devices in your current history. |
| Watch complication (Unlock) | The same non-identifying summary (counts, tier, age) already written for the Home Screen widget, relayed to your own paired Apple Watch over WatchConnectivity. The watch never scans on its own to produce this; nothing leaves your two devices. |

## Permissions LensBeacon requests

| Permission | Why | If you decline |
| --- | --- | --- |
| Bluetooth | To scan for camera-glasses advertisements. Central role only. | The app explains it can't scan; nothing else breaks. |
| Notifications *(optional, Unlock)* | A local alert when a likely/strong flag appears while you're not looking. | Background scanning still works silently; no alert. |

LensBeacon does **not** request: Location, Contacts, Photos, Camera, Microphone,
Local Network, Tracking (no ATT prompt — there is nothing to track).

## Contact

Security or privacy concerns: see [`SECURITY.md`](SECURITY.md).
