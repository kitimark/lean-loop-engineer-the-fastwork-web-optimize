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
