// RG8 (gap R8): IEEE double check of MT1/MT2 (lean/Fw/Parts/MorphTweenOpt.lean).
// The WAAPI variant of morph.tween uses `cubic-bezier(1/3, 1, 2/3, 1)`. In exact arithmetic that curve is the
// original's ease 1-(1-x)^3 (theorem `bezier_eq_ease`), and a solver tolerance eps moves the value by at most
// 3*eps (`solver_exact`). This test replays, in JS doubles (= C++ double), the engines' own solve and compares it
// with the original's JS ease on 10^4 points of [0, 1].
//
// Replica restated (not copied) from the pinned sources, read by raw fetch at the pinned sha:
// - Chromium ui/gfx/geometry/cubic_bezier.cc@f842f52: coefficients :50-56, spline samples :170-175, SolveCurveX
//   :181-237 (spline guess, <= 4 Newton steps with exit |X(t)-x| < min(1e-7, eps), bisection with (t0+t1)*.5);
//   cubic_bezier.h:23-37 (Horner sampling), :55-60 (SolveWithEpsilon); Solve() passes eps = 1e-7 (:239-241).
// - WebKit Source/WebCore/platform/graphics/UnitBezier.h@862f17d: coefficients :45-51, spline samples :89-91,
//   Horner :94-108, solveCurveX :111-160 (same algorithm, bisection with std::midpoint), solve :162-169.
//   WebKit's caller passes eps = 1/(1000 * duration_s) (TimingFunction.cpp:107-110, per the design note §4.1).
// Premise (INFERRED, not tested here): both CSS parsers keep the numbers as the doubles JS prints them as, so the
// control points are the doubles 1/3 and 2/3 (String(1/3) round-trips, checked below).
import { describe, expect, it } from 'vitest';
import { ease } from './logic';

const SPLINE_SAMPLES = 11;
const BEZIER_EPSILON = 1e-7;
const MAX_NEWTON = 4;

type Flavor = 'chromium' | 'webkit';
type Exit = 'newton' | 'newton-tail' | 'bisect' | 'fail';

interface Bezier {
  ax: number; bx: number; cx: number;
  ay: number; by: number; cy: number;
  samples: number[];
}

function makeBezier(p1x: number, p1y: number, p2x: number, p2y: number): Bezier {
  const cx = 3.0 * p1x;
  const bx = 3.0 * (p2x - p1x) - cx;
  const ax = 1.0 - cx - bx;
  const cy = 3.0 * p1y;
  const by = 3.0 * (p2y - p1y) - cy;
  const ay = 1.0 - cy - by;
  const b: Bezier = { ax, bx, cx, ay, by, cy, samples: [] };
  const deltaT = 1.0 / (SPLINE_SAMPLES - 1);
  for (let i = 0; i < SPLINE_SAMPLES; i++) b.samples.push(sampleX(b, i * deltaT));
  return b;
}

const sampleX = (b: Bezier, t: number) => ((b.ax * t + b.bx) * t + b.cx) * t;
const sampleY = (b: Bezier, t: number) => ((b.ay * t + b.by) * t + b.cy) * t;
const sampleDX = (b: Bezier, t: number) => (3.0 * b.ax * t + 2.0 * b.bx) * t + b.cx;

// libc++ std::midpoint for doubles with both |a|,|b| <= DBL_MAX/2 is (a + b) / 2, the same double as (a+b)*.5.
const mid = (flavor: Flavor, a: number, b: number) => (flavor === 'chromium' ? (b + a) * 0.5 : (a + b) / 2);

function solveCurveX(b: Bezier, x: number, epsilon: number, flavor: Flavor): { t: number; exit: Exit } {
  let t0 = 0.0;
  let t1 = 0.0;
  let t2 = x;
  let x2 = 0.0;
  let d2 = 0.0;
  const deltaT = 1.0 / (SPLINE_SAMPLES - 1);
  for (let i = 1; i < SPLINE_SAMPLES; i++) {
    if (x <= b.samples[i]) {
      t1 = deltaT * i;
      t0 = t1 - deltaT;
      t2 = t0 + ((t1 - t0) * (x - b.samples[i - 1])) / (b.samples[i] - b.samples[i - 1]);
      break;
    }
  }
  const newtonEpsilon = Math.min(BEZIER_EPSILON, epsilon);
  for (let i = 0; i < MAX_NEWTON; i++) {
    x2 = sampleX(b, t2) - x;
    if (Math.abs(x2) < newtonEpsilon) return { t: t2, exit: 'newton' };
    d2 = sampleDX(b, t2);
    if (Math.abs(d2) < BEZIER_EPSILON) break;
    t2 = t2 - x2 / d2;
  }
  if (Math.abs(x2) < epsilon) return { t: t2, exit: 'newton-tail' };
  while (t0 < t1) {
    x2 = sampleX(b, t2);
    if (Math.abs(x2 - x) < epsilon) return { t: t2, exit: 'bisect' };
    if (x > x2) t0 = t2;
    else t1 = t2;
    t2 = mid(flavor, t0, t1);
  }
  return { t: t2, exit: 'fail' };
}

