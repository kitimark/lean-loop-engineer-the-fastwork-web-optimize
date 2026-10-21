// The scroll scripts of the cadence lanes and the arm order of a rep (data and one rotation; no browser, no dependency).

/** The hero burst: `count` wheel events of `dy` CSS px, one every `everyMs`, then `tailMs` of rest. */
export const HERO_BURST = { count: 60, dy: 42, everyMs: 16, tailMs: 600 };
/** The end-of-page push: `dy` px open and back, each held `holdMs`. */
export const END_PUSH = { dy: 120, holdMs: 1000 };

/** The arms in the order of one rep: a rotation of the list by the rep number. */
export const orderFor = (arms, rep) => arms.map((_, i) => arms[(i + rep) % arms.length]);
