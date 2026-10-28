// Mid-flip readout of the geom-timed tracks in WebKitTestRunner (task geom-webkit-midflip). The tick rule is the Lean
// Fw.Parts.MorphTrackAccel (ticksContinuously, ticksMain, tickOf, binOf, normName); the golden lines "tick", "bin" and "name"
// of packages/contracts/golden/parts/morph-track-accel.jsonl are replayed in test/midflip.test.mjs.

export const ticksContinuously = (s) => s.rendered && (s.complete && s.accel ? s.threaded && s.disallowed : true);

export const ticksMain = (s) => s.pending || (s.running && s.active && ticksContinuously(s));

export function tickOf(s) {
  if (s.pending) return 'pending';
  if (!(s.running && s.active)) return 'quiet';
  return ticksContinuously(s) ? 'main' : 'accelerated';
}

export function binOf(permille) {
  if (permille === 0 || permille >= 1000) return null;
  if (permille < 400) return 30;
  if (permille < 650) return 50;
  return 80;
}

export const normName = (s) => String(s).split('').filter((c) => /[A-Za-z]/.test(c)).join('').toLowerCase();

/** The Lean inputs of one track readout. `complete` holds for the six geom properties (INFERRED, KeyframeEffect.cpp:1764-1768@862f17d); `disallowed` is not readable, so false. */
export function effOf(row, ph, rendered, threaded) {
  return {
    pending: row.p === 1,
    running: row.s === 'running',
    active: ph > 0 && ph < 1000,
    rendered,
    complete: true,
    accel: row.a === 1,
    threaded,
    disallowed: false,
  };
}

/** The engine's own answer: WebAnimation::timeToNextTick (WebAnimation.cpp:1917-1929@862f17d) below the animation interval means a tick every frame. */
export const oracleTicks = (ttnt, intervalSec) => (ttnt === 'inf' ? false : typeof ttnt === 'number' && typeof intervalSec === 'number' ? ttnt < intervalSec * 1000 : null);


const GROUP = (t) => `${t.mg}:${t.prop}`;

/** The ThreadedTimeBasedAnimations state the run shows: an accelerated-animation entry from the effect stack is `isThreaded` true, a Core Animation one false (GraphicsLayerCA.cpp:5299-5330@862f17d). */
export function prefOf(report) {
  for (const row of report.rows) for (const s of row.samples ?? []) for (const r of s.rows) if (r.th === true || r.th === false) return r.th;
  for (const row of report.rows) for (const e of row.early ?? []) for (const r of e.rows) if (r.threaded === true || r.threaded === false) return r.threaded;
  return null;
}

const blank = () => ({ n: 0, running: 0, pending: 0, accel: 0, unrendered: 0, oracleTicks: 0, oracleQuiet: 0, oracleNone: 0, leanTicks: 0, agree: 0 });

/** Per arm and sample: counts of the tracks per group (data-mg:property) by the engine's tick answer and the Lean rule. */
export function midSummary(report) {
  const tags = new Map(report.tags.map((t) => [t.id, t]));
  const pref = prefOf(report);
  const out = [];
  for (const row of report.rows) {
    for (const s of row.samples ?? []) {
      const bin = s.why === 'end' || s.why[0] === 'i' ? s.why : binOf(s.ph);
      const groups = {};
      s.rows.forEach((r, i) => {
        const tag = tags.get(r.id);
        if (!tag) return;
        const g = (groups[GROUP(tag)] ??= blank());
        const rendered = row.rendered ? row.rendered[i] !== false : true;
        g.n++;
        if (r.s === 'running') g.running++;
        if (r.p === 1) g.pending++;
        if (r.a === 1) g.accel++;
        if (!rendered) g.unrendered++;
        const o = oracleTicks(r.t, s.env.itv);
        if (o === true) g.oracleTicks++;
        else if (o === false) g.oracleQuiet++;
        else g.oracleNone++;
        const lean = ticksMain(effOf(r, s.ph, rendered, pref === true));
        if (lean) g.leanTicks++;
        if (o !== null && o === lean) g.agree++;
      });
      out.push({ arm: row.arm, bin, ph: s.ph, dt: s.dt, env: s.env, groups });
    }
  }
  return out;
}

const median = (xs) => (xs.length ? [...xs].sort((a, b) => a - b)[xs.length >> 1] : null);

/** Per arm: frames of the flip window, style recalcs per frame (differences of the cumulative `rc`), lastStyleUpdateSize per frame and timeline invalidations. */
export function frameSummary(report) {
  return report.rows.map((row) => {
    const fr = row.frames ?? [];
    const rc = fr.map((f, i) => (typeof f.rc === 'number' ? f.rc - (i && typeof fr[i - 1].rc === 'number' ? fr[i - 1].rc : 0) : null)).filter((x) => x !== null);
    const upd = fr.map((f) => f.upd).filter((x) => typeof x === 'number');
    const inv = fr.length > 1 && typeof fr[0].inv === 'number' ? fr[fr.length - 1].inv - fr[0].inv : null;
    const st = row.stages?.[0];
    return {
      arm: row.arm,
      frames: st?.frames ?? fr.length,
      ms: st?.ms ?? null,
      recalc: st?.recalc ?? null,
      recalcPerFrame: st && st.recalc !== null && st.frames ? Math.round((100 * st.recalc) / st.frames) / 100 : null,
      rcMedian: median(rc),
      rcMax: rc.length ? Math.max(...rc) : null,
      updMedian: median(upd),
      updMax: upd.length ? Math.max(...upd) : null,
      invDelta: inv,
      listed: row.listed ? { ph: row.listed.ph, listRc: row.listed.listRc, n: row.listed.list.length } : null,
    };
  });
}
