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

### Sensitivity tuning attempt 2026-08-30, reverted 2026-08-31 — don't repeat blindly
Reported: doing a real push-up (already the hard part) and having the app fail to count it was frustrating. Two changes were made without on-device testing (no camera access in this environment):
- Default sensitivity `medium` → `high` — **kept**, this part was fine (just picks the existing, already-most-lenient preset as default instead of a stricter one; changed `DATA.settings` seed, `MotionDetector` constructor default, the Settings dropdown's `selected` option, and the `sens-select` fallback — all four need to move together if touched again, they can drift).
- `high` preset's own numbers loosened (`diffTh` 15→12, `minMotion` 14→10, `downY/upY` band 0.54/0.46→0.53/0.47, `minFrames` 9→6) — **reverted 2026-08-31**. Tested for real on an actual phone/camera (both push-ups and squats, both `high` and `low`, multiple tries) and it made detection *worse*, not better — an untested guess about which direction "more lenient" numbers would help turned out wrong (most likely explanation: `diffTh`/`minMotion` that low starts picking up ordinary sensor/lighting noise as "motion" everywhere in frame, which pulls `smoothedY` toward the frame's vertical center — and center is exactly where a narrowed 0.53/0.47 band lives, so noise alone can dominate over real body-motion signal). Back to the original `high` numbers.
- **Lesson**: don't tune these six numbers by reasoning about the algorithm in the abstract again — it produced a confident-sounding but wrong change once already. Use the on-device debug readout below to see actual numbers before changing any of them.

### Debug readout added 2026-08-31 — use this before touching detection thresholds again
Visible live during a workout, under the UP/DOWN status pill: `px:<motionPx>/<minMotion>  Y:<smoothedY>  range:<minY>-<maxY> (down><downY> up<<upY>)`. `range` (added same day, after a squats test showed `Y:0.53` sitting suspiciously close to `down>0.54` in one snapshot — impossible to tell from a single reading whether that was near the true bottom of a rep or mid-transition) tracks the full min/max `smoothedY` reached since the set started (`MotionDetector.reset()` clears it) — that's the number that actually answers "does this setup ever clear the thresholds," not any single instantaneous reading.
- `motionPx` vs. `minMotion` — is the camera registering *any* qualifying motion at all this frame? If `motionPx` never gets close to `minMotion` during a real rep, the problem is `diffTh`/`minMotion` (too strict to notice the motion in the first place) — or camera framing/lighting isn't producing enough frame-to-frame pixel change to begin with, which no threshold tuning fixes.
- `smoothedY` vs. `downY`/`upY` — is the vertical motion-center actually swinging across the two thresholds? If `motionPx` clears the bar but `smoothedY` never gets close to `downY` (bottom of a rep) or stays stuck away from `upY` (top), the issue is specifically the down/up band or camera angle, not the motion-amount thresholds.
- Get real numbers from this during an actual set (both push-ups and squats) before changing `MotionDetector.cfg` again — this is the difference between the failed 2026-08-30 attempt (reasoning about the algorithm blind) and an actual fix.
- Meant to be temporary — pull the `#wo-debug` element, its `<!-- Temporary debug readout -->` HTML, the extra fields on `process()`'s return object, and the readout-update block in the `detect()` loop once thresholds are dialed in for real (search `2026-08-31` in each spot).
- Manual fallback always exists regardless: the big rep-count button can be tapped by hand if auto-detect isn't cooperating (pre-existing behavior).
- If threshold-tuning (now armed with real numbers) still can't get this reliable, the honest next step is swapping this heuristic for real pose estimation (e.g., MediaPipe Pose via CDN, counting off actual elbow/knee angle) — meaningfully more robust to camera angle/lighting, but a real rewrite of the detection loop, not a tuning change.

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

## Diagnosed 2026-08-31 — the real problem was never sensitivity, it was camera distance
The `wo-debug` readout above proved this with real on-device data (both push-ups and squats, multiple tries):
- **Push-ups**: `motionPx` was 1000+ (far past the ~14 threshold — motion detection was never the bottleneck), but `smoothedY` sat at 0.49, stuck in the dead zone between `down>0.54` and `up<0.46`. The camera view showed an extreme close-up of just the face. When the camera is that close, the subject fills the whole frame at every point in the rep — there's no room for the "where in frame is the motion" signal to swing distinctly toward top or bottom, regardless of sensitivity settings. No threshold combination fixes this; it's a framing problem, not a tuning problem.
- **Squats**: `motionPx` was also 900+, but the camera view was **solid black**. Frames were still being captured and diffed (a truly frozen/dead feed would show `motionPx: 0`) — the camera was just seeing almost nothing, and near-black footage still produces plenty of frame-to-frame pixel noise that the old code couldn't distinguish from real motion. Only 1 rep registered the whole set.

Both traced back to the phone being positioned too close to / too blocked by the body — and the in-app tips never said anything about distance (`pushups`/`squats` tips just said "on the floor" / "at hip height," unlike the `jumpingjacks` tip which explicitly says "Stand 1–2m from phone"). The guidance itself was incomplete for the exact failure mode that hit.

Fixed:
- `pushups`/`squats` tip text (`EXERCISES` array) now explicitly says prop the phone **1-1.5m away** so the **whole body** is in frame — not close-up.
- Added automatic too-dark detection: `MotionDetector.process()` now also computes average frame brightness (reusing the existing per-pixel sampling pass, no extra cost) and returns `tooDark` when it's below 25/255. `detect()` in `beginWorkout()` shows a `⚠️ Too dark to see` banner live during the workout when this is true — this directly targets the squats failure mode: previously, near-total darkness silently produced garbage counts with zero indication anything was wrong.
- No threshold-tuning was needed or attempted this round — the debug data made clear that would've been solving the wrong problem, same mistake as the 2026-08-30 attempt above.

**If it's still unreliable after repositioning at proper distance with good lighting**: use the `wo-debug` readout again with a *correctly-framed* setup — if `smoothedY` still isn't swinging across `downY`/`upY` with good framing/light, that's real evidence for a genuine threshold fix (not another guess). If it's still not reliable even then, that's the actual signal to invest in real pose estimation instead of continuing to tune this heuristic.

## Fixed 2026-08-31 — camera "doesn't switch on" for a second/third workout in the same session
`startWorkout()` re-attaches a fresh `getUserMedia` stream to the *same* `<video id="workout-camera">` element every time (not a new element) and did `await new Promise(r => vid.onloadedmetadata = r)` with no timeout. Reusing the same video element across multiple stream attachments is a known flaky spot (seen on iOS Safari) where `loadedmetadata` doesn't reliably re-fire on a later attach — when that happened, `startWorkout()` just hung at that line forever, since nothing else was gating progress. Countdown and workout screen never proceeded — looked exactly like "camera doesn't switch on." Fixed with `Promise.race([onloadedmetadata, 2.5s timeout])` so it always proceeds either way; harmless in the normal case since the real event still wins the race immediately when it fires.

## File layout
- `grind.html` — the entire app (HTML/CSS/JS inline).
- `index.html` — root-URL redirect to `grind.html` (added 2026-08-30, see Deployment above).
- `publish.sh` — deploy script (added 2026-08-30, see Publishing above).
