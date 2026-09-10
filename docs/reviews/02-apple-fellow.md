# Pass 2 — Apple Fellow: Vision & Tradeoffs

Reviewer lens: challenge Pass 1's conclusions. Is the abstraction right? What should
be cut? Where does it break at scale?

## Where I disagree with the Distinguished Engineer

The DE signed off on the architecture and filed battery/Dynamic-Type nits. Those are
real but they are not the risk. **The risk is that the confidence model is honest but
the signature data behind it is not yet trustworthy**, and no amount of clean
concurrency fixes that.

**AF-1 (blocker): the signature table is plausible-looking placeholder data.**
`SignatureTable.swift` ships specific company IDs (`0x03A3` for Meta, `0x0819` for
Snap) and service UUIDs (`FDF0`, `FE9F`, `FE60`). These are *illustrative*. Some are
almost certainly wrong, and a wrong company ID means either silent non-detection or
false flags on unrelated hardware. The app's entire moat is "transparent
evidence-per-flag" — shipping evidence that points at the wrong manufacturer is worse
than shipping nothing. **This must be validated against real advertisement captures
from actual devices before TestFlight goes wide.** The Quest headset on hand and any
borrowed Ray-Ban Meta / Spectacles are the test rig. Until then the table should be
treated as unverified and the onboarding/limits copy should say "LensBeacon is in
beta and still learning device signatures."

## Is the three-band confidence abstraction right?

**Yes, and Pass 1 undersold why.** A percentage would be dishonest precision. But the
current mapping has a gap:

**AF-2 (should-fix): `possible` is doing too much work.** Right now a bare Meta
company ID → `possible` camera glasses. That same advertisement could be Meta
earbuds, a Portal, a Quest that hasn't sent its name yet, or a Ray-Ban Meta. In a
Meta-heavy environment the Dashboard will fill with `possible` rows that are mostly
noise, and the user learns to ignore the badge — which kills the `strong` signal too.
*Recommendation:* either (a) require at least one corroborating signal (service or
name) to surface a row at all, and log manufacturer-only matches silently to
Sightings; or (b) add a fourth state, `unconfirmed`, that is logged but not shown on
the Dashboard by default. I lean (a) — it makes the Dashboard mean something.

## What to cut from the MVP to ship faster

| Candidate | Keep or cut | Why |
| --- | --- | --- |
| CSV export | **Keep** | Cheap, done, and it is a trust signal ("your data, portable"). |
| Live Activity | **Keep but de-risk** | It is the thing App Review will scrutinise for background-Bluetooth justification (see Pass 5). Worth the cost *because* it makes the background scan honest. |
| Home Screen widget | **Cut to v1.1** | It renders a stale snapshot the extension can't refresh itself. Marginal value, extra review surface, extra "why is this number old" support load. Ship without it; add when there's a BGTask story. |
| "Everything else in range" list | **Keep, collapsed** | Good for trust and debugging; already opt-in. |
| Alternate app icons | **Not built — leave out** | Nice-to-have, not MVP. |
| iPad layout | **Keep (free)** | It's just the same views; `TARGETED_DEVICE_FAMILY 1,2` costs nothing. |

**AF-3 (recommendation): cut the widget from the first TestFlight build.** It is the
weakest feature per unit of review risk and support burden. The Unlock value prop
survives on background scanning + Live Activity + unlimited history + export.

## Where the architecture breaks at scale

**AF-4 (should-fix): the Dashboard degrades in a dense environment.** In a
conference hall the `live` dictionary could hold 200–400 devices. Current behaviour:

- `flags` / `allInRange` are **computed properties that sort the whole dictionary on
  every SwiftUI re-render**. With `@Observable` and a snapshot write per
  advertisement (DE-3), that is O(n log n) sorting many times per second.
- The "everything else" `DisclosureGroup` would try to render a 300-row `VStack`
  inside a `ScrollView` — no cell reuse. That will stutter.

*Recommendations:*
1. Cache `flags` and `allInRange` as stored arrays, recomputed on a debounced tick
   (pairs with DE-3).
2. Cap the visible "everything else" list at ~50 with a "+N more in Sightings" line.
3. The Dashboard should show a count-only summary above ~20 flagged devices
   ("12 possible, 3 likely nearby") rather than 20 cards.

**AF-5 (vision): the dense-room case is also the most important real-world case.**
Someone opens this app *because* they walked into a crowded space and felt watched.
"Calm and factual" has to survive 40 devices, not just 2. The count-summary mode
(AF-4.3) is not a nice-to-have; it is the product working as intended under load.

## The North Stars

- **On-device privacy utility:** fully honoured. Nothing to add.
- **Apple editorial:** the icon is decent-not-distinctive (concentric rings read as
  RSS/podcast at a glance). Editorial-featured privacy apps have *memorable* marks.
  This is a v1.1 investment but flag it now. See **HIG-6**.

## Verdict

**Reshape before wide beta.** The engineering is fine. The product needs: (1)
verified signatures (**AF-1**, blocker), (2) a Dashboard that means something in a
crowd (**AF-2**, **AF-4**), (3) drop the widget from build 1 (**AF-3**). Do those and
this is genuinely differentiated.
