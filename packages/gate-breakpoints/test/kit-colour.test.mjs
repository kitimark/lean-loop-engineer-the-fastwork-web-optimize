// The kit's colour reading (src/trajectory/kit.mjs `colour`) against the vectors Lean generates (lean/Fw/Gate/Colour.lean,
// golden/gate/trajectory-colour.jsonl), against an independent forward conversion, and against the judge (reduce.mjs).
// Nothing is decided here: the error budget (chanErr, alphaErr) is the Lean constant and this file measures that the kit stays inside it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { installKit } from '../src/trajectory/kit.mjs';
import { TOL, judgeVal } from '../src/trajectory/reduce.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory-colour.jsonl', import.meta.url)), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const bounds = golden.find((l) => l.kind === 'bounds');

/** The kit as the probe runs it: its source text evaluated in a bare `window`, so it holds no closure over this module. */
const kit = (() => {
  const win = {};
  const g = globalThis;
  const had = Object.getOwnPropertyDescriptor(g, 'window');
  g.window = win;
  try { (0, eval)(`(${installKit.toString()})()`); } finally { if (had) Object.defineProperty(g, 'window', had); else delete g.window; }
  return win.__traj;
})();
const colour = kit.colour;

test('the golden file carries the judge tolerance the Lean budget is proved against', () => {
  assert.equal(bounds.tolColour, TOL.colour);
  assert.ok(2 * bounds.alphaErr <= bounds.tolColour && 2 * bounds.chanErr <= bounds.tolColour);
});

test('every Lean colour vector: the kit reads the same sRGB x1000 within the slack', () => {
  const cs = golden.filter((l) => l.kind === 'colour');
  assert.ok(cs.length >= 20);
  for (const l of cs) {
    const got = colour(l.in);
    assert.ok(Array.isArray(got) && got.length === 4, `${l.name}: ${l.in} -> ${JSON.stringify(got)}`);
    got.forEach((x, i) => assert.ok(Math.abs(x - l.out[i]) <= bounds.slack, `${l.name} [${i}]: kit ${x}, Lean ${l.out[i]}`));
  }
});

test('strings that are not a converted colour stay strings', () => {
  for (const l of golden.filter((x) => x.kind === 'string')) assert.equal(colour(l.in), l.in);
  assert.equal(colour('rgb(1 2)'), 'rgb(1 2)');
  assert.equal(colour('oklab(calc(infinity) 0 0)'), 'oklab(calc(infinity) 0 0)');
  assert.equal(colour('lab(50% 0 0)'), 'lab(50% 0 0)');
});

test('the spelling of one colour does not change its reading', () => {
  const same = [
    'rgba(10, 20, 30, 0.5)', 'rgb(10 20 30 / 0.5)', 'rgb(10 20 30 / 50%)', 'color(srgb 0.0392157 0.0784314 0.117647 / 0.5)',
  ].map(colour);
  for (const r of same) r.forEach((x, i) => assert.ok(Math.abs(x - same[0][i]) <= 20, JSON.stringify(same)));
  assert.deepEqual(colour('rgb(255, 255, 255)'), [255000, 255000, 255000, 255000]);
  assert.deepEqual(colour('rgba(0, 0, 0, 0)'), [0, 0, 0, 0]);
});

test('no reading is -0', () => {
  for (const s of ['oklab(0 0 0)', 'rgba(0, 0, 0, 0)', 'color(srgb 0 0 0 / 0)', 'lab(0 0 0)']) {
    for (const x of colour(s)) assert.ok(!Object.is(x, -0), s);
  }
});

// Independent reference: sRGB to Oklab with Ottosson's own matrices (bottosson.github.io/posts/oklab), not the ones in the kit.
const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const toOklab = (r, g, b) => {
  const [R, G, B] = [r, g, b].map(lin);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
};
// 6 significant digits, the way both engines print a component (WebKit FormattedCSSNumber, Chromium AppendNumber(.., 6))
const print6 = (x) => String(Number(x.toPrecision(6)));

