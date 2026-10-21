// Export of a recorded pass as a CI replay profile, and the packaging of a session for results/phone/<date>/. Pure: the CLI does
// the file I/O. The strokes come from device-session.mjs (Lean Fw.Device.Session `replay`); the profile is checked with the CI
// loader's own parseProfile before it is returned. Raw timestamps never enter the package (felt marks keep position and counts).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { parseProfile } from '../../measure-chromium/src/profile.mjs';
import { replay, replayOk, markFrames, reducePass, compareZones, normalize, PLAN, CONST } from './device-session.mjs';

const BASE = JSON.parse(readFileSync(new URL('../../measure-chromium/profiles/swipe-touch-v1.json', import.meta.url), 'utf8'));
const REST_FRAMES = 10;
const TAIL_FRAMES = 30;
const SLACK_FRAMES = 60;

/** The replay profile of a recorded pass (integer form), in the format of packages/measure-chromium/profiles/*.json. */
export function exportProfile(rec, { id, dpr = BASE.viewport.dpr, about }) {
  const ss = replay(rec.touches, rec.w, rec.h);
  if (ss === null) throw new Error('a second finger was down in this pass: no single-finger replay can be made');
  if (!replayOk(rec.w, rec.h, ss)) throw new Error('the replay is empty or has a stroke the loader refuses');
  const endFrame = ss[ss.length - 1].f0 + ss[ss.length - 1].path.length;
  const profile = {
    id,
    about: about ?? `Replay of one recorded finger gesture (${ss.length} strokes, ${endFrame} frames at ${BASE.hz} Hz): the touch positions of a person's pass, one event per virtual frame, over the first ${endFrame} frames after a short rest; taps (felt marks) are not replayed. Triple-tap marks fall at the frames listed in input.feltFrames. Open loop: the finger path is replayed exactly; the scroll after each lift-off is Chromium's own fling, not iOS momentum, so the positions at input.feltFrames are not the phone's (compare zones, not frames).`,
    hz: BASE.hz,
    viewport: { width: rec.w, height: rec.h, dpr, mobile: true, touch: true },
    pinnedDate: BASE.pinnedDate, timezone: BASE.timezone, locale: BASE.locale, seed: BASE.seed,
    load: BASE.load, zoneHeightPx: BASE.zoneHeightPx,
    input: {
      mode: 'replay', unit: 'css-px', maxFrames: endFrame + SLACK_FRAMES,
      strokes: ss.map((s) => ({ f0: s.f0, path: s.path.map(([x, y]) => [x / 10, y / 10]) })),
      feltFrames: markFrames(rec.touches),
    },
    segments: [{ name: 'rest', dyPerFrame: 0, frames: REST_FRAMES }, { name: 'replay', until: 'script' }, { name: 'tail', dyPerFrame: 0, frames: TAIL_FRAMES }],
  };
  parseProfile(profile);
  return profile;
}

/** The report of a pass as it is packaged: no clock value of the phone, no per-frame data. */
const publicReport = (rep) => ({
  total: rep.total, zones: rep.zones, taps: rep.taps, parts: rep.parts,
  felt: rep.felt.map(({ y, zone, stat }) => ({ y: Math.round(y / 10), zone, stat })),
});

/**
 * The package of a session: per-pass reports and the comparison, from the records (integer form). Keys of the plan steps are
 * kept; time stamps, per-frame series, touch points and the device are left out.
 */
export function packageSession(recs, { date }) {
  const passes = recs.map((r) => ({ arm: r.arm, pass: r.pass, viewport: { w: r.w, h: r.h }, frames: r.t.length, report: reducePass(r) }));
  const cmp = compareZones(passes.map((p) => ({ arm: p.arm, report: p.report })));
  return {
    schema: 'fw.phone.session/1', date,
    plan: PLAN.map(({ step, arm, seconds }) => ({ step, arm, seconds })),
    thresholdsMs: { slow: CONST.slow / 100, bad: CONST.bad / 100 },
    passes: passes.map((p) => ({ ...p, report: publicReport(p.report) })),
    compare: cmp,
  };
}

const norm = (rec) => (rec.schema === 'fw.phone.record.int/1' ? rec : normalize(rec));

/** A saved record (page units, or the integer form of the golden) read as the integer form. */
export const readRecord = (file) => norm(JSON.parse(readFileSync(file, 'utf8')));

/** Write the replay profile of one saved record to `out`. */
export function writeProfile(file, out, { id, dpr }) {
  const profile = exportProfile(readRecord(file), { id, dpr });
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, JSON.stringify(profile, null, 2) + '\n');
  return profile;
}

/** Write summary.json and summary.md of a session into `dir` (results/phone/<date>/); returns the package. */
export function writePackage(files, dir, { date }) {
  const pkg = packageSession(files.map(readRecord), { date });
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'summary.json'), JSON.stringify(pkg, null, 1) + '\n');
  writeFileSync(join(dir, 'summary.md'), sessionMarkdown(pkg));
  return pkg;
}

/** A small markdown table of the comparison: counts over 50 ms per 100 moving frames, per pass, and the verdict per arm. */
export function sessionMarkdown(pkg) {
  const f = (v) => (v / 100).toFixed(2);
  const lines = [`# Phone session ${pkg.date}`, '', 'Moving frames over 50 ms per 100 (lower is better), per pass; verdict against the original passes (an arm wins only beyond their spread).', '',
    '| zone | original | spread | arm | passes | verdict |', '| --- | --- | --- | --- | --- | --- |'];
  for (const z of pkg.compare) {
    const orig = z.original.map(f).join(' / ');
    if (z.arms.length === 0) lines.push(`| ${z.zone} | ${orig} | ${f(z.spread)} | | | |`);
    for (const a of z.arms) lines.push(`| ${z.zone} | ${orig} | ${f(z.spread)} | ${a.arm} | ${a.per50.map(f).join(' / ')} | ${a.verdict} |`);
  }
  lines.push('', '| arm | pass | frames | taps | felt marks | longest ms |', '| --- | --- | --- | --- | --- | --- |');
  for (const p of pkg.passes) lines.push(`| ${p.arm} | ${p.pass} | ${p.frames} | ${p.report.taps} | ${p.report.felt.length} | ${(p.report.total.longest / 100).toFixed(1)} |`);
  return lines.join('\n') + '\n';
}
