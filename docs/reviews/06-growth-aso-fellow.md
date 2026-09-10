# Pass 6 — Growth / ASO Fellow

Reviewer lens: given Passes 1–5 and that this is a beta, recommend the App Store
keyword set, screenshot sequence, and how to make "one-time, unlocks everything"
unmissable against a field trained on subscriptions and cheap entry points.

> Full ASO metadata (paste-ready App Name / Subtitle / Keywords) is produced by the
> `aso-playbook` skill and lives in `docs/ASO.md` once run. This pass covers strategy
> and the cross-references back to Passes 1–5.

## The one thing the listing must do

Every competitor teaches a pricing expectation:

- **Zuckoff / LensAware** → "this is a $9.99/yr subscription"
- **AntiZuck ($2.99) / NoGlasshole / Nearby Lens (free + IAP)** → "this is cheap or
  free to start, then nickel-and-dimed"

LensBeacon is **$9.99 once, everything included, scanning free forever**. If a user
reads the listing and still thinks "probably a subscription", the pitch failed.

**GR-1: lead the subtitle and the first screenshot with the model, not the feature.**
- Subtitle candidate: **"Spot camera glasses. Pay once."**
- First screenshot headline: **"One payment. No subscription. Ever."** with the
  feature list beneath.

## Keyword set (safe / high-intent)

**Use:** `smart glasses`, `camera glasses`, `glasses detector`, `spy glasses`,
`hidden camera`, `bluetooth scanner`, `privacy`, `detect`, `wearable camera`,
`recording glasses`, `AR glasses`, `nearby devices`, `BLE scanner`.

**Do NOT use (per Pass 5, AR-8):** `ray-ban`, `rayban`, `meta`, `oakley`, `snapchat`,
`spectacles`, competitor app names. Trademark-bidding + 5.2.1 + 4.3 risk.

**Borderline — test:** `zuck` (cultural shorthand, but reads as targeting a person;
skip for the calm-utility positioning). `anti spy` (fine).

Title should stay brand-free: **"LensBeacon"** or **"LensBeacon: Glasses Detector"**
(generic descriptor is allowed; a trademark is not).

## Screenshot sequence (6.9" / 6.5" / iPad)

| # | Shows | Caption | Why |
| --- | --- | --- | --- |
| 1 | Unlock screen feature list | **"One payment. No subscription. Ever."** | Kills the pricing objection before anything else |
| 2 | Dashboard with 2 flags (`possible` + `likely`), calm palette | "See what's broadcasting around you" | The core loop, undramatic |
| 3 | Sighting detail — the **evidence bullets** | "Every flag shows exactly which signals matched" | The actual differentiator — no competitor has this |
| 4 | Privacy detail screen | "No account. No servers. Works in Airplane Mode." | Editorial catnip; verifiable claim |
| 5 | Sightings log with filter | "A private history, only on your iPhone" | Depth without a subscription |
| 6 | Live Activity on Lock Screen | "Know when it's scanning. Stop it anytime." | Shows the background feature is honest, not creepy |

- **GR-3:** shoot from a **Release** build using `-skip-onboarding` and a demo-seed
  launch arg (needs building — see Punch List). Do **not** show real brand products
  or logos in the frame (Pass 5, AR-7).
- Captions use "camera glasses" generically; brand names only if they appear as
  incidental small UI text.

## Review-prompt / momentum plan

- `SKStoreReviewController` (`requestReview`) **only** after a genuinely positive
  moment: the user opened a flag's evidence, then marked a device "mine" (i.e. they
  engaged with the feature working), and only once per 120 days, never on first
  session, never after a `possible`-only session. **GR-4: this is not built yet** —
  add a lightweight `ReviewPrompt` gate.
- No incentivised reviews, no pop-up nag. The calm-utility positioning is
  incompatible with an aggressive review ask.

## What from Passes 1–5 hurts the editorial pitch if unresolved

| From | Finding | Why it blocks editorial |
| --- | --- | --- |
| **AF-1** | Unverified signature data | Editorial is a craft bet; a false or missed flag in a reviewer's hands ends it. **Blocker.** |
| **HIG-1** | Dynamic Type breaks above XXL | "Exceptional design craft" is the editorial thesis; accessibility failure contradicts it. **Blocker for feature consideration.** |
| **AF-4 / AF-5** | Dashboard degrades in a crowd | The demo environment for this app *is* a crowd. Stutter on stage = no feature. |
| **HIG-6 / this pass GR-5** | Icon is generic (reads as RSS) | Editorial-featured privacy apps have distinctive marks. Not a launch blocker; is a feature-consideration blocker. |
| **HIG-10** | No obvious "stop scanning" in Live Activity | A privacy app that's hard to turn off is an editorial non-starter. |
| **SP-1 / SP-4** | File protection level; CSV includes opaque key | Small, but editors' security reviewers do check. Cheap to fix. |

## GR-5: icon

The current mark (concentric rings + centre dot + arcs) is clean but reads as
RSS/podcast/broadcast at thumbnail size. For editorial, invest in a mark that says
*"a considered eye"* or *"a lens with a quiet signal"* — distinctive silhouette,
one idea, works at 29pt. Commission this before pitching for a feature; it is not a
1.0 launch blocker.

## Verdict

**The pitch is real and the price is the wedge — but the listing has to say "pay
once" louder than it says "detect glasses".** Ship the beta to gather signature data
(AF-1) and Dynamic Type feedback (HIG-1); do not pitch Apple editorial until AF-1,
HIG-1, AF-4 and the icon (GR-5) are resolved.
