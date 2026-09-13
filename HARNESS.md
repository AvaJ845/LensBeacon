# Phase 0 — Detection Validation Harness

**BLUF**: Built inside the existing app as `#if DEBUG`-only code (Settings ▸
About ▸ "Detection harness (dev only)") — not a separate app, not a product
feature, compiles out of every Release/TestFlight/App Store build entirely.
It promiscuously logs every BLE advertisement in range with ms-precision
timestamps to a private on-device SwiftData store, classifies packets
offline and re-runnably (never at capture time), and requires operator-
entered ground truth before any packet is even recorded. It cannot yet
answer the crux question — that needs real hardware, not spoofing (see
**Hardware gap**, bottom). **Kill criterion is pre-registered below, before
any field data exists.**

## What was built vs. the original spec

| Spec item | Status | Note |
|---|---|---|
| Promiscuous scanner, no service filter, `allowDuplicates: true` | ✅ Built | `LensBeacon/Support/Harness/HarnessScanner.swift` |
| Raw capture log, every field, ms timestamps | ✅ Built | `HarnessModels.swift` → `RawPacket`, one row per real packet |
| SQLite/Core Data storage, tens of thousands of rows | ✅ Built | SwiftData, private store, not the App Group |
| Classification kept strictly separate from capture, pure + re-runnable | ✅ Built | `PacketClassifier.swift` — un-gated, unit-tested, zero CoreBluetooth dependency |
| 4 tiers (`companyIDOnly`, `payloadConfirmed`, `unambiguousVendor`, `other`) | ✅ Built | exact tiers from the spec |
| Ground-truth session tagging | ✅ Built | `HarnessView.swift` — environment + per-device booleans + notes, required before capture starts |
| Analysis: counts, interval distribution, RSSI, payload ratio, TPR/TTFD | ✅ Built | `SessionAnalyzer.swift` |
| CSV export, raw + stats | ✅ Built | `HarnessCSVExporter.swift`, via the system share sheet |
| macOS companion target | ❌ **Skipped, deliberately** | the spec itself allows this ("if that's cleaner than exporting") — CSV export + the in-app Analysis/Aggregate screens cover the same need with far less build/signing surface for a tool that exists to answer one question, not to ship. Revisit only if CSV round-tripping into a spreadsheet/notebook proves too slow in practice. |
| Spoofed-advertiser pipeline validation | ⚠️ **Not automated** | the harness will correctly classify a spoofed `0x058E` + `META_RB_GLASS` payload as `payloadConfirmed` (unit-tested), but building an actual second-device broadcaster is a field-protocol step, not code — see protocol below. |
| Meta Quest negative control | ⚠️ **Not automated** | same — this is a field-protocol step (operator owns a Quest). The classifier-level equivalent (`0x058E` + wrong payload → `companyIDOnly`, never `payloadConfirmed`) is unit-tested. |
| Unit tests: truncated data, malformed payload, wrong payload, split-across-frames | ✅ Built | `LensBeaconTests/HarnessClassifierTests.swift`, `HarnessAnalyzerTests.swift` — 24 tests. See **Frame-splitting note** below. |
| Background scanning "for hours in a pocket" | ⚠️ **Honestly cannot promise this** | see **Background limitation**, below — stated loudly, per the spec's own instruction, rather than engineered around. |

## Frame-splitting note

