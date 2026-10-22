import { replayStrokes, t0Of, singleFinger, zoneOf, yAt } from './device-session.mjs';

export const TICK_MAX = 16;
export const LIM = Object.freeze({ pos: 10, time: 1700, speedPct: 10, startGap: 5000, window: 5000 });

const fdiv = (a, b) => Math.floor(a / b);
export const px = (v) => fdiv(v + 5, 10);
export const ms = (t) => fdiv(t + 50, 100);


export function swipeOf(t0, s) {
  if (s.length === 0) return null;
  const a = s[0], z = s[s.length - 1];
  return { start: a[0] - t0, lift: z[0] - a[0], s: s.filter((e) => e[1] !== 'e').map((e) => [e[0] - a[0], e[2], e[3]]) };
}

export function swipesOf(touches) {
  const ss = replayStrokes(touches);
  const t0 = t0Of(ss);
  return ss.map((s) => swipeOf(t0, s)).filter((s) => s !== null);
}

export const ofTouches = (id, touches, w, h) => (singleFinger(touches) ? { id, w, h, load: 'warm', swipes: swipesOf(touches) } : null);


export function chunks(n) {
  const out = [];
  let r = n;
  while (r > TICK_MAX) { out.push(TICK_MAX); r -= TICK_MAX; }
  out.push(r);
  return out;
}
const gap = (a, b) => Math.max(0, b - a);
const pauseRun = (n) => (n === 0 ? [] : chunks(n).map((c) => ['p', c]));

function emit(pts, i, fin) {
  const out = [];
  for (let k = i; k < pts.length; k++) {
    const p = pts[k];
    const g = gap(p.m, k + 1 < pts.length ? pts[k + 1].m : fin);
    const d = Math.min(g, TICK_MAX);
    out.push(['m', p.x, p.y, d], ...pauseRun(g - d));
  }
  return out;
}

function swipeActs(pts, fin) {
  const f = pts[0];
  const first = gap(f.m, pts.length > 1 ? pts[1].m : fin);
  return [['m', f.x, f.y, 0], ['d'], ...pauseRun(first), ...emit(pts, 1, fin), ['u']];
}

const swipePts = (s) => s.s.map(([t, x, y]) => ({ m: ms(s.start + t), x: px(x), y: px(y) }));
const swipeEnd = (s) => ms(s.start + s.lift);

export function compile(p) {
  const ss = p.swipes.filter((s) => s.s.length > 0);
  if (ss.length === 0) return [];
  let prev = swipePts(ss[0])[0].m;
  const out = [];
  for (const s of ss) {
    const pts = swipePts(s);
    out.push(...pauseRun(gap(prev, pts[0].m)), ...swipeActs(pts, swipeEnd(s)));
    prev = swipeEnd(s);
  }
  return out;
}

/**
 * The compiled actions cut at the swipes (Lean `Fw.Device.Replay.pieces`): one piece per swipe, its lead-in pause run first, the finger
 * up at its end. The pieces joined are `compile(p)`.
 */
export function pieces(p) {
  const ss = p.swipes.filter((s) => s.s.length > 0);
  if (ss.length === 0) return [];
  let prev = swipePts(ss[0])[0].m;
  return ss.map((s) => {
    const pts = swipePts(s);
    const pc = [...pauseRun(gap(prev, pts[0].m)), ...swipeActs(pts, swipeEnd(s))];
    prev = swipeEnd(s);
    return pc;
  });
}

/** The time a /actions call of a piece that takes `d` ms may take before the client calls it hung (Lean `pieceTimeoutMs`). */
export const pieceTimeoutMs = (d) => 2 * d + 10000;

export function w3c(acts) {
  const one = (a) => {
    switch (a[0]) {
      case 'm': return { type: 'pointerMove', duration: a[3], x: a[1], y: a[2], origin: 'viewport' };
      case 'd': return { type: 'pointerDown', button: 0 };
      case 'u': return { type: 'pointerUp', button: 0 };
      default: return { type: 'pause', duration: a[1] };
    }
  };
  return { actions: [{ type: 'pointer', id: 'finger', parameters: { pointerType: 'touch' }, actions: acts.map(one) }] };
}

