---
id: 2026-10-17-v2-plan-feasibility-review
kind: note
title: "Adversarial feasibility review of the v2 plan (PLAN.md, kickoff notes 01-07)"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:review-feasibility]
topics: [plan, measurement, lean, agent-teams, rewrite]
links:
  refs: []
  sources:
    - "chromium/chromium@317846d579b2 headless/lib/browser/protocol/target_handler.cc"
    - "chromium/chromium@317846d579b2 third_party/blink/renderer/core/animation/animation.cc"
    - "WebKit/WebKit@fba976461fc0 Source/WebCore/animation/WebAnimation.cpp"
    - "ChromeDevTools/devtools-protocol@e908551762a5 json/browser_protocol.json"
    - "leanprover/lean4@v4.35.0 src/runtime/object.cpp"
  experiments: []
  v1: [research/loop-distillation/README.md, research/cpu-throttle-calibration/README.md]
---

# Adversarial feasibility review of the v2 plan

Scope: try to refute the five key bets of `docs/plan/PLAN.md`, using the plan, the kickoff notes in
`research/kickoff/`, the v1 repo (read-only), and upstream sources I fetched today. I did not edit the plan.

Labels: **CONFIRMED** = I checked a cited source or doc today. **INFERRED** = my reasoning, still to test.
**REFUTES** = a plan assumption that a source contradicts.

## 0. Verdict in one screen

The plan is careful and mostly well sourced. Three findings block it as written, and about a dozen need changes
before M1:

| # | Severity | Finding | Short fix |
|---|---|---|---|
| B1 | blocker | `BeginFrameControl` is **not supported on macOS**. The M1 counts lane (D5-D6) assumes headless-shell frame stepping on this Mac (REFUTES, §1.1) | Run the counts lane in a Linux container, with fonts pinned. Add an M0 spike |
| B2 | blocker | The frame-stepped harness changes what it measures. Playwright's clock fakes `requestAnimationFrame`. Seeking an animation every step cancels or restarts compositor animations (Chromium) and invalidates style (WebKit) (CONFIRMED, §1.2) | Drive animation time with `frameTimeTicks` and don't seek in Chromium. Use a clock shim that keeps native rAF. Add a "harness neutrality" metric |
| B3 | blocker | The token goals contradict the plan's own estimates. G3 caps the project at $4k with the lead at 25 % or less, but the lead alone is estimated at $180 a day over a roadmap of about 40 working days, which is about $7k (§4) | Re-baseline G3, or cap the lead's context and request rate. Recompute the Opus share |
| M1 | major | L5 "within A's spread over 5 loads" means exact equality in a lane that is byte-identical by design. And equal counts are not equal cost (§2) | Set per-count tolerances. Add a timing-parity gate between A and R and a transfer check on the original |
| M2 | major | Class W ("lands on counts, no device") rests on dominance over an **incomplete** count vector (§1.4) | Require per-frame dominance plus a "no change in uncounted families" lint, or else use class S |
| M3 | major | WebKit Phase A has no restyled-element count, which is WebKit's largest term. D8 defers the only fix (§1.5) | Bring the WKTR spike into M1, or ban class W for changes that affect style |
| M4 | major | Chromium counts from Linux headless (software raster) are not counts from headed Mac Chrome (GPU raster). M-a validates on a Mac, not on the target (§1.6) | Add a Chromium count-transfer gate. Treat the Chromium model as counts-only, or validate it on Android |
| M5 | major | Coefficients **do** depend on the page mix (v1 measured 2.2×), against note 03 §11 (§1.7) | Add a page-context term fitted on arm A |
| M6 | major | The proved verdict rule (n ≥ 3, disjoint ranges) has a 1-in-20 one-sided false-win rate under the null. The proof says nothing about this (§3.3) | Use 4v4 (1/70) or sequential testing. Prove the p-value. Control for multiplicity |
| M7 | major | The Lean-to-TS glue has a silent wrong-answer path: a Lean `panic!` returns `default`, and the bridge matches replies to requests by arrival order with no ids (§3.2) | Echo request ids. Set `LEAN_ABORT_ON_PANIC=1`. Ban `!` ops in `Wire` |
| M8 | major | Lean's net value is overstated. v1's top bug class (device/IO, about 111 incidents) is untouched. Many lock bugs disappear through the single-writer design alone. M-l is a vanity metric (§3.1) | Keep waves 1-2, drop wave 3 and the ≥ 90 % M-l target, and keep a ledger of bugs caught by proofs vs by tests |
| M9 | major | `gh api` defaults to POST when `-f`/`-F` is given. The deny list only blocks `-X`, so writes to GitHub are allowed (CONFIRMED, §5) | Add deny rules for `-f`, `-F`, `--field`, `--raw-field` and `--input`, or wrap the call |
| M10 | major | A global 1-hour cache TTL bills every cache write at 2× instead of 1.25×. In v1, writes may have been about half of input-side spend (§4.2) | Set `experimental.cacheTtl: 1h` per agent, for teammates only. Measure in M0 |
| M11 | major | The WebKit model has a `− overlap` term, so it is not monotone. The dominance theorem's premise fails for `F` (§1.4) | Use `max(raster, alloc)` or drop the term |
| m* | minor | Lead window 400k; edit prompts in `default` mode; named role spawned without `isolation`; Fable ask-rule pattern; Nat-µs coefficient truncation; font and platform drift | §5 |

