import { catchupPair, frame, PAIR0, planCatchup, planWrite, sceneActive, titleWrapped, ulFire, ulStart, ulTimer, UL_DELAY, type Pair, type Ul } from './logic';

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
  section: El & StyleEl;
  card: El;
  runway: StyleEl;
  header: unknown;
  title: StyleEl;
  muted: unknown;
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
  reduced(): boolean;
  compact(): boolean;
  onReducedChange(cb: () => void): () => void;
  onCompactChange?(cb: () => void): () => void;
  observe(target: unknown, opts: { rootMargin?: string; threshold?: number[] }, cb: (e: IoEntry) => void): () => void;
  observeResize(target: unknown, cb: () => void): () => void;
  lineBoxes(target: unknown): number;
}

export interface Deps {
  els: Els;
  classes: Classes;
  engine: Engine;
  clock: Clock;
  env: Env;
}

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
    if (planWrite(opts.bandGate === true && compactNow, f.more)) writePair();
    els.section.classList.toggle(classes.entering, f.entering);
    els.section.classList.toggle(classes.shrinking, f.shrinking);
    els.section.toggleAttribute('data-fw-shrinking', f.shrinking);
    els.runway.style.height = f.runway === null ? '' : `${f.runway}px`;
    measureWrap();
    if (f.more) request();
  }

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
  body();
  const sec = els.section.getBoundingClientRect();
  active = sceneActive(sec.top, sec.bottom, env.vh());
  els.section.setAttribute('data-scene', active ? 'active' : 'paused');
  setRender(active);
  cleanups.push(env.observe(els.section, { rootMargin: '100% 0px' }, (e) => setActive(e.isIntersecting)));
  cleanups.push(engine.register('commission', COMMISSION_ORDER, () => {
    if (active) {
      cancelOwn?.();
      cancelOwn = null;
      body();
    }
    return undefined;
  }));
  request();
  cleanups.push(env.onReducedChange(request));
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

