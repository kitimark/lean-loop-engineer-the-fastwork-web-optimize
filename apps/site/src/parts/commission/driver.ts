import { catchupPair, frame, PAIR0, planCatchup, planWrite, sceneActive, titleWrapped, ulFire, ulStart, ulTimer, UL_DELAY, type Pair, type Ul } from './logic';

/** Order on the scroll engine (after the hero, before the nav: hero.exit 10, nav 13090 in the original). */
export const COMMISSION_ORDER = 50;

export interface Rect {
  top: number;
  bottom: number;
}
export interface El {
  getBoundingClientRect(): Rect;
}
export interface StyleEl {
  style: { setProperty(name: string, value: string): void; height: string };
  classList: { toggle(cls: string, on: boolean): void };
  setAttribute(name: string, value: string): void;
  toggleAttribute(name: string, force: boolean): boolean;
  getAttribute(name: string): string | null;
}

export interface Els {
  /** `section.commission`: gets the custom properties, the classes and the scene attributes. */
  section: El & StyleEl;
  /** `.commission-card`: its top drives the enter band. */
  card: El;
  /** `.commission-runway`: its height is 6 % of the viewport on desktop. */
  runway: StyleEl;
  /** `.commission-header`: observed for the underline. */
  header: unknown;
  /** the `h2`, and its muted span whose line boxes decide `title-wrapped`. */
  title: StyleEl;
  muted: unknown;
  /** the underline span. */
  underline: StyleEl;
}

export interface Classes {
  entering: string;
  shrinking: string;
  titleWrapped: string;
  enter: string;
  idle: string;
}

export interface Clock {
  subscribe(tick: (t: number) => void, opts?: { own?: boolean }): () => void;
  interval(ms: number, cb: () => void): () => void;
}
export interface Engine {
  register(id: string, order: number, cb: (f: { vh: number }) => void | (() => void)): () => void;
}
export interface IoEntry {
  isIntersecting: boolean;
  intersectionRatio: number;
}
export interface Env {
  vh(): number;
  /** `(prefers-reduced-motion: reduce)` now. */
  reduced(): boolean;
  /** `mq.c1000` now (the original's `A()`). */
  compact(): boolean;
  /** reduced motion changed (the original's `change` listener on the list). */
  onReducedChange(cb: () => void): () => void;
  /** `mq.c1000` changed (the `band-gate` variant writes the follower's pair when the band is left). */
  onCompactChange?(cb: () => void): () => void;
  /** IntersectionObserver with a root margin and thresholds; returns disconnect. */
  observe(target: unknown, opts: { rootMargin?: string; threshold?: number[] }, cb: (e: IoEntry) => void): () => void;
  /** ResizeObserver; returns disconnect. */
  observeResize(target: unknown, cb: () => void): () => void;
  /** `Range.getClientRects().length` over the node's contents. */
  lineBoxes(target: unknown): number;
}

export interface Deps {
  els: Els;
  classes: Classes;
  engine: Engine;
  clock: Clock;
  env: Env;
}

/** Run `fn` once, `n` frames from now (own rAF registrations); returns the cancel. */
export function afterFrames(clock: Clock, n: number, fn: () => void): () => void {
  let left = n;
  let off: (() => void) | null = null;
  off = clock.subscribe(() => {
    left -= 1;
    if (left > 0) return;
    off?.();
    off = null;
    fn();
  }, { own: true });
  return () => {
    off?.();
    off = null;
  };
}

/**
 * The section driver (JS 3092-3141 + the scene scheduler `dE`). One frame body reads the card and section rects, runs the
 * Lean `frame`, writes two custom properties on the section, two classes, the runway height and the title-wrap class, and
 * asks for another frame while the follower has not settled. The frame is requested by the engine callback (a scroll or
 * resize while the scene is active), by reduced-motion changes and by the scene turning active.
 */