---

## 1. Bet 1: engine-stat cost models can replace most device runs

### 1.1 BeginFrameControl does not exist on macOS (REFUTES the M1 week-1 schedule)

- The plan's counts lane is "`chrome-headless-shell` with BeginFrameControl and a virtual clock" (PLAN §4.1). It is
  due on this Mac on D5-D6 (PLAN §10.2).
- **CONFIRMED in source.** `chromium/chromium@317846d579b2`, `headless/lib/browser/protocol/target_handler.cc`
  l.62-65 contains:
  `#if BUILDFLAG(IS_MAC) if (enable_begin_frame_control...) return Response::ServerError("BeginFrameControl is not supported on MacOS yet");`
- The protocol doc agrees. `ChromeDevTools/devtools-protocol@e908551762a5`, `Target.createTarget.enableBeginFrameControl`
  says: "headless shell only, not supported on MacOS yet".
- The host is an M1 Pro running macOS 27 (note 04 §5). Note 03 §7.1 and §12 never mention the platform limit. The
  fallback in PLAN §4.6 ("Playwright clock + rAF stepping") gives up compositor stepping, so it loses exactly the
  property M-i depends on.
- **Fix.**
  1. Add spike **S-i** to M0: run Playwright's `chromium-headless-shell` for linux-arm64 in a Linux container
     (Docker or OrbStack on this Mac), with `--enable-begin-frame-control`, `--deterministic-mode` and
     `--run-all-compositor-stages-before-draw`. Show two byte-identical count vectors.
  2. **Pin fonts in the container.** Linux text shaping and fallback fonts change line breaks, so they change layout
     and paint counts. Serve every font from `snapshot/` and set `font-family` fallbacks to bundled fonts only.
     Otherwise counts from the container and timings from headed Mac Chrome describe different pages (INFERRED).
  3. Move D5-D6 behind S-i. If S-i fails, the Chromium counts lane is "Playwright clock without compositor stepping".
     M-i must then be re-scoped, because the state of compositor animations is no longer stepped.

### 1.2 The stepped harness perturbs the mechanism under test (CONFIRMED)

Three separate artefacts come from PLAN §4.2 steps 1, 3 and 4:

