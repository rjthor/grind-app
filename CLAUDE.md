# GRIND — Claude Code Instructions

## What this is
A single-file workout tracker PWA (push-ups/squats/sit-ups/jumping jacks/plank), with camera-based automatic rep counting. No backend, no build step, no framework — everything (HTML/CSS/JS) lives in one file, `grind.html`. Data persists in the browser's `localStorage` (key `grind_v1`) — per-device, nothing synced.

Repo: https://github.com/rjthor/grind-app

## Deployment — GitHub Pages, no build step
Served straight from the `main` branch root via classic GitHub Pages (not a Actions workflow) — a push to `main` is a deploy, live within ~30-60s, no CI to wait on.

- **Live URLs**: `https://rjthor.github.io/grind-app/grind.html` (the actual app) and `https://rjthor.github.io/grind-app/` (added 2026-08-30 — `index.html` is a tiny redirect to `grind.html`, since the repo root previously 404'd with no `index.html` present).
- **Don't rename `grind.html`**: the app has `apple-mobile-web-app-capable` meta tags and is meant to be "Added to Home Screen" on iOS — an existing home-screen icon is bound to the exact URL it was added from. `index.html` redirects instead of grind.html being renamed, specifically to avoid breaking that.

## Publishing changes
```bash
./publish.sh "commit message"
```
This (added 2026-08-30):
1. Bumps the `BUILD_ID` constant near the top of `<script>` in `grind.html` to the current timestamp.
2. `git add grind.html index.html && git commit && git push origin main`.

**Why the build stamp matters**: this is a PWA that can get stuck on a cached version (both normal browser cache and the home-screen-icon webview cache) — pushing a fix and testing on your phone without a version indicator makes it impossible to tell "is this still broken" apart from "did my phone just not pick up the new version." Build stamp is shown in **two places** (added 2026-08-31, was Settings-only before and easy to miss): top of the **Dashboard**, right under the streak badge, and at the bottom of Settings.

**GitHub Pages' CDN caches responses for `max-age=600` (10 min)** — confirmed via response headers, not configurable (GH Pages doesn't support custom headers without a paid custom-domain setup). A reload shortly after a push can still legitimately serve the pre-push version from cache, independent of anything on your phone. `publish.sh` prints a cache-busted URL (`grind.html?v=<BUILD_ID>`) after every push — a different query string is a different cache key, so it's a guaranteed-fresh fetch. Use that link, not the bare URL, when testing immediately after a publish.

Don't hand-edit `BUILD_ID` or commit/push manually for routine changes — use the script so the stamp and the push always move together (a mismatched stamp defeats the whole point).

## Local testing
No build step — open `grind.html` directly in a browser, or serve it (`python3 -m http.server 8000` from this directory, then visit `localhost:8000/grind.html`) if you need clean relative-path behavior.

**Camera testing specifically**: `getUserMedia` (used for auto rep-counting) is blocked by browsers on any non-HTTPS, non-localhost origin. That means:
- A desktop browser at `localhost` can exercise the camera code path (use a laptop webcam), but obviously can't do a real push-up test.
- Real on-device testing (phone, actual push-ups, actual camera framing) only works against the deployed HTTPS Pages URL — there's no meaningful way to test the camera-detection loop against a local dev server from a phone on the same LAN, since that's plain HTTP. This is why the publish-and-check-the-build-stamp workflow above exists: for this specific piece, "publish then test on phone" *is* the local-test loop.

## Rep-counting — how it actually works (important: NOT pose estimation)
`MotionDetector` class (`grind.html`, search `class MotionDetector`) is a lightweight frame-differencing heuristic, not skeleal/pose tracking (no MediaPipe/TensorFlow, nothing that knows what an elbow or a torso is):
1. Downscales each camera frame to 160×213 and diffs it against the previous frame, per-pixel (sampling every 2nd row/col for perf), to find "moving" pixels (`diffTh` = per-channel RGB delta threshold to count as moved).
2. Takes the average vertical position (`weightedY`, normalized 0=top/1=bottom) of only the moving pixels — a proxy for "where in frame is the movement happening" — and smooths it over time (`alpha`-weighted EMA → `smoothedY`).
3. State machine: `smoothedY` crossing below `upY` after being above `downY` (i.e., motion-center moved from low-in-frame to high-in-frame, sustained for `minFrames` consecutive qualifying frames) = one rep.

