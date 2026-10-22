import { BAND_ROOT_MARGIN, full, next, want, type Mode } from './listen.logic';

export type HubType = 'touchstart' | 'touchmove' | 'touchend' | 'touchcancel';

export interface TouchLikeEvent {
  touches: ArrayLike<unknown>;
}

export interface TouchClient<E extends TouchLikeEvent = TouchEvent> {
  touchstart(e: E): void;
  touchmove(e: E): void;
  active(): boolean;
}

export interface HubEnv<E extends TouchLikeEvent = TouchEvent> {
  add(type: HubType, fn: (e: E) => void, passive: boolean): void;
  remove(type: HubType, fn: (e: E) => void): void;
  observe(el: Element, onRatio: (ratio: number) => void): void;
  unobserve(el: Element): void;
}

export function createHub<E extends TouchLikeEvent = TouchEvent>(env: HubEnv<E>) {
  const clients: TouchClient<E>[] = [];
  const bands = new Map<Element, { full: boolean; n: number }>();
  let mode: Mode = 'none';
  let down = false;

  const each = (f: (c: TouchClient<E>) => void) => {
    for (const c of [...clients]) if (clients.includes(c)) f(c);
  };
  const onStart = (e: E) => {
    down = e.touches.length > 0;
    each((c) => c.touchstart(e));
  };
  const onMove = (e: E) => each((c) => c.touchmove(e));
  const onEnd = (e: E) => {
    down = e.touches.length > 0;
    refresh();
  };
  const inBand = () => bands.size === 0 || [...bands.values()].some((b) => b.full);

  const setMode = (m: Mode) => {
    if (m === mode) return;
    if (mode !== 'none') env.remove('touchmove', onMove);
    if (mode === 'none') {
      env.add('touchstart', onStart, true);
      env.add('touchend', onEnd, true);
      env.add('touchcancel', onEnd, true);
    }
    if (m === 'none') {
      env.remove('touchstart', onStart);
      env.remove('touchend', onEnd);
      env.remove('touchcancel', onEnd);
      down = false;
    } else env.add('touchmove', onMove, m === 'watch');
    mode = m;
  };
  function refresh() {
    setMode(next(mode, want(clients.length > 0, clients.some((c) => c.active()), inBand()), down));
  }

  return {
    attach(c: TouchClient<E>) {
      if (!clients.includes(c)) clients.push(c);
      refresh();
    },
    detach(c: TouchClient<E>) {
      const i = clients.indexOf(c);
      if (i >= 0) clients.splice(i, 1);
      refresh();
    },
    observe(el: Element): () => void {
      const b = bands.get(el);
      if (b) b.n++;
      else {
        bands.set(el, { full: true, n: 1 });
        env.observe(el, (ratio) => {
          const cur = bands.get(el);
          if (!cur) return;
          cur.full = full(ratio);
          refresh();
        });
      }
      refresh();
      return () => {
        const cur = bands.get(el);
        if (!cur || --cur.n > 0) return;
        bands.delete(el);
        env.unobserve(el);
        refresh();
      };
    },
    refresh,
    mode: () => mode,
  };
}

export type TouchHub = ReturnType<typeof createHub<TouchEvent>>;

let shared: TouchHub | undefined;

export function touchHub(): TouchHub {
  if (shared) return shared;
  const callbacks = new Map<Element, (ratio: number) => void>();
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) callbacks.get(e.target)?.(e.intersectionRatio);
    },
    { rootMargin: BAND_ROOT_MARGIN, threshold: [1] },
  );
  shared = createHub<TouchEvent>({
    add: (type, fn, passive) => window.addEventListener(type, fn, { passive, capture: true }),
    remove: (type, fn) => window.removeEventListener(type, fn, true),
    observe: (el, onRatio) => {
      callbacks.set(el, onRatio);
      io.observe(el);
    },
    unobserve: (el) => {
      callbacks.delete(el);
      io.unobserve(el);
    },
  });
  return shared;
}
