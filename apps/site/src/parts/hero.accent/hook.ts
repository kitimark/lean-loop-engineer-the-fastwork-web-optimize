export const HOOK_PARAM = 'fwpin';
export const HOOK_VALUE = 'accent';

export function accentHookSet(search: string): boolean {
  const q = search.startsWith('?') ? search.slice(1) : search;
  return q.split('&').some((kv) => {
    const p = kv.split('=');
    return p.length === 2 && p[0] === HOOK_PARAM && p[1]!.split(',').includes(HOOK_VALUE);
  });
}

export const chainStarts = (reduce: boolean, hook: boolean): boolean => !reduce && !hook;
