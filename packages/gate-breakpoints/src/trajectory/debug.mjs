// The debug recorders of the trajectory probe (task waapi-tail-webkit). A debug run loads the rewrite arms (role base and cand, never the
// original, which has no recorder) with `&fw-debug=<name>` and saves what the page recorded (`window.__fwDebug.<field>`) next to the
// readings, in `runs[].morph.debugReps`. The recorder lives in the page (apps/site/src/debug/nav-transition.ts) and is off in every
// other run. TS/JS stand-in: no Lean spec (a run's identity is still decided by armCheck on the search WITHOUT the debug param).

/** The recorders a page can run: `name` is the `fw-debug` value, `field` the key under `window.__fwDebug`. */
export const DEBUGS = [{ name: 'nav-transition', field: 'navTransition' }];

/**
 * Which recorder a run asks for: the env var `FW_DEBUG`, nothing else. On CI the workflow (trajectory-probe.yml) sets it from the
 * `debug=` key of the push commit line, which Lean decides (`Fw.Ci.Trigger.pushProbe`, allowlist `probeDebugs`); a local debug run
 * sets it by hand. No file of the repo requests a recorder, so nothing that lands on `main` turns one on.
 * Returns the recorder name, or '' (no recorder). An unknown name is an error, never a silent fallback.
 */
export function debugFor(env = process.env) {
  const name = env.FW_DEBUG ?? '';
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
