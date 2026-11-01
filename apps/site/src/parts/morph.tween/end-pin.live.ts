import { idle, live, moved, touch, type Ev, type Pin } from './end-pin.logic';

/** Lean `writesLive`: the end pin's writes made in a live state (an idle event whose time-advanced state is live and that writes). */
export function writesLive(p: Pin, es: readonly Ev[]): number {
  let n = 0;
  let cur = p;
  for (const e of es) {
    if (e[0] === 'move') cur = moved(cur, e[1]);
    else if (e[0] === 'idle') {
      const [next, w] = idle(cur, e[2], e[1]);
      if (w !== null && live({ ...cur, since: cur.since + e[1] })) n++;
      cur = next;
    } else cur = touch(cur, e[0] === 'down');
  }
  return n;
}

/** Lean `faithWritesLive`: the faithful pin writes `s` at once after each page move to a place other than `s`, in the state the move made (age 0). */
export function faithWritesLive(s: number, p: Pin, es: readonly Ev[]): number {
  let n = 0;
  let cur = p;
  for (const e of es) {
    if (e[0] === 'move') {
      cur = moved(cur, e[1]);
      if (e[1] !== s && live(cur)) n++;
    } else if (e[0] === 'idle') cur = { ...cur, since: cur.since + e[1] };
    else cur = touch(cur, e[0] === 'down');
  }
  return n;
}
