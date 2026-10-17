// THE decision code of the breakpoint gate: pure functions, no I/O, no page access, no clocks. Everything the runner
// collects is raw; everything below turns raw into statuses and the pass/fail rule. This file is the list handed to
// Lean ("Lean first"): each export has a statement in its comment. The tolerances come from PLAN section 6.6:
// boxes within 0.5 CSS px (PL1), computed styles exact after normalisation with numbers within 1e-3 (PL2).

export const TOL = Object.freeze({ boxPx: 0.5, styleNumber: 1e-3 });

/** Status of one compared item. 'na' items do not take part in a verdict. */
export const STATUS = Object.freeze({ equal: 'equal', differ: 'differ', missing: 'missing', na: 'na' });

// ---------------------------------------------------------------------------------------------------------------
// THE RULE (one function). For a list of item statuses:
//   no applicable item (empty, or every item 'na')  ->  'not-comparable'
//   some applicable item is not 'equal'              ->  'fail'
//   otherwise                                        ->  'pass'
// In math: let A = {s | s != na}. verdict = NC if A = {} ; fail if exists s in A, s != equal ; pass otherwise.
// Rollups (probe verdicts -> block verdict -> table) reuse the same function through `verdictToStatus`.
// ---------------------------------------------------------------------------------------------------------------
export function cellVerdict(statuses) {
  const applicable = statuses.filter((s) => s !== STATUS.na);
  if (applicable.length === 0) return 'not-comparable';
  return applicable.every((s) => s === STATUS.equal) ? 'pass' : 'fail';
}

/** pass -> equal, fail -> differ, not-comparable -> na, so verdicts can be rolled up with `cellVerdict` itself. */
export function verdictToStatus(v) {
  return v === 'pass' ? STATUS.equal : v === 'fail' ? STATUS.differ : STATUS.na;
}

// ---------------------------------------------------------------------------------------------------------------
// Value comparisons
// ---------------------------------------------------------------------------------------------------------------
const NUM = /-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/gi;

/**
 * Computed-style values: equal as strings, or, after replacing each number by a hole, equal skeletons with the same
 * count of numbers, each pair within 1e-3. Missing (undefined) on either side is never equal.
 * Statement: styleValueEq a b <-> a = b  or  (skel a = skel b  and  |nums a| = |nums b|  and  forall i, |a_i - b_i| <= 1e-3).
 */
export function styleValueEq(a, b) {
  if (a === undefined || b === undefined || a === null || b === null) return false;
  if (a === b) return true;
  const sa = String(a), sb = String(b);
  if (sa.replace(NUM, '#') !== sb.replace(NUM, '#')) return false;
  const na = (sa.match(NUM) ?? []).map(Number), nb = (sb.match(NUM) ?? []).map(Number);
  if (na.length !== nb.length) return false;
  return na.every((x, i) => Math.abs(x - nb[i]) <= TOL.styleNumber);
}

/** Box dimension in CSS px: |a - b| <= 0.5. Missing is never equal. */
export function boxEq(a, b) {
  if (typeof a !== 'number' || typeof b !== 'number' || Number.isNaN(a) || Number.isNaN(b)) return false;
  return Math.abs(a - b) <= TOL.boxPx;
}

/** Element counts of an anchor role: equal and positive. Both zero is 'missing' (the anchor is absent in both). */
export function countStatus(a, b) {
  if (a === 0 && b === 0) return STATUS.missing;
  return a === b ? STATUS.equal : STATUS.differ;
}

export function styleStatus(a, b) {
  if (a === undefined || b === undefined) return STATUS.missing;
  return styleValueEq(a, b) ? STATUS.equal : STATUS.differ;
}

export function boxStatus(a, b) {
  if (a === undefined || a === null || b === undefined || b === null) return STATUS.missing;
  return boxEq(a, b) ? STATUS.equal : STATUS.differ;
}

// ---------------------------------------------------------------------------------------------------------------
// Which properties are compared, and the items of one part
// ---------------------------------------------------------------------------------------------------------------

