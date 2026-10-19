import { armed as gateOpen, resumeAt } from './armed';
import {
  addExtra,
  avoidBox,
  baseLayout,
  createRng,
  dragAllowed,
  dragPos,
  INTERVAL_MS,
  keyDelta,
  keyPos,
  noteBox,
  NOTE_SIZE,
  tick,
  visible,
  type Box,
  type Note,
} from './logic';

export interface RectLike {
  top: number;
  width: number;
  height: number;
}
export interface DragPointer {
  pointerId: number;
  clientX: number;
  clientY: number;
  button: number;
  mouse: boolean;
}

export interface NotesEnv {
  /** The canvas `.pain-canvas`' rect: the notes' stage (JS `x.getBoundingClientRect()`, `x` bound at 4751). */
  stageRect(): RectLike | null;
  /** `.pain-copy`'s rect (the avoid box source, JS `C`), when mounted. */
  copyRect(): RectLike | null;
  /** The top of `.commission-card`, or null when it does not exist (JS 4599). */
  cardTop(): number | null;
  innerHeight(): number;
  /** `(width<=860px)` (JS `o`). */
  narrow(): boolean;
  /** `(prefers-reduced-motion: reduce)`. */
  reduced(): boolean;
  /** The drag-gate condition `mq.c860`. */
  c860(): boolean;
  /** A real `setInterval` on the engine clock; returns the cancel function. */
  interval(ms: number, cb: () => void): () => void;
  /** Milliseconds on one monotonic clock (`performance.now()`); read only by variant `visible`. */
  now?(): number;
  /** One engine-clock frame, once (the original's `requestAnimationFrame(ce)`); returns the cancel function. */
  frame(cb: () => void): () => void;
  /** The model changed in membership or at rest (layout, add, clear, drag start/end): render it. Not per pointer move. */
  commit(view: { base: Note[]; extras: Note[]; dragging: string | null }): void;
  /** Write a note's position straight to its element during a drag or key step (no React). */
  writeNote(id: string, left: number, top: number, z: number): void;
}

/**
 * The faithful driver of the notes (N2:4411-4748): base layout on mount/resize, the 3 s tick while the section shows,
 * the clear rule when the commission card comes up, pointer drag and arrow-key moves. Decisions are the pure functions
 * in logic.ts (Lean `PainNotes`); randomness is the seeded stream (the only delta from the original). The pointer and
 * key moves write the element style directly through `env.writeNote`; React state changes only at membership changes.
 */
