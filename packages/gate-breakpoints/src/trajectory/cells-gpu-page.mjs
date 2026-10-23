export const carouselSample = async ({ scene, cont, ms, still = 6, settleMs = 2200, tailMs = 1500, withMeta = false }) => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const sc = document.querySelector(scene), c = document.querySelector(cont);
  if (!sc || !c) return null;
  const read = () => {
    const cr = c.getBoundingClientRect();
    const v = [];
    for (const k of Array.from(c.children)) { const r = k.getBoundingClientRect(); v.push(r.x - cr.x, r.y - cr.y, r.width, r.height); }
    return v.map((x) => Math.round(x * 1000));
  };
  const same = (a, b) => a.length === b.length && a.every((x, j) => x === b[j]);
  sc.scrollIntoView({ block: 'center', behavior: 'instant' });
  await raf(); await raf();
  let prev = read(), moved = false, quiet = 0, consumed = 0;
  const s0 = performance.now();
  while (!(moved && quiet >= still) && performance.now() - s0 < settleMs) {
    await raf();
    consumed++;
    const v = read();
    if (!same(prev, v)) { moved = true; quiet = 0; } else if (moved) quiet++;
    prev = v;
  }
  const rows = [];
  const t0 = performance.now();
  let tail = 0;
  for (;;) {
    await raf();
    const t = performance.now() - t0, v = read();
    tail = rows.length > 0 && same(rows[rows.length - 1].v, v) ? tail + 1 : 0;
    rows.push({ t: Math.round(t * 10) / 10, v });
    if (t >= ms + tailMs || (t >= ms && tail >= still)) return withMeta ? { rows, consumed, settleQuiet: moved && quiet >= still, tailQuiet: t < ms + tailMs } : rows;
  }
};
