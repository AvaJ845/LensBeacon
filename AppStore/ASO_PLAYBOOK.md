# LensBeacon — ASO Playbook

The $50K/Month ASO engine applied to LensBeacon. A compounding asset, not a launch
sprint: keywords → impressions → screenshots → downloads → happy-moment reviews →
rank → room for better keywords. Every stage has to be built or the flywheel
breaks.

Metadata block: [`METADATA.md`](METADATA.md).

## 1 · Discovery — get found

- [x] Keyword-first store name: **Glasses Detector - LensBeacon**
- [x] Subtitle is a distinct keyword slot: **Bluetooth scanner, no account**
- [x] Keywords field 96/100, singular, comma-joined no spaces, no Name/Subtitle repeats
- [x] Naming Council run (Approve) — logged in `METADATA.md`
- [x] Exclusion list honoured (no brand names, no "surveillance/track/AI" framing)
- [ ] Enter metadata in App Store Connect
- [ ] Localize Name/Subtitle/Keywords for at least en-GB, de, fr, es, ja
- [ ] Baseline keyword ranks recorded on submission day

## 2 · The tap — conversion (3–5 second window)

- [x] Icon is a legible mark at home-screen size (Apple Fellow brand kit — beacon arcs + lens)
- [ ] **Fresh screenshots on the current UI** — the committed set in
  `../Screenshots/AppStore/` predates the redesign. Recapture on device with
  `-demo-data`; the raw-capture list is at the bottom of [`Tools/screenshot-frames.html`](../Tools/screenshot-frames.html).
- [x] Captioned frame builder: [`Tools/screenshot-frames.html`](../Tools/screenshot-frames.html) — brand-styled, correct
  aspect ratios (1320×2868 iPhone, 422×514 Watch), captions final. Drop raw
  captures into `AppStore/raw/` (git-ignored) and screenshot each frame.
- [ ] No frame opens on onboarding/permission
- [ ] Optional: 15–20 s App Preview of one real scan → flag → evidence loop
- [ ] Product-page A/B test after launch: frame 1 order first

### iPhone 6.9" — 8-frame story (final captions in `Tools/screenshot-frames.html`)

| # | Caption | Screen |
|---|---|---|
| 1 | **Camera glasses announce themselves over Bluetooth** — *LensBeacon listens* | Dashboard, one flag: tier badge + proximity meter |
| 2 | **Every flag shows its evidence** — *the AD field, the raw bytes, the tier — disagree with it* | Sighting detail, Evidence section |
| 3 | **High, Medium, Low — by manufacturer signature** — *not guesswork, and never colour alone* | Dashboard with a High flag + expanded "Name matches" |
| 4 | **A rough sense of distance** — *never a direction, never a name* | Detail scrolled to the proximity meter |
| 5 | **Display glasses have no camera** — *LensBeacon labels them, never counts them as one* | A `G1_…` detail with the "No camera" chip |
| 6 | **Own a pair? Mark them once** — *they stop raising alerts for good* | Detail with "These are mine" on |
| 7 | **Pay once. $9.99. No subscription.** — *background scan · Live Activity · widget · CSV* | Unlock sheet |
| 8 | **Nothing leaves your iPhone** — *no account, no server; Airplane Mode; erase it all in one tap* | Settings ▸ Data |

### Apple Watch (Ultra 3, 422×514) — 3 frames

1. **Is there a camera near me right now?** — scanning state
2. **Nearest signal, strongest tier** — summary + rows
3. **Why it thinks so — on your wrist** — evidence on the watch

The watch also ships a **complication** (`LensBeaconWatchWidget`) — a face
launcher, `accessoryCircular` / `Corner` / `Inline` / `Rectangular`. Capture one
face screenshot with it placed for the listing.

## 3 · Momentum — reviews

- [ ] `ReviewPrompt` helper — fire the native prompt at the **happy moment**:
  after the user opens the evidence view for their **3rd** distinct flag in a
  session (they've engaged with the core value), once per app version, never in
  session 1, never right after a permission denial.
- [ ] Reply to every review; convert 1★ by fixing the actual complaint.
- [ ] Support-email signature: "If LensBeacon's been useful, a short review really
  helps a solo project."
- [ ] Roadmap signal: ~20 identical review asks → build it, say so in a reply.
- [ ] Track keyword rank monthly; rotate the weakest keyword each update.

## Positioning vs. the field

| Competitor | Their wedge | LensBeacon's answer |
|---|---|---|
| Nearby Lens | broad device list, Watch included, one purchase | evidence-per-flag + tier honesty; calm, not a scanner UI |
| NoGlasshole | "someone might be secretly recording" | explicitly **not** accusation — "a detection is not proof" |
| Hidden Camera Detector (old) | IR / lens-reflection room sweep | BLE-signature only, no false "we see a lens" claims |
| ZuckOff (web) | same BLE signals, browser | native, on-device, background, Watch, no browser tab |

The one thing editorial rewards that none of them lead with: **restraint** — an
awareness tool that refuses to alarm you.
