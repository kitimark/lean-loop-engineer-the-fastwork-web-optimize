// The probe inputs of a ci/* push, read from the head commit message. Twin of Fw.Ci.Trigger.pushProbe
// (lean/Fw/Ci/Trigger.lean, task ci-push-probe-inputs), checked against the `probe` lines of
// packages/contracts/golden/ci/triggers.jsonl by trajectory-line.test.mjs.
//   EVENT=push|workflow_dispatch HEAD_MSG=<message> node .github/scripts/trajectory-line.mjs
// prints engines/fw/preset/widths/debug/source as `key=value` lines (for $GITHUB_OUTPUT); a refused line exits 1 with the reason.
import { pickWidths } from '../../packages/gate-breakpoints/src/trajectory/reduce.mjs';

const KW = '[trajectory';
const KEYS = ['fw', 'preset', 'widths', 'engines', 'debug'];
const ENGINES = ['both', 'chromium', 'playwright-webkit'];
/** Lean `probeDebugs`: the page recorders a push may ask for. */
const DEBUGS = ['nav-transition'];
const isWs = (c) => c === ' ' || c === '\t' || c === '\r';
const trim = (s) => {
  let a = 0;
  let b = s.length;
  while (a < b && isWs(s[a])) a++;
  while (b > a && isWs(s[b - 1])) b--;
  return s.slice(a, b);
};
const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());
const isCand = (l) => lowerAscii(trim(l)).startsWith(KW);
const valueOk = /^[A-Za-z0-9.:,_@-]+$/;

export const DEFAULT = { engines: 'both', fw: '', preset: '', widths: '', debug: '' };

function addTok(acc, t) {
  const i = t.indexOf('=');
  if (i < 0) return { error: `token '${t}' has no '='` };
  const k = t.slice(0, i);
  const v = t.slice(i + 1);
  if (!KEYS.includes(k)) return { error: `unknown key '${k}' (keys: fw, preset, widths, engines, debug)` };
  if (acc.some(([a]) => a === k)) return { error: `key '${k}' given twice` };
  if (v === '') return { error: `key '${k}' has no value` };
  if (!valueOk.test(v)) return { error: `the value of '${k}' has a character outside A-Z a-z 0-9 . : , _ @ -` };
  return { ok: [...acc, [k, v]] };
}

function build(kv) {
  const g = (k, d) => (kv.find(([a]) => a === k) ?? [k, d])[1];
  const p = { engines: g('engines', 'both'), fw: g('fw', ''), preset: g('preset', ''), widths: g('widths', ''), debug: g('debug', '') };
  if (p.fw !== '' && p.preset !== '') return { error: 'fw and preset are exclusive' };
  if (!ENGINES.includes(p.engines)) return { error: 'engines must be both, chromium or playwright-webkit' };
  if (pickWidths(p.widths) === null) return { error: 'widths must be a comma list of 390, 640, 641, 1280 without repeats' };
  if (p.debug !== '' && !DEBUGS.includes(p.debug)) return { error: 'debug must be nav-transition' };
  return { ok: p };
}

function parseOne(line) {
  const t = trim(line);
  if (!t.endsWith(']')) return { error: "the line has no closing ']'" };
  const body = t.slice(KW.length, -1);
  if (!(body === '' || body[0] === ' ' || body[0] === '\t')) return { error: 'expected a space after [trajectory' };
  let acc = [];
  for (const tok of body.split(' ').filter((w) => w !== '')) {
    const r = addTok(acc, tok);
    if (r.error) return r;
    acc = r.ok;
  }
  return build(acc);
}

/** Lean `parseLine`: { kind: 'absent' } | { kind: 'inputs', p } | { kind: 'refused', why }. */
export function parseLine(msg) {
  const cands = msg.split('\n').filter(isCand);
  if (cands.length === 0) return { kind: 'absent' };
  if (cands.length > 1) return { kind: 'refused', why: 'more than one [trajectory ...] line' };
  const r = parseOne(cands[0]);
  return r.error ? { kind: 'refused', why: r.error } : { kind: 'inputs', p: r.ok };
}

/** Lean `pushProbe`: the golden `result` shape. */
export function pushProbe(lane, msg) {
  const l = parseLine(msg);
  if (l.kind === 'refused') return { kind: 'refused', why: l.why };
  if (l.kind === 'absent') return lane ? { kind: 'run', ...DEFAULT } : { kind: 'notAsked' };
  return lane ? { kind: 'run', ...l.p } : { kind: 'needsLane' };
}

/** Lean `hasFrames`: the frames token `[frames:` in the message, ASCII case ignored. */
export const hasFrames = (msg) => lowerAscii(msg).includes('[frames:');

/** Lean `recorderOf`: the recorder the probe line asks for, '' for none, a refused line or no line. */
export const recorderOf = (msg) => {
  const r = pushProbe(true, msg);
  return r.kind === 'run' ? r.debug : '';
};

/** Lean `appleRuns`: does the macOS leg run (ev is `workflow_dispatch` or `push`; appleN the macOS legs of the plan). */
export const appleRuns = (ev, msg, appleN) =>
  appleN !== 0 && (ev !== 'push' || hasFrames(msg) || recorderOf(msg) !== '');

if (import.meta.url === `file://${process.argv[1]}`) {
  const e = process.env;
  if (process.argv[2] === 'apple') {
    // The plan step asks whether the macOS leg runs; the answer is the `apple_run` output.
    process.stdout.write(`apple_run=${appleRuns(e.EVENT ?? '', e.HEAD_MSG ?? '', Number(e.APPLE_N ?? '0'))}\n`);
    process.exit(0);
  }
  if ((e.EVENT ?? '') !== 'push') {
    // A dispatch carries its inputs itself; they pass through unchanged.
    const p = { engines: e.ENGINES || 'both', fw: e.FW ?? '', preset: e.PRESET ?? '', widths: e.WIDTHS ?? '', debug: '', source: 'dispatch' };
    process.stdout.write(Object.entries(p).map(([k, v]) => `${k}=${v}\n`).join(''));
  } else {
    // A push that reached this job asked for the lane (the guard `if:` is the Intent decision), so lane = true.
    const msg = e.HEAD_MSG ?? '';
    const r = pushProbe(true, msg);
    if (r.kind === 'refused') {
      console.error(`trajectory-line: refused: ${r.why}`);
      process.exit(1);
    }
    const source = parseLine(msg).kind === 'inputs' ? 'commit-line' : 'defaults';
    process.stdout.write(['engines', 'fw', 'preset', 'widths', 'debug'].map((k) => `${k}=${r[k]}\n`).join('') + `source=${source}\n`);
  }
}
