// The breakpoint gate's decisions, answered by Lean through fwcore. Every status, verdict, count and table cell
// comes from lean/Fw/Gate (statements and proofs there; the op table is lean/Fw/Wire/Gate.lean):
//   Fw.Gate.Rule     the rule: no applicable item -> not-comparable, an applicable item not equal -> fail, else pass;
//                    rollups and table cells (failing / comparable counts)
//   Fw.Gate.Compare  value comparisons: style values exact or numbers within 1/1000 (exact decimals), boxes within 1/2 px
//   Fw.Gate.Items    which properties are compared (skips with reasons), the items of one part, the part verdict
//   Fw.Gate.State    environment achieved, matchMedia truth items, the rows of one state, sweep hysteresis counts
//   Fw.Gate.Reach    cells an engine port cannot reach (WebKit: primary hover/pointer pairs, whole media width;
//                    Chromium: whole device px), proved; such rows are unreachable, never pass or fail
// This file has no decision logic: it shapes requests, moves JSON lines, and attaches the display values (orig /
// rewrite values of a failing item) from the raw data.
// The binary is lean/.lake/build/bin/fwcore (FW_CORE_BIN overrides), spawned with LEAN_ABORT_ON_PANIC=1.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

export function fwcoreBin() {
  const p = process.env.FW_CORE_BIN ?? join(ROOT, 'lean/.lake/build/bin/fwcore');
  if (!existsSync(p)) throw new Error(`fwcore not found at ${p}; build it with: cd lean && lake build fwcore`);
  return p;
}