This means accuracy is **very sensitive to camera placement/angle/lighting** — it has no idea what a body or a push-up actually looks like, only "where did the pixels that changed happen to be, vertically." The three sensitivity presets (`low`/`medium`/`high`, Settings → Sensitivity) tune how much motion and how sustained it needs to be before it registers.

### Fix applied 2026-08-30 — was under-counting, especially on fatigued/slower reps
Reported: doing a real push-up (already the hard part) and having the app fail to count it was actively frustrating. Root cause: default sensitivity was `medium`, and even `high` (the most lenient preset) still required a fairly wide vertical-position swing over enough sustained frames — exactly the kind of full-range, brisk motion that's hardest to sustain late in a set.
- Default sensitivity changed from `medium` → `high` (`DATA.settings` seed, `MotionDetector` constructor default, the Settings dropdown's `selected` option, and the `sens-select` fallback all updated together — check all four if touching this again, they can drift).
- `high` preset itself loosened: `diffTh` 15→12, `minMotion` 14→10, `downY/upY` band 0.54/0.46→0.53/0.47, `minFrames` 9→6, `alpha` 0.84→0.82 — registers subtler/slower motion and reacts faster, at some cost of being more prone to false triggers from camera shake. Untested against a real phone/camera (no camera access in this environment) — needs on-device verification via the publish workflow above, and further loosening (or a partial revert if it starts over-counting) may be needed.
- **Caveat**: this only changes the default for a *fresh* `localStorage` — a device that already has `grind_v1` saved (i.e., this app after any prior use) keeps whatever sensitivity was saved before, unaffected by code changes. On an already-used phone, go to Settings → Sensitivity → **High** manually to pick up the loosened preset immediately.
- If `high` is still too strict even after this, the honest next step isn't more threshold-nudging — it's swapping this heuristic for real pose estimation (e.g., MediaPipe Pose via CDN, counting off actual elbow angle) — meaningfully more robust to camera angle/lighting, but a real rewrite of the detection loop, not a tuning change. Not done — flag if the loosened heuristic still isn't enough.
- Manual fallback always exists regardless: the big rep-count button can be tapped by hand if auto-detect isn't cooperating (already-existing behavior, not new).

## Fixed 2026-08-31 — "Back to Dashboard" / "Do Another Set" buttons did nothing after a workout
Reported as the buttons "not going anywhere," blocking normal use (had to manually refresh the page to escape). Root cause was CSS specificity, not the button handlers or `showScreen()`'s logic (both were already correct) — **an ID selector's `display` always beats a class selector's, full stop, regardless of source order or how many classes are stacked**:
```css
.screen { display: none; }         /* specificity (0,1,0) */
.screen.active { display: block; } /* specificity (0,2,0) */
#complete-screen { display: flex; } /* specificity (1,0,0) — WINS regardless of the above */
```
`#complete-screen` needed `display:flex` for its centered layout, so it set that unconditionally on the ID selector. The *only* thing keeping it hidden before its first-ever appearance was a hardcoded inline `style="display:none"` in the HTML markup (inline beats even ID selectors) — the instant anything cleared that inline style, the ID rule took over permanently, independent of the `.active` class entirely. An earlier same-session fix attempt (clearing inline `display` on every screen on every `showScreen()` call, to stop a *different*, related symptom) actually made this fire on literally any navigation instead of only after visiting the complete screen once — a JS-level band-aid on what was really a CSS-level bug, which is why that first attempt didn't hold up under a second real test.

Real fix: scoped the flex rule to `#complete-screen.active { display: flex; }` (specificity (1,1,0), still ID-backed so it correctly beats `.screen.active`, but *only* applies together with `.active` — doesn't fight the hidden state when `.active` is absent), removed the now-pointless hardcoded inline `style="display:none"` from the markup, and simplified `showScreen()` back to pure class toggling with no inline-style involvement at all. If another screen ever needs a non-`block` display value, use the same `#id.active { display: ... }` pattern — never an unqualified `display` on a bare `#id` selector for anything that's shown/hidden via the `.screen`/`.active` mechanism.

**Lesson for next time a screen "gets stuck visible" or "won't respond to navigation" here**: check CSS specificity conflicts between ID selectors and the `.screen`/`.active` class mechanism *before* reaching for a JS-side fix — the bug quite plausibly isn't in the JS at all.

## File layout
- `grind.html` — the entire app (HTML/CSS/JS inline).
- `index.html` — root-URL redirect to `grind.html` (added 2026-08-30, see Deployment above).
- `publish.sh` — deploy script (added 2026-08-30, see Publishing above).
