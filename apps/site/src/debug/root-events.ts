import { DEBUG_GLOBAL, DEBUG_PARAM } from './nav-transition';

// Debug recorder of the animation and transition listeners (task react-root-quiet-events). Off unless the URL carries
// `?fw-debug=root-events`; not a flag, not in the config or the hash. TS stand-in: no Lean spec (debug only).

export const ROOT_EVENTS_DEBUG = 'root-events';
export const ROOT_EVENTS_FIELD = 'rootEvents';

export const WATCHED = ['animationstart', 'animationiteration', 'animationend', 'animationcancel', 'transitionrun', 'transitionstart', 'transitionend', 'transitioncancel'] as const;

export interface RootEventsLog {
  /** `<target>:<type>:<b|c>` -> registrations of a watched type; target is `root` (id root), `window` or `other` */
  registered: Record<string, number>;
  /** events of a watched type that reached the window capture phase, by type */
  dispatched: Record<string, number>;
}

export function rootEventsDebugOn(search: string): boolean {
  return new URLSearchParams(search).getAll(DEBUG_PARAM).flatMap((v) => v.split(',')).includes(ROOT_EVENTS_DEBUG);
}

export interface RootEventsEnv {
  proto: EventTarget;
  win: EventTarget;
  store: Record<string, unknown>;
}

const watched: ReadonlySet<string> = new Set(WATCHED);

/** Install before the React root exists, and before a container shim, so a shim's drops are what the log shows. */
export function installRootEventsDebug(env: RootEventsEnv): () => void {
  const log: RootEventsLog = { registered: {}, dispatched: {} };
  const bag = (env.store[DEBUG_GLOBAL] ??= {}) as Record<string, unknown>;
  bag[ROOT_EVENTS_FIELD] = log;
  const proto = env.proto as { addEventListener: EventTarget['addEventListener'] };
  const original = proto.addEventListener;
  proto.addEventListener = function (this: EventTarget, type: string, listener: EventListenerOrEventListenerObject | null, options?: boolean | AddEventListenerOptions) {
    if (watched.has(type)) {
      const target = this === env.win ? 'window' : (this as { id?: string }).id === 'root' ? 'root' : 'other';
      const capture = typeof options === 'object' ? options?.capture === true : options === true;
      const key = `${target}:${type}:${capture ? 'c' : 'b'}`;
      log.registered[key] = (log.registered[key] ?? 0) + 1;
    }
    original.call(this, type, listener, options);
  } as EventTarget['addEventListener'];
  const handlers = WATCHED.map((type) => {
    const h = () => {
      log.dispatched[type] = (log.dispatched[type] ?? 0) + 1;
    };
    original.call(env.win, type, h, true);
    return [type, h] as const;
  });
  return () => {
    proto.addEventListener = original;
    for (const [type, h] of handlers) env.win.removeEventListener(type, h, true);
  };
}
