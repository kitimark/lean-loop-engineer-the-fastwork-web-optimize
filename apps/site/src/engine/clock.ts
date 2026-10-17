/**
 * Minimal injectable MotionClock (placeholder for the engine package). All JS motion subscribes here;
 * parts never call requestAnimationFrame or setInterval themselves (PLAN 6.5 rule 2). One rAF loop,
 * running only while there is at least one subscriber.
 */
export type Tick = (nowMs: number) => void;

export interface MotionClock {
  subscribe(tick: Tick): () => void;
}

export function createRafClock(): MotionClock {
  const subs = new Set<Tick>();
  let handle = 0;
  const frame = (t: number) => {
    for (const s of subs) s(t);
    handle = subs.size > 0 ? requestAnimationFrame(frame) : 0;
  };
  return {
    subscribe(tick) {
      subs.add(tick);
      if (handle === 0) handle = requestAnimationFrame(frame);
      return () => {
        subs.delete(tick);
        if (subs.size === 0 && handle !== 0) {
          cancelAnimationFrame(handle);
          handle = 0;
        }
      };
    },
  };
}

let shared: MotionClock | undefined;
/** The page-wide clock (client only). */
export function getClock(): MotionClock {
  return (shared ??= createRafClock());
}
