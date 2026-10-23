// The lane's plan: which arms run in which zone, at which states. Pure data and two pure functions.
// Arms are the unit of decision (pinned): one result file per arm, each against the faithful arm of the same zone in the same session.

/** `base` is the faithful rewrite (no flags); the A/A control is a second, separately loaded copy of it. */
export const FAITHFUL = Object.freeze({ id: 'base', search: '', label: 'faithful' });

/** Flag arms. `zone` names the state list they are captured at. */
export const FLAG_ARMS = Object.freeze([
  { id: 'nav-clip-box', zone: 'nav', search: '?fw=nav:clip-box', label: 'nav:clip-box', task: 'nav-fixed-size' },
  { id: 'nav-bar-fixed', zone: 'nav', search: '?fw=nav:bar-fixed', label: 'nav:bar-fixed', task: 'nav-fixed-size' },
  { id: 'nav-logo-3d', zone: 'nav', search: '?fw=nav:logo-3d', label: 'nav:logo-3d', task: 'nav-fixed-size' },
  { id: 'morph-panel-threaded', zone: 'morph', search: '?fw=morph.panel:threaded', label: 'morph.panel:threaded', task: 'morph-panel-threaded' },
  { id: 'morph-panel-threaded-fade', zone: 'morph', search: '?fw=morph.panel:threaded,platform:fade-threaded', label: 'morph.panel:threaded + platform:fade-threaded (bundled)', task: 'morph-panel-threaded' },
  { id: 'pain-dark-scroll', zone: 'pain', search: '?fw=pain:dark-scroll', label: 'pain:dark-scroll', task: 'pain-dark-scroll' },
  { id: 'people-o-preview-translate', zone: 'people', search: '?fw=people.o:preview-translate', label: 'people.o:preview-translate', task: 'people-o-preview-translate' },
].map((a) => Object.freeze(a)));

/** Nav morph values: 0.1, 0.5, 0.9 for the clip and backdrop edge pixels, 0.25, 0.5, 0.75 for the glass colour (the task title). */
export const NAV_M = Object.freeze([0.1, 0.25, 0.5, 0.75, 0.9]);
export const NAV_EDGE_M = Object.freeze([0.1, 0.5, 0.9]);
export const NAV_GLASS_M = Object.freeze([0.25, 0.5, 0.75]);
/** The morph panel arms are captured at the middle three morph values. */
export const MORPH_M = Object.freeze([0.25, 0.5, 0.75]);
/** Scroll offsets around the pain flip (the first offset at which the original puts `is-pain-dark` on the section). */
export const PAIN_AROUND = Object.freeze([-16, -1, 0, 1, 16]);

/** The states of a zone, in capture order. `flipY` is only read by the pain zone. */
export function statesOf(zone, flipY = null) {
  if (zone === 'nav') return NAV_M.map((m) => ({ id: `m${m}`, kind: 'morph', m, mask: 'nav' }));
  if (zone === 'morph') return MORPH_M.map((m) => ({ id: `m${m}`, kind: 'morph', m, mask: 'frame' }));
  if (zone === 'pain') {
    if (!Number.isInteger(flipY)) throw new Error('the pain zone needs the flip offset of the faithful arm');
    return PAIN_AROUND.map((d) => ({ id: `y${d >= 0 ? '+' : ''}${d}`, kind: 'scroll', y: flipY + d, mask: 'frame' }));
  }
  throw new Error(`no state list for zone ${zone}`);
}

/** The arms of a zone in capture order: faithful, the A/A control (faithful again), then the flag arms. */
export function zoneArms(zone) {
  return [FAITHFUL, { ...FAITHFUL, id: 'base2', label: 'faithful (A/A control)' }, ...FLAG_ARMS.filter((a) => a.zone === zone), { ...FAITHFUL, id: 'base3', label: 'faithful (order probe)' }];
}
