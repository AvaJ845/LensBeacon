# Detection rules

Every flag LensBeacon raises comes from one small, versioned table:
`Shared/DetectionRules.swift` → `DetectionRuleTable.current`. The scan and UI layers
never change when the table grows.

## Schema

```
DetectionRuleTable
  schemaVersion: Int          // bump only if the Codable shape changes
  rules: [DetectionRule]

DetectionRule
  id:          String          // unique, stable
  productKey:  String          // product identity for "This is mine" (many rules may share one)
  productName: String
  vendor:      String
  category:    cameraGlasses | displayGlasses | headset | unknown
  tier:        manufacturer (1) | serviceUUID (2) | name (3)
  match:       .companyID(UInt16)
             | .serviceUUID16("FD5F")        // matched in AD 0x03 and 0x16
             | .nameContains("Spectacles")   // case-insensitive
             | .nameRegex(#"^G1_\d+_[LR]_"#)
  note:        String          // shown verbatim in the evidence view
```

## Tiers

| Tier | Signal | AD types | Confidence | Background alert? | Live Activity? |
| --- | --- | --- | --- | --- | --- |
| 1 | Manufacturer company ID | `0xFF` | High | Yes | Yes |
| 2 | 16-bit service UUID | `0x03`, `0x16` | Medium (labelled weaker) | Yes | Yes |
| 3 | Advertised local name | `0x08`, `0x09` | Low | **No** — log + in-app badge only | No |

`displayGlasses` (Even Realities) is never a camera detection and never alerts.
`headset` (Quest, Vision Pro) is camera-capable but worn openly — listed, never
flagged, never an alert. When a device matches rules in more than one category, the
**most specific wins**: `displayGlasses` > `cameraGlasses` > `headset` > `unknown`.

**"Confidence" ranks match specificity, not authenticity.** Every AD type here —
manufacturer data, service UUIDs, the local name — is self-reported by the
broadcasting device with no signing of any kind (see `SECURITY.md`'s "Known,
permanent limitation" section). A Tier 1 manufacturer-ID match is exactly as
spoofable as a Tier 3 name match; it's ranked higher only because fewer legitimate
products share it, not because it's been verified. Confirmed directly: a real
capture showed a generic BLE advertiser tool cloning `0x058E` onto a custom name in
under a minute.

## The current set

| Rule | Match | Tier | Category | Source |
| --- | --- | --- | --- | --- |
| `luxottica-company` | company `0x0D53` | 1 | camera | SIG assignment — EssilorLuxottica makes the frames, not the Quest |
| `snap-company` | company `0x03C2` | 1 | camera | SIG assignment (Snap Inc.) |
| `name-rayban-meta` | name `\b(ray-?ban\|oakley\|meta view\|meta glasses)\b` | 3 | camera | product names |
| `name-spectacles` | name contains `Spectacles` | 3 | camera | product name |
| `name-heycyan` | name contains `HeyCyan` | 3 | camera | product name |
| `name-vistaview` | name contains `VistaView` | 3 | camera | product name |
| `even-realities-company` | company `0x5245` ("ER") | 1 | display (no camera) | **captured** on a G2 |
| `even-realities-name` | name `^Even G[12]_\d+_[LR]_` | 3 | display (no camera) | **captured** on a G2 |
| `meta-reality-labs-company` | company `0x058E` | 1 | **headset** | shared Meta ID — **captured** on Quest 2 |
| `meta-feb8-service` | service `0xFEB8` | 2 | **headset** | Meta (Facebook) UUID — **captured** on Quest 2 (list + data `20 01`) |
| `oculus-service` | service `0xFD5F` | 2 | **headset** | SIG registry (Oculus VR) — not yet captured |
| `name-quest` | name `\b(quest\|oculus)\b` | 3 | **headset** | product names |
| `name-visionpro` | name contains `VisionPro` | 3 | **headset** | Apple Vision Pro |

## Shared identifiers that must not stand alone

**`0x058E`** (Meta Platforms Technologies / Reality Labs / Oculus) is used by the
Quest **and** the Ray-Ban / Oakley Meta glasses. First-party testing on 2026-09-10
confirmed a Quest with no glasses present advertises it. So a bare `0x058E` is
classified as a **headset** (worn openly, never flagged). A real pair of glasses is
identified by `0x0D53` (Luxottica, frame maker) or a glasses name — either of which
outranks the headset guess and makes it a camera flag.

## Deliberately excluded

`0x00E0` (Google) and `0x0075` (Samsung) are **not** in the table and must not be
added. Every Pixel and every Fast Pair accessory broadcasts the Google ID; Samsung's
is louder still. Neither vendor ships camera glasses. A future rule that needs either
must gate on a second discriminator (a specific service UUID or name), never the
company ID alone. This is enforced by `DetectionRuleTableTests` and a load-bearing
comment in `DetectionRules.swift`.

## Where new evidence comes from

Two paths feed this table, both landing as a user-sent report — LensBeacon has no
server to receive one automatically:

- **"Suggest what this is"** (`SightingDetailView`, ships to every user) — on any
  live device, matched or not, shares a plain-text report of its advertisement
  fields plus what the person believes it is. The one path that can produce
  anything for a truly unmatched device, since an unmatched `Detection` has no
  evidence of its own (see `Shared/ContributionReport.swift`).
- **BLE capture** (`Settings ▸ About`, Debug builds only) — the fuller developer
  tool, for confirming a rule against many advertisement variants at once
  before/after a table change.

## Adding a rule from a capture

1. Debug build → **Settings ▸ Signature capture**. Put the device in pairing mode,
   hold the phone close.
2. Read off:
   - **company** — the hex (e.g. `0x0D53`). This is Tier 1.
   - **services** — every 16-bit UUID. A vendor-specific one is Tier 2.
   - **name** — the exact advertised string. Tier 3; prefer a regex if it has a
     structured form.
3. Add a `DetectionRule` to `DetectionRuleTable.current`:
   - reuse an existing `productKey` if it is the same product;
   - `category: .displayGlasses` **only** if the hardware has no camera;
   - write a `note` a non-engineer can read.
4. `⌘U`. `DetectionEngineTests` / `DetectionRuleTableTests` should stay green; add a
   positive test for the new signature and, if it is a company ID, a negative test
   for a neighbouring value.
5. Re-capture on device to confirm **engine says** shows the tier you expect.
