import { describe, expect, it } from 'vitest';
import { band, EASING, markerDelay, MARKER_THETAS, TIMING } from './waapi.logic';
import { waapiRun } from './waapi.fake.testutil';

describe('morph.tween:waapi driver', () => {
  it('a taken push starts one animation per element with the effect easing and startTime = timeline time at the push (R5)', () => {
    const w = waapiRun();
    w.setTimeline(777.25);
    expect(w.wheel(100)).toBe(true);
    expect(w.calls.map((c) => c.target)).toEqual(['nav', 'platform']);
    for (const c of w.calls) {
      expect(c.options).toEqual(TIMING);
      expect(TIMING.easing).toBe(EASING);
      expect(TIMING.duration).toBe(680);
      expect(TIMING.fill).toBe('both');
      expect(c.anim.startTime).toBe(777.25);
      expect(c.keyframes.every((k) => !('easing' in k))).toBe(true); // easing on the effect, not per keyframe
    }
    expect(w.clockSubscribes()).toBe(0);
  });

  it('startTime stays unset when the timeline is inactive', () => {
    const w = waapiRun();
    w.setTimeline(null);
    w.wheel(100);
    expect(w.calls[0]!.anim.startTime).toBeNull();
  });

  it('a second push to the same goal is a no-op; the opposite goal retargets from the live value', () => {
    const w = waapiRun();
    w.wheel(100);
    w.wheel(100);
    expect(w.calls).toHaveLength(2);
    w.calls[0]!.anim.progress = 0.5;
    w.wheel(-100);
    expect(w.calls).toHaveLength(4);
    expect(w.calls[0]!.anim.cancelled && w.calls[1]!.anim.cancelled).toBe(true);
    const kf = w.calls[2]!.keyframes;
    expect(kf[0]).toMatchObject({ offset: 0, '--morph': '0.5' });
    expect(kf[kf.length - 1]).toMatchObject({ offset: 1, '--morph': '0' });
  });

  it('the finish publishes the end, and the opposite push then closes (not a no-op)', () => {
    const w = waapiRun();
    w.wheel(100);
    w.finish();
    expect(w.hints).toEqual([0, 1]);
    expect(w.d.state()).toMatchObject({ value: 1, pending: false });
    w.wheel(-100);
    expect(w.calls).toHaveLength(4);
  });

  it('reduced motion jumps with no animation', () => {
    const w = waapiRun({ reduced: true });
    expect(w.wheel(100)).toBe(true);
    expect(w.calls).toHaveLength(0);
    expect(w.settled).toHaveLength(1);
    expect(w.settled[0]!.value).toBe(1);
  });

  it('an upward push at rest is not taken', () => {
    const w = waapiRun();
    expect(w.wheel(-100)).toBe(false);
    expect(w.calls).toHaveLength(0);
  });

  it('a push starts one marker per threshold ahead, all at the push start time', () => {
    const w = waapiRun();
    w.setTimeline(0);
    w.wheel(100);
    expect(w.markers.map((m) => m.duration)).toEqual(MARKER_THETAS.map((th) => markerDelay(0, 1, th)));
    expect(w.markers.every((m) => m.startTime === 0)).toBe(true);
  });

  it('a marker that finishes before the crossing writes each frame until the value is past its threshold', () => {
    const w = waapiRun();
    w.setTimeline(0);
    w.wheel(100);
    const d = markerDelay(0, 1, 1 / 5);
    w.frameAt(d);
    expect(w.clockSubscribes()).toBe(1);
    expect(w.hints.at(-1)!).toBeLessThanOrEqual(1 / 5);
    w.frameAt(d + 17);
    expect(w.hints.at(-1)!).toBeGreaterThan(1 / 5);
    const n = w.hints.length;
    w.frameAt(d + 34);
    expect(w.hints).toHaveLength(n);
  });

  it('a retarget cancels the markers and the frame callback of the old push', () => {
    const w = waapiRun();
    w.setTimeline(0);
    w.wheel(100);
    const old = [...w.markers];
    w.frameAt(markerDelay(0, 1, 1 / 5));
    w.setTimeline(60);
    w.wheel(-100);
    expect(old.every((m) => m.cancelled)).toBe(true);
    const n = w.hints.length;
    w.frameAt(61);
    expect(w.hints).toHaveLength(n);
    expect(band(w.hints.at(-1)!)).toEqual(band(w.d.state().value));
  });
});