1. **`page.clock` fakes `requestAnimationFrame`.** The Playwright docs list `requestAnimationFrame`,
   `cancelAnimationFrame` and `performance` among the overridden globals (CONFIRMED, https://playwright.dev/docs/clock).
   Consequences (INFERRED from that list):
   - The app's rAF callbacks run inside `clock.runFor()` as a timer task, not in the engine's "update the rendering"
     step. Chromium's `FireAnimationFrame` count (C13) goes to 0 or is mis-attributed.
   - A scroll event dispatched during `beginFrame` schedules a fake rAF, which runs only at the next `runFor`. That
     adds a one-frame lag between scroll and the scroll-linked writes. The faithful `engine.scroll` ("one passive
     listener, one rAF, callbacks in the original's order", PLAN §6.4 rule 4) therefore no longer has the original's
     frame structure. v1's costs came from that frame structure (PLAN §6.1).
   - In WebKit, the harness's own "two rAFs" (PLAN §4.2 step 4; note 04 §8) are also faked. Unless the harness keeps
     the native function, they never wait for a real rendering update.
2. **Seeking cancels compositor animations in Chromium.** `chromium@317846d579b2`,
   `third_party/blink/renderer/core/animation/animation.cc`:
   - `setCurrentTime` (l.576-618) calls `SetCompositorPending(kPendingUpdate)`.
   - `PreCommit` (l.741-800) sets `needs_timing_update` when `start_time_`/`hold_time_` differ from the compositor
     copy, and cancels on the compositor when `!Playing() && compositor_state_` or when a restart is needed.
   - So a **paused** animation (note 04 §8: "pause, set `currentTime`") runs on the main thread. A **playing** one
     that is re-seeked every step is cancelled and restarted on the compositor every frame.
   - Either way, the counts lane charges main-thread and commit work to animations that run on the compositor in
     real playback. This erases the main-vs-compositor split that is v2's central optimization lever. The
     `compositeFailed` gate (PLAN §6.2) is also evaluated on a state the user never sees.
3. **Seeking invalidates style in WebKit.** `WebKit@fba976461fc0`, `Source/WebCore/animation/WebAnimation.cpp`:
   `setCurrentTime` (l.587-620) ends in `invalidateEffect()`, which calls `keyframeEffect->invalidate()` (l.1057-1063).
   It also calls `animationDidChangeTimingProperties()`. Every seeked animation therefore adds a style invalidation
   per step. That inflates the `RecalculateStyles` counts for accelerated animations, which note 04 §7.1 says "add
   nothing to W while running".

**Fix.**
- **Chromium:** do not seek. With BeginFrameControl, the document timeline advances by the `frameTimeTicks` you pass
  (CONFIRMED that the parameter exists, devtools-protocol `HeadlessExperimental.beginFrame`). Fake only `Date`,
  timers and `performance` with a small shim (or `--virtual-time-budget`), and leave rAF native so it fires inside
  `beginFrame`.
- **WebKit:** seeking is unavoidable without a test runner. Measure the harness's own cost with a fixture of N
  accelerated animations (seeked vs free-running), and subtract it or tag those counts `harness-induced`. Read
  compositor status from a free-running held-state census (`LayerTree` reasons), never from the stepped run.
- Add metric **M-n, harness neutrality**: on fixtures, stepped counts equal free-running counts per family (paint,
  layout, layers). A count family that fails cannot be used for screening.

### 1.3 Costs that stay invisible off the device (agree with the plan, with gaps)

The plan's §4.6 table is honest about the render server, finger-only effects, heat, LPM and version skew. Gaps:

| Invisible cost | Why it matters here | Status | Fix |
|---|---|---|---|
| **Image decode** | Neither count catalogue has a decode count. Chromium's C1-C18 has none; note 03 §8 names "image px decoded" without a C-number. WebKit's §7.1 has none. The `images` part and the lazy People avatars are in scope | INFERRED | Add `decodedPx` per frame, or exclude image and asset changes from class W |
| **CA animation rate** | WebKit asks for 80-120 Hz for every CA animation it creates (note 04 §2.3, CONFIRMED there). Moving an rAF effect to an accelerated animation can lower W but raise render-server load at up to 2× the page rate. Dominance over W counts calls that a pure win | INFERRED | Count "active accelerated animations × requested rate" as a vector component, so such a move is "mixed" |
| **GPU fill / overdraw on the A17 Pro** | C17/C18 exist for Chromium only. The WebKit `RS` term is calibration-only | CONFIRMED gap (PLAN §4.6) | Already class X; make the class-X classifier mechanical (a lint on `filter`, `backdrop-filter`, `mix-blend-mode`, group opacity) |
| **Scheduler mode switching** | B1 failure moves Chromium into high-latency mode based on its own p90 estimate (note 03 §3.4). Removing work can flip the mode and change which frames are partial. Prediction is not monotone in work across a mode boundary | INFERRED | Simulate the mode state machine (note 03 §9.6 proposes it) before using any "no device" claim near B1 |
| **Thermal within a session** | v1's phone ran at tool-induced Serious heat (loop-distillation §5). A per-run `θ` cannot absorb within-run drift | INFERRED | Record thermal state per block. Refuse a calibration block that changes thermal class mid-block |

### 1.4 The dominance screen and class W

- **The theorem is correct, but the premise does not hold.** `mainUs_mono` (`05-lean-sketch/Fw/Spec/Cost.lean`
  l.29-38) proves monotonicity for a 4-field `Work` with `Nat` coefficients. Class W uses it to land changes with no
  device "if counts dominate in both engines" (PLAN §9.2). Dominance is only as good as the vector:
  - The vector omits script ms ("measured, not modelled"), decode, CA rate and WebKit element counts (§1.5).
  - **Per-frame vs total.** Missed frames depend on per-frame peaks. A variant that moves work in time (batching,
    debouncing) can lower totals while raising one frame. W must require **per-frame** componentwise dominance on
    aligned steps, not dominance per zone.
  - **Frame alignment.** For a variant that changes layout height, step k shows different content in each arm.
    Dominance on misaligned frames is meaningless. Align by content anchor ("crossing coordinates", PLAN §4.6), not
    by y.
- **The WebKit model is not monotone as written.** Note 04 §7.1 has `F_f = max(0, s²·Ap/R_cg + Bn/R_alloc − overlap)`.
  The `− overlap` term breaks "linear in counts with non-negative coefficients" (PLAN §4.3). Replace it with
  `max(s²·Ap/R_cg, Bn/R_alloc)`, which is monotone, or drop it.
- **The proved model is not the planned model.** The sketch has no `κ`, no indicator terms (`c_sty0·[E>0]`), no
  `⌈T/I⌉`, no `max` and no p90. All of these are monotone, but the theorem has to be stated for the model actually
  used. Also, quantile regression is usually unconstrained: the τ = 0.9 fit must be constrained to `c ≥ 0`, or the
  theorem does not apply to the p90 predictor (INFERRED).
- **Fix.** Class W = per-frame dominance over a vector declared "complete for this mechanism class", plus a
  mechanical lint that the diff touches no uncounted family (images and assets, `filter`/`backdrop-filter`, new
  WAAPI or CSS animations, fonts). Anything else is class S.

### 1.5 WebKit Phase A lacks its largest term

- PLAN §4.2's table admits it: "no element count without WKTR". Note 04 §4.1 confirms that `RecalculateStyles`
  records carry no element count.
- Yet `E_f` (`c_sty·E_f`) drives the WebKit `W` model, and v1's WebKit costs were dominated by restyle:
  - custom-property restyle 2.2× (v1 `research/cpu-throttle-calibration/README.md` l.39);
  - presence-flip layouts (note 04 §3).
- D8 recommends skipping WKTR unless "a needed count is missing". By the plan's own table it is already missing.
- **Fix.** Pick one:
  - (a) Run the 1-day WKTR spike in M1 on a cloud Mac (a decision with a cost).
  - (b) Until WKTR exists, the WebKit model is at most `ranks-only` for style-affecting changes, and class W is barred
    for any diff that touches selectors, classes or custom properties.

### 1.6 Chromium count transfer and validation target

- **Raster counts differ by path.** Headless Chrome uses software GL (SwiftShader) unless GPU is forced
  (INFERRED, secondary sources only: Chromium commit d99a9664c873 "headless: Switch from osmesa to SwiftShader";
  https://www.remotion.dev/docs/cli/gpu). In a Linux container (§1.1) it certainly has no Metal GPU. Tile geometry
  for GPU raster comes from `tile_size_calculator.cc` (note 03 §5.5); software raster uses `default_tile_size`. Tile
  and raster counts (C8-C10) from the counts lane therefore need not match headed Mac Chrome, where the timing lane
  fits the coefficients.
- **No transfer gate.** WebKit has M-b (Simulator count = phone count); Chromium has no equivalent.
  **Fix:** add **M-b′**: headless-container counts equal headed Mac Chrome counts (from a traced, non-timed run) per
  family, before any coefficient is fitted on them.
- **M-a validates on the wrong device.** Stage MAPE on Mac Chrome (M1 Pro) says nothing about the target, iPhone
  Safari (D4). Either:
  - state that the Chromium model is a **development aid** (counts and mechanism only, no fitted coefficients), and
    spend the calibration budget on WebKit; or
  - take D4(c) and validate on an Android Chromium phone. That is also arguably closer to fastwork.com's real users
    (INFERRED; check the Thai mobile OS share before deciding).

### 1.7 Coefficients depend on the page mix (contradiction in note 03 §11)

- Note 03 §11 says "coefficients are per unit of work, so they do not depend on the page mix". The same note (§5.1)
  cites v1: `style_recalc_var` took 2.2× longer on the fastwork page than on a blank page. v1 attributes this to
  "the page's own every-frame animations compete with it" (v1 `research/cpu-throttle-calibration/README.md` l.39,
  CONFIRMED).
- Per-unit cost is also set by stylesheet size and selector shape, DOM depth and layout object types, none of which a
  micro-fixture reproduces (INFERRED).
- **Fix.** Fit `T = θ_run · ρ_page · (κ + c·x)`, with `ρ_page` estimated on arm A (the original) during M3. Report
  fixture-only predictions as `uncalibrated` until `ρ_page` exists. Fixtures for style and layout should carry the
  original's rule count and custom-property count as parameters, so the shape matches without copying Fastwork CSS.

### 1.8 Devices still needed: a realistic count

PLAN G2 targets ≤ 1 block per landed class S change. The licence rule (M-f: 5 of 5 blind verdicts per change class)
plus a calibration session per trigger plus a 1-in-5 spot-check means about 5-10 phone sessions before **any** class
leaves the device. Classes X and P always need the phone. That is far below v1's level, but it is not "the phone
only for calibration". Say so in §0 of the plan, so the user's expectation for pain point 1 is set correctly (INFERRED).

---

## 2. Bet 2: a visually identical React rewrite is a faithful perf proxy

1. **L5 cannot pass as specified.**
   - M-i requires byte-identical counts across runs. The counts lane is deterministic, so "A's spread over 5 loads"
     (PLAN §6.5 L5, M-h) is **zero**, and L5 then demands exact equality of every count.
   - A React tree cannot meet that. It has a different DOM node count, different stylesheet structure and invalidation
     sets, a different listener count (C15) and different `elementCount` per restyle (INFERRED).
   - **Fix.** Define L5 per count family as a relative band calibrated on the M2 pilot, for example
     `|R−A| ≤ max(2, 5 %)` for style and layout. Keep layers ±0 and the compositor/main split exact.
2. **Count parity is not cost parity.** "Dead CSS is not ported" (PLAN §6.1) removes about half of 11.8k lines of
   CSS. `elementCount` can match while the per-element matching cost falls, so the rewrite is cheaper than the
   original for the same counts (INFERRED; same mechanism as §1.7).
   - **Fix:** add **L6 timing parity**. Mac Chrome timing lane, per stage, R within A's A/A band (ABBA, n ≥ 4). Add
     one Simulator Timeline comparison and one phone block on the whole page at M4.
   - Optionally ship the dead rules as an inert stylesheet in the `faithful` preset (restated, not copied), so the
     rule count matches.
3. **Nothing tests that wins transfer back to fastwork.com.** M6 only writes up "what transferred". v1 could
   A/B on the original because it overlaid fixes on the snapshot.
   - **Fix:** for every landed optimization with a CSS-only or overlay-expressible form, run the same change as an
     overlay on arm A (the original) in the counts lane. Require the same sign of Δ per stage. Do this as a
     **transfer check** at L (land), not at M6.
   - Without it, a v2 win is a win on a page that only resembles fastwork.com. R1's mitigation ("L5 gate") covers
     look and counts, not decisions.
4. **"React" shrinks to shells around imperative code.** Rule 1 (no per-frame values through React state, `sx` or
   Emotion) and D3 (CSS Modules for every animated part; MUI only for non-animated chrome) are right for
   measurement. But they mean the perf-relevant code is hand-written imperative DOM code inside React components,
   and MUI is mostly absent from the experiment.
   - That is a valid design. But the user asked for MUI and for "easier to optimize" because of React. PLAN §0
     should say plainly that the gain comes from **readable source plus flags**, not from React or MUI themselves.
5. **Hydration and first-interaction behaviour** differ between Svelte 5 and React 19 (note 02 §7 risk 1). The plan
   puts them in class X. Agreed, but the prerender plus hydration path also needs one L6 check under load: rest 6 s
   and the first scroll.

---

## 3. Bet 3: Lean adds net value for a small agent team

### 3.1 Value vs cost

| Claim in the plan | Assessment |
|---|---|
| Lean removes v1's lock and console bug classes (PLAN §2.2, M-m) | Partly. Of the lock incidents note 05 §3 lists, I-005 (re-entrant across pids), I-012/I-035 (many writers) and I-041 (co-hold on a live lock) are cross-process IO races. The **single-writer console-api plus an append-only log** removes them whether or not the step function is in Lean (INFERRED). Lean adds a proof over *all* traces where fast-check model-based testing (`fc.commands`) would sample them. That is real but marginal for 100-line state machines |
| v1's biggest bug class | About 111 of 276 incidents involve the iPhone or Simulator driver (PLAN §0). Lean addresses none of them. Most v2 bugs will again be adapters (CDP, iwdp, Playwright webview backend, container) (INFERRED) |
| M-l: ≥ 90 % of the decision inventory proved by M4 | A vanity metric. It rewards proving trivial definitional facts (`compositorOnly_same_main` is `rfl`; `better_sound` restates the definition). Wave 3, engine rules as Lean data, proves facts about **our transcription** of `KeyframeEffect::canBeAccelerated`. Transcription error is the real risk, and a proof cannot catch it. A table-driven test against WKTR or `compositeFailed` can |
| Build and tool cost | Low and measured: 23 s clean build, 0.5 s incremental (note 05 §1). Real costs are elsewhere: 2.8 GB toolchain; a 214 MB `.lake` per worktree × 4 worktrees; `fwcore` must be built before L2 runs in each worktree (a turbo dependency); toolchain bumps every month (R11) |
| Agent proof productivity | Measured once, on a 630-line sketch with easy goals. Bounded-wait liveness (wave 2) is the first non-trivial proof. Note 05 §6.6 already says liveness is "harder". No estimate exists |

**Fix (recommendation).**
- Keep waves 1-2. They are cheap, and the lease and lifecycle specs are good design documents.
- Drop wave 3 and the M-l ≥ 90 % target. Replace M-l with a **bug ledger**: every incident is tagged "would a proof
  have caught it / did a property test catch it / adapter". At M4, decide from the ledger whether Lean pays, the way
  Cedar counted 4 proof-found vs 21 DRT/PBT-found bugs (note 05 §2).

### 3.2 Glue risks the plan does not list (CONFIRMED)

1. **A Lean panic returns a default value.** `leanprover/lean4@v4.35.0`, `src/runtime/object.cpp`:
   `lean_panic_fn(default_val, msg)` prints and `return default_val` (l.198-202). It aborts only when
   `LEAN_ABORT_ON_PANIC` is set (l.76-82). So `Wire` code using `get!`, `head!` or `[i]!` can return a well-formed
   **wrong decision** (for example a default `Verdict`) with only a stderr line.
   **Fix:** spawn `fwcore` with `LEAN_ABORT_ON_PANIC=1`, add an ast-grep/grep ban on `!`-suffixed partial ops in
   `Fw/Wire.lean` and `Main.lean`, and treat any stderr output as an incident.
2. **Replies are matched to requests by arrival order only.** The TS bridge (note 05 §5.3) resolves
   `waiting.shift()` per line. `Main.lean` l.7-10 **skips blank lines without replying**. One whitespace-only
   request, or one reply lost on a crash, shifts every later answer onto the wrong request.
   **Fix:** every request carries `id`, `fwcore` echoes it, the client rejects a mismatch. Add a per-call timeout and
   restart.
3. **Integer µs truncates coefficients.** `UnitCost` fields are `Nat` µs per element (`Cost.lean` l.21-25). A fitted
   per-element style cost below 1 µs truncates to 0.
   **Fix:** use `Rat` or ns for coefficients at the boundary.
4. **`Rat` over JSON.** PLAN §5.2 says numbers cross as integer µs or `Rat`. Check that `Rat` has
   `ToJson`/`FromJson`, or define the wire form (`{num, den}`) explicitly (INFERRED; not checked).

### 3.3 The proved verdict rule is statistically weak (INFERRED, exact arithmetic)

- `better` = all 3 variant runs are below all 3 control runs (note 05 §4.1). Under the null with exchangeable runs,
  P(that ordering) = 1 / C(6,3) = **1/20 = 5 %** one-sided, or 10 % for "better or worse".
- Over the 22-row M5 backlog plus ablations, about one false "better" is expected by chance.
- `better_sound` proves the rule does what it says, not that it controls error. v1 also had a sequential 4v4 rule
  (protocol §5.3; note 05 §4.1, U = 0 at 4v4 gives p = 1/70).
- **Fix.**
  - Make 4v4 (or the sequential rule) the landing verdict.
  - Prove the exact null probability in Lean (cheap: enumerate C(8,4) in `Rat`, the T2 row of note 05 §4.1). That
    is a theorem with real decision value.
  - Record the number of comparisons per experiment.

---

## 4. Bet 4: the agent-team token plan is realistic

### 4.1 The plan's own numbers break G3

| Item | Source | Value |
|---|---|---|
| Lead, one working day | PLAN §8.4 envelope | ≈ $180 |
| Roadmap length | PLAN §10.1: M0 3 d, M1 wk 1-2, M2 wk 3, M3 wk 3-4, M4 wk 4-6, M5 wk 6-8 | ≈ 40 working days |
| Lead total | 40 × $180 | **≈ $7,200** |
| G3 caps | PLAN §1.1 | whole project ≤ $4,000; lead ≤ 25 % (≤ $1,000); Opus ≤ 70 % |

- The lead alone is about 1.8× the whole-project cap and about 7× its own cap. The Opus share cannot be ≤ 70 %
  either: lead, eng-*, measure-engineer, lean-prover, experiment-owner and reviewer are all Opus. Only part-builder
  and console-builder are Sonnet.
- A rough bottom-up with the plan's envelopes (INFERRED):
  - lead $7.2k;
  - about 20 engine topics × $48 ≈ $1k;
  - about 30 parts × $6, with parity iteration likely 2-3× that, ≈ $0.2-0.5k;
  - measure, Lean and review at Opus/high, about $2-4k.

  That gives **$10-13k**, which is 75-95 % of v1, with an Opus share near 90 %.
- **Fix.** Either:
  - re-baseline G3 honestly (for example ≤ 60 % of v1, Opus ≤ 85 %); or
  - make the lead cheap for real: cW 150-200k, not 400k (PLAN §8.4 lever 2 says capping context is the second-biggest
    lever, but D14(iii) sets 400k), a target of ≤ 600 requests a day, and planning days only on `high`. At 600 ×
    150k × $0.20/M = $18 a day of cache reads, plus output, the lead fits about $1.5k over 40 days.

### 4.2 The global `subagentPromptCacheTtl: "1h"` may cost more than it saves

- Pricing (CONFIRMED, https://platform.claude.com/docs/en/about-claude/pricing): Opus 5.5 charges $5/M for a 5m
  write, $8/M for a 1h write and $0.20/M for a hit. A 1h write breaks even only after two reads.
- v1's meter shows about 25.8 G of 26.8 G tokens as cache reads (v1 `research/loop-distillation/README.md`, Money
  table), leaving at most about 1.0 G for writes, input and output.
- At Opus 5.5 prices, the reads cost about $5.2k. If about 0.9 G were writes, they cost about $4.5k at 5m or $7.2k at
  1h. **Writes are about half of input-side spend, and a global 1h TTL raises all of them by 60 %.** That is a net
  loss unless it removes about a third of the write volume as cold rewrites (INFERRED; the split between cold
  rewrites and incremental writes is unknown).
- **Fix.** Per-agent `experimental.cacheTtl: 1h` exists (CONFIRMED, sub-agents frontmatter, v2.1.248+). Use it for
  the teammates that idle 5-60 min (eng-*, exp-*). Keep 5m for bursty subagents (part-builder, reviewer,
  librarian). Decide from the M0 meter (cacheCreation vs cacheRead per role).

### 4.3 Other realism checks

- The in-process teammate effort and window rules hold, and `isolation` on the call keeps a named spawn a subagent
  (CONFIRMED, §5). Spike S-b is mostly answered by the docs.
- `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` **does not count teammates** ("teammates follow their own limits",
  CONFIRMED, sub-agents doc). The cap of 3 teammates therefore rests on `guard.mjs` alone, so test that hook.
- The ref-librarian's 100k window is the minimum allowed, and Haiku's price step is at a 100k prompt. Compaction
  triggers near the window, so many late requests will be in the 5× tier (INFERRED). Meter it, or cap at 100k with
  `maxTurns` low enough to end before that.

---

## 5. Bet 5: spot-checks of technical claims

| # | Claim (where) | Result | Evidence |
|---|---|---|---|
| 1 | In-process teammates apply the definition's `model`, `effort`, `tools`, `disallowedTools` and `autoCompactWindow`; split-pane ones don't apply effort or window (PLAN §8.1) | CONFIRMED | https://code.claude.com/docs/en/agent-teams "Use subagent definitions for teammates". Also: a teammate brought back re-applies a `.claude/agents/` definition **only if that folder is trusted** |
| 2 | `name` + `isolation` on the call stays a subagent (spike S-b) | CONFIRMED by docs | sub-agents "Subagent names": "...unless the call is a fork or passes `isolation` on the call itself". Note: `isolation: worktree` branches from the **default branch** unless `worktree.baseRef: "head"` (set in the plan) |
| 3 | `teammateMode: "in-process"` needs committing | CONFIRMED, but redundant | agent-teams: "The default is `in-process`". Harmless to commit |
| 4 | `subagentPromptCacheTtl`, `autoCompactWindow`, `worktree.{baseRef,symlinkDirectories}`, `includeGitInstructions` are valid settings keys | CONFIRMED (index rows) | https://code.claude.com/docs/en/settings-reference |
| 5 | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` default 3; `CLAUDE_CODE_ENABLE_TODO_TOOLS`; `CLAUDE_CODE_EFFORT_LEVEL` overrides every effort | CONFIRMED | https://code.claude.com/docs/en/env-vars. The env-vars page says settings-file `env` values are reapplied to running sessions, except for startup-only features such as OTel, and does not mark TODO_TOOLS as startup-only. Spike S-a is likely to pass (INFERRED) |
| 6 | Agent permission rules match literal parameters (`Agent(model:opus)` ≠ the full ID; an omitted parameter never matches) | CONFIRMED | https://code.claude.com/docs/en/permissions l."Parameter matching". Consequence: a role file with `model: claude-fable-5-1` and no call parameter is **not** caught by the ask rule. Use `Agent(model:*fable*)` and forbid fable in role files with a lint |
| 7 | Opus 5.5 / Sonnet 5.5 / Haiku 5.5 / Fable 5.1 prices (note 07 §4.1) | CONFIRMED | pricing page, matches the note exactly |
| 8 | Headless-shell BeginFrameControl is the steppable build (note 03 §7.1) | **REFUTED on macOS** | §1.1 |
| 9 | Seeking every animation each step is a neutral way to make counts deterministic (note 02 §3.5, note 04 §8) | **REFUTED** | §1.2 (Chromium `animation.cc`, WebKit `WebAnimation.cpp`) |
| 10 | `Bash(gh api * -X *)` deny keeps `gh api` read-only (PLAN §8.3) | **REFUTED** | `gh api --help`: "The default HTTP request method is GET normally and POST if any parameters were added". Deny `gh api * -f *`, `-F`, `--field`, `--raw-field`, `--input`, `--method`, or route reads through `pnpm fw src:fetch` |
| 11 | JSON-lines `fwcore` is safe glue (note 05 §5) | WEAKENED | §3.2 (Lean `object.cpp` panic semantics; `Main.lean` blank-line skip) |

Smaller config findings:
- **Edit prompts.** With D14(i) `default` mode, file modification prompts (CONFIRMED, permissions table: "File
  modification … Approval required: Yes"). The allow-list has no `Edit`/`Write` rules and no `git add`/`git commit`,
  so every worktree agent's edits and commits prompt the user through the lead.
  **Fix:** add lane-scoped `Edit(/apps/site/src/parts/**)` and similar rules, plus `Bash(git add -- *)` and
  `Bash(git commit -m *)`, and keep `guard.mjs` as the per-role fence.
- **Teammate by accident.** A named spawn of an editing role **without** `isolation` on the call becomes a
  teammate in the main checkout (CONFIRMED, item 2). `guard.mjs` should deny an `Agent` call that has a `name`, an
  editing `subagent_type` and no `isolation`.
- **`symlinkDirectories: [".cache"]`** shares raw traces and upstream clones across worktrees. Make sure the artifact
  store's single-writer rule also holds across worktrees (v1 I-095 disk incident) (INFERRED).

---

## 6. Suggested changes to the plan, in order

1. **M0:** add spike S-i (Linux container counts lane with BeginFrameControl and pinned fonts) and S-j (harness
   neutrality fixtures: seek vs free-run, clock shim with native rAF). Re-plan D5-D8 to depend on them.
2. **§4:** add M-b′ (Chromium count transfer), M-n (harness neutrality) and `ρ_page`. Fix the WebKit `F` term. Make
   class W per-frame, over a complete-for-class vector, with an uncounted-family lint. Decide D8 now, since the
   element count is already missing.
3. **§6.5:** replace "A's spread" with per-family bands. Add L6 timing parity and a per-landing transfer check on
   arm A.
4. **§5:** drop wave 3 and the M-l ≥ 90 % target. Add the bug ledger, request ids, `LEAN_ABORT_ON_PANIC=1` and a
   ban on partial ops. Prove the verdict's null probability and move landing to 4v4 or sequential.
5. **§8:** re-baseline G3 or the lead's window. Use per-agent cache TTL. Fix the `gh api` deny list, the edit allow
   rules, the isolation guard and the Fable rule pattern.
6. **§0:** tell the user plainly that the phone stays in the loop for classes X and P and for the licences (about
   5-10 sessions before any class is licensed), and that "React + MUI" is in practice "readable parts + flags",
   with MUI kept out of anything animated.

## 7. Sources

- Chromium `chromium/chromium@317846d579b2` (main, 2026-10-16):
  `headless/lib/browser/protocol/target_handler.cc` l.55-68, 148-149;
  `headless/lib/browser/headless_web_contents_impl.cc` l.415-417;
  `third_party/blink/renderer/core/animation/animation.cc` l.576-660, 741-800, 2826-2860.
- WebKit `WebKit/WebKit@fba976461fc0` (main, 2026-10-16): `Source/WebCore/animation/WebAnimation.cpp` l.587-620,
  1048-1063.
- DevTools protocol `ChromeDevTools/devtools-protocol@e908551762a5`: `json/browser_protocol.json`
  (`Target.createTarget.enableBeginFrameControl`, `HeadlessExperimental.beginFrame`).
- Lean `leanprover/lean4@v4.35.0`: `src/runtime/object.cpp` l.76-82, 114-206.
- Playwright clock: https://playwright.dev/docs/clock
- Claude Code docs (fetched 2026-10-17): https://code.claude.com/docs/en/agent-teams,
  https://code.claude.com/docs/en/sub-agents, https://code.claude.com/docs/en/settings-reference,
  https://code.claude.com/docs/en/env-vars, https://code.claude.com/docs/en/permissions
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing
- `gh api --help` (local gh CLI)
- Headless GPU (secondary, INFERRED): https://chromium.googlesource.com/chromium/src.git/+/d99a9664c873fc38e226e33bc92da974fb852da3,
  https://www.remotion.dev/docs/cli/gpu
- v1 (read-only): `research/loop-distillation/README.md` §5 "Money" and §6.5;
  `research/cpu-throttle-calibration/README.md` l.39.
- This repo: `docs/plan/PLAN.md`; `research/kickoff/02-07`; `research/kickoff/05-lean-sketch/{Main.lean,Fw/Spec/Cost.lean}`.
