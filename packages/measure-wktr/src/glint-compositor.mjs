// JS stand-in (temporary) of lean/Fw/Device/GlintHoldCompositor.lean, replayed against packages/contracts/golden/device/glint-compositor.jsonl.
import { GH_C, cellNums, numsBand, reportToCells } from './glint-hold.mjs';

export const VC = {
  unread: 'unread', noContrast: 'no-contrast', uninformative: 'uninformative', atFloor: 'within the floor band', partly: 'cuts partly', noCut: 'no cut',
};
const JUDGED = new Set([VC.atFloor, VC.partly, VC.noCut]);
export const judgedC = (v) => JUDGED.has(v);

/** The span `s` is the natural-number difference base - floor; the band is Nums.band. */
export function judgeC(minF, x) {
  const band = numsBand(x);
  const s = Math.max(0, x.b - x.f);
  if (x.nb < minF || x.nf < minF || x.n < minF) return VC.unread;
  if (x.b < x.f + GH_C.minSpread) return VC.noContrast;
  if (s <= 2 * band) return VC.uninformative;
  if (x.h <= x.f + band) return VC.atFloor;
  if (x.b <= x.h + band) return VC.noCut;
  return VC.partly;
}

export function overallC(vs) {
  const js = vs.filter(judgedC);
  if (js.length < GH_C.minValid) return 'inconclusive';
  return js.slice(1).every((v) => v === js[0]) ? js[0] : 'mixed';
}

export function decideJobC(base, comp) {
  const cells = reportToCells(base, comp);
  const one = (c, minF) => {
    const nums = cellNums(c);
    return { nums, band: numsBand(nums), verdict: judgeC(minF, nums) };
  };
  return { idle: one(cells.idle, GH_C.minIdle), flip: one(cells.flip, GH_C.minFlip) };
}

export const jobLineC = (label, kind, d) => {
  const x = d.nums;
  return `glint-compositor ${label} ${kind}: base ${x.b} floor ${x.f} compositor ${x.h} per 100 frames, band ${d.band} spread ${x.spread}, frames base ${x.nb} floor ${x.nf} compositor ${x.n}, verdict ${d.verdict}`;
};

export const glintCompositorLines = (label, base, comp) => {
  const d = decideJobC(base, comp);
  return [jobLineC(label, 'idle', d.idle), jobLineC(label, 'flip', d.flip)];
};

export const overallJobsC = (ds) => ({ idle: overallC(ds.map((d) => d.idle.verdict)), flip: overallC(ds.map((d) => d.flip.verdict)) });
