#!/usr/bin/env python3
"""Build the full App Store Connect screenshot set from raw captures in
AppStore/raw/ (git-ignored — recapture with the recipe below), rendering
straight to every exact pixel size ASC accepts. Run from anywhere:

    python3 Tools/build_appstore_screenshots.py

Output lands in AppStore/screenshots/{iphone-6.5,ipad-13,watch-ultra3,
watch-s11,watch-s9,watch-s6}/NN.png — upload those directly.

RECAPTURING RAW SCREENSHOTS (simulator)
----------------------------------------
Build once for iphonesimulator + watchsimulator, install on:
  iPhone 6.5" — a sim whose native screenshot is 1284×2778 or 1242×2688
                (this repo used "Hummingbird Shot 12ProMax")
  iPad 13"    — "iPad Pro 13-inch (M5)" (native 2064×2752)
  Watch       — one sim per size: Ultra 3 (422×514), Series 11 (416×496),
                Series 9 (396×484), Series 6 (368×448)

Then for EACH shot, as its own separate command (do not chain several
terminate+launch cycles in one script — under load, a fresh relaunch of an
app that hasn't *fully* exited yet silently reuses the old process and its
original launch arguments, so `-skip-onboarding`/`-screen`/`-detail-key`
appear to have no effect):

    xcrun simctl terminate <sim> <bundle-id>
    sleep 8   # let it fully die before relaunching
    xcrun simctl launch <sim> <bundle-id> -skip-onboarding -demo-data -screen <name> [-detail-key <key>]
    sleep 6   # let the view settle before capturing
    xcrun simctl io <sim> screenshot AppStore/raw/<device>/<NN-name>.png

iOS `-screen` values: sightings, detail (+ `-detail-key demo-t1|demo-display|
demo-mine` to pick which seeded record), settings, unlock. Watch: `-demo-scanning`
for the empty-scan state, `-demo-data` for the nearby list, `-demo-data -screen
detail` for one flag's evidence. `-demo-data` is real `DetectionEngine` output
for synthetic advertisements (see DemoSeed.swift / WatchScanModel.loadDemo) —
never fabricated UI. Frame 1 (iPhone hero) is a real device capture, not a
simulator one; Dashboard flags require an actual BLE radio and DemoSeed
deliberately never fakes the "nearby now" state.
"""
import os

from render_screenshots import render_frame, render_watch_frame

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RAW = os.path.join(REPO, "AppStore", "raw")
OUT = os.path.join(REPO, "AppStore", "screenshots")

IPHONE_SIZE = (1284, 2778)   # 6.5" display
IPAD_SIZE = (2064, 2752)     # 13" display
WATCH_SIZES = {
    "watch-ultra3": (422, 514),
    "watch-s11": (416, 496),
    "watch-s9": (396, 484),
    "watch-s6": (368, 448),
}

# (raw file, headline, subhead) — payoff first, per the ASO playbook.
IPHONE_FRAMES = [
    ("01-hero.png", "Camera glasses announce themselves over Bluetooth",
     "LensBeacon listens"),
    ("02-sightings.png", "High, Medium, Low — by manufacturer signature",
     "Not guesswork, and never colour alone"),
    ("03-detail-t1.png", "Every flag shows its evidence",
     "The AD field, the raw bytes, the tier — disagree with it"),
    ("03-detail-t1.png", "How close, and how strong",
     "dBm, plainly explained — never a direction, never a name"),
    ("05-detail-display.png", "Display glasses have no camera",
     "LensBeacon labels them, and never counts them as one"),
    ("06-detail-mine.png", "Own a pair? Mark them once",
     "They stop raising alerts — for good"),
    ("07-unlock.png", "Pay once. $9.99. No subscription.",
     "Background scan · Live Activity · widget · CSV export"),
    ("08-settings.png", "Nothing leaves your iPhone",
     "No account, no server. Works in Airplane Mode. Erase it all in one tap."),
]

# iPad has no BLE-hero shot (the simulator has no radio, and DemoSeed never
# fakes "nearby now") — leads with the tier-signature frame instead.
IPAD_FRAMES = IPHONE_FRAMES[1:]

WATCH_FRAMES = [
    ("w1-scanning.png", "Is there a camera near me right now?"),
    ("w2-summary.png", "Nearest signal, strongest tier"),
    ("w3-evidence.png", "Why it thinks so — on your wrist"),
]


def main():
    os.makedirs(os.path.join(OUT, "iphone-6.5"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "ipad-13"), exist_ok=True)

    for i, (src, headline, sub) in enumerate(IPHONE_FRAMES, start=1):
        render_frame(os.path.join(RAW, "iphone", src), headline, sub,
                     os.path.join(OUT, "iphone-6.5", f"{i:02d}.png"), IPHONE_SIZE)

    for i, (src, headline, sub) in enumerate(IPAD_FRAMES, start=1):
        render_frame(os.path.join(RAW, "ipad", src), headline, sub,
                     os.path.join(OUT, "ipad-13", f"{i:02d}.png"), IPAD_SIZE,
                     shot_width_frac=0.62, headline_size_frac=0.038,
                     sub_size_frac=0.022, side_pad_frac=0.14)

    for name, size in WATCH_SIZES.items():
        os.makedirs(os.path.join(OUT, name), exist_ok=True)
        for i, (src, headline) in enumerate(WATCH_FRAMES, start=1):
            render_watch_frame(os.path.join(RAW, name, src), headline,
                                os.path.join(OUT, name, f"{i:02d}.png"), size)

    print("ALL DONE")


if __name__ == "__main__":
    main()