/** A property is skipped if it equals a skip name, or equals/starts with `prefix-` of a skip prefix. */
export function isSkipped(prop, skipNames, skipPrefixes) {
  if (skipNames.includes(prop)) return true;
  return skipPrefixes.some((p) => prop === p || prop.startsWith(`${p}-`));
}

/** The properties compared for a role: the rewrite-declared (restated) set minus the role's skips. Order kept. */
export function comparedProps(restated, roleSpec, anchors) {
  const names = [...(roleSpec.skipProps ?? [])];
  for (const set of roleSpec.skipSets ?? []) names.push(...anchors.style.skipSets[set].props);
  const prefixes = anchors.style.skipPrefixes.map((p) => p.prefix);
  return restated.filter((p) => !isSkipped(p, names, prefixes));
}

/** Box of an item relative to the first item of a reference role (or absolute when there is none). */
export function relBox(item, ref) {
  if (!item) return null;
  if (!ref) return { x: item.rect.x, y: item.rect.y, w: item.rect.w, h: item.rect.h };
  return { x: item.rect.x - ref.rect.x, y: item.rect.y - ref.rect.y, w: item.rect.w, h: item.rect.h };
}

/**
 * All items of one part at one probe, as plain records {cls, role, idx, key, a, b, status}. a = original, b = rewrite.
 * origPart / rewritePart: the raw `parts[partId]` of each arm. props: { [role]: { restated, originOnly } } of the run.
 * `info` items (properties only the original declares) are returned with cls 'info' and status 'na' (never in a verdict).
 */
