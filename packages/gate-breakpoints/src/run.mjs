// The runner: loads both arms for every probe and sweep, in one engine, and writes the RAW facts as JSON.
// Output is deterministic by construction: no timestamps, no durations, canonical order, nothing from the machine
// except the browser's own version string. Progress goes to stderr only.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { LAUNCHERS } from './engines.mjs';
import { attachAlignFacts, collectAlignFacts } from './align-equiv.mjs';
import { SCAN_EXTRA, SCAN_GAP_MS, unionDeclared } from './declared.mjs';
import { KIT_SRC, PIN_SRC, bringInPage, collectInPage, freezeInPage, prepareInPage, scrollTopInPage, settleInPage, waitReady, waitResize } from './page.mjs';
import { HOLD_LOAD_MS, MAIN_OFF_MS, ORIG_GRACE_MS, POST_RESIZE_MS, READY_TO_MS, SLOT_MS, STEP_MS, checkAt, instant, lateWait, mountRank, newRec, observeAt, ovRank, stopBase, viewRank } from './freeze.mjs';
import { GATE_POLICY, commitHolds, commitNeeded, commitOutcome, crosses, fold, idlePolicy, nudge, view, viewFor, waitTrace } from './settle.mjs';
import { snapshotRoot, siteDist, startServer, rewriteFor, PKG } from './serve.mjs';
import { makeViewBarrier, skippedParts, viewStage } from './view.mjs';
import { DIAG_INIT, diagSnap } from './diag-cv.mjs';
import { loadAnchors, loadGen, probeEnv, scopeFor, selectParts, sweepDefs } from './spec.mjs';

const collectWith = async (s, arg) => { const raw = await s.evaluate(collectInPage, arg); if (arg.props) attachAlignFacts(raw, await s.evaluate(collectAlignFacts, { parts: arg.parts, props: arg.props })); return raw; };
const log = (...a) => process.stderr.write(a.join(' ') + '\n');
// Lean Fw.Gate.Settle.viewCell in the probes, per engine (Lean Fw.Gate.Settle.viewFor, src/settle.mjs viewFor): ON for Chromium, OFF for
// WebKit. Chromium needs it: its getComputedStyle reads stale used auto margins in a skipped content-visibility subtree (run
// 39101532038: commission margin-inline 869.5 against 869 at one probe). WebKit breaks with it: scrolling flips the commission
// scene's content-visibility and --commission-shrink in one arm (run 39105279831: 11 probes). FW_GATE_VIEW=1 forces it on both
// engines, =0 off (debug switches, never a result). The bring scroll puts the part's first root at the viewport top in both arms.
const VIEW_ENV = process.env.FW_GATE_VIEW;
// The frozen clock (gate-shard-balance round 2, Lean Fw.Gate.Freeze, src/freeze.mjs): the page clock is frozen before load and moved
// only by the harness, animations are frozen before each observation. On for the gate; off for the gaps lane (its own native
// timing) and with FW_GATE_FROZEN=0 (a debug switch, never a result).
const FROZEN_ON = process.env.FW_GATE_FROZEN !== '0';
/** The kinds of anchors.json `prepare` step that page.mjs prepareInPage runs. */
export const PREPARE_KINDS = ['mount', 'overlay'];
const SITES = ['orig', 'rewrite'];
const FILTER = { orig: '\\.svelte-', rewrite: '-module_' };
const CAP_MS = { orig: 20000, rewrite: 15000 };
async function pool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  }));
  return results;
}

async function withRetry(label, fn, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); } catch (e) { last = e; log(`  retry ${label} (${i + 1}/${tries}): ${String(e.message).split('\n')[0]}`); }
  }
  throw last;
}

/** The engine port each launcher drives (Lean `Fw.Gate.Port`, wire names): the verdict rule needs it to name unreachable cells.
 *  Playwright WebKit is the Apple port on macOS and the GLib port (WebKitGTK/WPE) on Linux. */
export const portOf = (engineName, platform = process.platform) =>
  (engineName === 'chromium' ? 'chromium' : platform === 'darwin' ? 'webkit-apple' : 'webkit-glib');

/**
 * `gaps` (optional, used only by the gaps lane, src/gaps/): { launcher, mapProbe, collect, collectArg } replaces the engine
 * launcher, maps each matrix probe to the environment the lane builds (Lean's environment plus the mechanism fields, for
 * example a browser zoom), and adds one extra in-page report under `raw.gap`. The record keeps Lean's environment as `env`
 * (what the verdict rule is asked about) and the mapped one as `realized`. Null (the default) adds no `realized` and no `raw.gap`.
 */
