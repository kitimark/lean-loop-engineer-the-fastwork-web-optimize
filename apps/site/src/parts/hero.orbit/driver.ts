import { blur, CANVAS_W, EXPAND_AT, place, SPLASH_END, type Piece } from './logic';

export interface OrbitClock {
  subscribe(tick: (t: number) => void, opts?: { own?: boolean }): () => void;
  interval(ms: number, cb: () => void): () => void;
}

export interface StyleTarget {
  style: { setProperty(name: string, value: string): void; removeProperty(name: string): string };
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
}

export interface OrbitDeps {
  clock: OrbitClock;
  /** the `.orbit` element (the original's `C`): custom properties and the data-expand / data-done flags */
  orbit: StyleTarget & { clientWidth: number };
  /** the hero stage (the original's `x`): `data-splash` = prep | run | done */
  hero: StyleTarget & { offsetWidth: number };
  /** cards in piece order */
  cards: StyleTarget[];
  pieces: readonly Piece[];
  /** ring index per piece (Lean `ringIndex`) */
  ring: readonly number[];
  innerWidth(): number;
  /** `performance.now()` */
  perfNow(): number;
  /** reduced motion or `(max-width: 600px)` at the time of a restart (N2:4218) */
  skip(): boolean;
}

const px = (n: number) => `${n}px`;

/**
 * The faithful ring splash (N2:4138-4229). `reset` is the original's `p()` (run at mount and on `pageshow` persisted):
 * the hero goes to `prep`, every card gets its resting-ring start offset, one forced layout read, `prep` is dropped; then
 * either the splash is finished at once (reduced motion, width <= 600) or a per-frame loop (own rAF, the part's own
 * registration) writes `--ring-motion-blur` and three variables per card, `data-expand` is set at 1164 ms, and a 1820 ms
 * timer ends it (`finish`, the original's `d()`). All of it is time-driven by the clock; nothing goes through React.
 */
export function createOrbitDriver(deps: OrbitDeps) {
  let stopLoop: (() => void) | null = null;
  let stopTimer: (() => void) | null = null;
  let expanded = false;
  let start = 0;

  const writeCard = (i: number, n: number, e: number, exp: boolean) => {
    const p = deps.pieces[i]!;
    const r = place({ left: p.left, top: p.top, width: p.width, height: p.height, idx: deps.ring[i]!, n, e, expanded: exp });
    const card = deps.cards[i]!;
    card.style.setProperty('--orbit-enter-x', px(r.x));
    card.style.setProperty('--orbit-enter-y', px(r.y));
    card.style.setProperty('--orbit-start-rot', `${r.rotTenths / 10}deg`);
  };

  const clearLoop = () => {
    stopLoop?.();
    stopLoop = null;
    deps.orbit.style.removeProperty('--ring-motion-blur');
  };
  const clearTimer = () => {
    stopTimer?.();
    stopTimer = null;
  };

  const finish = () => {
    clearLoop();
    clearTimer();
    deps.orbit.setAttribute('data-done', '');
    deps.hero.setAttribute('data-splash', 'done');
  };

  const frame = (now: number) => {
    const e = now - start;
    deps.orbit.style.setProperty('--ring-motion-blur', `${blur({ e }).toFixed(2)}px`);
    if (!expanded && e >= EXPAND_AT) {
      expanded = true;
      deps.orbit.setAttribute('data-expand', '');
    }
    const w = deps.orbit.clientWidth || deps.innerWidth();
    for (let i = 0; i < deps.cards.length; i++) writeCard(i, expanded ? w : CANVAS_W, e, expanded);
  };

  const reset = () => {
    clearLoop();
    clearTimer();
    expanded = false;
    deps.orbit.removeAttribute('data-done');
    deps.orbit.removeAttribute('data-expand');
    deps.hero.setAttribute('data-splash', 'prep');
    for (let i = 0; i < deps.cards.length; i++) writeCard(i, CANVAS_W, 0, false);
    void deps.hero.offsetWidth; // forced layout, as the original reads x.offsetWidth
    deps.hero.setAttribute('data-splash', 'run');
    if (deps.skip()) {
      finish();
      return;
    }
    start = deps.perfNow();
    stopLoop = deps.clock.subscribe(frame, { own: true });
    const off = deps.clock.interval(SPLASH_END, () => {
      off();
      finish();
    });
    stopTimer = off;
  };

  return {
    reset,
    finish,
    stop() {
      clearLoop();
      clearTimer();
    },
  };
}
