// The pure half of the profile loader (run.mjs reads the file, this checks it). Twin of Fw.Device.Session replayOk / strokeOk /
// ordered / endFrame: test/profile.test.mjs checks it against the "loader" lines of packages/contracts/golden/device/session.jsonl.
// Positions inside a replay are tenth CSS px (integers) in the checks and CSS px in the file.

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
  const mode = profile.input?.mode ?? 'scrollTo';
  const script = profile.segments.filter((s) => s.until === 'script');
  if (mode !== 'replay') {
    if (script.length > 0) throw new Error(`profile ${profile.id}: a "script" segment needs input.mode "replay"`);
    return { profile, strokes: null };
  }
  const inp = profile.input;
  if (script.length !== 1) throw new Error(`profile ${profile.id}: a replay has exactly one "script" segment, found ${script.length}`);
  if (!Array.isArray(inp.strokes)) throw new Error(`profile ${profile.id}: replay without input.strokes`);
  const strokes = inp.strokes.map((s) => ({ f0: s.f0, path: s.path.map(([x, y]) => [tenth(x), tenth(y)]) }));
  const cap = Math.min(inp.maxFrames ?? HARD_CAP, HARD_CAP);
  if (!replayOk(tenth(vp.width), tenth(vp.height), cap, strokes)) {
    throw new Error(`profile ${profile.id}: the replay is refused (empty, a stroke shorter than 2 points or outside ${vp.width}x${vp.height}, strokes out of order, or longer than ${cap} frames)`);
  }
  return { profile, strokes };
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