export function createNotesDriver(env: NotesEnv, seed: number, opts: { armWhenVisible?: boolean } = {}) {
  const gated = opts.armWhenVisible === true;
  const rng = createRng(seed);
  let base: Note[] = [];
  let extras: Note[] = [];
  let dragging: string | null = null;
  let drag: { id: string; startX: number; startY: number; originLeft: number; originTop: number; w: number; h: number; wPct: number; hPct: number } | null = null;
  let visibleNow = false;
  let j = 0;
  let cancelInterval: (() => void) | null = null;
  let cancelWait: (() => void) | null = null;
  /** When the original's interval would have been armed (the section came into view): the tick grid's origin. */
  let t0 = 0;
  let cancelFrame: (() => void) | null = null;

  const view = () => env.commit({ base, extras, dragging });

  /** JS 4555 `ce`. */
  const layout = () => {
    if (drag) return;
    const r = env.stageRect();
    if (!r || r.width < 8 || r.height < 8) return;
    base = baseLayout({ narrow: env.narrow(), stageW: r.width, stageH: r.height });
    view();
  };

  const scheduleLayout = () => {
    cancelFrame?.();
    cancelFrame = env.frame(() => {
      cancelFrame = null;
      layout();
    });
  };

  /** JS 4590 `le`: the 3 s tick. */
  const onTick = () => {
    const stage = env.stageRect();
    const t = tick({
      visible: visibleNow,
      dragging: drag !== null,
      extras: extras.length,
      narrow: env.narrow(),
      reduced: env.reduced(),
      cardTop: env.cardTop(),
      vh: env.innerHeight(),
      stageW: stage?.width ?? 0,
      stageH: stage?.height ?? 0,
    });
    if (t === 'skip' || !stage) return;
    if (t === 'clear') {
      extras = [];
      view();
      return;
    }
    const copy = env.copyRect();
    const avoid: Box[] = copy ? [avoidBox({ copyTop: copy.top, copyH: copy.height, stageTop: stage.top, stageH: stage.height })] : [];
    const n = addExtra({ stageW: stage.width, stageH: stage.height, base, extras, avoid, j }, rng);
    if (!n) return;
    extras = [...extras, n];
    j += 1;
    view();
  };

  const covered = () => {
    const top = env.cardTop();
    return top !== null && top < env.innerHeight() * 0.995;
  };
  const stopTimers = () => {
    cancelWait?.();
    cancelWait = null;
    cancelInterval?.();
    cancelInterval = null;
  };
  const now = () => Math.ceil(env.now?.() ?? 0);
  /**
   * Variant `visible` (Lean `armed`, `resumeAt`): the interval exists only while the gate is open. Every tick is a
   * one-shot aimed at the original's absolute grid (t0 + 3000k) and re-armed after it fires, so a late timer never
   * shifts later ticks (a free-running period after a re-arm would carry the lateness: `naive_rearm_shifts`).
   */
  const sync = () => {
    if (!gateOpen({ inView: visibleNow, narrow: env.narrow(), covered: covered() })) {
      stopTimers();
      return;
    }
    if (cancelWait) return;
    const at = now();
    aim(resumeAt(t0, at) - at);
  };
  const aim = (delay: number) => {
    cancelWait = env.interval(Math.max(0, delay), () => {
      cancelWait?.();
      cancelWait = null;
      onTick();
      if (!gated || cancelWait) return;
      const at = now();
      if (gateOpen({ inView: visibleNow, narrow: env.narrow(), covered: covered() })) aim(resumeAt(t0, at + 1) - at);
    });
  };
  const arm = () => {
    if (gated) sync();
    else cancelInterval ??= env.interval(INTERVAL_MS, onTick);
  };
  const disarm = () => {
    if (gated) stopTimers();
    else {
      cancelInterval?.();
      cancelInterval = null;
    }
  };

  const all = () => [...base, ...extras];
  const setPos = (id: string, left: number, top: number, z: number) => {
    base = base.map((n) => (n.id === id ? { ...n, left, top, z } : n));
    extras = extras.map((n) => (n.id === id ? { ...n, left, top, z } : n));
    env.writeNote(id, left, top, z);
  };

  return {
    /** Mount: the first layout runs on the next engine frame (JS 4690). */
    start: scheduleLayout,
    /** ResizeObserver or the narrow list changing (JS 4705-4709). */
    relayout: scheduleLayout,
    /** The narrow list changing (JS 4709 `c = () => ce()`): laid out in the same task, not on a frame. */
    layoutNow() {
      layout();
    },
    /** IntersectionObserver entry for the notes block (JS 4698-4701). */
    intersect(intersecting: boolean, ratio: number) {
      const was = visibleNow;
      visibleNow = visible({ intersecting, ratio });
      if (visibleNow && !was) t0 = now();
      if (visibleNow) arm();
      else {
        disarm();
        extras = [];
        view();
      }
    },
    /** The per-scroll-frame rule (JS 4728-4731): the commission card coming up clears the extras. */
    onScroll() {
      const top = env.cardTop();
      if (top !== null && top < env.innerHeight() * 0.995) {
        extras = [];
        view();
      }
      if (gated) sync();
    },
    /** The gate may have changed (the `(width<=860px)` list flipped): variant `visible` re-evaluates. */
    sync() {
      if (gated) sync();
    },
    tick: onTick,
    /** JS 4647 `W`. Returns whether the event was taken (the caller then prevents default and stops propagation). */
    pointerDown(id: string, e: DragPointer): boolean {
      if (!dragAllowed({ c860: env.c860(), button: e.button, mouse: e.mouse })) return false;
      const stage = env.stageRect();
      const n = all().find((x) => x.id === id);
      if (!stage || !n) return false;
      dragging = id;
      drag = {
        id,
        startX: e.clientX,
        startY: e.clientY,
        originLeft: n.left,
        originTop: n.top,
        w: stage.width,
        h: stage.height,
        wPct: (NOTE_SIZE / stage.width) * 100,
        hPct: (NOTE_SIZE / stage.height) * 100,
      };
      view();
      return true;
    },
    /** JS 4710 `l`. */
    pointerMove(e: { clientX: number; clientY: number }) {
      if (!drag) return;
      const left = dragPos({ origin: drag.originLeft, start: drag.startX, cur: e.clientX, container: drag.w, sizePct: drag.wPct });
      const top = dragPos({ origin: drag.originTop, start: drag.startY, cur: e.clientY, container: drag.h, sizePct: drag.hPct });
      setPos(drag.id, left, top, 40);
    },
    /** JS 4725 `u`. */
    pointerEnd() {
      drag = null;
      if (dragging !== null) {
        dragging = null;
        view();
      }
    },
    /** JS 4671 `ue`. Returns whether the key was an arrow (the caller prevents default). */
    key(id: string, key: string): boolean {
      const d = keyDelta({ key });
      if (!d) return false;
      const stage = env.stageRect();
      const n = all().find((x) => x.id === id);
      if (!stage || !n) return true;
      const box = noteBox(n, stage.width, stage.height);
      setPos(id, keyPos({ pos: n.left, delta: d[0], sizePct: box.width }), keyPos({ pos: n.top, delta: d[1], sizePct: box.height }), n.z);
      return true;
    },
    dispose() {
      cancelFrame?.();
      stopTimers();
    },
    /** Test access. */
    model: () => ({ base, extras, dragging, visible: visibleNow, armed: cancelInterval !== null || cancelWait !== null }),
  };
}
