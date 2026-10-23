/**
 * The capture hook of hero.accent (Lean `Fw.Gate.PathPix.hookSet`, `chainStarts`; golden
 * `packages/contracts/golden/gate/path-pix.jsonl`, kinds `hook` and `chainStarts`). A page opened with `?fwpin=accent`
 * keeps the accent as the server sent it: the effect returns before it starts the timer chain, as it does under reduced
 * motion. With the parameter unset nothing changes. The path-pix capture sets it on every arm instead of swapping the
 * element by hand.
 */
export const HOOK_PARAM = 'fwpin';
export const HOOK_VALUE = 'accent';

/** True when the search holds `fwpin=` with `accent` among its comma-separated values (no percent-decoding, as in Lean). */
export function accentHookSet(search: string): boolean {
  const q = search.startsWith('?') ? search.slice(1) : search;
  return q.split('&').some((kv) => {
    const p = kv.split('=');
    return p.length === 2 && p[0] === HOOK_PARAM && p[1]!.split(',').includes(HOOK_VALUE);
  });
}

/** The effect starts the timer chain unless reduced motion or the hook stops it. */
export const chainStarts = (reduce: boolean, hook: boolean): boolean => !reduce && !hook;
