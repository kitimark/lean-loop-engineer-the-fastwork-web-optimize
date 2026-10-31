// sim-park-engage: does hero.exit:threaded-park engage at the end of the page on the iOS Simulator (task park-engage).
//
// The page code only reads and scrolls; the engage rule is Lean `Fw.Parts.ScrollPark` (scrollEvent_engages, jump_engages, walk_engages) and
// its TS twin apps/site/src/parts/hero.exit/park.ts is checked against packages/contracts/golden/parts/scroll-park.jsonl. Nothing here decides.

const PARK = 'engine.scroll:unthrottle,hero.exit:threaded-park,platform:faded-pause';
/**
 * The park arms (set `park`, picked by `--arms park`): v2p with the threaded hero swapped for its park. `park` reaches the end with the instant jump
 * of sim-end-floor; `parkWalk` reaches it with a scroll in steps of one frame (`WALK_STEP` px), so the sentinel crosses the viewport.
 */
export const PARK_ARMS = Object.freeze([
  { id: 'park', fw: PARK, search: `?fw=${PARK}`, set: 'park' },
  { id: 'parkWalk', fw: PARK, search: `?fw=${PARK}`, act: 'walk', set: 'park' },
]);
export const WALK_STEP = 100;

/**
 * The page-side state of the park, read from the DOM: `live` (the hand-over ran, so startParkOn ran), `styled` (startParkOn installed the park
 * stylesheet), `parked` (the track carries data-exit-parked).
 */
export const PARK_PROBE_JS = `(() => {
    const t = document.querySelector('[data-fw="hero-exit"]');
    if (!t) return null;
    return { variant: t.getAttribute('data-fw-variant'), live: t.hasAttribute('data-exit-live'), parked: t.hasAttribute('data-exit-parked'),
      styled: [...document.querySelectorAll('style')].some((s) => s.textContent.includes('data-exit-parked')), y: Math.round(scrollY) };
  })`;

/** The first scroll of the in-page script: the instant jump to the end, or from the top in steps of one frame. */
export const firstScrollJs = (act) => (act === 'walk'
  ? `scrollTo({ top: 0, behavior: 'instant' }); await frame();
  for (let y = 0, max = root.scrollHeight - innerHeight; y < max;) { y = Math.min(max, y + ${WALK_STEP}); scrollTo({ top: y, behavior: 'instant' }); await frame(); }`
  : "scrollTo({ top: root.scrollHeight - innerHeight, behavior: 'instant' });");

/** Where the park stood: no hero, never handed over, handed over without the stylesheet, installed but not parked, or parked. */
export function parkState(p) {
  if (!p) return 'noHero';
  if (!p.live) return 'notLive';
  if (!p.styled) return 'noStyle';
  return p.parked ? 'parked' : 'live';
}

export const viewDriven = (c) => Object.entries(c?.by ?? {}).filter(([k]) => k.startsWith('view:')).reduce((s, [, n]) => s + n, 0);
/** The park took when the track is parked and no animation is still on a view timeline. */
export const took = (c) => parkState(c?.park) === 'parked' && viewDriven(c) === 0;

/** The report: per round and arm the park state and the view-driven count at the end stage (after the first scroll settled), then the overall line. */
export function parkLines(raw) {
  const out = [`sim-park-engage rounds ${raw.rounds.length}; runtime ${raw.meta?.runtime ?? '-'}`];
  const tally = {};
  for (const r of raw.rounds) {
    for (const a of PARK_ARMS) {
      const arm = r.arms[a.id];
      if (!arm) { out.push(`round ${r.round} ${a.id}: unread`); continue; }
      const c = arm.anims;
      const p = c?.park ?? null;
      const ok = took(c);
      (tally[a.id] ??= []).push(ok);
      out.push(`round ${r.round} ${a.id}: park ${parkState(p)} (live ${p?.live} styled ${p?.styled} parked ${p?.parked} y ${p?.y ?? '-'}); view-driven ${viewDriven(c)}; took ${ok}`);
    }
  }
  for (const a of PARK_ARMS) {
    const t = tally[a.id] ?? [];
    out.push(`overall ${a.id}: took in ${t.filter(Boolean).length} of ${t.length} rounds`);
  }
  return out;
}
