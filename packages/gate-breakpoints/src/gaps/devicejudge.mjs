// Pass rule of the phone session. Pure. Input: the records the probe page POSTed from the real iPhone (`device`), the
// iOS Simulator records of the same lane (`sim`, iPhone, from evidence.json), and the Lean-generated gen file.
//
//   W (WebKit fractional cell unreachable on the device):  forall r in device, mediaWidth(r) in N  and
//        forall N in edges, (width <= N) or (width >= N+1)                                     [Lean no_gap_ofNat]
//   X (WebKit cross cell unreachable on the device):       forall r in device (no mouse label), the 15 pointer facts of r equal
//        the Simulator iPhone's (load record); records labelled "mouse..." differ only in any-hover / any-pointer
//   S (same width, same answers):  r and a Simulator record with equal (media width, screen width, hover, pointer): the 30
//        conditions and 4 neutral queries are equal
//   L (Lean):  when the matrix has a vector for (media width, screen width, hover, pointer, reduced motion, scheme), the 30
//        conditions and 4 neutral queries equal it; records without a vector are listed, not judged
//   pass = W and X and S and L, with at least one record.
// Informative only (never fails): records with a non-whole visualViewport.width (a fraction existed and was rounded) and
// records where mediaWidth differs from round(screenWidth / (zoom label)).
import { expectFor } from '../spec.mjs';
import { fractionalEvidence, pairOf } from './judge.mjs';

const ANY = ['anyHoverHover', 'anyHoverNone', 'anyPointerFine', 'anyPointerCoarse', 'anyPointerNone'];
const eqObj = (a, b, keys) => keys.every((k) => a[k] === b[k]);

export function judgeDevice({ device, sim, gen }) {
  const checks = [];
  const add = (id, ok, detail) => checks.push({ id, ok, detail });
  if (device.length === 0) return { pass: false, checks: [{ id: 'records', ok: false, detail: 'no device records' }], informative: {} };
  const simLoads = sim.filter((r) => r.gap);
  const simRef = simLoads[0] ?? null;

  const w = fractionalEvidence(device.map((r) => ({ ...r, req: { label: r.label, seq: r.seq } })));
  add('W whole media width, no gap', w.ok, w.ok ? `${device.length} records` : w.bad);

  const allKeys = Object.keys(device[0].gap.pointer);
  const primary = allKeys.filter((k) => !ANY.includes(k));
  const xBad = [];
  if (!simRef) add('X pointer facts equal the Simulator', false, 'no Simulator record to compare with');
  else {
    for (const r of device) {
      const mouse = /^mouse/i.test(r.label ?? '');
      const keys = mouse ? primary : allKeys;
      if (!eqObj(r.gap.pointer, simRef.gap.pointer, keys)) xBad.push({ label: r.label, seq: r.seq, pair: pairOf(r.gap.pointer) });
    }
    add('X pointer facts equal the Simulator', xBad.length === 0, xBad.length === 0 ? `${device.length} records` : xBad);
  }

  const conds = (r) => ({ ...r.truth, ...r.neutral });
  const sBad = [], sCompared = [];
  for (const r of device) {
    const twin = simLoads.find((s) => s.gap.mediaWidth === r.gap.mediaWidth && s.gap.screenWidth === r.gap.screenWidth && pairOf(s.gap.pointer).hover === pairOf(r.gap.pointer).hover && pairOf(s.gap.pointer).pointer === pairOf(r.gap.pointer).pointer);
    if (!twin) continue;
    sCompared.push(`${r.label}#${r.seq}`);
    const a = conds(r), b = conds(twin);
    const diff = Object.keys(a).filter((k) => a[k] !== b[k]);
    if (diff.length > 0) sBad.push({ label: r.label, seq: r.seq, diff });
  }
  add('S equal to the Simulator at the same width', sBad.length === 0, sBad.length === 0 ? `${sCompared.length} records compared` : sBad);

  const lBad = [], lCompared = [], lNone = [];
  for (const r of device) {
    const p = pairOf(r.gap.pointer);
    const v = expectFor(gen, { width: r.gap.mediaWidth, deviceWidth: r.gap.screenWidth, hover: p.hover, pointer: p.pointer, reducedMotion: r.observed.reducedMotion ? 'reduce' : 'no-preference', colorScheme: r.observed.dark ? 'dark' : 'light' });
    if (!v) { lNone.push(`${r.label}#${r.seq}`); continue; }
    lCompared.push(`${r.label}#${r.seq}`);
    const diff = [...Object.keys(v.expect).filter((k) => r.truth[k] !== v.expect[k]), ...Object.keys(v.expectNeutral).filter((k) => r.neutral[k] !== v.expectNeutral[k])];
    if (diff.length > 0) lBad.push({ label: r.label, seq: r.seq, vector: v.from, diff });
  }
  add('L equal to Lean where a vector exists', lBad.length === 0, lBad.length === 0 ? `${lCompared.length} compared, ${lNone.length} without a vector` : lBad);

  const informative = {
    fractionalVv: device.filter((r) => r.gap.vvWidth !== null && !Number.isInteger(r.gap.vvWidth)).map((r) => `${r.label}#${r.seq}`),
    withoutLeanVector: lNone,
  };
  return { pass: checks.every((c) => c.ok), checks, informative };
}
