// The debug recorders of the trajectory probe (task waapi-tail-webkit). A debug run loads the rewrite arms (role base and cand, never the
// original, which has no recorder) with `&fw-debug=<name>` and saves what the page recorded (`window.__fwDebug.<field>`) next to the
// readings, in `runs[].morph.debugReps`. The recorder lives in the page (apps/site/src/debug/nav-transition.ts) and is off in every
// other run. TS/JS stand-in: no Lean spec (a run's identity is still decided by armCheck on the search WITHOUT the debug param).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** The recorders a page can run: `name` is the `fw-debug` value, `field` the key under `window.__fwDebug`. */
export const DEBUGS = [{ name: 'nav-transition', field: 'navTransition' }];

/**
 * Which recorder a run asks for. The workflow (trajectory-probe.yml) has no input for it and `fw run` cannot express one (the dispatch is
 * Lean's `store.trajectory`), so the request travels two ways: the env var `FW_DEBUG` (a local debug run), or a row of
 * `debug.requests.json` whose `search` equals the run's search exactly (a dispatched run on the branch that commits the row).
 * Returns the recorder name, or '' (no recorder). An unknown name is an error, never a silent fallback.
 */
export function debugFor(search, env = process.env, requests = readRequests()) {
  const named = env.FW_DEBUG ?? '';
  const name = named !== '' ? named : (requests.find((r) => r.search === search)?.debug ?? '');
  if (name !== '' && !DEBUGS.some((d) => d.name === name)) throw new Error(`debug: unknown recorder "${name}"; known: ${DEBUGS.map((d) => d.name).join(', ')}`);
  return name;
}

/** The URL search of a rewrite arm that runs recorder `name` (the arm's own search stays as it is for the config lookup). */
export function withDebug(search, name) {
  if (name === '') return search;
  return search === '' ? `?fw-debug=${name}` : `${search}&fw-debug=${name}`;
}

/** What the page recorded, read in the page: `null` when the recorder did not install (a stale build, a wrong flag). */
export function readDebug(field) {
  const bag = window.__fwDebug;
  return bag && bag[field] ? bag[field] : null;
}

export const fieldOf = (name) => DEBUGS.find((d) => d.name === name)?.field;

function readRequests() {
  return JSON.parse(readFileSync(fileURLToPath(new URL('./debug.requests.json', import.meta.url)), 'utf8'));
}