/** The engines' value for 0 <= x <= 1 (the x < 0 / x > 1 gradient branches are never reached by a 0..1 progress). */
const solve = (b: Bezier, x: number, epsilon: number, flavor: Flavor) => {
  const r = solveCurveX(b, x, epsilon, flavor);
  return { y: sampleY(b, r.t), t: r.t, exit: r.exit };
};

/** The original's ease as its JS writes it (snapshot 2.DyWL8TcE.js:12688). */
const easeJs = (x: number) => 1 - (1 - x) ** 3;

const N = 10_000;
const points = Array.from({ length: N }, (_, i) => i / (N - 1));

const LANES: { flavor: Flavor; epsilon: number }[] = [
  { flavor: 'chromium', epsilon: BEZIER_EPSILON },
  { flavor: 'webkit', epsilon: 1 / (1000 * 0.68) },
];

describe('morph.tween curve: cubic-bezier(1/3,1,2/3,1) in IEEE double (RG8)', () => {
  const b = makeBezier(1 / 3, 1, 2 / 3, 1);

  it('control points round-trip through their decimal text', () => {
    expect(Number(String(1 / 3))).toBe(1 / 3);
    expect(Number(String(2 / 3))).toBe(2 / 3);
  });

  it('x coefficients are exactly (1, 0, 0) in double, y are (3, -3, 1)', () => {
    expect(3.0 * (1 / 3)).toBe(1.0);
    expect(2 / 3 - 1 / 3).toBe(1 / 3);
    expect([b.cx, b.bx, b.ax]).toEqual([1, 0, 0]);
    expect([b.cy, b.by, b.ay]).toEqual([3, -3, 1]);
    expect(b.samples).toEqual(Array.from({ length: SPLINE_SAMPLES }, (_, i) => i * (1 / 10)));
  });

  for (const { flavor, epsilon } of LANES) {
    it(`${flavor} (eps ${epsilon.toExponential(3)}): engine value matches 1-(1-x)**3 to a few ulp on 10^4 points`, () => {
      let maxJs = 0;
      let maxLogic = 0;
      let maxDt = 0;
      const exits: Record<Exit, number> = { newton: 0, 'newton-tail': 0, bisect: 0, fail: 0 };
      for (const x of points) {
        const r = solve(b, x, epsilon, flavor);
        exits[r.exit]++;
        maxJs = Math.max(maxJs, Math.abs(r.y - easeJs(x)));
        maxLogic = Math.max(maxLogic, Math.abs(r.y - ease({ x })));
        maxDt = Math.max(maxDt, Math.abs(r.t - x));
      }
      console.log(
        `RG8 ${flavor}: cx===1 ${b.cx === 1}, max|engine-easeJs| ${maxJs.toExponential(3)}, ` +
          `max|engine-logic.ease| ${maxLogic.toExponential(3)}, max|t-x| ${maxDt.toExponential(3)}, ` +
          `exits ${JSON.stringify(exits)}`,
      );
      // every solve leaves on the first Newton test (X(t) = t, spline guess t ~ x)
      expect(exits.newton).toBe(N);
      // MT2 in exact arithmetic gives 3*eps; in double the gap is a few ulp of 1
      expect(maxDt).toBeLessThanOrEqual(4 * Number.EPSILON);
      expect(maxJs).toBeLessThanOrEqual(8 * Number.EPSILON);
      expect(maxLogic).toBeLessThanOrEqual(8 * Number.EPSILON);
      // far inside one device pixel even on a 10^4 px span
      expect(maxJs * 10_000).toBeLessThan(1e-9);
    });
  }
});