export const actsMs = (acts) => acts.reduce((t, a) => t + (a[0] === 'm' ? a[3] : a[0] === 'p' ? a[1] : 0), 0);

/**
 * The touch events a WebKit touch source makes of compiled actions (WebKit SimulatedInputDispatcher.cpp:315-345@862f17d): down is a
 * start, up an end, a move an event only while down and only when the whole-px location changes. Returns [ms, 's'|'m'|'e', x, y] in
 * page units. Test double of the phone, not a measurement.
 */
export function simulateEvents(acts) {
  const out = [];
  let t = 0, x = 0, y = 0, down = false;
  for (const a of acts) {
    if (a[0] === 'm') {
      if (down && (a[1] !== x || a[2] !== y)) out.push([t, 'm', a[1], a[2]]);
      x = a[1]; y = a[2]; t += a[3];
    } else if (a[0] === 'd') { down = true; out.push([t, 's', x, y]); }
    else if (a[0] === 'u') { down = false; out.push([t, 'e', x, y]); }
    else t += a[1];
  }
  return out;
}


const same = (e, prev) => px(e[1]) === prev[0] && px(e[2]) === prev[1];
function keep(prev, es) {
  const out = [];
  for (const e of es) { if (same(e, prev)) continue; out.push(e); prev = [px(e[1]), px(e[2])]; }
  return out;
}
const lastPos = (s) => (s.s.length === 0 ? [0, 0] : [s.s[s.s.length - 1][1], s.s[s.s.length - 1][2]]);

export function expected(s) {
  if (s.s.length === 0) return [];
  const [f, ...r] = s.s;
  return [f, ...keep([px(f[1]), px(f[2])], r), [s.lift, ...lastPos(s)]];
}

export const seen = (s) => (s.s.length === 0 ? [] : [...s.s, [s.lift, ...lastPos(s)]]);

export function liftVel(window, evs) {
  if (evs.length === 0) return [0, 0, 1];
  const z = evs[evs.length - 1];
  const a = evs.find((e) => z[0] - window <= e[0]);
  return a ? [z[1] - a[1], z[2] - a[2], Math.max(1, z[0] - a[0])] : [0, 0, 1];
}

const zip = (a, b) => a.slice(0, Math.min(a.length, b.length)).map((x, i) => [x, b[i]]);
const eventsOk = (a, b) => expected(a).length === seen(b).length;
const posOk = (lim, a, b) => zip(expected(a), seen(b)).every(([e, r]) => Math.abs(r[1] - e[1]) <= lim.pos && Math.abs(r[2] - e[2]) <= lim.pos);
const timeOk = (lim, a, b) => zip(expected(a), seen(b)).every(([e, r]) => Math.abs(r[0] - e[0]) <= lim.time);
function speedOk(lim, a, b) {
  const [ax, ay, at] = liftVel(lim.window, expected(a));
  const [bx, by, bt] = liftVel(lim.window, seen(b));
  const [AX, AY, AT, BX, BY, BT] = [ax, ay, at, bx, by, bt].map(BigInt);
  const ex = BX * AT - AX * BT, ey = BY * AT - AY * BT;
  return 10000n * (ex * ex + ey * ey) <= BigInt(lim.speedPct) * BigInt(lim.speedPct) * ((AX * BT) ** 2n + (AY * BT) ** 2n);
}
const startOk = (lim, a, b) => Math.abs(b.start - a.start) <= lim.startGap;

export function conjuncts(lim, a, b) {
  const c = { eventsOk: eventsOk(a, b), posOk: posOk(lim, a, b), timeOk: timeOk(lim, a, b), speedOk: speedOk(lim, a, b), startOk: startOk(lim, a, b) };
  return { ...c, swipe: c.eventsOk && c.posOk && c.timeOk && c.speedOk && c.startOk };
}

