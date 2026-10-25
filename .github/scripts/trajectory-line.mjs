// The probe inputs of a ci/* push, read from the head commit message. Twin of Fw.Ci.Trigger.pushProbe
// (lean/Fw/Ci/Trigger.lean, task ci-push-probe-inputs), checked against the `probe` lines of
// packages/contracts/golden/ci/triggers.jsonl by trajectory-line.test.mjs.
//   EVENT=push|workflow_dispatch HEAD_MSG=<message> node .github/scripts/trajectory-line.mjs
// prints engines/fw/preset/widths/debug/diagnostic/source as `key=value` lines (for $GITHUB_OUTPUT); a refused line exits 1 with the reason.
// The mark rule (task traj-dispatch-push-lane) binds the trajectory lane only (Lean ProbeLane): the smoothness workflow reads the same line
// but its verdict is at 390,1280, so it keeps the widths allowlist and an unknown token `diagnostic`; a `[frames:` message is a frames run,
// exempt. Each workflow passes its lane as LANE=trajectory|smoothness. In the trajectory lane a run is verdict (walks all four widths) or diagnostic (the bare word `diagnostic` on the
// line, the boolean `diagnostic` dispatch input; any nonempty subset). `dispatchIn` is the twin of Fw.Gate.Trajectory.Dispatch.dispatchIn,
// checked against golden/gate/trajectory-dispatch.jsonl; the push line, the workflow input and `fw run` all follow that one Lean rule.
import { ALLOWED_WIDTHS, pickWidths } from '../../packages/gate-breakpoints/src/trajectory/reduce.mjs';

const KW = '[trajectory';
const KEYS = ['fw', 'preset', 'widths', 'engines', 'debug'];
const ENGINES = ['both', 'chromium', 'playwright-webkit'];
const DEBUGS = ['nav-transition', 'root-events'];
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
/** Lean `diagnosticWord`: the bare word that marks the run diagnostic. */
const DIAG = 'diagnostic';

/** Lean `ProbeLane`. */
export const LANES = ['trajectory', 'smoothness', 'frames'];
/** Lean `ProbeLane.marked`: does the mark rule hold the lane to the widths? */
const marked = (lane) => lane === 'trajectory';
/** Lean `ProbeLane.word`: does the lane know the bare word `diagnostic`? */
const wordOf = (lane) => lane !== 'smoothness';

export const DEFAULT = { engines: 'both', fw: '', preset: '', widths: '', debug: '', diagnostic: false };

/** Lean `Dispatch.dispatch`: none is empty, a width outside the lane or a repeated one is bad, a verdict run short of a lane width is scoped. */
export function dispatch(mark, ws) {
  if (ws.length === 0) return { kind: 'refused', why: 'emptyWidths' };
  if (!ws.every((w) => ALLOWED_WIDTHS.includes(w)) || new Set(ws).size !== ws.length) return { kind: 'refused', why: 'badInput' };
  if (mark === 'verdict' && !ALLOWED_WIDTHS.every((w) => ws.includes(w))) return { kind: 'refused', why: 'scopedVerdict' };
  return { kind: 'accepted', widths: ws };
}

/** Lean `Dispatch.dispatchIn`: the decision on a mark ('verdict' | 'diagnostic') and the `widths` input. */
export function dispatchIn(mark, s) {
  const ws = pickWidths(s);
  return ws === null ? { kind: 'refused', why: 'badInput' } : dispatch(mark, ws);
}

/** Lean `Dispatch.Why.text`: the words every entry point shares. */
export function whyText(why, s) {
  if (why === 'emptyWidths') return 'no widths to walk';
  if (why === 'badInput') return 'widths must be a comma list of 390, 640, 641, 1280 without repeats';
  return `widths ${s} is a subset, and a verdict run (stored, judged) walks all four widths (${ALLOWED_WIDTHS.join(',')}); a run short of a width gets no verdict`;
}

/** The refusal of the `widths` input of a run of this mark, or null when the rule accepts it. `hint` says how this entry point marks a run diagnostic. */
export function walkRefusal(diagnostic, widths, hint) {
  const d = dispatchIn(diagnostic ? 'diagnostic' : 'verdict', widths);
  if (d.kind === 'accepted') return null;
  return whyText(d.why, widths) + (d.why === 'scopedVerdict' ? `; ${hint}` : '');
}

function addTok(lane, acc, t) {
  const i = t.indexOf('=');
  if (i < 0) {
    if (!(wordOf(lane) && t === DIAG)) return { error: `token '${t}' has no '='` };
    if (acc.some(([a]) => a === DIAG)) return { error: `key '${DIAG}' given twice` };
    return { ok: [...acc, [DIAG, 'true']] };
  }
  const k = t.slice(0, i);
  const v = t.slice(i + 1);
  if (wordOf(lane) && k === DIAG) return { error: 'diagnostic is a bare word, not diagnostic=...' };
  if (!KEYS.includes(k)) return { error: `unknown key '${k}' (keys: fw, preset, widths, engines, debug${wordOf(lane) ? ', diagnostic' : ''})` };
  if (acc.some(([a]) => a === k)) return { error: `key '${k}' given twice` };
  if (v === '') return { error: `key '${k}' has no value` };
  if (!valueOk.test(v)) return { error: `the value of '${k}' has a character outside A-Z a-z 0-9 . : , _ @ -` };
  return { ok: [...acc, [k, v]] };
}

