// Run keys: mirrors lean/Fw/Engine/Keys.lean (runKey, hpSearch, answers); checked against golden/keys.jsonl.

export const hiddenPauseArms = ['engine.scene:hidden-pause', 'morph.columns:hidden-pause', 'morph.countdown:hidden-pause'];

/** @param {{target: string, search: string}} m */
export function runKey(m) {
  return m.search === '' ? m.target : `${m.target}+${m.search}`;
}

/** @param {string} s */
export function hpSearch(s) {
  return s.startsWith('?fw=') && s.slice(4).split(',').every((f) => hiddenPauseArms.includes(f));
}

/** @param {{target: string, search: string}} m @param {string} v */
export function answers(m, v) {
  return runKey(m) === v || (v === 'hidden-pause' && m.target === 'rewrite' && hpSearch(m.search));
}
