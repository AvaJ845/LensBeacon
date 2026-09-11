# LensBeacon — App Store metadata (paste-ready)

_Apple indexes **App Name + Subtitle + Keywords** as one concatenated string. No
word is repeated across the three._

```
Name (≤30):      Glasses Detector - LensBeacon      (28)
Subtitle (≤30):  Bluetooth scanner, no account      (29)
Keywords (≤100): camera,spy,hidden,smart,wearable,privacy,recording,anti,ble,radar,nearby,alert,protect,find   (96)
```

Home-screen / bundle display name stays **LensBeacon**.

**Combinations harvested:** "glasses detector", "camera glasses detector", "smart
glasses detector", "hidden camera glasses", "spy glasses detector", "bluetooth
glasses scanner", "camera detector no account", "wearable camera radar", "anti spy
glasses", "nearby glasses alert".

**Deliberately excluded:**
- `ray-ban`, `meta`, `oakley`, `snap`, `spectacles`, `even realities` — competitor
  / trademark names; Apple rejects these in metadata (brand names appear in the
  app body only, per App Review note AR-7).
- `hidden camera detector` as a primary target — Trap quadrant, owned by the
  decade-old "Hidden Camera Detector" (id532882360). `hidden` + `camera` ride as
  individual keywords instead.
- `surveillance`, `track`, `stalker`, `who is recording` framing — invites the
  App Review "surveillance of a person" question. The subject is a **device
  broadcasting publicly**; keep the language there.
- `AI`, `detect anyone`, `see through` — false-capability claims.

**Category:** Utilities. **Age rating:** 4+. **Privacy nutrition label:** Data Not
Collected (no network requests exist).

---

## Naming Council — 2026-09-10

| Fellow | Lean | Key finding |
|---|---|---|
| Discoverability | Approve | Keyword-first name (28 ch). Subtitle reuses no Name word; Keywords 96/100, singular, no repeats. "glasses detector" is Indie Battlefield — 3 sub-1-year competitors ([Nearby Lens](https://apps.apple.com/us/app/nearby-lens-glasses-detector/id6760046620), [NoGlasshole](https://apps.apple.com/us/app/noglasshole-glasses-detector/id6760988897), [Nearby Glasses Ray-Ban Scanner](https://apps.apple.com/us/app/nearby-glasses-ray-ban-scanner/id6760216782)), none dominant. |
| Collision | Approve (note) | No "LensBeacon" / "Lens Beacon" on the App Store. Nearest confusable is "Nearby Lens: Glasses Detector" — shares the word "Lens" and the category; "Beacon" + distinct icon/positioning separate them. No exact or near-exact collision. |
| Portfolio | Approve | `com.avaresearch.lensbeacon` — correct AvaResearch utility namespace, not a bird name (reserved for the Kestrel / Hummingbird finance lane). No portfolio keyword conflict. No trademarked mascot to split. |

**VERDICT: Approve** — ship "LensBeacon", store name "Glasses Detector - LensBeacon".

Sources: [Nearby Lens](https://apps.apple.com/us/app/nearby-lens-glasses-detector/id6760046620) ·
[NoGlasshole](https://apps.apple.com/us/app/noglasshole-glasses-detector/id6760988897) ·
[Nearby Glasses Ray-Ban Scanner](https://apps.apple.com/us/app/nearby-glasses-ray-ban-scanner/id6760216782) ·
[Hidden Camera Detector](https://apps.apple.com/us/app/hidden-camera-detector/id532882360)