export const replayMatches = (lim, src, rep) => src.length === rep.length && zip(src, rep).every(([a, b]) => conjuncts(lim, a, b).swipe);


export function speed2(s) {
  const [dx, dy, dt] = liftVel(5000, expected(s)).map(BigInt);
  return Number(((dx * dx + dy * dy) * 1000000n) / (dt * dt));
}
export const scrollsDown = (s) => s.s.length > 0 && s.s[s.s.length - 1][2] < s.s[0][2];
export function fastest(swipes) {
  let best = null;
  for (const s of swipes.filter(scrollsDown)) if (best === null || speed2(best) < speed2(s)) best = s;
  return best;
}

export function layout(g, swipes) {
  let at = 0;
  return swipes.map((s) => { const o = { ...s, start: at }; at += s.lift + g; return o; });
}

export function fastFling(p, n, g) {
  const f = fastest(p.swipes);
  return f === null ? null : { ...p, id: `${p.id}-fast-fling`, load: 'warm', swipes: layout(g, Array.from({ length: n }, () => f)) };
}

export const mirror = (h10, s) => ({ ...s, s: s.s.map(([t, x, y]) => [t, x, h10 - y]) });

export const segment = (z, vh10, maxY10, frames, t0, swipes) => swipes.filter((s) => zoneOf(vh10, maxY10, yAt(frames, t0 + s.start)) === z);

export function zoneLoop(p, z, maxY10, frames, t0, reps, g) {
  const h10 = p.h * 10;
  const seg = segment(z, h10, maxY10, frames, t0, p.swipes);
  if (seg.length === 0) return null;
  const one = [...seg, ...seg.map((s) => mirror(h10, s))];
  return { ...p, id: `${p.id}-zone-${z}`, load: 'warm', swipes: layout(g, Array.from({ length: reps }, () => one).flat()) };
}

export const cold = (p) => ({ ...p, id: `${p.id}-cold`, load: 'cold' });

export function rotation(n, r) {
  const k = r % n;
  const a = Array.from({ length: n }, (_, i) => i);
  return [...a.slice(k), ...a.slice(0, k)];
}

export const KINDS = Object.freeze(['recorded', 'fast-fling', 'zone-hero', 'zone-finish', 'cold']);

export const schedule = (kinds, reps, n) => kinds.flatMap((kind) => Array.from({ length: reps }, (_, rep) => ({ kind, rep, order: rotation(n, rep) })));

export function makeProfile(source, kind, { n, gap, reps }) {
  const { profile, zone } = source;
  switch (kind) {
    case 'recorded': return profile;
    case 'fast-fling': return fastFling(profile, n, gap);
    case 'zone-hero': return zone ? zoneLoop(profile, 'hero', zone.maxY10, zone.frames, zone.t0, reps, gap) : null;
    case 'zone-finish': return zone ? zoneLoop(profile, 'finish', zone.maxY10, zone.frames, zone.t0, reps, gap) : null;
    case 'cold': return cold(profile);
    default: throw new Error(`kind must be one of ${KINDS.join(', ')}`);
  }
}


export const touchesOf = (rec) => rec.touches.map(([t, ph, x, y, n]) => [Math.round(t * 100), ph, Math.round(x * 10), Math.round(y * 10), n]);

export function fromCiProfile(cp) {
  const dtc = 100000 / cp.hz;
  const strokes = cp.input.strokes;
  const base = strokes.length > 0 ? strokes[0].f0 : 0;
  return {
    id: cp.id, w: cp.viewport.width, h: cp.viewport.height, load: 'warm',
    swipes: strokes.map((st) => ({
      start: Math.round((st.f0 - base) * dtc), lift: Math.round(st.path.length * dtc),
      s: st.path.map(([x, y], i) => [Math.round(i * dtc), Math.round(x * 10), Math.round(y * 10)]),
    })),
  };
}