CoreBluetooth doesn't expose true link-layer fragmentation to an app — each
`didDiscover` callback already hands over one fully-assembled manufacturer-
data blob. What "payload present but split across advertisement frames"
actually means on real hardware is a device alternating between broadcasts
that omit the fingerprint and ones that carry it (a legacy 31-byte
advertisement is cramped; not every interval needs to repeat everything).
`PacketClassifier.classify` stays strictly **per-packet** — it will
correctly report `companyIDOnly` for a packet missing the payload, even from
a real pair of glasses. `SessionAnalyzer.outcomes` is where this gets
reassembled into a session-wide answer ("was a confirming payload ever seen
from this session, on *any* packet"), which is the layer that actually needs
to tolerate this. Both are unit-tested for this distinction.

## Background-scanning limitation

iOS only keeps a background BLE scan running reliably when it is filtered by
service UUID. This harness is deliberately unfiltered (a filtered scan could
only ever confirm signatures already in the filter, defeating the point of a
measurement instrument). Consequence: **a multi-hour unattended pocket
session cannot be promised end-to-end.** There is no restart-timer or other
trick that fixes this without narrowing the scan. Field-protocol
implication: run collection sessions **foregrounded** (screen can be off,
but app not force-quit or superseded by another app for extended periods)
wherever the interval-distribution number actually matters; treat any
multi-minute gap in a background capture as probably this throttling, not a
real absence of BLE traffic.

## What this harness can and cannot establish

| Can establish | Cannot establish |
|---|---|
| Per-company-ID advertisement counts and RSSI/interval distributions, for whatever devices are actually presented to it | The crux question, at all, without real Ray-Ban Meta / Spectacles hardware — spoofing only validates the pipeline (explicitly labeled as such everywhere it's used) |
| The payload-confirmed vs. company-ID-only ratio for Meta's shared IDs — quantifies the Quest false-positive problem directly | Cross-session device identity — iOS rotates the peripheral UUID, so two sessions can never be confirmed to be the same physical unit |
| True-positive rate and time-to-first-detection **per session**, segmented by ground-truth category | Which of *N* tagged devices in one session produced a given detection — protocol requires one tagged device per session for a clean read |
| Whether the `META_RB_GLASS` fingerprint / `0x01AB` hypothesis holds up against the operator's own captures | Population-level generalization — this is a screening instrument run by one operator with borrowed/owned hardware, not a market study |
| A reliable answer for **foregrounded** sessions | A reliable answer for **unattended, hours-long backgrounded** sessions (see above) |

## Field protocol

Run **before** trusting any TPR number, in this order:

| Step | Sessions | Duration each | Purpose |
|---|---|---|---|
| 1. Pipeline validation | 1 | 5 min | Second device broadcasting `0x058E` + `META_RB_GLASS` in peripheral mode. Confirms capture → classify → export end to end. **Label all output from this session "pipeline validation only" — never mix into the TPR table.** |
| 2. Quest negative control | ≥3 | 10 min each | Operator's own Meta Quest. Every packet must classify `companyIDOnly`, never `payloadConfirmed`. **Any `payloadConfirmed` hit here falsifies the payload check — stop and investigate before proceeding.** |
| 3. Worn + paired (the crux state) | **≥10 independent sessions**, foregrounded, ≥15 min each, one tagged device per session | 15 min | The number the whole product depends on. Spread across isolated + low-density environments at minimum. |
| 4. Idle (paired, not worn) | ≥5 | 15 min | Contrast: is detectability materially different once actually worn vs. just sitting nearby? |
| 5. Bagged | ≥5 | 15 min | Contrast: the "in a bag" case a user might reasonably assume is invisible anyway. |
| 6. High-density environment | ≥3, worn + paired | 15 min | Does a crowded RF environment (more concurrent BLE traffic) degrade detection independent of device state? |

**"Independent session"** means a fresh app launch and a fresh scan start —
not 10 consecutive 90-second windows inside one long capture. Vary time of
day and location loosely; don't run all 10 back-to-back in the same room.

**Multi-component hardware gotcha, confirmed in the first real field data
(2026-09-12)**: a session's Meta Quest was reported "powered off" in ground
truth, but its peripheral (self-identified by name, "Quest 2") kept
advertising for the full session anyway — most likely its **controllers**,
which have their own BLE radio independent of the headset's power state,
were still on. A single `poweredOff` toggle can't capture "headset off,
accessory still on" for hardware with detachable powered components. Not a
code fix (the Quest isn't the target hardware), but worth remembering for
any negative control run with multi-part gear: power down every component,
not just the one you're thinking of.

## Pre-registered kill criterion

> **If the worn + paired true-positive rate, measured across at least 10
> independent sessions per target device, has a 95%-confidence lower bound
> below 25%, do not build the paid detection feature on this hypothesis
> as-is.**

Rationale for 25%, not higher or lower, stated now so it can't be
rationalized after seeing the data:

- **Not 0%** — some non-zero detection is expected even in the worst case
  (BLE stacks still advertise periodically for reasons unrelated to
  discovery, e.g. connection-parameter updates), so a near-zero floor isn't
  a meaningful bar.
- **Not ~80%+** — that bar would kill almost any passive-RF awareness
  product; LensBeacon's own copy (`Copy.standaloneSilence`,
  `SECURITY.md`'s "Known, permanent limitation") already commits to "a
  silent scan is never proof nothing is nearby" rather than promising
  reliable detection. The product's honesty framing is built to survive
  imperfect recall.
- **25% is the line where the product's core promise stops being honest at
  any framing.** Below it, the feature would be silent more often than not
  during the *exact* scenario ("worn and paired") the whole category is
  sold on and the one state this harness was built to measure. At that
  point no amount of careful copy turns "usually doesn't work when it
  matters most" into a $9.99 Unlock feature worth shipping — the honest
  move is to cut the detection claim, not soften the wording further.

If the measured rate clears 25% but sits well below what feels sellable
(this document does not pre-commit a second, higher "ship with confidence"
threshold — that is a product call for whoever reviews the actual numbers,
not an engineering one), report the number plainly and let that conversation
happen with real data in hand, not before it.

## Hardware gap

Real Ray-Ban Meta or Snap Spectacles hardware is required to run field-
protocol steps 3–6. It cannot be answered by spoofing (step 1 only proves
the pipeline, never the real-world rate). Recommended paths, cheapest first:
a beta tester or friend who owns a pair (fastest, zero cost — matches this
session's existing plan), a retail try-on session at a Ray-Ban / EssilorLuxottica
store (free, but time-boxed and likely one session's worth, not ten), or a
return-window purchase (highest cost, but the only path to unrestricted
session count and duration). Do not treat this gap as a blocker to be
engineered around — there is no synthetic substitute for it.
