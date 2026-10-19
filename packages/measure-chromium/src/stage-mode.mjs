// Container and workflow twin of Lean Fw.Site.StageMode (part-page plan, accept and read decisions), checked against
// packages/contracts/golden/parts/stage-mode.jsonl in test/stage-mode.test.mjs. Rules only: the caller refuses the run.
import { viewportFaithful } from './viewport.mjs';

export function pairs(q) {
  const s = q.startsWith('?') ? q.slice(1) : q;
  return s.split('&').filter((p) => p !== '').map((p) => { const i = p.indexOf('='); return i < 0 ? [p, ''] : [p.slice(0, i), p.slice(i + 1)]; });
}

export const onlySearch = (q) => pairs(q).some(([k]) => k === 'only');
export const hasStage = (q) => pairs(q).some(([k]) => k === 'stage');
export const plannedEnv = (p) => [0, p.w, p.h];
export const stageParam = (p) => `vw:${p.w},vh:${p.h}`;

export function planSearch(q, p) {
  if (!onlySearch(q)) return q;
  return hasStage(q) ? null : `${q}&stage=${stageParam(p)}`;
}

const sameEnv = (a, b) => a !== null && a !== undefined && a.length === 3 && a.every((v, i) => v === b[i]);

export function accepts(q, p, r) {
  if (!r.hydrated || r.errors !== 0) return false;
  if (onlySearch(q)) return r.mode === 'client-render' && sameEnv(r.stage, plannedEnv(p)) && r.missing === 0;
  return r.mode === 'hydrate';
}

export const scrollRead = (q) => (onlySearch(q) ? 'scrollTop' : 'scrollY');
// The gate decides on the real frame size (native innerWidth/innerHeight captured before the page pins them), on a stage page as on a
// whole page; the pinned sizes and clientWidth/clientHeight are recorded, never gated (Lean StageMode.gateSize, viewportGate).
export const gateSize = (f) => f.real;
export const viewportGate = (profile, f) => viewportFaithful(profile, gateSize(f));

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const [cmd, q, w, h] = process.argv.slice(2);
  if (cmd !== 'plan' || q === undefined || !/^[1-9][0-9]*$/.test(w ?? '') || !/^[1-9][0-9]*$/.test(h ?? '')) {
    console.error('usage: node stage-mode.mjs plan <search> <width> <height>');
    process.exit(2);
  }
  const r = planSearch(q, { w: +w, h: +h });
  if (r === null) { console.error('refused: the search already names a stage'); process.exit(1); }
  process.stdout.write(r);
}
