// One test per premise of lean/Fw/Ops/Premise.lean (`registry`). `id` is the registry's testId, `premise` its id; the
// Lean lint (`premiseLint`, ported in apps/runner/src/premises.ts) fails when the two lists drift.
// A test loads its tiny page from ../pages, drives the browser, and asserts with node:assert/strict. It returns what it
// observed; the runner stores that next to the verdict.
import assert from 'node:assert/strict';
import { collectAlignFacts, alignEquiv, modeOf, contentFill, parseTracks } from '../../gate-breakpoints/src/align-equiv.mjs';

/** Wait for n animation frames in the page. */
export const frames = (page, n) =>
  page.evaluate(
    (count) => new Promise((resolve) => { let i = 0; const f = () => (++i >= count ? resolve() : requestAnimationFrame(f)); requestAnimationFrame(f); }),
    n,
  );

/** Wait (up to 3 s) until the engine reports the content-visibility:auto subtree skipped, without reading any style. */
export const waitSkipped = async (page) => {
  await page.waitForFunction(() => window.__cv.length > 0, null, { timeout: 3000 }).catch(() => {});
  return page.evaluate(() => ({ events: window.__cv.slice(), scrollY, innerHeight, top: document.getElementById('cv').getBoundingClientRect().top }));
};

export const TESTS = [
  {
    id: 'prem.anim.list', premise: 'anim.list', page: 'anim.list.html',
    async run({ page }) {
      const o = await page.evaluate(async () => {
        const describe = () => document.body.getAnimations({ subtree: true }).map((a) => ({
          kind: a instanceof CSSTransition ? 'transition' : a instanceof CSSAnimation ? 'animation' : 'other',
          target: a.effect.target.id,
          name: a instanceof CSSTransition ? a.transitionProperty : a instanceof CSSAnimation ? a.animationName : '',
        }));
        for (const id of ['tr', 'quick']) { const e = document.getElementById(id); getComputedStyle(e).width; e.style.width = '90px'; }
        const t0 = performance.now();
        const lerp = document.getElementById('lerp'); let w = 10; let stop = false;
        const loop = () => { w += (90 - w) * 0.1; lerp.style.width = `${w}px`; if (!stop) requestAnimationFrame(loop); };
        requestAnimationFrame(loop);
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        const during = describe();
        // Elapsed ms from the style change to the `during` sample: above 300 the short transition may have ended
        // (a slow runner), so a failure then is a timing flake, not an engine difference (premise-ack, ledger
        // premise.anim.list).
        const msToDuring = Math.round(performance.now() - t0);
        await new Promise((r) => setTimeout(r, 1500)); // the 300 ms transition is long over
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        const after = describe();
        const lerpMoved = parseFloat(lerp.style.width) > 20;
        stop = true;
        return { during, after, lerpMoved, msToDuring };
      });
      const has = (l, target, kind) => l.some((x) => x.target === target && x.kind === kind);
      try {
        assert.ok(has(o.during, 'css', 'animation'), 'the CSS animation is listed');
        assert.ok(o.during.some((x) => x.target === 'css' && x.name === 'grow'), 'with its keyframes name');
        assert.ok(has(o.during, 'tr', 'transition'), 'the running CSS transition is listed');
        assert.ok(has(o.during, 'quick', 'transition'), 'the short transition is listed while running');
        assert.ok(o.lerpMoved, 'the rAF lerp really ran');
        assert.ok(!o.during.some((x) => x.target === 'lerp'), 'the rAF lerp is not listed');
        assert.ok(!has(o.after, 'quick', 'transition'), 'a finished transition leaves the list');
        assert.ok(has(o.after, 'css', 'animation') && has(o.after, 'tr', 'transition'), 'running ones stay');
      } catch (e) { e.observed = o; throw e; }
      return o;
    },
  },
  {
    id: 'prem.cv.auto-margin', premise: 'cv.auto-margin', page: 'cv.auto-margin.html',
    async run({ page }) {
      const state = await waitSkipped(page);
      const skipped = await page.evaluate(() => {
        const m = document.getElementById('m');
        return { margin: getComputedStyle(m).marginLeft, width: getComputedStyle(m).width, wasSkipped: window.__cv[0] === true };
      });
      skipped.state = state;
      await page.evaluate(() => document.getElementById('cv').scrollIntoView());
      await frames(page, 3);
      const shown = await page.evaluate(() => getComputedStyle(document.getElementById('m')).marginLeft);
      const observed = { skipped, shown };
      try {
        assert.equal(skipped.margin, 'auto', `skipped subtree reports unresolved auto margin, got ${skipped.margin}`);
        assert.match(shown, /^[0-9.]+px$/, `once rendered the margin resolves to px, got ${shown}`);
      } catch (e) { e.observed = observed; throw e; }
      return observed;
    },
  },
  {
    // The behaviour found when prem.cv.auto-margin was first run (both engines): a style read forces the lock open.
    id: 'prem.cv.read-forces-lock', premise: 'cv.read-forces-lock', page: 'cv.read-forces-lock.html',
    async run({ page }) {
      const state = await waitSkipped(page);
      const o = await page.evaluate(() => {
        const cs = getComputedStyle(document.getElementById('m'));
        return { skippedBefore: window.__cv[0] === true, margin: cs.marginLeft, width: cs.width, displayNoneMargin: getComputedStyle(document.getElementById('dm')).marginLeft };
      });
      o.state = state;
      try {
        assert.equal(o.skippedBefore, true, 'the engine reported the subtree skipped before the read');
        assert.equal(o.margin, '150px', 'a getComputedStyle read in a skipped subtree resolves the auto margin');
        assert.equal(o.width, '100px');
        assert.equal(o.displayNoneMargin, 'auto', 'control: only a display:none subtree reports the unresolved auto');
      } catch (e) { e.observed = o; throw e; }
      return o;
    },
  },
  {
    // The gate's skipped-subtree flag (Fw.Gate.Settle.viewCell): checkVisibility() true and the contentVisibilityAuto form false
    // exactly while the engine reports the subtree skipped; true on both once scrolled into view. No style is read before the flag.
    id: 'prem.cv.skip-flag', premise: 'cv.skip-flag', page: 'cv.skip-flag.html',
    async run({ page }) {
      const state = await waitSkipped(page);
      const flags = () => page.evaluate(() => {
        const f = (id) => { const e = document.getElementById(id); return { visible: e.checkVisibility(), visibleAuto: e.checkVisibility({ contentVisibilityAuto: true }) }; };
        return { m: f('m'), plain: f('plain'), events: window.__cv.slice() };
      });
      const skipped = await flags();
      await page.evaluate(() => document.getElementById('cv').scrollIntoView());
      await frames(page, 3);
      const shown = await flags();
      const observed = { state, skipped, shown };
      try {
        assert.equal(state.events[0], true, 'the engine reported the subtree skipped');
        assert.deepEqual(skipped.m, { visible: true, visibleAuto: false }, 'a node in the skipped subtree: checkVisibility() true, contentVisibilityAuto form false');
        assert.deepEqual(skipped.plain, { visible: true, visibleAuto: true }, 'control: an ordinary node is not flagged');
        assert.equal(skipped.events.at(-1), true, 'the flag read did not unlock the subtree');
        assert.deepEqual(shown.m, { visible: true, visibleAuto: true }, 'scrolled into view and two frames later the node is not flagged');
        assert.equal(shown.events.at(-1), false, 'the engine reports the subtree no longer skipped');
      } catch (e) { e.observed = observed; throw e; }
      return observed;
    },
  },
  {
    // fix-commission-margin: a subtree skipped through a viewport resize (one section static, one given its content while already
    // skipped) shows the fresh used auto margin, equal to the geometry-derived one, once it is brought into view.
    id: 'prem.cv.fresh-after-resize', premise: 'cv.fresh-after-resize', page: 'cv.fresh-after-resize.html',
    async run({ page }) {
      await page.setViewportSize({ width: 800, height: 600 });
      const state = await waitSkipped(page);
      await frames(page, 4); // the second section has its content now
      const lateSkipped = await page.evaluate(() => document.getElementById('lm').checkVisibility() && !document.getElementById('lm').checkVisibility({ contentVisibilityAuto: true }));
      await page.setViewportSize({ width: 1100, height: 600 });
      await frames(page, 3);
      const measure = (inner, section) => page.evaluate(([i, s]) => {
        const ie = document.getElementById(i), se = document.getElementById(s);
        const cs = getComputedStyle(ie);
        const r = ie.getBoundingClientRect(), sr = se.getBoundingClientRect();
        return { style: cs.marginLeft, geometry: r.left - sr.left - parseFloat(getComputedStyle(se).paddingLeft), width: r.width, innerWidth };
      }, [inner, section]);
      // Observed only, the gate's first reading: a read in a skipped subtree (not asserted).
      const lateBefore = await measure('lm', 'late');
      const out = {};
      for (const [inner, section] of [['m', 'cv'], ['lm', 'late']]) {
        await page.evaluate((s) => document.getElementById(s).scrollIntoView({ block: 'center' }), section);
        await frames(page, 3);
        out[inner] = await measure(inner, section);
      }
      const want = (1100 - 40 - 300) / 2;
      const observed = { state, lateSkipped, lateBefore, out, want };
      try {
        assert.equal(state.events[0], true, 'the first section was skipped at load');
        assert.equal(lateSkipped, true, 'the second section was skipped when its content arrived');
        for (const k of ['m', 'lm']) {
          assert.equal(out[k].innerWidth, 1100, `${k}: the page sees the new viewport`);
          assert.equal(out[k].width, 300, `${k}: width`);
          assert.equal(out[k].style, `${want}px`, `${k}: the used auto margin is fresh once the subtree is in view, got ${out[k].style}`);
          assert.ok(Math.abs(out[k].geometry - want) < 0.5, `${k}: the geometry-derived margin is ${out[k].geometry}, want ${want}`);
        }
      } catch (e) { e.observed = observed; throw e; }
      return observed;
    },
  },
  {
    // cmr-margin-typed-om: the margin read through the Typed OM (computedStyleMap) is the computed value, not the used one:
    // a CSSKeywordValue auto, a percent CSSUnitValue, a px CSSUnitValue, for the four keys, in normal flow, in a skipped
    // content-visibility:auto subtree (one subtree per read, each checked skipped just before its read) and under a scaled ancestor.
    id: 'prem.cv.margin-typed-om', premise: 'cv.margin-typed-om', page: 'cv.margin-typed-om.html',
    async run({ page }) {
      await page.waitForFunction(() => Object.keys(window.__cv).length === 12 && Object.values(window.__cv).every(Boolean), null, { timeout: 5000 }).catch(() => {});
      const o = await page.evaluate(() => {
        const keys = ['margin-left', 'margin-right', 'margin-inline-start', 'margin-inline-end'];
        const show = (v) => (v instanceof CSSKeywordValue ? { type: 'keyword', value: v.value }
          : v instanceof CSSUnitValue ? { type: 'unit', value: v.value, unit: v.unit } : { type: String(v && v.constructor && v.constructor.name) });
        const cells = {};
        const read = (caseName, kind, key, el, wantSkipped) => {
          const skippedBefore = !el.checkVisibility({ contentVisibilityAuto: true });
          const value = show(el.computedStyleMap().get(key));
          const skippedAfter = !el.checkVisibility({ contentVisibilityAuto: true });
          cells[`${caseName}|${kind}|${key}`] = { value, skippedBefore, skippedAfter, wantSkipped };
        };
        for (const kind of ['auto', 'pct', 'px']) {
          for (const key of keys) {
            read('normal', kind, key, document.getElementById(`n-${kind}`), false);
            read('scaled', kind, key, document.getElementById(`s-${kind}`), false);
            read('skipped', kind, key, document.getElementById(`node-${kind}:${key}`), true);
          }
        }
        return { cells, flags: { ...window.__cv }, scaleTransform: getComputedStyle(document.getElementById('scale')).transform };
      });
      const want = (kind, key) => {
        const first = key === 'margin-left' || key === 'margin-inline-start';
        if (kind === 'auto') return { type: 'keyword', value: 'auto' };
        if (kind === 'pct') return { type: 'unit', value: first ? 10 : 20, unit: 'percent' };
        return { type: 'unit', value: first ? 30 : 40, unit: 'px' };
      };
      const bad = [];
      for (const [name, c] of Object.entries(o.cells)) {
        const [, kind, key] = name.split('|');
        if (c.skippedBefore !== c.wantSkipped) bad.push(`${name}: expected skipped=${c.wantSkipped} before the read, saw ${c.skippedBefore}`);
        else if (c.skippedAfter !== c.wantSkipped) bad.push(`${name}: expected skipped=${c.wantSkipped} after the read, saw ${c.skippedAfter}`);
        else if (JSON.stringify(c.value) !== JSON.stringify(want(kind, key))) bad.push(`${name}: read ${JSON.stringify(c.value)}, want ${JSON.stringify(want(kind, key))}`);
      }
      try {
        assert.match(o.scaleTransform, /^matrix\(0\.9166/, 'the ancestor is scaled');
        assert.equal(bad.length, 0, `${bad.length} of ${Object.keys(o.cells).length} cells differ: ${bad.slice(0, 6).join('; ')}`);
      } catch (e) { e.observed = o; throw e; }
      return o;
    },
  },
  {
    id: 'prem.frame.raf-order', premise: 'frame.raf-order', page: 'frame.raf-order.html',
    async run({ page }) {
      const log = await page.evaluate(() => new Promise((resolve) => {
        const a = document.getElementById('a'); const log = [];
        new ResizeObserver((es) => log.push(`ro:${Math.round(es[0].contentRect.width)}`)).observe(a);
        const f = (n, then) => (n ? requestAnimationFrame(() => f(n - 1, then)) : then());
        f(4, () => { // the initial observation is delivered; start clean
          log.length = 0;
          setTimeout(() => {
            requestAnimationFrame(() => { log.push('raf1'); a.style.width = '50px'; });
            requestAnimationFrame(() => log.push('raf2'));
            setTimeout(() => resolve(log), 150);
          }, 0);
        });
      }));
      assert.deepEqual(log, ['raf1', 'raf2', 'ro:50'], 'rAF callbacks first, then the layout-time observer sees the rAF write');
      return { log };
    },
  },
  {
    id: 'prem.frame.ro-same-frame', premise: 'frame.ro-same-frame', page: 'frame.ro-same-frame.html',
    async run({ page }) {
      const log = await page.evaluate(() => new Promise((resolve) => {
        const a = document.getElementById('a'); const log = [];
        new ResizeObserver((es) => log.push(`ro:${Math.round(es[0].contentRect.width)}`)).observe(a);
        const f = (n, then) => (n ? requestAnimationFrame(() => f(n - 1, then)) : then());
        f(4, () => {
          log.length = 0;
          setTimeout(() => {
            a.style.width = '50px'; // the write happens outside any frame
            requestAnimationFrame(() => { log.push('raf-n'); requestAnimationFrame(() => log.push('raf-n+1')); });
            setTimeout(() => resolve(log), 150);
          }, 0);
        });
      }));
      assert.deepEqual(log, ['raf-n', 'ro:50', 'raf-n+1'], 'the RO callback runs in the frame of the write, before the next rAF');
      return { log };
    },
  },
  {
    id: 'prem.resize.lag', premise: 'resize.lag', page: 'resize.lag.html',
    async run({ page }) {
      const K = 2;
      await page.setViewportSize({ width: 800, height: 600 });
      await frames(page, 3);
      await page.evaluate(() => {
        const w = document.getElementById('w'); const q = document.getElementById('q'); window.__t = []; window.__stop = false;
        let ro = 0; new ResizeObserver((es) => { ro = es[0].contentRect.width; }).observe(w);
        const tick = () => {
          window.__t.push({ iw: innerWidth, ro, w: w.getBoundingClientRect().width, q: q.getBoundingClientRect().width, mq: matchMedia('(max-width: 600px)').matches });
          if (!window.__stop) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
      await frames(page, 3);
      await page.setViewportSize({ width: 500, height: 600 });
      await frames(page, 8);
      const t = await page.evaluate(() => { window.__stop = true; return window.__t; });
      const ok = (r) => r.iw === 500 && r.ro === 500 && r.w === 500 && r.q === 100 && r.mq === true;
      const i0 = t.findIndex((r) => r.iw === 500);
      assert.ok(i0 >= 0, 'the page sees the new viewport');
      let j = t.length; while (j > 0 && ok(t[j - 1])) j--; // first frame from which everything agrees
      assert.ok(j < t.length, 'the layout reflects the new viewport');
      assert.ok(j - i0 <= K, `layout lags the viewport by ${j - i0} frames, premise k = ${K}`);
      return { firstNewViewportFrame: i0, firstFullyAgreeingFrame: j, lag: j - i0, K };
    },
  },
  {
    id: 'prem.clock.raf-timeline', premise: 'clock.raf-timeline', page: 'clock.raf-timeline.html',
    async run({ page }) {
      const rows = await page.evaluate(() => new Promise((resolve) => {
        const rows = []; const f = (t) => {
          rows.push({ t, tl: document.timeline.currentTime, now: performance.now() });
          if (rows.length < 12) requestAnimationFrame(f); else resolve(rows);
        };
        requestAnimationFrame(f);
      }));
      const worst = Math.max(...rows.map((r) => Math.abs(r.t - Number(r.tl))));
      assert.ok(worst <= 1, `rAF time and timeline time differ by ${worst} ms (premise: offset 0 within 1 ms)`);
      assert.ok(rows.every((r) => r.now >= r.t - 1), 'rAF time is not in the future');
      return { worst, sample: rows[0] };
    },
  },
  {
    id: 'prem.css.number-linear', premise: 'css.number-linear', page: 'css.number-linear.html',
    async run({ page }) {
      await frames(page, 2);
      const v = await page.evaluate(() => ['p25', 'p50', 'p75'].map((id) => parseFloat(getComputedStyle(document.getElementById(id)).getPropertyValue('--n'))));
      [2.5, 5, 7.5].forEach((want, i) => assert.ok(Math.abs(v[i] - want) < 1e-6, `--n at ${(i + 1) * 25}% is ${v[i]}, want ${want}`));
      return { values: v };
    },
  },
  {
    id: 'prem.css.inherits-false', premise: 'css.inherits-false', page: 'css.inherits-false.html',
    async run({ page }) {
      const o = await page.evaluate(() => {
        const p = getComputedStyle(document.getElementById('parent')); const c = getComputedStyle(document.getElementById('child'));
        return { parentNo: p.getPropertyValue('--no').trim(), childNo: c.getPropertyValue('--no').trim(), childYes: c.getPropertyValue('--yes').trim() };
      });
      assert.equal(o.parentNo, '5');
      assert.equal(o.childNo, '0', 'inherits:false: the child reads the initial value');
      assert.equal(o.childYes, '5', 'control: inherits:true reaches the child');
      return o;
    },
  },
  {
    id: 'prem.dom.token-toggle-noop', premise: 'dom.token-toggle-noop', page: 'dom.token-toggle-noop.html',
    async run({ page }) {
      const counts = await page.evaluate(() => {
        const el = document.getElementById('el'); const mo = new MutationObserver(() => {}); mo.observe(el, { attributes: true });
        const step = (fn) => { fn(); return mo.takeRecords().length; };
        return [
          step(() => el.classList.toggle('a', true)), // present, force true
          step(() => el.classList.toggle('b', false)), // absent, force false
          step(() => el.classList.toggle('a', false)), // present, force false: a real change
          step(() => el.classList.toggle('a', false)), // now absent, force false
          step(() => el.classList.toggle('a', true)), // absent, force true: a real change
        ];
      });
      assert.deepEqual(counts, [0, 0, 1, 0, 1], 'toggle(token, force) writes the attribute only when presence changes');
      return { counts };
    },
  },
  {
    id: 'prem.dom.inline-same-value', premise: 'dom.inline-same-value', page: 'dom.inline-same-value.html',
    async run({ page }) {
      const counts = await page.evaluate(() => {
        const el = document.getElementById('el'); const mo = new MutationObserver(() => {}); mo.observe(el, { attributes: true });
        const step = (fn) => { fn(); return mo.takeRecords().length; };
        return [
          step(() => el.style.setProperty('opacity', '0.5')), // new value
          step(() => el.style.setProperty('opacity', '0.5')), // same value
          step(() => { el.style.opacity = '0.5'; }), // same value through the property
          step(() => el.style.setProperty('opacity', '0.6')), // new value
          step(() => el.style.setProperty('--exit-opacity', '1')), // new custom property
          step(() => el.style.setProperty('--exit-opacity', '1')), // same custom value
        ];
      });
      assert.deepEqual(counts, [1, 0, 0, 1, 1, 0], 'a same-value inline write is not a mutation');
      return { counts };
    },
  },
  {
    id: 'prem.read.forced-update', premise: 'read.forced-update', page: 'read.forced-update.html',
    async run({ page }) {
      const o = await page.evaluate(() => {
        const box = document.getElementById('box'); const top = document.getElementById('top');
        box.classList.add('wide'); const rect = box.getBoundingClientRect().width;
        box.style.width = '33px'; const computed = getComputedStyle(box).width;
        box.style.width = '44px'; const offset = box.offsetWidth;
        const before = document.elementFromPoint(50, 50).id;
        top.classList.add('off'); const off = document.elementFromPoint(50, 50).id;
        top.classList.remove('off'); const on = document.elementFromPoint(50, 50).id;
        return { rect, computed, offset, before, off, on };
      });
      assert.deepEqual(o, { rect: 70, computed: '33px', offset: 44, before: 'top', off: 'under', on: 'top' },
        'every read sees all earlier writes of the same task');
      return o;
    },
  },
  {
    id: 'prem.hit.pointer-events', premise: 'hit.pointer-events', page: 'hit.pointer-events.html',
    async run({ page }) {
      const o = await page.evaluate(() => {
        const ids = (x, y) => document.elementsFromPoint(x, y).map((e) => e.id).filter(Boolean);
        return { top: document.elementFromPoint(50, 50).id, hole: document.elementFromPoint(150, 50).id, stackNone: ids(50, 50), stackHole: ids(150, 50) };
      });
      assert.equal(o.top, 'under', 'pointer-events:none layer is skipped');
      assert.equal(o.hole, 'hole', 'a pointer-events:auto child of a none parent is hit');
      assert.ok(!o.stackNone.includes('layer') && !o.stackHole.includes('layer'), 'the none box itself is never in the stack');
      assert.ok(o.stackHole.includes('hole') && o.stackHole.includes('under'));
      return o;
    },
  },
  {
    id: 'prem.layout.unit-truncation', premise: 'layout.unit-truncation', page: 'layout.unit-truncation.html',
    async run({ page }) {
      const got = await page.evaluate(() => ['w1', 'w2', 'w3', 'w4'].map((id) => document.getElementById(id).getBoundingClientRect().width));
      const want = [10.01, 10.02, 100.99, 33.3333].map((x) => Math.floor(x * 64) / 64);
      assert.deepEqual(got, want, 'lengths truncate to 1/64 px');
      return { got, want };
    },
  },
  {
    id: 'prem.io.async-delivery', premise: 'io.async-delivery', page: 'io.async-delivery.html',
    async run({ page }) {
      const K = 3;
      const o = await page.evaluate(() => new Promise((resolve) => {
        let inObserve = false; let frame = 0; let syncDelivery = false; let deliveredAt = -1;
        const io = new IntersectionObserver(() => { if (inObserve) syncDelivery = true; if (deliveredAt < 0) deliveredAt = frame; });
        const tick = () => {
          frame++;
          if (frame === 1) { inObserve = true; io.observe(document.getElementById('t')); inObserve = false; }
          if (frame < 10) requestAnimationFrame(tick); else resolve({ syncDelivery, deliveredAt });
        };
        requestAnimationFrame(tick);
      }));
      assert.equal(o.syncDelivery, false, 'observe() never calls back synchronously');
      assert.ok(o.deliveredAt >= 1, 'not delivered inside the observing rAF callback');
      assert.ok(o.deliveredAt - 1 <= K, `delivered ${o.deliveredAt - 1} frames after observing, premise k = ${K}`);
      return { ...o, K };
    },
  },
  {
    id: 'prem.grid.normal-aspect-ratio-no-stretch', premise: 'grid.normal-aspect-ratio-no-stretch', page: 'grid.normal-aspect-ratio-no-stretch.html',
    async run({ page }) {
      // fresh grids, each in a 300 px row taller than the ratio box: n/s/t = normal/start/stretch on a ratio box,
      // m = normal on a block without a ratio. normal on the ratio box is engine-dependent (CI run 39080496538:
      // Chromium fills the row, WebKit gives the ratio height), so it is observed only (Lean modeOf_normal_ratio).
      const read = () => page.evaluate(() => ['n', 's', 't', 'm'].map((id) => {
        const r = document.querySelector(`#${id} > :first-child`).getBoundingClientRect();
        return { w: r.width, h: r.height };
      }));
      const fresh = await read();
      const [n, s, t, m] = fresh;
      const ratioH = s.w * 512 / 640;
      assert.ok(Math.abs(s.h - ratioH) <= 1 / 64, `start: ratio height ${ratioH}, got ${s.h}`);
      assert.equal(t.h, 300, 'stretch fills the 300 px row');
      assert.equal(m.h, 300, 'normal without an aspect ratio fills the row as stretch does');
      const normalWithRatio = Math.abs(n.h - 300) <= 1 / 64 ? 'fill' : Math.abs(n.h - ratioH) <= 1 / 64 ? 'content' : 'neither';
      // observed only (the WebKit stale-track question of fix-stagebg-webkit): a width change and back
      const vp = page.viewportSize();
      await page.setViewportSize({ width: vp.width - 100, height: vp.height });
      await frames(page, 3);
      const narrow = await read();
      await page.setViewportSize(vp);
      await frames(page, 3);
      const after = await read();
      return { normalWithRatio, fresh, narrow, after, ratioH };
    },
  },
  {
    id: 'prem.grid.stretch-fill-equals-start', premise: 'grid.stretch-fill-equals-start', page: 'grid.stretch-fill-equals-start.html',
    async run({ page }) {
      const arg = {
        parts: { p: [{ role: 'a', selector: '#a > .slot' }, { role: 'b', selector: '#b > .slot' }, { role: 'c', selector: '#c > .slot' }] },
        props: { p: { a: ['align-self'], b: ['align-self'], c: ['align-self'] } },
      };
      const read = async () => {
        const f = (await page.evaluate(collectAlignFacts, arg)).p;
        return { a: f.a[0], b: f.b[0], c: f.c[0] };
      };
      const { a, b, c } = await read();
      assert.deepEqual([modeOf(a), modeOf(b), modeOf(c)], ['content', 'fill', 'fill'], 'modes: start, stretched slot, stretched ratio box');
      const rows = parseTracks(a.rows);
      assert.ok(rows !== null && rows.length === 2, `resolved grid-template-rows lists both rows: ${a.rows}`);
      assert.ok(Math.abs(rows[0] - a.rectHeight) <= 1 / 64, `row 1 (${rows[0]}) is the start-aligned slot's height (${a.rectHeight})`);
      assert.equal(contentFill(a), true, 'the start-aligned slot fills its row (Fw.Gate.AlignEquiv.contentFill)');
      assert.equal(b.rectHeight, a.rectHeight, 'stretch places the slot as start does');
      assert.equal(c.rectHeight, a.rectHeight, 'the stretched ratio box (original shape) has the same height');
      assert.equal(b.rectTop - b.parentRectTop, a.rectTop - a.parentRectTop, 'same offset in the row');
      assert.equal(alignEquiv(b, a) && alignEquiv(c, a), true, 'the rule judges both pairs equivalent');
      // observed only: the same facts after a width change and back
      const vp = page.viewportSize();
      await page.setViewportSize({ width: vp.width - 100, height: vp.height });
      await frames(page, 3);
      await page.setViewportSize(vp);
      await frames(page, 3);
      const after = await read();
      const h = (x) => ({ rows: x.rows, h: x.rectHeight, top: x.rectTop - x.parentRectTop });
      return {
        fresh: { a: h(a), b: h(b), c: h(c) },
        after: { a: h(after.a), b: h(after.b), c: h(after.c), fills: contentFill(after.a), equiv: alignEquiv(after.b, after.a) && alignEquiv(after.c, after.a) },
      };
    },
  },
  {
    id: 'prem.sweep.layer-pixels', premise: 'sweep.layer-pixels', page: 'sweep.layer-pixels.html',
    async run({ page }) {
      await page.setViewportSize({ width: 800, height: 1680 });
      await frames(page, 3);
      const shot = (await page.screenshot({ clip: { x: 0, y: 0, width: 800, height: 1680 } })).toString('base64');
      const geo = await page.evaluate(() => {
        const r = (e) => { const b = e.getBoundingClientRect(); return [b.x, b.y, b.width, b.height]; };
        const d = document.querySelector('div.t0');
        return { a: r(d.querySelector('.a')), b: r(d.querySelector('.b')), i: r(d.querySelector('.b i')),
          times: document.getAnimations().slice(0, 4).map((x) => [x.playState, x.currentTime]), dpr: devicePixelRatio };
      });
      const o = await page.evaluate(async (b64) => {
        const bmp = await createImageBitmap(await (await fetch(`data:image/png;base64,${b64}`)).blob());
        const c = document.createElement('canvas'); c.width = bmp.width; c.height = bmp.height;
        const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(bmp, 0, 0);
        const px = g.getImageData(0, 0, c.width, c.height).data;
        const scale = bmp.width / 800;
        const rows = []; const where = [];
        for (let i = 0; i < 5; i++) {
          let max = 0; let n = 0; let big = 0; let sat = 0; let satB = 0; let wordMax = 0; let corner = 0;
          for (let y = 0; y < 60 * scale; y++) for (let x = 0; x < bmp.width; x++) {
            const a = ((i * 120 * scale + y) * bmp.width + x) * 4; const b = ((i * 120 * scale + 60 * scale + y) * bmp.width + x) * 4;
            let d = 0; for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(px[a + k] - px[b + k]));
            if (d > 0) n++; if (d > 40) big++; if (d > max) max = d;
            if (x < 4 && y < 4) { if (d > corner) corner = d; } else if (d > wordMax) wordMax = d;
            if (d > 40 && where.length < 16) where.push({ row: i, x, y, orig: [px[a], px[a + 1], px[a + 2]], layer: [px[b], px[b + 1], px[b + 2]] });
            if (Math.max(px[a], px[a + 1], px[a + 2]) - Math.min(px[a], px[a + 1], px[a + 2]) > 100) sat++;
            if (Math.max(px[b], px[b + 1], px[b + 2]) - Math.min(px[b], px[b + 1], px[b + 2]) > 100) satB++;
          }
          rows.push({ max, wordMax, corner, differing: n, over40: big, saturated: sat, saturatedLayer: satB });
        }
        const cmp = (ra, rb) => { let m = 0; for (let y = 0; y < 60 * scale; y++) for (let x = 0; x < bmp.width; x++) { const a = ((ra * 60 * scale + y) * bmp.width + x) * 4; const b = ((rb * 60 * scale + y) * bmp.width + x) * 4; for (let k = 0; k < 3; k++) m = Math.max(m, Math.abs(px[a + k] - px[b + k])); } return m; };
        const seam = { repeatVsNoRepeat: cmp(0, 10), layerVsNoRepeat: cmp(1, 10), layerVsRepeat: cmp(0, 1), delayMinus1ms: cmp(12, 13), noWillChange: cmp(14, 15), clipVsOrig: cmp(16, 17), clipDelayVsOrig: cmp(18, 19), clipPathVsOrig: cmp(20, 21), unsnappedVsOrig: cmp(22, 23), flatWhite: cmp(24, 25), flatWhiteHalf: cmp(26, 27) };
        const lst = (ra, rb) => { const out = []; for (let y = 0; y < 60 * scale; y++) for (let x = 0; x < bmp.width; x++) { const a = ((ra * 60 * scale + y) * bmp.width + x) * 4; const b = ((rb * 60 * scale + y) * bmp.width + x) * 4; let d = 0; for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(px[a + k] - px[b + k])); if (d > 0 && out.length < 12) out.push({ x, y, d, a: [px[a], px[a + 1], px[a + 2]], b: [px[b], px[b + 1], px[b + 2]] }); } return out; };
        const seamPixels = { origVsLayer: lst(0, 1), origVsNoRepeat: lst(0, 10), noRepeatVsLayer: lst(10, 1), clipPath: lst(20, 21), unsnapped: lst(22, 23), flatWhite: lst(24, 25), flatWhiteHalf: lst(26, 27) };
        const lit = (i) => { let m = 0; for (let y = 0; y < 60 * scale; y++) for (let x = 0; x < bmp.width; x++) { const a = ((i * 120 * scale + y) * bmp.width + x) * 4; m = Math.max(m, px[a], px[a + 1], px[a + 2]); } return m; };
        return { rows, where, seam, seamPixels, lit: lit(0) };
      }, shot);
      o.geo = geo;
      assert.ok(o.lit > 200, `the page is drawn (brightest channel ${o.lit})`);
      o.rows.slice(1, 4).forEach((r, i) => assert.ok(r.saturated > 100 && r.saturatedLayer > 100, `time ${i + 1}: both words show the colour band (${r.saturated}, ${r.saturatedLayer} saturated pixels)`));
      const worst = Math.max(...o.rows.map((r) => r.max));
      if (worst > 40) throw Object.assign(new Error(`a pixel differs by ${worst} of 255 (premise: within 40)`), { observed: o });
      return o;
    },
  },
  {
    id: 'prem.glint.hold-pixels', premise: 'glint.hold-pixels', page: 'glint.hold-pixels.html',
    async run({ page }) {
      await page.setViewportSize({ width: 520, height: 130 });
      await frames(page, 3);
      await page.evaluate(() => window.start('paused-first'));
      const plan = [0, 0.4, 0.999, 1, 1.001, 1.6, 2, 2.5, 2.999, 3, 3.6, 4, 4.5, 4.999, 5, 5.001, 6, 7.5, 9.999, 10, 11, 12, 14.5, 15, 16, 17.5, 19.99, 20, 21.2, 23]
        .map((s, i) => ({ s, mode: i % 3 === 2 ? 'resume' : 'seek' }));
      plan.push({ s: 3.3, mode: 'back' }, { s: 0.2, mode: 'back' });
      const shots = [];
      const anim = [];
      for (const { s, mode } of plan) {
        await page.evaluate(([t, m]) => {
          for (const svg of document.querySelectorAll('svg')) {
            if (m !== 'seek') svg.unpauseAnimations();
            svg.setCurrentTime(10 + t);
            if (m !== 'seek') svg.pauseAnimations();
          }
        }, [s, mode]);
        await frames(page, 2);
        anim.push(await page.evaluate(() => ['oL', 'hL', 'oR', 'hR'].map((id) => { const g = document.getElementById(`${id}-g`); return [g.x1.animVal.value, g.x2.animVal.value]; })));
        shots.push((await page.screenshot({ clip: { x: 0, y: 0, width: 520, height: 130 } })).toString('base64'));
      }
      const rows = await page.evaluate(async (list) => {
        const out = [];
        for (const b64 of list) {
          const bmp = await createImageBitmap(await (await fetch(`data:image/png;base64,${b64}`)).blob());
          const c = document.createElement('canvas'); c.width = bmp.width; c.height = bmp.height;
          const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(bmp, 0, 0);
          const px = g.getImageData(0, 0, c.width, c.height).data;
          const k = bmp.width / 520;
          const diff = (ra, rb) => {
            let m = 0; let sat = 0;
            for (let y = 2 * k; y < 18 * k; y++) for (let x = 0; x < bmp.width; x++) {
              const a = ((ra * 30 * k + y) * bmp.width + x) * 4; const b = ((rb * 30 * k + y) * bmp.width + x) * 4;
              for (let i = 0; i < 3; i++) m = Math.max(m, Math.abs(px[a + i] - px[b + i]));
              if (Math.max(px[a], px[a + 1], px[a + 2]) - Math.min(px[a], px[a + 1], px[a + 2]) > 100) sat++;
            }
            return [m, sat];
          };
          const l = diff(0, 1); const r = diff(2, 3);
          out.push({ left: l[0], right: r[0], satLeft: l[1], satRight: r[1] });
        }
        return out;
      }, shots);
      const o = { samples: plan.map((p, i) => ({ ...p, ...rows[i], anim: anim[i] })) };
      assert.ok(o.samples.some((x) => x.satLeft > 100) && o.samples.some((x) => x.satRight > 100), 'the colour band is drawn in both dashes');
      const moved = new Set(o.samples.map((x) => x.anim[0][0].toFixed(3))).size;
      assert.ok(moved >= 5, `the original gradient moves over the samples (${moved} distinct x1)`);
      const judged = o.samples.filter((x) => x.mode !== 'back');
      const worst = Math.max(...judged.map((x) => Math.max(x.left, x.right)));
      o.backWorst = Math.max(...o.samples.filter((x) => x.mode === 'back').map((x) => Math.max(x.left, x.right)));
      o.worst = worst;
      if (worst > 12) throw Object.assign(new Error(`a pixel differs by ${worst} of 255 (premise: within 12)`), { observed: o });
      return o;
    },
  },
];
