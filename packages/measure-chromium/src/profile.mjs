// The pure half of the profile loader (run.mjs reads the file, this checks it). Twin of Fw.Device.Session replayOk / strokeOk /
// ordered / endFrame: test/profile.test.mjs checks it against the "loader" lines of packages/contracts/golden/device/session.jsonl.
// Positions inside a replay are tenth CSS px (integers) in the checks and CSS px in the file. The kind, dropFlags, css and
// user-agent half is the twin of Fw.Measure.Profile, checked against packages/contracts/golden/measure/profile.jsonl.

const NEEDS = ['id', 'hz', 'viewport', 'pinnedDate', 'timezone', 'locale', 'seed', 'load', 'segments'];

/** Lean `strokeOk`: two points or more, all inside the viewport box [0, w10] x [0, h10]. */
export const strokeOk = (w10, h10, st) =>
  st.path.length >= 2 && st.path.every(([x, y]) => x >= 0 && x <= w10 && y >= 0 && y <= h10);

/** Lean `ordered`: each stroke starts at or after the end of the one before. */
export function ordered(strokes) {
  let floor = 0;
  for (const st of strokes) {
    if (floor > st.f0) return false;
    floor = st.f0 + st.path.length;
  }
  return true;
}

/** Lean `endFrame`: the frame after the last stroke, 0 for none. */
export const endFrame = (strokes) => (strokes.length === 0 ? 0 : strokes[strokes.length - 1].f0 + strokes[strokes.length - 1].path.length);

/** Lean `replayOk`: what the loader accepts of a replay. */
export const replayOk = (w10, h10, cap, strokes) =>
  strokes.length > 0 && strokes.every((st) => strokeOk(w10, h10, st)) && ordered(strokes) && endFrame(strokes) <= cap;

/** A loader limit on top of the file's own `input.maxFrames`: 200 s at 60 Hz (the golden's `maxReplayFrames`). */
export const HARD_CAP = 12000;

const tenth = (v) => Math.round(v * 10);

/** Lean `pinned`: harness flags no drop entry may remove. */
export const PINNED = ['--remote-debugging-port=', '--user-data-dir=', '--enable-begin-frame-control', '--run-all-compositor-stages-before-draw'];

/** Lean `Kind.dir`: the directory under packages/measure-chromium/ that holds the files of a kind. */
export const DIRS = { counts: 'profiles', probe: 'probes' };

/** Lean `parseKind`: absent is "counts", an unknown name is null. */
export const parseKind = (k) => (k === undefined || k === null ? 'counts' : k === 'counts' || k === 'probe' ? k : null);

const pre = (d, a) => a.startsWith(d);

/** Lean `dropOk`: `--` and one more character, comparable by prefix with no pinned flag. */
export const dropOk = (d) => d.length > 2 && pre('--', d) && PINNED.every((p) => !pre(d, p) && !pre(p, d));

/** Lean `keep`: every argument that starts with no drop entry, in order. */
export const keep = (args, drops) => args.filter((a) => !drops.some((d) => pre(d, a)));

/** Lean `problem`: the first refusal of a wire record, null when the loader accepts it. */
export function problem(w) {
  if (w.kind === 'counts' && w.dropFlags.length > 0) return 'dropInCounts';
  if (w.kind === 'counts' && w.variants !== 0) return 'variantsInCounts';
  if (w.dropFlags.some((d) => !dropOk(d))) return 'badDrop';
  return w.css === '' ? 'emptyCss' : null;
}

/** Lean `userAgent`: Chrome 156's reduced user agent, Android for a mobile profile, Linux desktop otherwise. */
export const userAgent = (mobile) => (mobile
  ? 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36'
  : 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36');

/** The wire record of a profile file: `css` is null when absent, `variants` the length of `probe.variants`. */
export const wireOf = (profile, kind) => ({
  kind, mobile: !!profile.viewport.mobile, css: typeof profile.css === 'string' ? profile.css : null,
  dropFlags: profile.dropFlags ?? [], variants: profile.probe?.variants?.length ?? 0,
});

/**
 * Check a parsed profile file. Returns { profile, strokes } where strokes is null unless input.mode is "replay", then the
 * strokes in tenth CSS px. Throws with the reason when the file is refused.
 */
export function parseProfile(profile) {
  if (profile === null || typeof profile !== 'object') throw new Error('profile is not an object');
  for (const k of NEEDS) if (profile[k] === undefined) throw new Error(`profile ${profile.id ?? '?'}: missing "${k}"`);
  const vp = profile.viewport;
  for (const k of ['width', 'height', 'dpr']) if (!(vp[k] > 0)) throw new Error(`profile ${profile.id}: viewport.${k} must be positive`);
  if (!Array.isArray(profile.segments) || profile.segments.length === 0) throw new Error(`profile ${profile.id}: no segments`);
  const kind = parseKind(profile.kind);
  if (kind === null) throw new Error(`profile ${profile.id}: kind must be "counts" or "probe", got ${JSON.stringify(profile.kind)}`);
  if (profile.dropFlags !== undefined && !(Array.isArray(profile.dropFlags) && profile.dropFlags.every((d) => typeof d === 'string'))) {
    throw new Error(`profile ${profile.id}: dropFlags must be a list of strings`);
  }
  if (profile.css !== undefined && typeof profile.css !== 'string') throw new Error(`profile ${profile.id}: css must be a string`);
  const why = problem(wireOf(profile, kind));
  if (why !== null) throw new Error(`profile ${profile.id}: refused (${why}); a counts profile has no dropFlags or probe.variants, a drop entry is a flag (--x) that is no pinned harness flag, css is not empty`);
  const mode = profile.input?.mode ?? 'scrollTo';
  const script = profile.segments.filter((s) => s.until === 'script');
  if (mode !== 'replay') {
    if (script.length > 0) throw new Error(`profile ${profile.id}: a "script" segment needs input.mode "replay"`);
    return { profile, kind, strokes: null };
  }
  const inp = profile.input;
  if (script.length !== 1) throw new Error(`profile ${profile.id}: a replay has exactly one "script" segment, found ${script.length}`);
  if (!Array.isArray(inp.strokes)) throw new Error(`profile ${profile.id}: replay without input.strokes`);
  const strokes = inp.strokes.map((s) => ({ f0: s.f0, path: s.path.map(([x, y]) => [tenth(x), tenth(y)]) }));
  const cap = Math.min(inp.maxFrames ?? HARD_CAP, HARD_CAP);
  if (!replayOk(tenth(vp.width), tenth(vp.height), cap, strokes)) {
    throw new Error(`profile ${profile.id}: the replay is refused (empty, a stroke shorter than 2 points or outside ${vp.width}x${vp.height}, strokes out of order, or longer than ${cap} frames)`);
  }
  return { profile, kind, strokes };
}

/**
 * The touch event of every frame of a replay, in CSS px: touchStart at the first point of a stroke, touchMove at each point
 * between, touchEnd at the last. `events[f]` is undefined for a frame without an event.
 */
export function replayEvents(strokes) {
  const events = new Array(endFrame(strokes));
  for (const st of strokes) {
    const last = st.path.length - 1;
    st.path.forEach(([x, y], i) => {
      events[st.f0 + i] = { type: i === 0 ? 'touchStart' : i === last ? 'touchEnd' : 'touchMove', x: x / 10, y: y / 10 };
    });
  }
  return events;
}