/** Send requests (objects with `op`) in one fwcore run, return the replies (ids stripped). Throws on any `error` reply. */
export function call(requests) {
  const input = requests.map((r, i) => JSON.stringify({ ...r, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 30 });
  if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
  if (r.stderr.length) console.error(`fwcore stderr (incident): ${r.stderr}`);
  const replies = r.stdout.toString().trim().split('\n').map((l) => JSON.parse(l));
  if (replies.length !== requests.length) throw new Error(`fwcore: ${replies.length} replies for ${requests.length} requests`);
  return replies.map((x, i) => {
    if (x.id !== i) throw new Error(`fwcore: reply ${i} has id ${x.id}`);
    if (x.error !== undefined) throw new Error(`fwcore ${requests[i].op}: ${x.error}`);
    const { id, ...rest } = x;
    return rest;
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Request shapes
// ---------------------------------------------------------------------------------------------------------------

/** One arm of a raw record ({truth, truthLegacy, neutral, observed, viewport, parts}, or {raw: ...}), trimmed to the
 *  covered parts. The matchMedia maps travel as [key, value] entries so their order is kept. */
import { canonParts } from './align-equiv.mjs';
import { normalizeParts } from './transition-list.mjs';
const canonArm = (o, r) => { const rr = r.raw ?? r, oo = o.raw ?? o; return { ...rr, parts: canonParts(oo.parts, rr.parts) }; };
const armReq = (x, parts) => {
  const r = x.raw ?? x;
  return {
    viewport: r.viewport, observed: r.observed,
    truth: Object.entries(r.truth ?? {}), truthLegacy: Object.entries(r.truthLegacy ?? {}), neutral: Object.entries(r.neutral ?? {}),
    parts: partsReq(normalizeParts(r.parts), parts), // both arms: transition lists compared in the Lean normal form (Fw.Gate.TransitionList)
  };
};
const partsReq = (rawParts, parts) => Object.fromEntries(parts.filter((p) => rawParts?.[p] !== undefined).map((p) => [p, rawParts[p]]));
const mapReq = (m) => (m ? Object.entries(m) : null);

/** The shared context of a request: anchors.json as is, the covered part ids (in order), the run's recorded
 *  properties, the device-width edge pairs [n, n+1], the engine port (`chromium`, `webkit-apple`,
 *  `webkit-glib`; absent: no reach claim) and the variant each part rendered on the rewrite arm (run header `variants`;
 *  Lean selects the part's variant role from it, Fw.Gate.variantRole; absent: none). */
export const context = ({ anchors, parts, props, deviceEdges, port, variants }) => ({ anchors, parts, props, deviceEdges, port: port ?? null, variants: variants ?? null });

/** A `gate.state` request: states are {requested, orig, rewrite, expect?, expectNeutral?} with raw arms. */
export const stateRequest = (ctx, states) => ({
  op: 'gate.state', ...ctx,
  states: states.map((s) => ({ requested: s.requested, orig: armReq(s.orig, ctx.parts), rewrite: armReq(canonArm(s.orig, s.rewrite), ctx.parts), expect: mapReq(s.expect), expectNeutral: mapReq(s.expectNeutral) })),
});

/** A `gate.stale` request: pairs are {after, fresh} raw records (the arm after a sweep, a fresh load there). */
export const staleRequest = (ctx, pairs) => ({
  op: 'gate.stale', ...ctx,
  pairs: pairs.map(({ after, fresh }) => ({ after: partsReq((after.raw ?? after).parts, ctx.parts), fresh: partsReq((fresh.raw ?? fresh).parts, ctx.parts) })),
});

// ---------------------------------------------------------------------------------------------------------------
// Replies -> the records summary.mjs prints
// ---------------------------------------------------------------------------------------------------------------

/** Display values of a part item (orig a, rewrite b), read from the raw data; no decision is made here. Boxes are
 *  shown relative to the reference item exactly as Lean compares them (Fw.Gate.relRect), in floating point. */
function shown(roleSpecs, oPart, rPart, it, w) {
  const o = oPart?.[w?.role === it.role ? w.countOf : it.role], r = rPart?.[it.role];
  if (it.cls === 'count') return { a: o ? o.count : null, b: r ? r.count : null };
  if (it.cls === 'box') {
    const rs = roleSpecs.find((x) => x.role === it.role);
    const rel = (part, item) => {
      const ref = rs.boxRel ? part?.[rs.boxRel.role]?.items?.[rs.boxRel.index] : null;
      const q = item.rect;
      return (ref ? { x: q.x - ref.rect.x, y: q.y - ref.rect.y, w: q.w, h: q.h } : { x: q.x, y: q.y, w: q.w, h: q.h })[it.key];
    };
    return { a: rel(oPart, o.items[it.idx]), b: rel(rPart, r.items[it.idx]) };
  }
  return { a: o.items[it.idx].style[it.key], b: r.items[it.idx].style[it.key] };
}

/** The key of the page-root anchor item (Lean `Fw.Gate.PageRoot.itemKey`): its values are the arms' document scrollWidth. */
const PAGE_ROOT_KEY = 'scrollWidth<=requestedWidth';
const scrollWidthOf = (arm) => (arm.raw ?? arm).viewport?.scrollWidth ?? null;

/** One `gate.state` reply entry with the raw arms it was asked about -> {dev, achieved, truth, truthCounts, rows,
 *  compared, reach, verdict, fails, infoDiffs}. `reach`: null or the reason the port cannot reach the state;
 *  `verdict`: Lean's rollup of every row, part rows included. `fails`: per part, the failing count/box/style items; `infoDiffs`: per part, the
 *  properties only the original declares whose values differ (never in a verdict). `byRect`: per part, the margin cells
 *  Lean decided by the node's rect cell (Fw.Gate.marginStatus; `status` is that rect cell, `styleStatus` the style comparison). */
export function readState(anchors, state, ev, variants = null) {
  const o = (state.orig.raw ?? state.orig).parts, r = (state.rewrite.raw ?? state.rewrite).parts;
  const fails = {}, infoDiffs = {}, byRect = {};
  for (const [pid, p] of ev.parts) {
    const roles = anchors.parts[pid].roles;
    // the variant role in force (Lean selected it the same way): its original count is shown from the counted role
    const w = (anchors.parts[pid].variantRoles ?? []).find((x) => x.variant === variants?.[pid]);
    fails[pid] = p.fails.map((it) => ({ ...it, ...(it.key === PAGE_ROOT_KEY ? { a: scrollWidthOf(state.orig), b: scrollWidthOf(state.rewrite) } : shown(roles, o?.[pid], r?.[pid], it, w)) }));
    infoDiffs[pid] = p.infoDiffs.map((it) => ({ ...it, ...shown(roles, o?.[pid], r?.[pid], it) }));
    byRect[pid] = (p.byRect ?? []).map((it) => ({ ...it, ...shown(roles, o?.[pid], r?.[pid], it) }));
  }
  return {
    dev: ev.dev, achieved: ev.achieved,
    truth: ev.truth,
    truthCounts: ev.truthCounts,
    rows: Object.fromEntries(ev.rows), compared: Object.fromEntries(ev.compared),
    reach: ev.reach, verdict: ev.verdict,
    fails, infoDiffs, byRect,
  };
}

/** Evaluate states and sweep hysteresis pairs in one fwcore run: {states: [readState ...], stale: [{compared, differ}]}. */
export function evaluate(ctx, states, stalePairs = []) {
  const [s, t] = call([stateRequest(ctx, states), staleRequest(ctx, stalePairs)]);
  return { states: s.states.map((ev, i) => readState(ctx.anchors, states[i], ev, ctx.variants)), stale: t.stale };
}

/** Table cells (Lean `Fw.Gate.tally`, `Fw.Gate.blockCell`): cells are {verdicts, block}; a block cell with no
 *  verdicts is not-run. Returns {verdict, failing, total, unreachable} per cell (`total` counts pass and fail only). */
export const tallies = (cells) =>
  (cells.length === 0 ? [] : call([{ op: 'gate.tally', cells }])[0].cells.map(({ verdict, failing, total, unreachable }) => ({ verdict, failing, total, unreachable })));

/** The reach rule (Lean `Fw.Gate.reqReason`) on requested environments for one port: null or a reason per env. */
export const reach = (port, envs) => (envs.length === 0 ? [] : call([{ op: 'gate.reach', port, envs }])[0].reasons);

/** The rule over status lists (Lean `Fw.Gate.cellVerdict`), one verdict per list. */
export const cellVerdicts = (lists) => call(lists.map((statuses) => ({ op: 'gate.cell', statuses }))).map((x) => x.verdict);

/** Computed-style equality (Lean `Fw.Gate.styleValueEq`) for [a, b] pairs; undefined/null is absent. */
export const styleEq = (pairs) => call([{ op: 'gate.styleEq', pairs: pairs.map(([a, b]) => [a ?? null, b ?? null]) }])[0].eq;
