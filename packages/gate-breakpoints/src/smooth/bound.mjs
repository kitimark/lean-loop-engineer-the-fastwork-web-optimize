// The probe-only `bound` arm of the WebKit smoothness legs (task earn-bound-arm), and the options that run a subset of the arms with a
// longer end-of-page hold. Glue only: the verdict over the arms is Lean's (Fw.Gate.Smooth `across`, Fw.Measure.WebKitProfile `zoneVerdict`).
//
// `bound` is the faithful rewrite page plus one injected stylesheet that switches the earn button's CSS transitions off at all times
// (nav.module.css `.btn.earn`, found by its `data-fw="nav-earn"` hook). It loads the same configuration as `base`, so the arm-identity check
// passes for it, and it never enters a preset or the shipped site. The button then shows the computed value on every frame, which is
// the least main-thread work any variant of the earn animation can leave: a lower bound, never a candidate. The `.actions` gap transition
// (0.68 s) stays on; it is not an earn transition.
import { END_PUSH } from './schedule.mjs';

/** The stylesheet text of the `bound` arm. `!important` beats every state rule of the module (hero pill, still, phone). */
export const BOUND_CSS = '[data-fw="nav-earn"], [data-fw="nav-earn"]::before, [data-fw="nav-earn"]::after { transition: none !important; }';

/** Page script that adds the `bound` stylesheet once and returns the button's computed transition duration (`null` when the hook is missing). Run it before the recorder starts. */
export const BOUND_JS = `(() => {
  if (!document.getElementById('fw-bound')) {
    const s = document.createElement('style');
    s.id = 'fw-bound';
    s.textContent = ${JSON.stringify(BOUND_CSS)};
    document.head.appendChild(s);
  }
  const b = document.querySelector('[data-fw="nav-earn"]');
  return b ? getComputedStyle(b).transitionDuration : null;
})()`;

/** The arm ids a leg can run, in report order. `look` and `v2` need the candidate search; `bound` and `aa` do not. */
export const KNOWN_ARMS = ['orig', 'base', 'aa', 'look', 'v2', 'bound'];

/** `--arms base,aa,bound` as a list of known arm ids; undefined/empty means every arm of the default plan; an unknown or repeated id throws. */
export function parseArms(spec) {
  if (spec === undefined || spec === null || spec === '') return undefined;
  const ids = String(spec).split(',').map((s) => s.trim()).filter(Boolean);
  if (!ids.length) return undefined;
  for (const id of ids) if (!KNOWN_ARMS.includes(id)) throw new Error(`unknown arm "${id}" (known: ${KNOWN_ARMS.join(', ')})`);
  if (new Set(ids).size !== ids.length) throw new Error('an arm id is listed twice');
  return ids;
}

/** The end-of-page push with a different hold: the same push, each half held `holdMs` (default: the shared schedule's). */
export const endPushFor = (holdMs) => (holdMs ? { ...END_PUSH, holdMs: Number(holdMs) } : END_PUSH);