export function mountCommission({ els, classes, engine, clock, env }: Deps, opts: { bandGate?: boolean } = {}): () => void {
  let pair: Pair = PAIR0;
  let cancelOwn: (() => void) | null = null;
  let active = false;
  let compactNow = false;
  const cleanups: Array<() => void> = [];

  const request = () => {
    cancelOwn ??= clock.subscribe(tick, { own: true });
  };
  function tick() {
    cancelOwn?.();
    cancelOwn = null;
    body();
  }

  const writePair = () => {
    const w = catchupPair(pair);
    els.section.style.setProperty('--commission-enter-shrink', String(w.enter));
    els.section.style.setProperty('--commission-shrink', String(w.shrink));
  };

  const measureWrap = () => {
    const wrapped = compactNow && titleWrapped(compactNow, env.lineBoxes(els.muted));
    els.title.classList.toggle(classes.titleWrapped, wrapped);
  };

  function body() {
    compactNow = env.compact();
    const vh = env.vh();
    const reduced = env.reduced();
    const card = els.card.getBoundingClientRect();
    const section = els.section.getBoundingClientRect();
    const f = frame(pair, card.top, section.bottom, vh, reduced, compactNow);
    pair = { n: f.n, r: f.r };
    // variant band-gate (Lean CommissionOpt): in the c1000 band the CSS pins scale 1 and radius 0, so the pair is not read;
    // the first frame that reads the band off writes the current pair, in the same rAF before paint
    if (planWrite(opts.bandGate === true && compactNow, f.more)) writePair();
    els.section.classList.toggle(classes.entering, f.entering);
    els.section.classList.toggle(classes.shrinking, f.shrinking);
    els.section.toggleAttribute('data-fw-shrinking', f.shrinking);
    els.runway.style.height = f.runway === null ? '' : `${f.runway}px`;
    measureWrap();
    if (f.more) request();
  }

  // scene scheduler: active while the section is within one viewport above / two below (initial) or per observer
  let renderCancel: (() => void) | null = null;
  const setRender = (on: boolean) => {
    renderCancel?.();
    renderCancel = null;
    if (on) {
      els.section.setAttribute('data-render', 'active');
      return;
    }
    if (els.section.getAttribute('data-render') !== 'deferred') {
      renderCancel = afterFrames(clock, 2, () => {
        renderCancel = null;
        if (active) return;
        const h = els.section.getBoundingClientRect();
        const height = h.bottom - h.top;
        if (height > 0) els.section.style.setProperty('--start-selling-intrinsic-block-size', `${height}px`);
        els.section.setAttribute('data-render', 'deferred');
      });
    }
  };
  const setActive = (on: boolean) => {
    els.section.setAttribute('data-scene', on ? 'active' : 'paused');
    if (active === on) return;
    active = on;
    setRender(on);
    if (on) request();
  };

  // underline: fires once when the heading is at least 45 % visible
  let ul: Ul = 'hidden';
  const paintUl = () => {
    els.underline.classList.toggle(classes.enter, ul === 'enter');
    els.underline.classList.toggle(classes.idle, ul === 'idle');
  };
  let stopTimer: (() => void) | null = null;
  const stopUl = env.observe(els.header, { threshold: [0, 0.45, 0.75] }, (e) => {
    if (!ulFire(e.isIntersecting, e.intersectionRatio)) return;
    ul = ulStart(env.reduced());
    paintUl();
    stopTimer = clock.interval(UL_DELAY, () => {
      stopTimer?.();
      stopTimer = null;
      ul = ulTimer(ul);
      paintUl();
    });
    stopUl();
  });
  cleanups.push(() => {
    stopUl();
    stopTimer?.();
  });

  cleanups.push(env.observeResize(els.title, measureWrap));
  body(); // the original runs the body once at mount
  const sec = els.section.getBoundingClientRect();
  active = sceneActive(sec.top, sec.bottom, env.vh());
  els.section.setAttribute('data-scene', active ? 'active' : 'paused');
  setRender(active);
  cleanups.push(env.observe(els.section, { rootMargin: '100% 0px' }, (e) => setActive(e.isIntersecting)));
  cleanups.push(engine.register('commission', COMMISSION_ORDER, () => {
    // the original's `iE` runs the callback inside the same animation frame as the scroll/resize (no extra frame)
    if (active) {
      cancelOwn?.();
      cancelOwn = null;
      body();
    }
    return undefined;
  }));
  request(); // the scheduler asks for a frame when a scene registers (rE())
  cleanups.push(env.onReducedChange(request));
  // band-gate: a change of mq.c1000 out of the band writes the follower's pair at once (no body: the original has none then)
  if (opts.bandGate === true && env.onCompactChange) {
    cleanups.push(env.onCompactChange(() => {
      if (planCatchup(env.compact())) writePair();
    }));
  }

  return () => {
    cancelOwn?.();
    cancelOwn = null;
    renderCancel?.();
    for (const c of cleanups.splice(0)) c();
  };
}