/** Lean `ProbeIn.widthsOk`/`widthsWhy`: the refusal of the widths of a run in this lane, or null. */
function widthsRefusal(lane, diagnostic, widths, hint) {
  if (marked(lane)) return walkRefusal(diagnostic, widths, hint);
  return pickWidths(widths) === null ? whyText('badInput', widths) : null;
}

function build(lane, kv) {
  const g = (k, d) => (kv.find(([a]) => a === k) ?? [k, d])[1];
  const p = { engines: g('engines', 'both'), fw: g('fw', ''), preset: g('preset', ''), widths: g('widths', ''), debug: g('debug', ''), diagnostic: wordOf(lane) && kv.some(([a]) => a === DIAG) };
  if (p.fw !== '' && p.preset !== '') return { error: 'fw and preset are exclusive' };
  if (!ENGINES.includes(p.engines)) return { error: 'engines must be both, chromium or playwright-webkit' };
  const refused = widthsRefusal(lane, p.diagnostic, p.widths, 'add the word diagnostic to the line for a run read by hand');
  if (refused !== null) return { error: refused };
  if (p.debug !== '' && !DEBUGS.includes(p.debug)) return { error: 'debug must be nav-transition or root-events' };
  return { ok: p };
}

function parseOne(lane, line) {
  const t = trim(line);
  if (!t.endsWith(']')) return { error: "the line has no closing ']'" };
  const body = t.slice(KW.length, -1);
  if (!(body === '' || body[0] === ' ' || body[0] === '\t')) return { error: 'expected a space after [trajectory' };
  let acc = [];
  for (const tok of body.split(' ').filter((w) => w !== '')) {
    const r = addTok(lane, acc, tok);
    if (r.error) return r;
    acc = r.ok;
  }
  return build(lane, acc);
}

/** Lean `parseLine`: { kind: 'absent' } | { kind: 'inputs', p } | { kind: 'refused', why }, the line read in `lane`. */
export function parseLineIn(lane, msg) {
  const cands = msg.split('\n').filter(isCand);
  if (cands.length === 0) return { kind: 'absent' };
  if (cands.length > 1) return { kind: 'refused', why: 'more than one [trajectory ...] line' };
  const r = parseOne(lane, cands[0]);
  return r.error ? { kind: 'refused', why: r.error } : { kind: 'inputs', p: r.ok };
}

/** Lean `hasFrames`: the frames token `[frames:` in the message, ASCII case ignored. */
export const hasFrames = (msg) => lowerAscii(msg).includes('[frames:');

/** Lean `effLane`: the trajectory workflow reads a message with the frames token as a frames run. */
export const effLane = (wf, msg) => (wf === 'trajectory' && hasFrames(msg) ? 'frames' : wf);

/** Lean `pushProbe`: the golden `result` shape. `wf` is the workflow's lane, `lane` whether the commit asks for the lane token. */
export function pushProbeIn(wf, lane, msg) {
  const l = parseLineIn(effLane(wf, msg), msg);
  if (l.kind === 'refused') return { kind: 'refused', why: l.why };
  if (l.kind === 'absent') return lane ? { kind: 'run', ...DEFAULT } : { kind: 'notAsked' };
  return lane ? { kind: 'run', ...l.p } : { kind: 'needsLane' };
}

/** Lean `pushProbe .trajectory`: the trajectory-probe workflow's reading of a push (the mark rule applies; a `[frames:` message is exempt). */
export const pushProbe = (lane, msg) => pushProbeIn('trajectory', lane, msg);

/** Lean `parseLine (effLane .trajectory msg) msg`: the line as the trajectory workflow reads it. */
export const parseLine = (msg) => parseLineIn(effLane('trajectory', msg), msg);

/** Lean `recorderOf`: the recorder the probe line asks for, '' for none, a refused line or no line. */
export const recorderOf = (msg) => {
  const r = pushProbeIn('trajectory', true, msg);
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
  const wf = e.LANE || 'trajectory';
  if (!LANES.includes(wf)) {
    console.error(`trajectory-line: refused: LANE must be one of ${LANES.join(', ')}`);
    process.exit(1);
  }
  if ((e.EVENT ?? '') !== 'push') {
    // A dispatch carries its inputs itself; they pass through unchanged, after the mark rule on its `widths` and `diagnostic` inputs.
    const diagnostic = (e.DIAGNOSTIC ?? '') === 'true';
    const refused = widthsRefusal(wf, diagnostic, e.WIDTHS ?? '', 'set the diagnostic input to true for a run read by hand (fw run --trajectory --diagnostic)');
    if (refused !== null) {
      console.error(`trajectory-line: refused: ${refused}`);
      process.exit(1);
    }
    const p = { engines: e.ENGINES || 'both', fw: e.FW ?? '', preset: e.PRESET ?? '', widths: e.WIDTHS ?? '', debug: '', diagnostic, source: 'dispatch' };
    process.stdout.write(Object.entries(p).map(([k, v]) => `${k}=${v}\n`).join(''));
  } else {
    // A push that reached this job asked for the lane (the guard `if:` is the Intent decision), so lane = true.
    const msg = e.HEAD_MSG ?? '';
    const r = pushProbeIn(wf, true, msg);
    if (r.kind === 'refused') {
      console.error(`trajectory-line: refused: ${r.why}`);
      process.exit(1);
    }
    const source = parseLineIn(effLane(wf, msg), msg).kind === 'inputs' ? 'commit-line' : 'defaults';
    process.stdout.write(['engines', 'fw', 'preset', 'widths', 'debug', 'diagnostic'].map((k) => `${k}=${r[k]}\n`).join('') + `source=${source}\n`);
  }
}