export async function runEngine({ engineName, outDir, concurrency = 4, probeFilter = null, sweepFilter = null, partFilter = null, gaps = null }) {
  const DIAG_CV = process.env.FW_GATE_DIAG_CV === '1' || (Array.isArray(partFilter) && partFilter.join() === 'commission' && process.env.FW_GATE_DIAG_CV !== '0'); // TEMPORARY
  const { gen, sha256: genSha } = loadGen();
  const anchors = loadAnchors();
  // Part selection (glue): only the chosen parts' elements are collected, so only their raw facts and property lists are
  // written. The header names the parts when some are skipped; a default run writes the same bytes as before the flag.
  const sel = selectParts(Object.keys(anchors.parts), partFilter);
  // Probe scope (glue): a narrowed run loads only the union of its parts' Lean scopes (src/scope.gen.json,
  // Fw.Gate.scope_sound); --probes/--sweeps narrow further. The header lists the scope so merge-gate knows what to expect.
  const scope = scopeFor(sel, gen);
  const activeParts = Object.fromEntries(sel.covered.map((pid) => [pid, anchors.parts[pid]]));
  const lock = JSON.parse(readFileSync(resolve(PKG, '../../snapshot.lock.json'), 'utf8'));
  const dist = siteDist();
  const buildInfo = JSON.parse(readFileSync(join(dist, 'build-info.json'), 'utf8'));
  const variantPage = rewriteFor(dist); // FW_SEARCH: a flagged config of the rewrite (default: none)
  const frozen = FROZEN_ON && !gaps;
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(dist, variantPage.rewrite) };
  const engine = await (gaps ? gaps.launcher : LAUNCHERS[engineName])();
  const VIEW_ON = !gaps && viewFor(VIEW_ENV, engineName);
  const cond = gen.conditions.map((c) => ({ tsId: c.tsId, css: c.css, legacyCss: c.legacyCss }));
  const neutral = gen.neutral.map((n) => ({ tsId: n.tsId, css: n.css }));
  const partsArg = Object.fromEntries(['orig', 'rewrite'].map((site) => [site, Object.fromEntries(
    Object.entries(activeParts).map(([pid, p]) => {
      // a box is collected only where it is compared or used as a reference: the original's headline is animated text
      const needed = new Set(p.roles.flatMap((r) => (r.dims.length > 0 ? [r.role, ...(r.boxRel ? [r.boxRel.role] : [])] : [])));
      // a variant role (Lean Fw.Gate.VariantRole) is read on the rewrite arm only and only for its count
      const variantRoles = site === 'rewrite' ? (p.variantRoles ?? []).map((v) => ({ role: v.role, selector: v.rewrite, rect: false, inline: [] })) : [];
      return [pid, [...p.roles.map((r) => ({ role: r.role, selector: r[site], rect: needed.has(r.role), inline: site === 'orig' ? (r.skipIfInline ?? []) : [] })), ...variantRoles]];
    }))]));

  async function load(env, site) {
    return engine.open(env, { origin: servers[site].origin, path: site === 'rewrite' ? '/' + variantPage.search : '/', init: frozen ? PIN_SRC + '\n' + KIT_SRC : PIN_SRC, frozen });
  }
  // anchors.json `prepare` (per part and arm) is the one route for page states that exist only after an action, all run by
  // page.mjs prepareInPage. A part with a prepare step is collected AFTER the rest, so every other part is read in the state a
  // fresh load has (mounting the morph panel scrolls the original there and back, and its scroll-driven values lag): early
  // parts first, then overlay parts one at a time (open, collect, close), then the mount parts once the mounts have run.
  //  kind "mount" (morph.countdown, morph.columns, morph.panel): scroll near `scrollNear`, wait for `waitFor`, back to the top.
  //  kind "overlay" (overlays.*): click `trigger`, wait for `ready`; click `close`, wait until `gone` is gone.
  // A prepare step of an unknown kind would be skipped silently, and its part would then be compared on a page that never
  // reached the state (run 39114796757: morph.columns and morph.countdown read 0 original nodes): refuse it.
  for (const [pid, p] of Object.entries(activeParts)) for (const site of SITES) for (const st of (p.prepare && p.prepare[site]) || []) {
    if (!PREPARE_KINDS.includes(st.kind)) throw new Error(`anchors.json ${pid}.prepare.${site}: unknown kind ${JSON.stringify(st.kind)} (expected one of ${PREPARE_KINDS.join(', ')})`);
  }
  const stepsOf = (site, kind) => Object.fromEntries(Object.entries(activeParts)
    .map(([pid, p]) => [pid, ((p.prepare && p.prepare[site]) || []).filter((st) => st.kind === kind)])
    .filter(([, steps]) => steps.length > 0));
  const mountOf = Object.fromEntries(SITES.map((site) => [site, stepsOf(site, 'mount')]));
  const overlayOf = Object.fromEntries(SITES.map((site) => [site, stepsOf(site, 'overlay')]));
  // The ready wait ends with a hold to READY_TO_MS in both arms; the clock read there is checked (a miss is recorded in `rec`).
  const evalReady = async (s, site, rec) => {
    const r = await s.evaluate(waitReady, { site, capMs: CAP_MS[site], ...(frozen ? { holdMs: HOLD_LOAD_MS, readyToMs: READY_TO_MS, graceMs: site === 'orig' ? ORIG_GRACE_MS : 0 } : {}) });
    if (frozen) checkAt(rec, 'ready', READY_TO_MS, s.clockMs());
    return r;
  };
  // The instants (Lean Fw.Gate.Freeze.instant, stopBase, both_arms_same_instant): every observation of a stop is read at an absolute
  // fake time that depends on the stop index and the reading's rank alone, never on what the arm did before (the original runs a
  // mount stage the rewrite does not; an overlay arm opens and closes a dialog). The parts that need work in one arm are the union
  // over both arms, so an arm without that work still holds to the same instant and reads there.
  const unionIds = (of) => Object.keys(activeParts).filter((pid) => SITES.some((site) => of[site][pid]));
  const ovIds = unionIds(overlayOf);
  const mtIds = unionIds(mountOf);
  for (const pid of mtIds) if (ovIds.includes(pid)) throw new Error(`anchors.json ${pid}: a part cannot have both a mount and an overlay prepare step (each has its own observation instant)`);
  const plainIds = Object.keys(activeParts).filter((pid) => !ovIds.includes(pid) && !mtIds.includes(pid));
  const readingCount = (view) => ovIds.length + (view ? plainIds.length : 0);
  // The frozen clock before a live resize: hold to the stop base, resize, four frames, hold to base + POST_RESIZE_MS.
  const resizeTo = async (s, next, i, view, rec) => {
    if (!frozen) { await s.resize(next); await s.evaluate(waitResize); return; }
    const base = stopBase(i, readingCount(view));
    await s.holdTo(base);
    checkAt(rec, `stop ${i}`, base, s.clockMs());
    await s.resize(next);
    await s.evaluate(waitResize, { holdTo: base + POST_RESIZE_MS });
    checkAt(rec, `resize ${i}`, base + POST_RESIZE_MS, s.clockMs());
  };
  // Lean Fw.Gate.Settle.committed / nudge: a used auto margin in a content-visibility:auto skipped subtree reads 0px after a fresh load
  // until a committed layout pass includes the box (research/notes/2026/10-20-commission-margin-recur.md). A fresh load that is read
  // without a view bring is therefore opened one CSS pixel wider and resized to the read width first, as every later stop of a sweep
  // is; a read with no resize behind it has an `unsettled` wait (Lean commitOutcome), never a pass or a fail. The nudge must not cross
  // a breakpoint edge (Lean crosses_iff): the page would then load in another regime than the one it is read in.
  const EDGE_PAIRS = [...gen.edgePairs.width, ...gen.edgePairs.deviceWidth, ...gen.edgePairs.touchRm];
  const nudgeEnv = (env) => {
    if (crosses(EDGE_PAIRS, env.width) || (env.deviceWidth === env.width ? false : crosses(EDGE_PAIRS, env.deviceWidth))) {
      throw new Error(`the nudge from width ${env.width} (device ${env.deviceWidth}) crosses a breakpoint edge`);
    }
    return { ...env, width: nudge(env.width), deviceWidth: env.deviceWidth === env.width ? nudge(env.deviceWidth) : env.deviceWidth };
  };
  const COMMIT_ON = !gaps && commitNeeded(VIEW_ENV, engineName);
  const afterCommit = (settleWait, viewed, resizes) => ({ ...settleWait, outcome: commitOutcome(commitHolds(COMMIT_ON, viewed, resizes), settleWait.outcome) });
  // The settle wait (Lean Fw.Gate.Settle, settle.mjs): before anything is collected, in both arms and both engines, the pointer is
  // parked where it is over no probed element (hover cannot move a probed value), then the page is observed on real frames
  // until nothing animates, two frames have passed since the resize, the probed values stay within eps for three frames, and the
  // pointer is outside every probed element; or the budget is spent (outcome 'unsettled', recorded, never a silent pass).
  const rootsOf = (site) => Object.values(partsArg[site]).flatMap((roles) => roles.map((r) => r.selector));
  // The sample's wait is the first wait plus the waits for the overlays opened during collection, the parts brought into view
  // and the mount stage's idle wait: unsettled when any is (Lean Fw.Gate.Settle.fold).
  const foldSettle = (first, extra) => (extra || []).reduce((a, w) => ({
    ...a, outcome: fold(a.outcome, [w.outcome]),
    observations: a.observations + w.observations, waitedMs: a.waitedMs + w.waitedMs, parked: a.parked && w.parked,
  }), first);
  // The mount stage's idle wait (page.mjs prepareInPage 'ready'): Lean's `wait` under idlePolicy (nothing runs, the arm's cap,
  // the frame budget) decides its outcome from the trace; it is folded into the sample like an overlay's settle.
  const idleWait = (trace, site, env) => {
    const last = trace[trace.length - 1];
    const outcome = waitTrace(idlePolicy(GATE_POLICY, CAP_MS[site]), trace);
    log(`  idle ${engineName} ${site} ${env.width}x${env.height}: ${last.t} ms, ${last.frames} frames, ${outcome}`);
    return { outcome, parked: true, observations: trace.length, frames: last.frames, waitedMs: last.t, running: last.running, stable: 0, hoverInside: false, idle: true };
  };
  // The pointer is parked outside the viewport (-1, -1): no element is under it, so a resize can bring no element under it and
  // a hover rule or a pointerenter handler never runs. (A point inside the viewport can lie over a hover target at some widths:
  // hero.orbit z-index = 1 + the pointerenter events, run 39078493093 with the pointer at the corner.)
  const park = async (s, env) => { if (env.hover === 'hover' && s.mouse) { await s.mouse(-1, -1); return true; } return false; };
  const parkEarly = park;
  async function settleArm(s, site, env, only) {
    const roots = only || rootsOf(site);
    const parked = await park(s, env);
    const { trace } = await s.evaluate(settleInPage, { policy: GATE_POLICY, roots, hoverCapable: env.hover === 'hover' });
    const last = trace[trace.length - 1];
    const outcome = waitTrace(GATE_POLICY, trace);
    // stderr only (the output JSON carries the same numbers in settleWait): per-stop settle time, for gate-speed's before/after
    log(`  settle ${engineName} ${site} ${env.width}x${env.height}${only ? ' (overlay)' : ''}: ${last.t} ms, ${last.frames} frames, ${outcome}`);
    return {
      outcome, parked, hoverCapable: env.hover === 'hover',
      observations: trace.length, frames: last.frames, waitedMs: last.t, running: last.running, stable: last.stable, hoverInside: last.hoverInside,
    };
  }
  const collectArg = (site, env, props, parts, view = false) => ({
    site, conditions: cond, neutral, dprWanted: env.dpr, widthWanted: env.width, parts, props, flagSkipped: view, filter: FILTER[site],
  });
  // `ctx` = { base, rec } (frozen only): the stop base and the sample's record of readings that missed their instant. Order of the
  // readings and their ranks (Lean Fw.Gate.Freeze): the main parts 0, overlay j = 1 + j, the mount parts together = nOverlay + 1, a
  // part brought into view = nOverlay + 2 + its index among the plain parts.
  async function evalCollect(s, site, env, props, settleRoots, view = false, ctx = null, viewSync = null, page = null) {
    const at = (rank, label) => (ctx ? observeAt(s, instant(ctx.base, rank), freezeInPage, ctx.rec, label) : true);
    const pick = (ids) => Object.fromEntries(Object.entries(partsArg[site]).filter(([pid]) => ids.includes(pid)));
    const withMain = page !== 'mounted';
    const withMount = page !== 'plain';
    if (withMain) await at(0, 'main');
    const raw = await collectWith(s, collectArg(site, env, props, pick(withMain ? plainIds : []), view));
    for (const [j, pid] of (withMain ? ovIds : []).entries()) {
      const steps = overlayOf[site][pid] || [];
      if (steps.length > 0) {
        await s.evaluate(prepareInPage, { stage: 'open', steps, capMs: CAP_MS[site] });
        // an opened overlay animates in (WebKit run 39067170911 read the signup dialog at scale 0.9977): settle it before reading
        if (settleRoots) (raw.overlaySettle ||= []).push(await settleRoots(partsArg[site][pid].map((r) => r.selector), env));
      }
      await at(ovRank(j), `overlay ${pid}`);
      const one = await collectWith(s, collectArg(site, env, props, { [pid]: partsArg[site][pid] }, view));
      raw.parts = { ...raw.parts, ...one.parts };
      if (steps.length > 0) await s.evaluate(prepareInPage, { stage: 'close', steps, capMs: CAP_MS[site] });
    }
    if (mtIds.length > 0 && withMount) {
      if (Object.keys(mountOf[site]).length > 0) {
        const ready = await s.evaluate(prepareInPage, { stage: 'ready', steps: Object.values(mountOf[site]).flat(), capMs: CAP_MS[site], maxFrames: GATE_POLICY.maxFrames });
        raw.prepared = ready.found;
        log(`  mount ${engineName} ${site} ${env.width}x${env.height}: found ${JSON.stringify(ready.found)}`);
        if (settleRoots) (raw.overlaySettle ||= []).push(idleWait(ready.idle, site, env));
      }
      await at(mountRank(ovIds.length), 'mount');
      const late = await collectWith(s, collectArg(site, env, props, pick(mtIds), view));
      raw.parts = { ...raw.parts, ...late.parts };
    }
    if (props && view) await bringSkipped(s, site, env, props, raw, settleRoots, at, viewSync);
    const miss = ctx && lateWait(ctx.rec);
    if (miss) {
      (raw.overlaySettle ||= []).push(miss);
      raw.late = ctx.rec.misses;
      log(`  LATE ${engineName} ${site} ${env.width}x${env.height}: ${JSON.stringify(ctx.rec.misses)}`);
    }
    return raw;
  }
  // Lean Fw.Gate.Settle.view, src/view.mjs. A part with a node read in a skipped content-visibility subtree (page.mjs collectInPage flags
  // it) is brought into view, settled and read again; the second reading is the one kept (`view true first again`, node by node), the
  // first is recorded under raw.viewFirst. The parts brought are the UNION over both arms (`viewSync` posts this arm's skipped parts
  // and returns the union once both arms have posted), so both arms bring, settle and read the same parts at the same view instants.
  // A node still skipped carries the flag again and summary.mjs maskNotRendered gives it no verdict (cell notRendered). A part
  // without a skipped node in either arm is left exactly as read. The page is scrolled back to the top.
  async function bringSkipped(s, site, env, props, raw, settleRoots, at, viewSync) {
    const mine = skippedParts(raw.parts, plainIds);
    const ids = viewSync ? await viewSync(mine) : mine;
    await viewStage({
      roots: (pid) => partsArg[site][pid].map((r) => r.selector),
      bring: (roots) => s.evaluate(bringInPage, { roots }),
      settle: (roots) => (settleRoots ? settleRoots(roots, env) : null),
      at: (pid) => at(viewRank(ovIds.length, plainIds.indexOf(pid)), `view ${pid}`),
      again: (pid) => collectWith(s, collectArg(site, env, props, { [pid]: partsArg[site][pid] }, true)).then((r) => r.parts),
      keep: view,
      log: (pid, bt, still) => log(`  view ${engineName} ${site} ${env.width}x${env.height} ${pid}: ${bt.skippedBefore} skipped, ${still} still skipped`),
    }, raw, ids);
    if (ids.length > 0) await s.evaluate(scrollTopInPage);
  }

  // Phase 0: the property lists. Declared names depend on the stylesheets and the elements, not on the environment,
  // so one reference load per arm fixes them (the engine expands shorthands, so they are per engine). A timer-driven part
  // matches different rules at different instants, so the names are the union of several scans across one timer period
  // (declared.mjs): otherwise two shards could fix different lists and merge-gate would refuse their headers.
  const refEnv = { width: 1440, height: 900, deviceWidth: 1440, deviceHeight: 900, dpr: 1, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
  const declared = {};
  let loadedConfig = null;
  const variants = {};
  for (const site of SITES) {
    const s = await load(refEnv, site);
    await parkEarly(s, refEnv); // the declared lists are read with the pointer parked, as every sample is (nav.hitTest header flake)
    const rec0 = newRec();
    await evalReady(s, site, rec0);
    // The declared lists are read from a settled page (Lean Fw.Gate.Settle), as every sample is: a rule that matches only while an
    // entry animation or a pointer/focus state runs (WebKit run 39077507337: the original nav `opacity` listed in 3 of 4 jobs) must
    // not decide the list. The union over the timer period still covers a state that never settles. An unsettled wait is logged,
    // and the scans go on (the list is a union, so it only gains names).
    await settleArm(s, site, refEnv);
    const scans = [(await evalCollect(s, site, refEnv, null, null, false, frozen ? { base: stopBase(0, 0), rec: rec0 } : null)).parts];
    const timed = Object.fromEntries(Object.entries(partsArg[site]).filter(([pid]) => !overlayOf[site][pid]));
    for (let i = 0; i < SCAN_EXTRA; i++) {
      if (frozen) await s.advance(SCAN_GAP_MS); else await new Promise((r) => setTimeout(r, SCAN_GAP_MS));
      scans.push((await collectWith(s, collectArg(site, refEnv, null, timed))).parts);
    }
    declared[site] = unionDeclared(scans);
    if (site === 'rewrite') {
      // Regression check of incident inc-variant-gate-flags-off: the page the browser actually loaded must be the config the
      // flags name (the page's own data-fw-config), never silently the default one.
      loadedConfig = await s.evaluate(() => document.getElementById('root')?.dataset.fwConfig ?? null);
      const want = variantPage.hash ?? buildInfo.configHash;
      if (loadedConfig !== want) throw new Error(`rewrite arm loaded config ${loadedConfig}, expected ${want} for flags "${variantPage.search}"`);
      // the variant each part with variant roles rendered, read from the page's own data-fw-variant on the part root
      for (const [pid, p] of Object.entries(activeParts)) {
        if (!(p.variantRoles ?? []).length) continue;
        variants[pid] = await s.evaluate((fw) => document.querySelector(`[data-fw="${fw}"]`)?.getAttribute('data-fw-variant') ?? null, p.anchors[0]);
      }
    }
    await s.close();
  }
  const props = {};
  for (const [pid, p] of Object.entries(activeParts)) {
    props[pid] = {};
    for (const r of p.roles) {
      const rw = declared.rewrite[pid][r.role].declared;
      const or = declared.orig[pid][r.role].declared;
      props[pid][r.role] = { restated: rw, originOnly: or.filter((x) => !rw.includes(x)) };
    }
  }
  const collectProps = Object.fromEntries(Object.entries(props).map(([pid, roles]) => [pid, Object.fromEntries(
    Object.entries(roles).map(([role, v]) => [role, [...v.restated, ...v.originOnly]]))]));

  // `viewSync` (only a pair sample, samplePair) makes the view set the union over both arms; the pair retries as one, an arm never alone.
  // `nudged` (a read without the view bring, Lean committed): the load is one pixel wider and resized to `env` before the read.
  async function sample(env, site, view = VIEW_ON, viewSync = null, nudged = false) {
    const retry = viewSync ? (label, fn) => fn() : withRetry;
    return retry(`${site} ${env.width}x${env.height}`, async () => {
      const s = await load(nudged && COMMIT_ON ? nudgeEnv(env) : env, site);
      try {
        await parkEarly(s, env);
        const rec = newRec();
        const settle = await evalReady(s, site, rec);
        if (nudged && COMMIT_ON) await resizeTo(s, env, 0, view, rec);
        const settleWait = afterCommit(await settleArm(s, site, env), view, nudged && COMMIT_ON ? 1 : 0);
        const raw = await evalCollect(s, site, env, collectProps, (roots, e) => settleArm(s, site, e, roots), view, frozen ? { base: stopBase(0, readingCount(view)), rec } : null, viewSync);
        raw.settleWait = foldSettle(settleWait, raw.overlaySettle); delete raw.overlaySettle;
        if (gaps) raw.gap = await s.evaluate(gaps.collect, gaps.collectArg);
        return { settle, raw };
      } finally { await s.close().catch(() => {}); }
    });
  }

  // Both arms of one probe with the view set shared (Lean viewCell with the same bring flag for both arms): the arms load and run
  // together, meet at the barrier after their first reading, and bring the union of the parts either arm read skipped.
  async function samplePair(env) {
    return withRetry(`pair ${env.width}x${env.height}`, async () => {
      const barrier = makeViewBarrier(plainIds, SITES);
      const rs = await Promise.allSettled(SITES.map((site) => sample(env, site, true, (list) => barrier.post(site, list)).catch((e) => { barrier.fail(e); throw e; })));
      const bad = rs.find((r) => r.status === 'rejected');
      if (bad) throw bad.reason;
      return rs.map((r) => r.value);
    });
  }


  if (DIAG_CV) {
    // Variants: [load offset, steps]. R<d> = resize to width+d, S = settle, r = snapshot, c = the gate's own collect.
    const VARIANTS = {
      A: [0, ['S', 'c', 'c', 'r']],
      B: [1, ['R0', 'S', 'c', 'c', 'r']],
      C: [0, ['r', 'R1', 'r', 'R0', 'r']],
      D: [0, ['S', 'c', 'R1', 'c', 'R0', 'c']],
      E: [1, ['R0', 'S', 'c', 'R1', 'c', 'R0', 'c']],
      F: [0, ['S', 'c', 'R-1', 'c']],
      G: [1, ['R0', 'S', 'r', 'r', 'c']],
    };
    const N = Number(process.env.FW_DIAG_LOADS || 12);
    const sel = (site, role) => partsArg[site].commission.find((r) => r.role === role).selector;
    const withTimeout = (p, ms, label) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('diag timeout ' + label)), ms))]);
    for (const width of [1440, 1512]) {
      const env = { ...refEnv, width, deviceWidth: width };
      for (let k = 0; k < N; k++) {
        for (const [name, [off, steps]] of Object.entries(VARIANTS)) {
          await Promise.all(SITES.map(async (site) => {
            const t0 = Date.now();
            const at = (d) => ({ ...env, width: width + d, deviceWidth: width + d });
            const s = await load(at(off), site);
            const out = { engine: engineName, site, width, k, variant: name, snaps: [] };
            try {
              await withTimeout((async () => {
                const INNER = sel(site, 'inner'), ROWS = sel(site, 'rows');
                await parkEarly(s, env);
                const rec = newRec();
                await evalReady(s, site, rec);
                let touched = false, used = -1, cur = at(off);
                for (const st of steps) {
                  if (st === 'S') { await settleArm(s, site, cur); touched = true; }
                  else if (st === 'r') { out.snaps.push(await s.evaluate(diagSnap, { inner: INNER, rows: ROWS, tag: 'r' + out.snaps.length })); touched = true; }
                  else if (st === 'c') {
                    const raw = await evalCollect(s, site, cur, collectProps, null, false, frozen ? { base: stopBase(Math.max(used, 0), readingCount(false)), rec } : null, null, null);
                    (out.cs ||= []).push([raw.parts.commission.inner.items[0].style['margin-inline-start'], raw.parts.commission.rows.items[0].style['margin-inline-start']]); touched = true;
                  } else {
                    const d = Number(st.slice(1)); cur = at(d);
                    used = touched && used < 0 ? 1 : used + 1; await resizeTo(s, cur, used, false, rec);
                  }
                }
              })(), 120000, `${site} ${width} ${k} ${name}`);
            } catch (e) { out.error = String(e.message || e); }
            finally { await s.close().catch(() => {}); }
            out.ms = Date.now() - t0;
            log('DIAGCV ' + JSON.stringify(out));
          }));
        }
      }
    }
    process.exit(0);
  }

  // Phase 1: the matrix.
  const probes = gen.matrix.probes.filter((p) => (!probeFilter || probeFilter.some((o) => p.id.includes(o) || p.block === o))
    && (!scope || scope.probes.includes(p.id)));
  const tasks = probes.flatMap((p) => SITES.map((site) => ({ p, site })));
  let done = 0;
  const tProbes = Date.now();
  // `load <id> <site>: <ms> ms` lines are the measured unit costs of Fw.Gate.ShardCosts (gate-shard-balance).
  const loaded = (p, site, t0) => {
    log(`  load ${engineName} ${p.id} ${site}: ${Date.now() - t0} ms`);
    if (++done % 20 === 0) log(`  ${engineName}: ${done}/${tasks.length} loads`);
  };
  const sampled = VIEW_ON
    ? (await pool(probes, Math.max(1, Math.floor(concurrency / 2)), async (p) => {
      const t0 = Date.now();
      const pair = await samplePair(gaps ? gaps.mapProbe(p) : probeEnv(p));
      for (const site of SITES) loaded(p, site, t0);
      return pair;
    })).flat()
    : await pool(tasks, concurrency, async ({ p, site }) => {
      const t0 = Date.now();
      const r = await sample(gaps ? gaps.mapProbe(p) : probeEnv(p), site);
      loaded(p, site, t0);
      return r;
    });
  log(`  ${engineName}: probes done (${tasks.length} loads, ${Date.now() - tProbes} ms)`);
  const probeRecords = probes.map((p, i) => ({
    id: p.id, block: p.block, env: probeEnv(p), ...(gaps ? { realized: gaps.mapProbe(p) } : {}),
    orig: sampled[2 * i], rewrite: sampled[2 * i + 1],
  }));

  // Phase 2: live-resize sweeps. Each arm of a sweep is one page that is only resized after the first load.
  const sweeps = sweepDefs(gen).filter((s) => (!sweepFilter || sweepFilter.some((o) => s.id.includes(o)))
    && (!scope || scope.sweeps.includes(s.id)));
  const sweepRecords = [];
  for (const sw of sweeps) {
    const tSweep = Date.now();
    // One page load of one arm: all stops of the sweep, with the parts of `page` (Lean Fw.Gate.Freeze.pageOf; null = all of them).
    const armStops = (site, page) => withRetry(`sweep ${sw.id} ${site}${page ? ` ${page}` : ''}`, async () => {
      const s = await load(COMMIT_ON ? nudgeEnv(sw.stops[0]) : sw.stops[0], site);
      try {
        const stops = [];
        let resizes = 0;
        await parkEarly(s, sw.stops[0]);
        const rec0 = newRec();
        await evalReady(s, site, rec0);
        for (let i = 0; i < sw.stops.length; i++) {
          const rec = i === 0 ? rec0 : newRec();
          if (i > 0 || COMMIT_ON) {
            const t1 = Date.now();
            await resizeTo(s, sw.stops[i], i, false, rec);
            resizes++;
            log(`  resize ${engineName} ${site} ${sw.stops[i].width}x${sw.stops[i].height}: ${Date.now() - t1} ms`);
          }
          const settleWait = afterCommit(await settleArm(s, site, sw.stops[i]), false, resizes);
          const raw = await evalCollect(s, site, sw.stops[i], collectProps, (roots, e) => settleArm(s, site, e, roots), false, frozen ? { base: stopBase(i, readingCount(false)), rec } : null, null, page);
          raw.settleWait = foldSettle(settleWait, raw.overlaySettle); delete raw.overlaySettle;
          stops.push(raw);
        }
        return stops;
      } finally { await s.close().catch(() => {}); }
    });
    // The mount stage scrolls the page away and back, and a part that needs no mount must not be read after that history (the original
    // recomputes its pain notes when its section renders, its typing visual keeps cycling): parts without a mount step are read on a page
    // that never scrolls, the mount parts on a second page that does (Lean Fw.Gate.Freeze.pageOf, pages_partition). Without a mount part
    // there is one page, as before. The two pages' readings of a stop are joined; the sample is unsettled when any wait of it is.
    const hasPlain = plainIds.length + ovIds.length > 0;
    const joinStop = (a, b) => ({
      ...a, parts: { ...a.parts, ...b.parts }, ...(b.prepared ? { prepared: b.prepared } : {}),
      ...(a.late || b.late ? { late: [...(a.late || []), ...(b.late || [])] } : {}),
      settleWait: foldSettle(a.settleWait, [b.settleWait]),
    });
    const perSite = await Promise.all(SITES.map(async (site) => {
      if (mtIds.length === 0) return armStops(site, null);
      const mounted = await armStops(site, 'mounted');
      if (!hasPlain) return mounted;
      return (await armStops(site, 'plain')).map((a, i) => joinStop(a, mounted[i]));
    }));
    const last = sw.stops[sw.stops.length - 1];
    const fresh = await Promise.all(SITES.map((site) => sample(last, site, false, null, true)));
    sweepRecords.push({ id: sw.id, blurb: sw.blurb, stops: sw.stops, orig: perSite[0], rewrite: perSite[1], freshFinal: { orig: fresh[0], rewrite: fresh[1] } });
    log(`  ${engineName}: sweep ${sw.id} done (${sw.stops.length} stops, ${Date.now() - tSweep} ms)`);
  }

  const header = {
    schema: 'fw.gate-breakpoints.run/1',
    engine: engineName,
    browser: await engine.version(),
    gen: { sha256: genSha, schema: gen.schema, probes: gen.matrix.loadsPerEngine },
    snapshot: lock.snapshot,
    site: { buildId: buildInfo.buildId, configHash: buildInfo.configHash, muiCss: buildInfo.muiCss },
    // the flags the rewrite arm ran with ('' = the default config) and the config hash the browser read from the loaded page
    flags: { search: variantPage.search, configHash: loadedConfig },
    // per part with variant roles: the variant the rewrite page rendered (null: no data-fw-variant)
    ...(Object.keys(variants).length ? { variants } : {}),
    port: portOf(engineName),
    pinnedDate: '2026-10-01T00:00:00+07:00',
    clock: frozen ? { kind: 'frozen', stepMs: STEP_MS, holdLoadMs: HOLD_LOAD_MS, readyToMs: READY_TO_MS, postResizeMs: POST_RESIZE_MS, mainOffMs: MAIN_OFF_MS, slotMs: SLOT_MS } : { kind: 'native' },
    ...(sel.narrowed ? { parts: { covered: sel.covered, skipped: sel.skipped, ...(scope ? { scope } : {}) } } : {}),
    props,
  };
  await engine.close();
  await Promise.all(SITES.map((s) => servers[s].close()));

  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${engineName}.json`);
  const lines = [
    '{"header":' + JSON.stringify(header) + ',',
    '"probes":[',
    probeRecords.map((r) => JSON.stringify(r)).join(',\n'),
    '],',
    '"sweeps":[',
    sweepRecords.map((r) => JSON.stringify(r)).join(',\n'),
    ']}',
  ];
  writeFileSync(file, lines.join('\n') + '\n');
  log(`wrote ${file}`);
  return file;
}
