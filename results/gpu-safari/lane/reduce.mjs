// Reduction of a captured zone to one result per flag arm: per state the graded pixel cell (existing Lean-backed `grade`) plus descriptive counts.
// The census numbers are layers and bytes the Inspector reports; they are a proxy for allocation, not IOSurface counts.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { decodePng } from '../../../packages/measure-webkit/src/pathpix-png.mjs';
import { pixelCell, maskOf, hashOf } from './pix.mjs';
import { FLAG_ARMS } from './plan.mjs';

/** Union of two micro-px boxes [x, y, w, h]. */
export function unionBox(a, b) {
  const x0 = Math.min(a[0], b[0]), y0 = Math.min(a[1], b[1]);
  const x1 = Math.max(a[0] + a[2], b[0] + b[2]), y1 = Math.max(a[1] + a[3], b[1] + b[3]);
  return [x0, y0, x1 - x0, y1 - y0];
}

const load = (dir, f) => decodePng(readFileSync(join(dir, f)));

/** One flag arm against `base`, with `base2` as the A/A control. `cap` is the captureZone result. */
export function reduceArm({ cap, arm, shotsDir, run }) {
  const { session } = cap;
  const states = cap.states.map((st) => {
    const A = cap.arms.base.states.find((s) => s.id === st.id);
    const C = cap.arms.base2.states.find((s) => s.id === st.id);
    const B = cap.arms[arm.id].states.find((s) => s.id === st.id);
    const [a0, a1] = A.files.map((f) => load(shotsDir, f));
    const [b0, b1] = B.files.map((f) => load(shotsDir, f));
    const [c0, c1] = C.files.map((f) => load(shotsDir, f));
    const D = cap.arms.base3?.states.find((s) => s.id === st.id);
    const d0 = D ? load(shotsDir, D.files[0]) : null;
    const box = st.mask === 'nav' ? unionBox(A.state.rect, B.state.rect) : null;
    const m = maskOf(st.mask, session.dpr, a0.w, a0.h, box);
    const own = st.mask === 'nav' ? maskOf('nav', session.dpr, a0.w, a0.h, A.state.rect) : null;
    const r = pixelCell({ run, engine: 'webkit', dpr: session.dpr, a0, a1, b0, b1, c0, c1, d0, m, box, own });
    return {
      id: st.id, kind: st.kind, m: st.m ?? null, y: st.y ?? null, mask: m, maskKind: st.mask,
      grade: r.grade, premises: r.premises,
      counts: { inside: r.cell.inside, out: r.cell.out, hist: r.hist, ring: r.ring, control: r.cell.control, controlOut: r.controlOut },
      stable: { faithful: r.cell.sameA, arm: r.cell.sameB, control: r.cell.control.same },
      glass: st.mask === 'nav' ? r.glass : null, own: r.own, loads: r.loads,
      hash: { ...r.hash, d: d0 ? hashOf(d0) : null }, stateSeen: { faithful: A.state, arm: B.state, control: C.state },
      census: { faithful: A.census, arm: B.census, control: C.census, order: D?.census ?? null },
      iosurface: { faithful: A.iosurface ?? null, arm: B.iosurface ?? null, control: C.iosurface ?? null, order: D?.iosurface ?? null },
    };
  });
  return { arm: arm.id, search: arm.search, states };
}

export const armsOfZone = (zone) => FLAG_ARMS.filter((a) => a.zone === zone);
