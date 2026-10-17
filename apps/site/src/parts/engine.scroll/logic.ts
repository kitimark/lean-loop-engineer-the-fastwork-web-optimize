/**
 * Pure logic of engine.scroll (no DOM, no clock). Original: _app/immutable/nodes/2.DyWL8TcE.js
 *   rE 2667-2669 (schedule one rAF if none is pending), iE 2670-2673 (run every active callback),
 *   aE/oE 2674-2689 (listeners attached on the first registration, removed when the set is empty),
 *   dE 2749-2782 (register, then rE()).
 * Golden vectors: packages/contracts/golden/parts/engine.scroll.jsonl (lean-parts), see logic.test.ts.
 */
export type ScrollVariant = 'faithful' | 'batched';

export interface Entry {
  id: string;
  order: number;
  /** registration sequence number, the tie break (the original iterates a Set in insertion order). */
  seq: number;
}

/** Callback order: ascending `order`, then registration order. Returns ids. */
export function orderCallbacks(entries: readonly Entry[]): string[] {
  return [...entries].sort((a, b) => a.order - b.order || a.seq - b.seq).map((e) => e.id);
}

export interface Step {
  op: 'read' | 'write';
  /** index into the ordered callback list */
  i: number;
}

/**
 * The frame's step sequence. A callback's read phase is the callback itself; a callback that returns a writer
 * (`writers[i]`) also has a write step. faithful: read(i), write(i) for each i in turn (reads and writes interleave,
 * as the original's callbacks do). batched: every read, then every write.
 */
export function framePlan(variant: ScrollVariant, writers: readonly boolean[]): Step[] {
  const out: Step[] = [];
  if (variant === 'faithful') {
    writers.forEach((w, i) => {
      out.push({ op: 'read', i });
      if (w) out.push({ op: 'write', i });
    });
    return out;
  }
  writers.forEach((_, i) => out.push({ op: 'read', i }));
  writers.forEach((w, i) => {
    if (w) out.push({ op: 'write', i });
  });
  return out;
}

/** rE: `tE ||= requestAnimationFrame(iE)`: request a frame iff none is pending. */
export function shouldSchedule(pending: boolean): boolean {
  return !pending;
}

/** aE / oE: attach on the first registration, detach when the set empties. */
export function listenerAction(attached: boolean, size: number): 'attach' | 'detach' | 'none' {
  if (size > 0 && !attached) return 'attach';
  if (size === 0 && attached) return 'detach';
  return 'none';
}

/* ---- Forced style/layout cost model (Lean Fw.Parts.EngineScroll: forced, planLayouts, forcedCounts, engineRuns) ---- */

/** RS style read, RL layout read, WS style-only write, WL layout-affecting write. */
export type Access = 'RS' | 'RL' | 'WS' | 'WL';
export type Role = 'check' | 'dirty' | 'neutral';

export function isReadAccess(a: Access): boolean {
  return a === 'RS' || a === 'RL';
}
/** Any read checks style, any write dirties it. */
export function styleRole(a: Access): Role {
  return isReadAccess(a) ? 'check' : 'dirty';
}
/** Layout reads check, layout-affecting writes dirty, the rest is neutral. */
export function layoutRole(a: Access): Role {
  return a === 'RL' ? 'check' : a === 'WL' ? 'dirty' : 'neutral';
}

/** Forced updates of one kind: a `check` while dirty is one forced update and leaves the flag clean. */
export function forced(role: (a: Access) => Role, dirty: boolean, accesses: readonly Access[]): number {
  let d = dirty;
  let n = 0;
  for (const a of accesses) {
    const r = role(a);
    if (r === 'check') {
      if (d) n++;
      d = false;
    } else if (r === 'dirty') d = true;
  }
  return n;
}

/** Reads first, then writes, each in order (the batched reordering). */
export function batchedOrder(accesses: readonly Access[]): Access[] {
  return [...accesses.filter(isReadAccess), ...accesses.filter((a) => !isReadAccess(a))];
}

export function forcedCounts(accesses: readonly Access[], dirty: boolean): { style: number; layout: number } {
  return { style: forced(styleRole, dirty, accesses), layout: forced(layoutRole, dirty, accesses) };
}
export function forcedCountsBatched(accesses: readonly Access[], dirty: boolean): { style: number; layout: number } {
  return forcedCounts(batchedOrder(accesses), dirty);
}

/** A TS plan step as an access: a read phase reads layout, a write phase may change layout (worst case). */
export function stepAccess(s: Step): Access {
  return s.op === 'read' ? 'RL' : 'WL';
}
/** Forced layouts of one frame plan. */
export function planLayouts(variant: ScrollVariant, writers: readonly boolean[], dirty: boolean): number {
  return forced(layoutRole, dirty, framePlan(variant, writers).map(stepAccess));
}

/** `iE` calls over a trace of `scroll` events and rendering `frame`s, from a pending flag (coalescing). */
export function engineRuns(pending: boolean, events: readonly ('scroll' | 'frame')[]): number {
  let p = pending;
  let n = 0;
  for (const e of events) {
    if (e === 'scroll') p = p || shouldSchedule(p);
    else {
      if (p) n++;
      p = false;
    }
  }
  return n;
}

/** The original nav callback's accesses outside the morph (JS 12955-13007): ee() style reads, two rects, F(), track rect. */
export const NAV_ACCESSES: readonly Access[] = ['RS', 'RS', 'RL', 'RL', 'RL', 'WS', 'RL', 'WS', 'RL'];
/** The hero exit body (JS 4162-4171): track rect, then two style writes. */
export const HERO_EXIT_ACCESSES: readonly Access[] = ['RL', 'WS', 'WS'];
/** A steady faithful frame: the hero's own rAF runs before the engine callback (JS 4239 queued it first). */
export const PILOT_FRAME: readonly Access[] = [...HERO_EXIT_ACCESSES, ...NAV_ACCESSES];
