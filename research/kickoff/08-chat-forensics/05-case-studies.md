# 08-05 Case studies: four v1 topics traced end to end

**Lens.** Four topics from v1's `fixes/`, each traced across the raw transcripts, the digests and the local console
(threads, steps, proposals, incidents): two clear wins, one line that churned, one tooling incident with a long tail.
For each one: the timeline from question to landing, the agents, messages, measurement runs, phone holds, rework,
review, wall-clock and tokens. Then what was on the critical path, what slowed it, and what the v2 plan
(`docs/plan/PLAN.md` rev 2) would change. Where v2 would not help, the note says so.

**Labels.** MEASURED = computed from the data with the command shown. INFERRED = my reading of measured data.
QUOTED = taken from a v1 file or a kickoff note, cited. All times are UTC. Token counts are per model request,
deduplicated by `requestId` (the same rule as the digest's `extract.mjs`). "Cache-read" is the cache-read input
tokens, the main cost driver (kickoff [01 §C]).

| Case | Kind | Question → landing | Wall-clock | Phone time on the path | Main cost |
|---|---|---|---|---|---|
| A. `sticky-walk` → g0.0j | clear win, counts-led | 10-08 18:48 → 10-09 00:46 | **5 h 58 min** | 65 min (one block, no re-runs) | owner investigation: 393 requests before the phone |
| B. `people-blink` → g0.0l, then `reveal-paint` → g0.0m | clear win, look change + device-only trade | 10-09 03:38 → 10-10 03:4x | **~24 h** (7 h + 16 h 45 min) | 41 + 43 min of blocks, **11 h 52 min waiting for the phone** | waiting for a re-plug overnight |
| C. End-of-page morph line (T-204 → rollback → return) | churn | 10-05 21:14 → 10-09 03:40 (PR-040 accepted) | **~78 h** | 19 end-of-page phone blocks, 5 passes (QUOTED [01 §B]) | 37 agents, 2.78 B cache-read; changing behaviour target |
| D. iPhone link (USB/WDA/Wi-Fi) | tooling incident, long tail | 10-01 16:36 → 10-13 (never root-caused) | 12 days | — | an LLM cron: 1,889 fires, 1.06 B lead cache-read |

## How to reproduce

```sh
cd .local/v1-chat-digest/out                     # every jq/node one-liner below runs here unless it says otherwise
V1=~/.claude/projects/<v1-project-dir>           # raw transcripts, read-only
LEAD=$(ls $V1/391f6dee-*.jsonl)                     # the main lead session (id shortened here)
SUB=$(ls -d $V1/391f6dee-*/subagents)
C=<v1-repo>/console; F=<v1-repo>/fixes           # console store and fix folders, read-only
H=<dir with the two helper scripts in the appendix> # win.mjs (usage in a time window), trig.mjs (what woke the lead)
# transcript of a named agent:  jq -r '.[]|select(.name=="fix-scrollcb-g0").file' agents.json
```

Each `peer-messages.jsonl` message appears twice (the queue record and the delivered record), so this note counts
messages from `sendmessage.jsonl` (the sender's side), which has no duplicates.

---

## Case A. `sticky-walk` → g0.0j (a clear win, found by counts)

**What landed.** On touch screens the profile deck's six cards are sized with container-relative units instead of an
aspect ratio, so a dirty sticky box no longer makes WebKit's whole-view layout re-lay them out during a finger drag. CSS only. QUOTED (`fixes/BEST_BUILDS.md`, g0.0j row):
iPhone P-172, finger-down y 1000-3400: Layout ≥ 5 ms per run 152-159 → 0-1; frames > 34 ms 12-18 → 2-6; frames
> 50 ms 1-3 → 1, "no separation at n=4, threshold-sensitive". It landed on the less-work rule (counts plus a phone
no-worse check), not on the primary feel metric.

**Timeline** (MEASURED, `jq -r 'select(.ts>="2026-10-08T18:48" and .ts<="2026-10-09T00:47" and ((.who|endswith("/fix-scrollcb-g0")) or .to=="fix-scrollcb-g0")) | [.ts[0:16],(.who|split("/")|last),.to,.msg[0:100]]|@tsv' sendmessage.jsonl`):

| Time | Event |
|---|---|
| 10-08 17:11 | `fix-scrollcb-g0` (fix-owner, Opus, named worktree subagent) spawned for another topic (scroll callback on g0.0f) |
| 18:48 | That topic closes **closed-no-fix**; the lead hands the same owner a new topic, `sticky-far` |
| 18:56 | The owner's existing knock-out data predicts `sticky-far` gains nothing; it does not build it and proposes another reading. Lead: rename to `sticky-walk` |
| 19:03 | Incident I-253: the shared Simulator session is refused (Simulator left booted); non-blocking |
| 19:02, 20:47 | Two Sonnet mappers read WebKit source (sticky relayout mid-drag; aspect-ratio flex relayout) |
| 20:38-20:46 | Simulator "nudge map" (1 px programmatic nudges every 200 px) locates the layouts under the deck |
| 20:54 | D card **LOCATED**, signed by the lead the same minute |
| 21:27 | Simulator WDA drag check: layouts ≥ 5 ms 138-144 → 36-49 per run → lead signs **D NAMED** (fast path). The lead then sends three near-identical "start F now" messages at 21:28 |
| 22:05 | F interim: 2-4 layouts ≥ 5 ms per run vs 129-169 |
| 23:00 | Another landing (g0.0i) moves the best build; the owner restacks onto it |
| 23:27-23:28 | Phone card drafted and signed (P-172) |
| 23:31-00:36 | **Phone block P-172**: 12 holds valid, both sentinels pass, no re-runs |
| 00:42-00:46 | Lead rulings, commit, landed on main. The user later asks for a blind swipe test (10-09 03:19), which starts case B |

**Agents and messages** (MEASURED): one owner; two Sonnet mappers (20 and 50 requests, 1.1 M and 4.6 M cache-read;
`jq '.[]|select(.name|IN("map-sticky-middrag","map-aspect-relayout"))|{name,asst,cr:.usage.cacheRead}' agents.json`);
16 lead → owner and 18 owner → lead messages in the window (jq above, `| cut -f2 | sort | uniq -c`). No `fix-reviewer`
was spawned: every signature (D LOCATED, D NAMED, the P-172 card, the verdict rulings) came from the lead.

**Wall-clock and tokens** (MEASURED, `node $H/win.mjs $V1/$(jq -r '.[]|select(.name=="fix-scrollcb-g0").file' agents.json) <t0> <t1>`;
lead: `node $H/win.mjs $LEAD 2026-10-08T18:48 2026-10-09T00:47 'sticky|fixcq|P-172|scrollcb-g0|g0\.0j|g0-0j'`):

| Phase | Wall-clock | Owner requests | Owner cache-read | Owner output |
|---|---|---|---|---|
| Investigation + build + gates (18:48-23:31) | 4 h 43 min | 393 | 93.7 M | 47.8 k |
| Phone block (23:31-00:37) | 65 min | 24 | 6.4 M | 2.3 k |
| Whole window | 5 h 58 min | 449 | 111.0 M | 56.7 k (3 compactions) |
| Lead, requests whose content names the topic | — | 86 | 27.8 M | 32.0 k |

**Critical path** (INFERRED from the timeline): Simulator counts (nudge map 2 h, drag check 35 min) → build and
gates (2 h, including a restack onto a newly landed build) → phone (65 min). The phone was 18 % of the wall-clock and
5 % of the owner's tokens; the tokens went into the investigation at about 270 k cache-read per request (owner
lifetime average: `jq '.[]|select(.name=="fix-scrollcb-g0")|.usage.cacheRead/.asst' agents.json`). Nothing waited on
the user. What slowed it: a shared Simulator lane (queued behind a priority-1 topic), I-253, and the restack.

**What v2 would change.**
- *Helps:* the decisive evidence was WebKit **counts** in the Simulator (layout passes ≥ 5 ms per drag), which is
  what v2's WebKit counts lane produces (§4.1-4.2). The knock-out arms (a positioning change, fixed sizes, container-relative units)
  are exactly v2's generated ablation and optimized variants (§6.2): flags instead of hand-built overlays. The
  Simulator sign matched the phone's (Simulator 138-144 → 36-49; phone 152-159 → 0-1), the kind of row V-d needs.
- *Does not help, as written:* (1) the diff adds CSS rules, so under §4.2 / Q10 ("class W is barred for any diff that
  touches selectors, classes or custom properties" until WKTR exists) it is **class SM, so the phone is still
  needed** until the model is licensed. (2) The mechanism needs the drag state (the owner's WebKit source read: the
  layouts appear while the scroll view is dragging), and v2's WebKit stepping (§4.2) uses scroll steps, not WDA
  finger drags; §4.6 files finger-only effects under "device". v1 got the drag state from **Simulator WDA drags**, a
  middle tier the plan lacks. (3) The primary feel metric did not separate at n=4; v2's 4v4 verdict (§5, Q13) would
  return "noise" exactly as v1's reader did. The win is a work win, and v2 has the same rule for it as v1 (class W).
- *Net:* at best v2 saves the 65-min block plus about 1 h of card drafting and reading, out of 6 h. It saves few
  tokens unless the ablation flags shorten the investigation (INFERRED).

---

## Case B. The people card: `people-blink` → g0.0l, then `reveal-paint` → g0.0m (a clear win with a device tail)

**What landed.** g0.0l: on a fast scroll down, the people card appears already sharp instead of fading in from a blur,
so the profile deck no longer "blinks" (a look change, proposal PR-041). g0.0m: on touch screens the hidden card is
kept painted but transparent rather than hidden, so its layers are painted before the reveal rather than in the
reveal frame; the reveal frame went 50 → 30.5 ms on a flick, at about +22 MB graphics memory (QUOTED,
`fixes/BEST_BUILDS.md` g0.0l/g0.0m rows).

**Timeline** (MEASURED from `sendmessage.jsonl` with the same jq pattern for `fix-scrollcb-g0` 10-09 03:38-10:47 and
`fix-reveal-paint` 10-09 10:58-10-10 03:40; user messages from `$C/threads/T-228.json`; steps from `$C/steps/`):

| Time | Event |
|---|---|
| 10-09 03:38 | During the g0.0j blind swipe test the user reports the deck still blinks (T-228 #124); 03:45 "fix it in the next version" |
| 04:22 | User: the original site blinks too (inherited, not a regression) |
| 04:24 | The owner wants to decode its Simulator video; the lead rules no (the user's no-screen-frames rule, enforced by the git guard) |
| 04:36 | The user allows Simulator videos; a toolsmith is spawned to widen the guard (guard lands 06:52) |
| 06:06-06:43 | Simulator screenshot bursts; the s5 strips catch it: the card's own blur-and-fade reveal; knocking out the reveal removes it |
| 06:26-06:54 | `fix-deck-chrome` (Opus, 96 requests) does the Chrome side in parallel; same reading |
| 06:42-06:49 | A 7-min iPhone hold confirms it on the real phone |
| 07:10 → 07:23 | PR-041 posted (the first publish fails a validation rule and is re-posted), **accepted 13 min later** |
| 07:41-09:25 | Gates paused: the baseline snapshot gets a new pin (6 missing thumbnails); gate round 2 finds and fixes a photo diff (rev 2) |
| 09:34 | Phone card P-174 signed, three times (the signature crossed the owner's hand-back, then a status-row reminder) |
| 09:43-09:47 | P-174 stops before data: the phone is off the Mac's Wi-Fi (I-260); user step C-138 done 09:53; restart 09:54 |
| ~10:35 / 10:4x | P-174 done; **g0.0l lands** (7 h after the report) |
| 10:58 | `fix-reveal-paint` spawned for the cost P-174 disclosed (reveal frame 44-60 ms vs 35-47) |
| 11:43 → 11:53 | A side answer to the user (images repainted) names async decode; 10 min later the decisive check corrects it: cause unresolved. The lead relays both to the user |
| 12:33-12:34 | D card signed with 5 rulings; ruling 1: **"Gate class is NOT less-work"** (paint moves 1-3 frames earlier, total equal, more memory) |
| 13:24 | Rev 3 to match g0.0l's accessibility tree and focus order exactly (6 hidden profile tabs stay live) |
| 14:44 | Phone card signed (P-175) |
| 15:00 | Attempt 1 stops at the part start: the phone automation helper (WDA) cannot start |
| 15:08 → 10-10 02:49 | **User step C-140 (unlock + re-plug) waits 11 h 41 min** (`$C/steps/C-140.json`: posted 15:08:39, done 02:49:20) |
| 10-10 02:52-03:35 | P-175 runs and passes; g0.0m lands 03:4x |

**Wall-clock and tokens** (MEASURED, `node $H/win.mjs $SUB/<file> <t0> <t1>`; files from
`jq -r '.[]|select(.name=="fix-reveal-paint" or .name=="fix-scrollcb-g0").file' agents.json`):

| Phase | Wall-clock | Requests | Cache-read | Note |
|---|---|---|---|---|
| people-blink owner, 03:38-10:47 | ~7 h | 518 | 144.6 M | 2 compactions; 26 lead → owner, 20 owner → lead messages |
| reveal-paint owner, active 10:58-15:26 | 4 h 28 min | 683 | 178.1 M | 2 compactions; 12 lead → owner, 13 owner → lead messages |
| reveal-paint owner, waiting 15:26-02:52 | **11 h 26 min** | **1** | 0.4 M | idle costs nothing |
| reveal-paint owner, phone 02:52-03:40 | 48 min | 24 | 9.9 M | +0.9 M cache **write** to rebuild the expired cache |
| Lead, requests naming the topic, 03:38 → 03:40 next day | — | 314 | 100.3 M | `'people-blink\|PR-041\|reveal-paint\|g0\.0[lm]\|g0-0[lm]\|P-17[45]\|C-140\|deck\|fix-deck-chrome'` |

**Critical path** (INFERRED): for g0.0l, cause-finding (3 h, partly gated by the screen-frame rule) → proposal
(13 min) → gates (2 h, of which 1 h 44 min paused for a baseline re-pin) → phone (41 min + 7 min lost to Wi-Fi). For
g0.0m, 3 h 49 min of work, then 11 h 52 min waiting for the phone, then 43 min of phone. Half the case's wall-clock was
a device that needed a human hand overnight. The user answered the look decision in 13 minutes, so the user was not
the bottleneck; the user's availability to touch the phone was.

**Rework loops** (MEASURED from the timeline): PR-041 rev 2 (publish validation), g0.0l rev 2 (photo diff), g0.0m
rev 3 (accessibility and focus parity), one mechanism claim corrected after 10 min, P-174 signed three times.

**What v2 would change.**
- *Does not help on the critical path:* g0.0l is a look change → **class P** (always the phone plus the user's
  Try-it, §9.2). g0.0m trades paint timing for memory and touches a first-interaction reveal → **class X/SM**, and
  v1's lead ruled it "not less-work". The 11 h 52 min wait is about when a human can touch the phone, which v2 does
  not change (§4.6 says so).
- *Helps:* v2's per-frame dominance screen (§4.3) computes that ruling mechanically: "paint moved 1-3 frames earlier,
  total equal" is not componentwise dominance per frame, so it is not class W. That is a good golden fixture for
  `fwcore screen`. A Try-it page over flag presets (§6.2 `proposal` kind) replaces building `people-blink--b2/--b3`
  overlays.
- *Gaps the plan does not cover:* (1) the parity gate PL0-PL6 (§6.6) has no accessibility-tree or focus-order check,
  which forced g0.0m rev 3; (2) the screen-capture policy was decided mid-investigation, in three separate chat
  instructions (10-09 06:43, 14:26, 10-10 03:54; `jq -r 'select(.text|test("picture|guard";"i"))|.ts' human.jsonl`)
  plus a toolsmith; (3) the device lane has no notion of when the user can be reached.

---

## Case C. The end-of-page morph line: T-204 → v10-v14 → rollback → return (churn)

**What happened.** The user asked on 10-05 21:14 to make the end-of-page nav morph smooth (T-204) and made it the
only priority at 22:40. Over the next 78 hours the line went through a composited "menu follows your finger" morph
(v10-v14), a user-requested **rollback to the original end-of-page behaviour** (g0.0, g0.0b), eleven small g0.0x
landings on the original behaviour, and then **"the menu follows your finger again"** (PR-040, accepted 10-09 03:40).
QUOTED [01 §B]: "The end-of-page line cost ~349 fix commits, a rollback and a return" and "19 end-of-page phone
blocks: 5 pass, 6 fail, 5 open or insufficient, 2 attribution-only, 1 mixed".

**Timeline of decisions** (MEASURED from `$C/proposals/PR-0*.json` `.decision`, `$C/threads/T-204.json`,
`$C/threads/T-228.json`, `$F/BEST_BUILDS.md`):

| When | Decision |
|---|---|
| 10-04 20:12 | PR-018 accepted: the end-of-page morph **follows the scroll** (phones). 10-05 10:15 PR-023 refines it (v9-final) |
| 10-05 21:14 | T-204: optimize the end-of-page morph; `fix-end-morph` and `fix-end-morph-p1` spawned within 1.5 h |
| 10-06 03:21 | PR-012 rev 3 accepted (GPU clip reveal); the user calls it very smooth (T-204 #8) |
| 10-06 15:49 | PR-030 accepted (`arch-compositor-morph`, the menu card on the GPU), "land this into v10" |
| 10-07 | v11 / v12 / v13 phone checks fail on the **first menu open** (P-158, P-159 05:48Z, P-160 08:17Z); v14 passes (P-161) |
| 10-07 10:49-11:59 | The user sees the logo, language and Join buttons rise a little and the corners move; asks for an independent review that "reads our mistakes" and designs from zero (`arch-end-fresh`, 11:08) |
| 10-07 15:36 | PR-029 and PR-033 rejected |
| 10-07 15:38 / 15:51 | The user asks to roll back only the end-of-page scroll behaviour to the original and optimize it on the GPU |
| 10-07 16:02 → 18:44 | `fix-g0-revert` + `fix-g0-gpu` + 4 mappers; PR-034 accepted; g0.0b is best |
| 10-07 19:00 → 10-08 22:5x | g0.0c … g0.0i: corners, Join fade, logo jump, GPU bar, held photo columns, menu clock layer (phone checks P-164 … P-170b) |
| 10-08 18:38 → 10-09 03:40 | `fix-cm-return` revives PR-030's composited morph with a steady glass bar; PR-040 accepted; g0.0k lands 06:5x (P-173) |

**Size of the line** (MEASURED):
- 37 agents spawned in the window whose names belong to the line (14 fix/arch owners, the rest mappers and
  reviewers): **11,264 requests, 2.78 B cache-read (10.8 % of the project's 25.73 B), 1.08 M output, 48 compactions**.
  `jq '[.[]|select(.kind=="agent" and .first>="2026-10-05T21:00" and .first<"2026-10-09T07:00" and ((.name//"")|test("^(fix-end-|review-end|review-p1b|fix-panel-height|arch-compositor-morph|map-platform-fade|bm-cm-|map-cm-|map-end-|arch-end-fresh|map-nav-shift|arch-gpu-original|map-g0-|fix-g0-|fix-join-fade|map-jf-|fix-logo-close|fix-heat-fling|map-s-clusters|map-spotA|fix-menu-layers|map-menu-layers|map-morph-var|map-cd-morphcenter|map-nav-layers|fix-cm-return|bm-g0box)")))]|{n:length,turns:(map(.asst)|add),out:(map(.usage.output)|add),cacheRead:(map(.usage.cacheRead)|add),compactions:(map(.compactions)|add)}' agents.json`;
  project total `jq '[.[].usage.cacheRead]|add' agents.json`. (`int-v11`, 111.6 M, is left out because its build also
  carried other fixes.)
- The two largest contexts: `arch-compositor-morph` 2,793 requests, 719 M cache-read, 13 compactions in 28 h, at 257 k
  per request; `fix-g0-box` 2,317 requests, 585 M, 253 k per request
  (`jq '.[]|select(.name|IN("arch-compositor-morph","fix-g0-box"))|{name,asst,cr:.usage.cacheRead,compactions}' agents.json`).
  `arch-compositor-morph` left 13 `.diff` variants in its folder (c1, c2, c3, c3b-a, c3b-k4/k6/k8, …;
  `ls $F/compositor-morph/*.diff | wc -l`).
- Lead in the window: 6,990 requests, 2.06 B cache-read, 16 compactions; 3,562 of those requests (1.06 B) name the
  line (`node $H/win.mjs $LEAD 2026-10-05T21:14 2026-10-09T03:41 'end-morph|compositor-morph|cm-return|fix-cm|g0[.-]|P1b|PR-0(1[28]|2[3-9]|3[0-9]|40)|end of (the )?page|end-of-page|menu|v1[0-4]\b|int-v11|arch-end|join-fade|logo-close'`).
- Messages: 1,194 SendMessages to or from line agents in the window, 509 of them from the lead.
- Proposals: 17 of v1's 41 proposals are end-of-page, with 44 revisions in all; 2 rejected, 1 "changes requested"
  (`node -e 'const fs=require("fs");const P=fs.readdirSync(process.argv[1]).filter(f=>f.endsWith(".json")).map(f=>JSON.parse(fs.readFileSync(process.argv[1]+"/"+f)));const E=P.filter(p=>/end of (the )?page|end-of-page|menu|join waitlist|logo/i.test(p.title));console.log(P.length,E.length,E.reduce((s,p)=>s+(p.rev||1),0),E.map(p=>p.decision&&p.decision.value).join(" "))' $C/proposals`).
- Fix folders: 34 of v1's 150 (`ls -d $F/*/ | xargs -n1 basename | grep -cE '^(end-|cm-|compositor-morph|morph-|menu-layers|join|logo-close|g0-(revert|gpu|box)|v3w)'`).
- Device incidents reported by line owners during their phone blocks: I-214, I-215, I-216, I-217, I-222 (end-morph
  owners), I-244 (`arch-end-fresh`), I-254 (`fix-menu-layers`) (`$C/incidents.json`, `reportedBy`).

**Where time and tokens went** (INFERRED from the above):
1. **The target moved.** The user accepted a finger-following end three times (PR-018, PR-030, PR-040) and asked once
   to roll it back. Each change of target restarted a chain of builds that had been stacked on the previous one (v10 →
   v11 → v12 → v13 → v14 each carried the last; g0.0 had to split v14's hunks into "above the end" and "the end", with
   4 mappers). The rollback came after **small look regressions** the user found by hand (a 4 px row rise, corner
   movement), not after a performance failure: v14 had just passed its phone check.
2. **Device-only regressions found late.** v11-v13 each failed on the first menu open after load, a first-interaction
   layer build that Chrome and counts did not show; three consecutive phone blocks were needed to see it.
3. **Long-lived Opus contexts iterating.** The two largest owners ran 28 h and 35 h at about 255 k cache-read per
   request, with 13 and 12 compactions, iterating variants without a stop rule.
4. **Phone blocks with device trouble.** Long blocks (70+ min) lost their link mid-run (I-220: "fails at the 4th part
   start … about 70 min into the block"; I-222), see case D.

**What v2 would change.**
- *Helps a lot:* the rollback and the return are **preset changes** in v2 (`morph.*: faithful` vs the finger-following
  `proposal` variant, §6.2-6.3), not two revert agents plus four mappers splitting a stacked patch. Every candidate
  (v10-v14, g0.0x) becomes a flag vector over the same parts, so "v14 above the end + the original end" is a
  configuration, not a build job. The 200 k context cap and per-part time box (§8.2) would have stopped the 2,793-request
  owner long before its 13th compaction.
- *Helps somewhat:* v2's WebKit `LayerTree` census at held states (§4.2) can count layers created on the first open,
  the quantity that failed v11-v13; whether that count predicts the felt first-open frame is exactly the "first-interaction
  layer builds" limit the plan lists in §4.6 (count-based predictions missed in the same direction five times in v1).
- *Does not help:* this is **class X** (backdrop-filter, filter, first-interaction layer builds), so every candidate
  still needs the phone (§9.2). And no measurement design prevents the target from moving: the churn was a product
  decision (behaviour and look), taken after seeing builds. v2 can make that decision cheaper and earlier (see
  Improvements 6), not unnecessary.

---

## Case D. The iPhone link: USB, WDA and Wi-Fi (a tooling incident with a long tail)

**What happened.** From 10-01 the phone's USB link to the Mac dropped repeatedly (usbmux lost the device while the USB
device stayed present), and after each drop the automation helper (WDA), the web inspector proxy, the phone's lock
state, UI Automation permission, Wi-Fi or Xcode's device service needed attention. The cause of the drops was **never
found**: I-222's resolution says "Cause of the drops UNRESOLVED (usbmux link ends, USB device stays)" (QUOTED,
`$C/incidents.json`). v1 answered with detection and recovery tooling, a re-plug console step, and an LLM cron.

**Timeline** (MEASURED, `$C/incidents.json` and `$C/steps/`):

| When | Event |
|---|---|
| 10-01 16:36 | I-040: the phone drops off USB right after each finger test answer; Wi-Fi-only checked and rejected (usbmux and the proxy do not see the phone over Wi-Fi) |
| 10-01 17:34 | The user starts `/loop 5m check iphone connection` in the lead session |
| 10-04 → 10-06 | I-127, I-173 (link lost), I-212 (stale WDA session after reconnect), I-215 / I-217 (phone auto-locked during cooling waits), I-216, I-220 (WDA restart fails ~70 min into long blocks) |
| 10-06 13:36 | I-222: third drop that day; mid-block drops voided blocks |
| 10-06 14:55-18:54 | I-223 (phone on another USB port, 14:55-15:40); I-227 (UI Automation not authorized after a re-plug, 16:43-18:54), whose fix is the preflight with named trap codes |
| 10-07 04:55-06:09 | `ts-usb-link` builds `usblink.mjs` (status / watch / proxy; a re-plug console step after 60 s; LINK-LOST exit code so blocks resume instead of voiding) |
| 10-07 → 10-09 | I-235, I-239, I-242 (watch misses re-attach), I-244, I-251 (Xcode's device service stuck after a link loss; fixed by restarting it), I-252 (watch posts a re-plug step while the user is using the phone), I-254, I-260 (phone off the Mac's Wi-Fi), I-262 |
| 10-08 17:37 | Last cron fire (the recurring task stops after 7 days, INFERRED from the gap) |
| 10-09 15:08 → 10-10 02:49 | C-140 re-plug waits overnight and stalls case B's g0.0m |
| 10-12 → 10-13 | I-266, I-271: a Command Line Tools update and an unaccepted Xcode licence break the compiled usblink shim; tooling commits blocked until the user accepts the licence |

**Size of the tail** (MEASURED):
- **Incidents:** 36 of 276 match the link pattern (20 of class env), first 10-01 16:36, last 10-13 04:33
  (`node -e 'const d=require(process.argv[1]);const rx=/usb|wda|re-?plug|link lost|dropped off|not visible|not reachable|automation mode|usbmux|usblink|coredevice|another usb port|UI testing|ServerURLHere/i;const s=d.filter(i=>rx.test(i.title+" "+(i.error||"")));console.log(d.length,s.length,s.filter(i=>i.class==="env").length)' $C/incidents.json`).
- **User steps:** 52 of the console's 166 steps are link steps (re-plug, unlock, UI Automation, Wi-Fi, trust,
  device service), 31 %; 39 answered, 13 cancelled (posted, then the link came back). The answered median is
  **1.3 min**, but 3 answered waits exceed 30 min (C-071 158 min, C-091 376 min, C-140 701 min) and the answered total
  is 22.5 h (`node -e 'const fs=require("fs"),d=process.argv[1];const rx=/plug|cable|usb|unlock|ui automation|wi-fi|reconnect|trust the test helper|preparing the iphone|device service|not seen/i,ex=/thermal|heat|serious|licen/i;const all=fs.readdirSync(d).filter(f=>f.endsWith(".json")).map(f=>JSON.parse(fs.readFileSync(d+"/"+f)));const S=all.filter(s=>rx.test(s.title)&&!ex.test(s.title));const w=S.filter(s=>s.status==="answered").map(s=>(new Date(s.result.at)-new Date(s.createdAt))/6e4).sort((a,b)=>a-b);console.log(all.length,S.length,S.filter(s=>s.status==="cancelled").length,w[w.length>>1],w.filter(x=>x>30),w.reduce((a,b)=>a+b,0)/60)' $C/steps`).
  A further 33 steps asked the user to set or clear Xcode's thermal condition (same command with `ex` as the filter).
- **Toolsmiths:** 7 link toolsmiths, 621 requests, 117.5 M cache-read
  (`jq '[.[]|select(.name|IN("ts-i220","ts-i223","ts-i227","ts-usb-link","ts-usb-attach","ts-251","ts-252"))]|{n:length,turns:(map(.asst)|add),cacheRead:(map(.usage.cacheRead)|add)}' agents.json`).
- **The cron:** 1,889 fires of "check iphone connection", every 5 min from 10-01 17:39 to 10-08 17:37
  (`grep '"scheduled_task_fire"' $LEAD | jq -r '.prompt[0:40]' | sort | uniq -c | sort -rn`). Lead requests in the
  chains these fires woke: **4,381 requests, 1,056.9 M cache-read (18.0 % of the lead session's 5,862.7 M), 1.40 M
  output**, about 241 k cache-read per request (`node $H/trig.mjs $LEAD`). Each fire was one shell check plus a
  status line; five sampled fires show "still connected" or a WDA restart in progress, and two of them also carried
  unrelated lead work (a message to an owner, a commit check), so this attribution is an upper bound (INFERRED). The
  user's own Claude Code chat shows why it existed: 23 of the user's 229 typed messages are about the phone link
  (`jq -r .text human.jsonl | grep -ciE 'iphone|cable|plug|usb|wda'`).
- **Lead attention:** 2,235 lead requests across the session name link terms (574 M cache-read; overlaps the cron
  figure) (`node $H/win.mjs $LEAD 2026-09-30 2026-10-12 'usblink|re-?plug|usbmux|\bWDA\b|wda (ensure|start|stop|check)|iphone connection|I-2(15|16|17|20|22|23|27|35|39|42|44|51|52|60)|C-140'`).

**Knock-on cost in the other cases** (MEASURED above): case B lost 11 h 52 min (C-140) and 7 min (I-260); case C's
P-163 was paused after its get-ready step waited 1 h (T-228 #57); long end-of-page blocks were voided or resumed
after mid-block drops (I-220, I-222).

**What v2 would change.**
- *Helps by exposure:* the counts lane takes the phone out of the inner loop (§4.1), so fewer device sessions means
  fewer drops to recover from. The plan's targets (≤ 10 phone sessions before the first licensed class, device-driver
  incidents ≤ 10 % of incidents, G2) imply that.
- *Does not help:* every calibration session, class X and class P change, and spot-check still runs on the same phone,
  cable and Mac (§4.6). Nothing in the plan addresses the link itself: the device lane is "iPhone Safari blocks as
  console steps for you" (§4.1), §11 has no device-link risk, and Appendix B has no spike for it. The recurring-check
  cost is covered in principle by §8.4 lever 1 ("recurring checks as `pnpm fw status` scripts"), but the plan never
  names device health.

---

## Cross-case patterns

1. **Phone blocks are a wall-clock problem, not a token problem** (MEASURED): a block costs the owner about 24
   requests (A: 6.4 M cache-read; B: 9.9 M). Tokens go to investigation in long contexts (A: 393 requests before the
   phone; C: 2.78 B). Waiting is free for the owner (B: 1 request in 11 h 26 min) apart from the cache rebuild after.
2. **The lead was the reviewer** in A and B: every D, F and V signature and the gate-class rulings came from the lead,
   at about 233 k cache-read per request (`jq '.[]|select(.who=="lead:391f6dee")|.usage.cacheRead/.asst' agents.json`).
   The rulings were good (B's "not less-work"), but they are rule applications a script can make.
3. **Messages crossing hand-backs.** A named worktree subagent ends its turn at each hand-back, and the lead's next
   message resumes it, so instructions cross reports: 39 lead messages say "crossed", 55 nag an owner about its
   status row, and 1,334 of the lead's 4,761 SendMessages follow another to the same recipient within 3 min
   (`node -e 'const S=require("fs").readFileSync("sendmessage.jsonl","utf8").split("\n").filter(Boolean).map(JSON.parse).filter(r=>/^lead/.test(r.who));const c=rx=>S.filter(r=>rx.test(r.msg)).length;const by={};S.sort((a,b)=>a.ts<b.ts?-1:1).forEach(r=>(by[r.to]??=[]).push(r));let n=0;for(const k in by)for(let i=1;i<by[k].length;i++)if(new Date(by[k][i].ts)-new Date(by[k][i-1].ts)<18e4)n++;console.log(S.length,c(/crossed/i),c(/status row (still )?says|your status row/i),n)'`).
   A (21:28, three "start F" messages) and B (P-174 signed three times) both show it.
4. **The user decides fast; the user's hands are slow.** PR-041 was accepted in 13 min and PR-040 overnight; link
   steps were answered in a median 1.3 min, but three waits exceeded 2.5 h. The console carried most of the
   conversation: 989 user messages in console threads against 229 typed in chat
   (`node -e 'const fs=require("fs"),d=process.argv[1];let u=0;for(const f of fs.readdirSync(d).filter(f=>f.endsWith(".json")))for(const m of JSON.parse(fs.readFileSync(d+"/"+f)).messages)if(m.by==="user")u++;console.log(u)' $C/threads`).
5. **Late look regressions drove the biggest churn.** C's rollback followed a 4 px row rise and corner movement found
   by hand on a build that had just passed its phone check; B's g0.0m needed a third revision for accessibility and
   focus parity. Both are parity failures, not speed failures.

## Improvements for v2

Each item cites its evidence above and names the PLAN.md section it changes.

1. **Device health is a script with one console status, never a lead cron.** Evidence: 1,889 fires; 4,381 lead
   requests; 1,056.9 M cache-read, 18 % of the lead session (case D). Change: console-api runs a device watcher
   (usbmux, WDA, proxy, lock state, Wi-Fi) and exposes one status plus at most one open re-plug step (v1 posted 13
   that it later cancelled). The lead's `CLAUDE.md` forbids `/loop` checks; `session-brief` shows device state.
   **§8.4 lever 1, §8.3 hooks, §3.1 console-api, §4.1 device lane.**
2. **Device sessions are scheduled with the user, and start with one bundled get-ready step.** Evidence: 52 of 166
   steps (31 %) were link steps; C-140 waited 11 h 41 min and stalled g0.0m; C-071 (Auto-Lock), C-088 (UI Automation),
   C-138 (Wi-Fi) and C-139 (Do Not Disturb) were each posted reactively. Change: the device lane accepts runs only
   inside a session window the user opens in the console; the first step is one checklist (cable on the usual port,
   unlocked, Auto-Lock Never, UI Automation on, same Wi-Fi, Do Not Disturb, thermal state), then the queued blocks run
   back to back. Owners hand off and stop; nobody waits on a hold. **§4.1, §9.2 device stage, §10.2, Q7.**
3. **Add the device link as a named risk and a Day-1 spike.** Evidence: 36 link incidents over 12 days, never
   root-caused; a toolchain update broke the compiled link shim (I-266, I-271). Change: R17 "device link instability"
   with mitigations (log every attach and detach from Day 1, a cable and port swap test, no compiled native shims or a
   pinned toolchain); SPK-n "one-hour idle link soak with the logger". **§11, Appendix B.**
4. **Add a Simulator finger-drag counts profile to the WebKit counts lane.** Evidence: case A's decisive numbers were
   Simulator WDA drag counts (layouts ≥ 5 ms 138-144 → 36-49), which matched the phone's sign (152-159 → 0-1); the
   mechanism only exists while the scroll view is dragging, which scroll steps do not reproduce. Change: a
   `wda-drag` profile in the WebKit counts lane with count types classed *stable* (not deterministic) and a stated
   tolerance; §4.6 "finger-only effects" moves from device-only to "Simulator drag counts for mechanism, device for
   feel". **§4.2, §4.6.**
5. **Bring the WKTR spike forward, or narrow the class-W bar.** Evidence: the cleanest less-work landings of v1's last
   phase were CSS diffs (g0.0i "WebKit-only CSS", g0.0j "CSS only", `$F/BEST_BUILDS.md`), and §4.2/Q10 bar class W for
   any selector, class or custom-property change until WKTR exists (M3). Change: run the WKTR spike in M1, or allow W
   when the diff is scoped to one part's own selectors and the part's element count bounds the restyle (INFERRED; to be
   checked by the spike). **§4.2, Q10, §9.2, §10.1.**
6. **For an experiment part whose behaviour is in question, decide the behaviour (class P) before optimizing.**
   Evidence: case C: finger-following accepted three times and rolled back once; 37 agents, 2.78 B cache-read, 34 fix
   folders; the rollback followed small look regressions on a build that had passed its phone check. Change: the M5
   end-of-page experiment starts with a Try-it decision between the `faithful` 680 ms tween and the finger-following
   `proposal` variant, with both shown against the `original` preset; only the chosen variant is optimized; reversing
   the choice later is a preset change, and the question card records it. **§10.1 M5, §9.2 question stage, §6.2.**
7. **Give experiment owners a time box and an iteration cap, not only part-builders.** Evidence:
   `arch-compositor-morph` 2,793 requests, 13 compactions and 13 diff variants in 28 h at 257 k per request;
   `fix-g0-box` 2,317 requests. Change: an `exp-*` owner gets 1 agent-day or 3 build iterations per question, then
   must stop, write the measured deltas in the card and pass the review stage before another iteration. **§8.2 roster
   (experiment-owner row), §9.2.**
8. **Add accessibility and focus parity to the parity gate.** Evidence: g0.0m needed rev 3 to match g0.0l's
   accessibility tree and focus order (6 hidden profile tabs stay focusable). Change: a PL2b check at each stop:
   accessibility-tree snapshot and tab order equal to the original's, also when a part hides content by opacity.
   **§6.6.**
9. **Decide the screen-capture policy on Day 1.** Evidence: case B's cause-finding was paused by the no-frames rule,
   then the rule was widened in three separate chat instructions and a guard commit during work. Change: a default in
   §12.2: Simulator frames are always allowed; phone-screen frames are allowed for named recording sets made with Do
   Not Disturb on, stored only in the local artifact store; the guard enforces the set names. **§12.2, §7.3.**
10. **Make the screen's gate-class decision a tested function, with v1 cases as golden fixtures.** Evidence: B's
    "not less-work" ruling (paint moved 1-3 frames earlier, total equal, +22 MB) and A's less-work landing were lead
    judgments at ~233 k cache-read per request. Change: add both as `fwcore screen` golden tests (A: dominates on layout
    per frame; B: not dominating, paint shifted), so the reviewer checks the card and not the rule. **§4.3, §5.4,
    §9.2.**
11. **Owner state comes from the event log, and a lead message waits for an acknowledgement.** Evidence: 39 "crossed"
    messages, 55 status-row nags, 1,334 back-to-back lead sends within 3 min (28 %). Change: `fw` stage commands
    (card, gates, device queued, done) emit events to console-api, and the lead reads the projection instead of
    nagging; a named worktree subagent's hand-back carries `waiting-for: lead|device|user`, and the lead sends one
    message per hand-back. **§2.2 ("status as a projection"), §3.2, §8.1.**
12. **Keep the 5-minute cache TTL for owners who wait on the device.** Evidence: the reveal-paint owner made 1 request
    in an 11 h 26 min wait, then rebuilt its cache (0.9 M cache write); a 1 h TTL would not span that wait and costs 2×
    on writes. Change: §8.4 lever 3 adds "owners blocked on the device stay at 5 m"; the meter decides only for
    teammates idle 5-60 min. **§8.4.**

## Appendix: helper scripts

`win.mjs`: usage of one transcript in a time window, optionally only requests whose content matches a regex.
Compactions and tool errors are counted for the whole window, whatever the regex.

```js
// node win.mjs <file.jsonl> <t0> <t1> [regex]
import fs from 'fs'; import readline from 'readline';
const [f,t0,t1,rx]=process.argv.slice(2); const re=rx?new RegExp(rx,'i'):null;
const seen=new Set(); const u={turns:0,input:0,output:0,cacheRead:0,cacheWrite:0,compactions:0,toolErr:0,bashCalls:0,sendMsg:0};
for await (const line of readline.createInterface({input:fs.createReadStream(f),crlfDelay:Infinity})){ let r; try{r=JSON.parse(line)}catch{continue}
  const ts=r.timestamp; if(!ts||ts<t0||ts>t1) continue;
  if(r.type==='system'&&r.subtype==='compact_boundary') u.compactions++;
  if(r.type==='user'&&Array.isArray(r.message?.content)) for(const b of r.message.content) if(b.type==='tool_result'&&b.is_error) u.toolErr++;
  if(r.type!=='assistant') continue; const m=r.message||{};
  if(re && !re.test(JSON.stringify(m.content||''))) continue;
  for(const b of m.content||[]) if(b.type==='tool_use'){ if(b.name==='Bash')u.bashCalls++; if(b.name==='SendMessage')u.sendMsg++; }
  const key=r.requestId||m.id; if(seen.has(key)) continue; seen.add(key); u.turns++;
  const x=m.usage||{}; u.input+=x.input_tokens||0; u.output+=x.output_tokens||0; u.cacheRead+=x.cache_read_input_tokens||0; u.cacheWrite+=x.cache_creation_input_tokens||0; }
console.log(JSON.stringify(u));
```

`trig.mjs`: attributes each lead request to the input that last woke the lead (a cron fire, a human message, a
teammate message, a background-task notification). Tool results do not change the trigger. Work done on messages that
arrive mid-chain is attributed to the chain's trigger, so per-trigger figures are upper bounds.

```js
// node trig.mjs <lead.jsonl>
import fs from 'fs'; import readline from 'readline';
const seen=new Set(); const agg={}; let trig='start';
for await (const line of readline.createInterface({input:fs.createReadStream(process.argv[2]),crlfDelay:Infinity})){ let r; try{r=JSON.parse(line)}catch{continue}
  if(r.type==='system'&&r.subtype==='scheduled_task_fire'){ trig='cron:'+(r.prompt||'').slice(0,24); continue; }
  if(r.type==='user'){ const c=r.message?.content; if(Array.isArray(c)&&c.some(b=>b.type==='tool_result')) continue;
    if(r.isMeta && r.origin?.kind!=='peer') continue;
    const k=r.origin?.kind||'none'; const t=typeof c==='string'?c:(Array.isArray(c)?c.map(b=>b.text||'').join(''):'');
    trig = k==='none'&&/^<command-/.test(t) ? 'command' : 'user:'+k; continue; }
  if(r.type!=='assistant') continue; const key=r.requestId||r.uuid; if(seen.has(key)) continue; seen.add(key);
  const u=r.message?.usage||{}; const a=agg[trig]??={turns:0,out:0,cacheRead:0,cacheWrite:0};
  a.turns++; a.out+=u.output_tokens||0; a.cacheRead+=u.cache_read_input_tokens||0; a.cacheWrite+=u.cache_creation_input_tokens||0; }
for (const [k,v] of Object.entries(agg).sort((a,b)=>b[1].cacheRead-a[1].cacheRead)) console.log(k.padEnd(36), v.turns, v.out, (v.cacheRead/1e6).toFixed(1)+'M');
```
