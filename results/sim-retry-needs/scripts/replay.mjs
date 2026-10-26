// Replays the retry and tab gates of packages/measure-webkit/src/sim-host.mjs (Lean SimHost, golden-checked) over the
// decisions of pieces.json. usage: node replay.mjs <repo root> <pieces.json> <out.json>
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const [root, piecesPath, outPath] = process.argv.slice(2);
const sh = await import(pathToFileURL(join(root, 'packages/measure-webkit/src/sim-host.mjs')).href);
const jobs = JSON.parse(readFileSync(piecesPath, 'utf8'));
const tabWaitMs = sh.NAV_WAIT_MS * 8;
const arms = {
  derived: { scroll: sh.SCROLL_NEED_S, pass: sh.PASS_NEED_S, tab: true },
  derivedNoTab: { scroll: sh.SCROLL_NEED_S, pass: sh.PASS_NEED_S, tab: false },
  shipped: { scroll: 589, pass: 436, tab: false },
  derivedFromServing: { scroll: sh.SCROLL_NEED_S, pass: sh.PASS_NEED_S, tab: true, fromServing: true },
};
const out = { needs: { scrollNeedS: sh.SCROLL_NEED_S, passNeedS: sh.PASS_NEED_S, tabNeedS: sh.tabNeedS(tabWaitMs), shipped: { scroll: 589, pass: 436 } }, arms: {} };
for (const [name, a] of Object.entries(arms)) {
  const refused = [];
  const byKind = { scroll: 0, pass: 0, tab: 0 };
  for (const j of jobs) {
    const b = sh.gateBoundS(35 * j.sessions);
    const at = (d) => d.at - (a.fromServing ? j.servingOffS : 0);
    const first = j.decisions.find((d) => (d.kind === 'tab'
      ? a.tab && !sh.tabFits(at(d), tabWaitMs, b)
      : !sh.afterFailure(d.tries ?? 1, j.maxTries, at(d), a[d.kind], b)));
    if (first) { refused.push({ job: j.job, run: j.run, kind: first.kind, atS: at(first), boundS: b }); byKind[first.kind]++; }
  }
  out.arms[name] = { jobs: jobs.length, refused: refused.length, byKind, list: refused };
  console.log(name, 'refused', refused.length, 'of', jobs.length, JSON.stringify(byKind));
}
const dec = (k) => jobs.reduce((n, j) => n + j.decisions.filter((d) => d.kind === k).length, 0);
out.decisions = { scroll: dec('scroll'), pass: dec('pass'), tab: dec('tab'), jobsWithRetry: jobs.filter((j) => j.decisions.some((d) => d.kind !== 'tab')).length };
console.log('decisions', JSON.stringify(out.decisions));
writeFileSync(outPath, JSON.stringify(out, null, 1) + '\n');
