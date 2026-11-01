import { idle, live, moved, touch, type Ev, type Pin, type Policy } from './end-pin.logic';

export const faithMay: Policy = (q, s) => q.b !== s;

export function writesLive(may: Policy, p: Pin, es: readonly Ev[]): number {
  let n = 0;
  let cur = p;
  for (const e of es) {
    if (e[0] === 'move') cur = moved(cur, e[1]);
    else if (e[0] === 'idle') {
      const [next, w] = idle(cur, e[2], e[1], may);
      if (w !== null && live({ ...cur, since: cur.since + e[1] })) n++;
      cur = next;
    } else cur = touch(cur, e[0] === 'down');
  }
  return n;
}