export function partItems(partSpec, origPart, rewritePart, props, anchors) {
  const out = [];
  for (const spec of partSpec.roles) {
    const o = origPart?.[spec.role], r = rewritePart?.[spec.role];
    if (!o || !r) { out.push({ cls: 'count', role: spec.role, idx: -1, key: 'count', a: o ? o.count : null, b: r ? r.count : null, status: STATUS.missing }); continue; }
    out.push({ cls: 'count', role: spec.role, idx: -1, key: 'count', a: o.count, b: r.count, status: countStatus(o.count, r.count) });
    const n = Math.min(o.items.length, r.items.length);
    const refRole = spec.boxRel ? spec.boxRel.role : null;
    const refO = refRole ? origPart[refRole]?.items?.[spec.boxRel.index] : null;
    const refR = refRole ? rewritePart[refRole]?.items?.[spec.boxRel.index] : null;
    const compared = comparedProps(props[spec.role]?.restated ?? [], spec, anchors);
    const info = (props[spec.role]?.originOnly ?? []).filter((p) => !isSkipped(p, [], anchors.style.skipPrefixes.map((x) => x.prefix)));
    for (let i = 0; i < n; i++) {
      if (spec.dims.length > 0) {
        const bo = relBox(o.items[i], refO), br = relBox(r.items[i], refR);
        for (const d of spec.dims) out.push({ cls: 'box', role: spec.role, idx: i, key: d, a: bo?.[d], b: br?.[d], status: boxStatus(bo?.[d], br?.[d]) });
      }
      for (const p of compared) {
        const a = o.items[i].style[p], b = r.items[i].style[p];
        out.push({ cls: 'style', role: spec.role, idx: i, key: p, a, b, status: styleStatus(a, b) });
      }
      for (const p of info) {
        const a = o.items[i].style[p], b = r.items[i].style[p];
        out.push({ cls: 'info', role: spec.role, idx: i, key: p, a, b, status: STATUS.na, differs: !styleValueEq(a, b) });
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Environment achieved, and matchMedia truth
// ---------------------------------------------------------------------------------------------------------------

/** Both on the same side of every device-width edge pair [n, n+1]: (a <= n) == (b <= n). */
export function sameSideOfEdges(a, b, edgePairs) {
  return edgePairs.every(([n]) => (a <= n) === (b <= n));
}

/**
 * Which requested features the engine did not deliver, from what the page itself reports. Empty = env achieved.
 * requested: { width, height, deviceWidth, dpr, hover, pointer, reducedMotion, colorScheme }; raw: one arm's {viewport, observed}.
 * Device width is allowed to differ when both are on the same side of every device-width edge (500/501), because no
 * condition can tell them apart (Lean: MQ.eval_congr). Width must be exact (matchMedia `(width: Wpx)`).
 */
export function envDeviations(requested, raw, deviceEdgePairs) {
  const v = raw.viewport, o = raw.observed, d = [];
  if (o.widthExact !== true) d.push('width');
  if (v.innerHeight !== requested.height) d.push('height');
  if (!(v.screenWidth === requested.deviceWidth || sameSideOfEdges(v.screenWidth, requested.deviceWidth, deviceEdgePairs))) d.push('deviceWidth');
  if (v.dpr !== requested.dpr) d.push('dpr');
  if (requested.hover === 'hover' ? !(o.hoverHover === true && o.hoverNone === false) : !(o.hoverNone === true && o.hoverHover === false)) d.push('hover');
  if (requested.pointer === 'fine' ? !(o.pointerFine === true && o.pointerCoarse === false) : !(o.pointerCoarse === true && o.pointerFine === false)) d.push('pointer');
  if ((requested.reducedMotion === 'reduce') !== (o.reducedMotion === true)) d.push('reducedMotion');
  if ((requested.colorScheme === 'dark') !== (o.dark === true)) d.push('colorScheme');
  return d;
}

/**
 * matchMedia items of one probe. a = original, b = rewrite, expect = Lean's value (undefined when the probe has no vector).
 *  truth.AR      orig = rewrite                                  (always applicable)
 *  truth.lean    orig = expect and rewrite = expect              (applicable only when the env is achieved on both arms and a vector exists)
 *  truth.legacy  the legacy max-/min- text gives the same value as the range text, on each arm (where a legacy text exists)
 *  truth.neutral.AR / truth.neutral.lean  the same two checks for the neutral queries (print, forced colors, the hover pair)
 */
export function truthItems(orig, rewrite, expect, expectNeutral, achieved) {
  const out = [];
  for (const k of Object.keys(orig.truth)) {
    out.push({ cls: 'truth.AR', key: k, a: orig.truth[k], b: rewrite.truth[k], status: orig.truth[k] === rewrite.truth[k] ? STATUS.equal : STATUS.differ });
    if (expect && achieved) {
      const ok = orig.truth[k] === expect[k] && rewrite.truth[k] === expect[k];
      out.push({ cls: 'truth.lean', key: k, a: orig.truth[k], b: rewrite.truth[k], expect: expect[k], status: ok ? STATUS.equal : STATUS.differ });
    } else {
      out.push({ cls: 'truth.lean', key: k, a: orig.truth[k], b: rewrite.truth[k], expect: expect ? expect[k] : null, status: STATUS.na });
    }
    if (orig.truthLegacy[k] !== null && orig.truthLegacy[k] !== undefined) {
      const ok = orig.truthLegacy[k] === orig.truth[k] && rewrite.truthLegacy[k] === rewrite.truth[k];
      out.push({ cls: 'truth.legacy', key: k, a: orig.truthLegacy[k], b: rewrite.truthLegacy[k], expect: null, status: ok ? STATUS.equal : STATUS.differ });
    }
  }
  for (const k of Object.keys(orig.neutral)) {
    out.push({ cls: 'truth.neutral.AR', key: k, a: orig.neutral[k], b: rewrite.neutral[k], status: orig.neutral[k] === rewrite.neutral[k] ? STATUS.equal : STATUS.differ });
    if (expectNeutral && achieved) {
      const ok = orig.neutral[k] === expectNeutral[k] && rewrite.neutral[k] === expectNeutral[k];
      out.push({ cls: 'truth.neutral.lean', key: k, a: orig.neutral[k], b: rewrite.neutral[k], expect: expectNeutral[k], status: ok ? STATUS.equal : STATUS.differ });
    } else {
      out.push({ cls: 'truth.neutral.lean', key: k, a: orig.neutral[k], b: rewrite.neutral[k], expect: null, status: STATUS.na });
    }
  }
  return out;
}

/** Verdict of a list of probe verdicts (block or table cell): the same rule, through verdictToStatus. */
export function rollup(verdicts) {
  return cellVerdict(verdicts.map(verdictToStatus));
}
