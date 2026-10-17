// Pass rule of the phone session. Input: the records the probe page POSTed from the real iPhone (`device`), the iOS Simulator
// records of the same lane (`sim`, iPhone, from evidence.json), and the Lean-generated gen file. Decisions are Lean's (fwcore):
// W is Lean's reach model on the reported facts (judge.mjs modelCheck); L compares with Lean's vectors; X, S and T compare
// records with each other or with a vector value.
//
//   W (WebKit cells unreachable on the device):  Lean's model holds on every record (gate.reach on the media width and the
//        primary pair each record reports; pass = no record is a fraction or a non-Apple pair)                [Fw.Gate.Reach]
//   X (same pointer facts as the Simulator):  forall r in device (no mouse label), the 14 pointer facts of r other than touchArm
//        equal the Simulator iPhone's (load record); records labelled "mouse..." differ only in any-hover / any-pointer
//   T (touchArm at the record's own width):  touchArm = (hover: none) and (pointer: coarse) and (width <= 1200) depends on the
//        width, so it is NOT compared with the Simulator's 430 px record: it is compared with Lean's vector at the record's own
//        (media width, screen width, hover, pointer, motion, scheme) as  pair = (none, coarse) and vector.wLe1200;
//        records without a vector are listed, not judged
//   S (same width, same answers):  r and a Simulator record with equal (media width, screen width, hover, pointer): the 30
//        conditions and 4 neutral queries are equal
//   L (Lean):  when the matrix has a vector for (media width, screen width, hover, pointer, reduced motion, scheme), the 30
//        conditions and 4 neutral queries equal it; records without a vector are listed, not judged
//   pass = W and X and T and S and L, with at least one record.
// Informative only (never fails): records with a non-whole visualViewport.width (a fraction existed and was rounded) and
// records without a Lean vector.
import { expectFor } from '../spec.mjs';
import { modelCheck, pairOf } from './judge.mjs';

const ANY = ['anyHoverHover', 'anyHoverNone', 'anyPointerFine', 'anyPointerCoarse', 'anyPointerNone'];
const eqObj = (a, b, keys) => keys.every((k) => a[k] === b[k]);
const own = (r) => {
  const p = pairOf(r.gap.pointer);
  return { width: r.gap.mediaWidth, deviceWidth: r.gap.screenWidth, hover: p.hover, pointer: p.pointer, reducedMotion: r.observed.reducedMotion ? 'reduce' : 'no-preference', colorScheme: r.observed.dark ? 'dark' : 'light' };
};

export function judgeDevice({ device, sim, gen }) {
  const checks = [];
  const add = (id, ok, detail) => checks.push({ id, ok, detail });
  if (device.length === 0) return { pass: false, checks: [{ id: 'records', ok: false, detail: 'no device records' }], informative: {} };
  const simLoads = sim.filter((r) => r.gap);
  const simRef = simLoads[0] ?? null;

  const w = modelCheck('webkit-apple', device.map((r) => ({ ...r, req: { label: r.label, seq: r.seq } })));
  add('W Lean reach model holds (whole media width, primary pair)', w.verdict === 'pass', w.verdict === 'pass' ? `${device.length} records` : w);

  const allKeys = Object.keys(device[0].gap.pointer).filter((k) => k !== 'touchArm');
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

  const tBad = [], tCompared = [], tNone = [];
  for (const r of device) {
    const e = own(r);
    const v = expectFor(gen, e);
    if (!v) { tNone.push(`${r.label}#${r.seq}`); continue; }
    tCompared.push(`${r.label}#${r.seq}`);
    const expected = e.hover === 'none' && e.pointer === 'coarse' && v.expect.wLe1200 === true;
    if (r.gap.pointer.touchArm !== expected) tBad.push({ label: r.label, seq: r.seq, vector: v.from, expected, got: r.gap.pointer.touchArm });
  }
  add("T touchArm equals Lean at the record's own width", tBad.length === 0, tBad.length === 0 ? `${tCompared.length} compared, ${tNone.length} without a vector` : tBad);

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
    const v = expectFor(gen, own(r));
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
