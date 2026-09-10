# Pass 5 — App Review Fellow: App Store readiness

Reviewer lens: walk the build against likely rejection vectors. Bluetooth strings,
background mode justification, IAP compliance, trademark exposure, and 4.3 / 5.2.1
risk from naming commercial products.

## Info.plist / permissions

| Item | State | Risk |
| --- | --- | --- |
| `NSBluetoothAlwaysUsageDescription` | Present, specific: says what the scan does *and* that the app never connects/pairs/transmits | **Low.** This is a model usage string. |
| `NSBluetoothPeripheralUsageDescription` | **Absent** | **OK** — deprecated; only needed pre-iOS 13. Not required. |
| `UIBackgroundModes: [bluetooth-central]` | Present | **Medium — see AR-1** |
| `NSLocationWhenInUseUsageDescription` etc. | Absent, CoreLocation not linked | **Low / positive** — reviewers sometimes assume BLE proximity apps sneak in location; this app demonstrably doesn't. |
| `NSSupportsLiveActivities` | `true` | Low |
| `ITSAppUsesNonExemptEncryption` | `false` | Low — correct, no crypto beyond OS file protection |

**AR-1 (should-fix before submission): `bluetooth-central` background mode needs an
airtight justification in the App Review notes.** Guideline 2.5.4 rejects apps that
declare background modes they don't clearly need. The justification is solid but must
be *stated*: "Background Bluetooth scanning is a user-initiated, opt-in feature
(LensBeacon Unlock → 'Keep scanning in the background'). While active it presents a
persistent Live Activity so the user always knows scanning is running and can stop it.
The app is central-role only and never connects to a device." Include a screen
recording of enabling it and the Live Activity appearing.

**AR-2 (should-fix): the background mode ships enabled in the binary even for free
users who can't use it.** That's normal and fine, but a reviewer testing the free
tier won't see any background behaviour — make sure the notes say the feature is
gated behind the IAP so they don't reject for "declared but unused".

**AR-3 (nit): usage string could add one clause** — "Detection while the app is in
the background is limited by iOS and may miss some devices." Sets expectations and
shows good faith.

## StoreKit 2 / IAP compliance

- **Non-consumable**, one product (`com.avaresearch.lensbeacon.unlock`), no
  subscription, no consumables. `UnlockStore` uses `Product.products(for:)`,
  `product.purchase()`, `Transaction.currentEntitlements` as the source of truth,
  `Transaction.updates` listener, and `AppStore.sync()` for restore. **This is a
  textbook StoreKit 2 non-consumable implementation.**
- **Guideline 3.1.1:** all unlocked features are digital and delivered in-app — fine.
- **Guideline 3.1.2 (Restore):** "Restore Purchase" button is present in `UnlockView`
  **and** in `SettingsView`'s unlock section is a path to it. **AR-4 (should-fix):
  the Restore button must be reachable without an existing purchase and clearly
  labelled** — it is in `UnlockView`, always visible, labelled "Restore Purchase".
  Good. Confirm it's not hidden when `product == nil` (it isn't — only the Buy button
  is disabled).
- **AR-5 (nit): no "Terms of Use (EULA)" / "Privacy Policy" links on the purchase
  screen.** For a one-time IAP Apple is lenient, but add both links to `UnlockView`
  footer to be safe. Privacy policy already exists (`PRIVACY.md` → host it).
- **Pending / Ask-to-Buy** handled (`.pending` → "needs approval" copy, resolved via
  the updates listener). Good.
- **AR-6 (must-fix before submission): StoreKit configuration file for testing is
  not in the repo.** Add `LensBeacon.storekit` so the fellows can test purchase/
  restore in the simulator without App Store Connect. (Local testing only; not
  shipped.)

## Trademark exposure — "Ray-Ban", "Meta", "Snap", "Oakley"

This is the **highest-risk area** (Guideline 5.2.1 — Intellectual Property; 4.3 —
Spam; and general trademark).

**AR-7 (must-fix): audit where brand names appear.**

| Location | Currently | Required |
| --- | --- | --- |
| Binary string constants | `SignatureTable.displayName` = "Ray-Ban Meta", "Oakley Meta", "Snap Spectacles"; onboarding copy names them; `ConfidenceEngine.Evidence.bullets` interpolates vendor/product | **Acceptable as *nominative* reference** (identifying a product by name to describe compatibility/detection). Keep it factual and non-branded — no logos, no trade dress. |
| App name / subtitle | "LensBeacon" — no brand | **Good. Keep it brand-free.** |
| App icon | Abstract mark, no brand | **Good.** |
| Screenshots | TBD | **Do NOT put "Ray-Ban Meta" as headline text or show the product.** Use generic "camera glasses" in captions; brand names may appear only as small in-app UI text within a screenshot, if at all. See Pass 6. |
| Keywords | TBD | **AR-8: do not buy "ray-ban", "meta", "oakley", "snapchat" as ASO keywords** — high 4.3/5.2.1 flag risk and trademark-bidding exposure. "smart glasses", "camera glasses", "glasses detector" are safe. |
| Promo text / description | Brand names OK **in body prose** as "detects devices such as …" | Keep out of the first line; keep out of anything that looks like a claim of partnership. |

**AR-9 (should-fix): add a disclaimer** in the description and in-app About:
"LensBeacon is not affiliated with, endorsed by, or sponsored by Meta, Ray-Ban,
EssilorLuxottica, Oakley, or Snap. Product names are used only to describe what
LensBeacon detects." This materially lowers 5.2.1 risk.

## 4.3 (Spam) — "is this a duplicate of Zuckoff / AntiZuck / etc."

**AR-10 (medium risk):** there are already 5+ near-identical "glasses detector" apps
live. Apple has been rejecting the Nth entrant in crowded utility categories as 4.3.
Mitigations that are already true and should be foregrounded in the review notes:

1. **Evidence-per-flag** — no competitor shows *which signals matched*. This is a
   genuine functional difference, not a reskin.
2. **One-time price in a subscription field** — different business model.
3. **No account, zero network calls** — verifiable (Airplane Mode demo).
4. **Fellow-level craft** — the review notes can point to this repo's review docs.

Include a short "How LensBeacon differs from existing glasses-detector apps"
paragraph in the review notes. Do **not** name competitors in the App Store listing
itself.

## Other

- **AR-11 (nit): no `NSUserTrackingUsageDescription`** — correct, there is no
  tracking, no IDFA access, no ATT prompt. Privacy nutrition label should be "Data
  Not Collected" across the board — **make sure App Store Connect privacy answers say
  exactly that**, since one wrong toggle there contradicts the whole pitch.
- **AR-12 (nit): widget + Live Activity** need to be shown working in the demo video
  or a reviewer may not find them.

## Verdict

**Not submittable as-is; ~1 day of listing/notes work + AR-6/AR-7/AR-9 to be
submittable.** No architectural blockers. The trademark audit (**AR-7/AR-8/AR-9**)
and the background-mode justification (**AR-1**) are the must-dos. The crowded-
category 4.3 risk is real but the app has honest differentiation to point at.