test('oklab printed to 6 digits reads back within the Lean channel budget, over a grid of the sRGB cube', (t) => {
  let worst = 0;
  const steps = [0, 1, 2, 3, 5, 8, 13, 30, 64, 100, 128, 160, 200, 230, 254, 255];
  for (const r of steps) for (const g of steps) for (const b of steps) {
    const [L, A, B] = toOklab(r / 255, g / 255, b / 255);
    const got = colour(`oklab(${print6(L)} ${print6(A)} ${print6(B)})`);
    [r, g, b].forEach((v, i) => { worst = Math.max(worst, Math.abs(got[i] - v * 1000)); });
  }
  t.diagnostic(`worst channel error ${worst}`);
  assert.ok(worst <= bounds.chanErr, `worst channel error ${worst}`);
  // MEASURED bound, so a looser budget in Lean than the data needs shows up in review
  assert.ok(worst < 200, `worst channel error ${worst}`);
});

test('oklch and lch agree with oklab and lab on the same colour', () => {
  const [L, A, B] = [0.62, 0.11, -0.07];
  const ch = Math.hypot(A, B), h = (Math.atan2(B, A) * 180) / Math.PI;
  const a = colour(`oklab(${L} ${A} ${B})`), b = colour(`oklch(${L} ${ch} ${h < 0 ? h + 360 : h})`);
  a.forEach((x, i) => assert.ok(Math.abs(x - b[i]) <= 2, `oklch ${i}`));
  const c = colour('lab(40 30 -20)'), d = colour(`lch(40 ${Math.hypot(30, -20)} ${(Math.atan2(-20, 30) * 180) / Math.PI + 360})`);
  c.forEach((x, i) => assert.ok(Math.abs(x - d[i]) <= 2, `lch ${i}`));
});

test('alpha: the engines round it to 8 bit and print 2 or 3 decimals, within the Lean alpha budget', (t) => {
  // Chromium color.cc SerializeLegacyColorAsCSSColor 1084-1096 (WebKit ColorSerialization.cpp 609-618 prints the same 8 bit value)
  let worst = 0;
  for (let k = 0; k <= 1000; k++) {
    const alpha = k / 1000;
    const int = Math.min(255, Math.max(0, Math.round((alpha + 1e-7) * 255)));
    const two = Math.round((int * 100) / 255) / 100;
    const printed = Math.round(two * 255) === int ? two.toFixed(2) : (Math.round((int * 1000) / 255) / 1000).toFixed(3);
    const got = colour(`rgba(1, 2, 3, ${printed})`)[3];
    worst = Math.max(worst, Math.abs(got - alpha * 255000));
  }
  t.diagnostic(`worst alpha error ${worst}`);
  assert.ok(worst <= bounds.alphaErr,`worst alpha error ${worst}`);
});

test('the judge: one colour read in oklab and in rgb is a pass, a different colour still fails', () => {
  const white = colour('rgb(255, 255, 255)');
  const oklabWhite = colour('oklab(1 0 0)');
  assert.equal(judgeVal('colour', [oklabWhite], white), 'pass');
  // the stored Chromium late-close tuple: oklab 0.989 grey, alpha 0.103 against the candidate rgb(255,255,255,0.1)
  assert.equal(judgeVal('colour', [colour('oklab(0.989 0 0 / 0.10344)')], colour('rgba(251, 251, 251, 0.1)')), 'pass');
  // the same pair compared as raw numbers was far outside the tolerance before the kit normalised: L x 1000 against 255
  assert.equal(judgeVal('colour', [colour('oklab(0.3 -0.01 -0.03)')], colour('rgb(255, 255, 255)')), 'fail:apart');
  // the logo bug: white on the dark panel in the original, still dark in the rewrite
  assert.equal(judgeVal('colour', [colour('rgb(255, 255, 255)')], colour('rgb(43, 49, 59)')), 'fail:apart');
  assert.equal(judgeVal('colour', [colour('oklab(0.95 0 0)')], colour('rgb(43, 49, 59)')), 'fail:apart');
});
