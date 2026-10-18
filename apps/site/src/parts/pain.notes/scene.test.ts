import { describe, expect, it } from 'vitest';
import { createScene, type SceneEnv } from './scene';

function fake(rect: { top: number; bottom: number } | null) {
  const frames: Array<() => void> = [];
  const log: string[] = [];
  let render: 'active' | 'deferred' | null = null;
  const env: SceneEnv = {
    sectionRect: () => rect,
    innerHeight: () => 900,
    frame: (cb) => {
      frames.push(cb);
      return () => {
        const i = frames.indexOf(cb);
        if (i >= 0) frames.splice(i, 1);
      };
    },
    setScene: (s) => log.push(`scene ${s}`),
    getRender: () => render,
    setRender: (s) => {
      render = s;
      log.push(`render ${s}`);
    },
    setIntrinsic: (px) => log.push(`size ${px}`),
    onActivate: () => log.push('activate'),
  };
  const run = () => frames.shift()?.();
  return { env, log, run, render: () => render };
}

describe('pain.notes scene', () => {
  it('an out-of-range section is deferred two frames after mount', () => {
    const f = fake({ top: 4085, bottom: 5800 });
    const s = createScene(f.env);
    s.start();
    expect(s.active()).toBe(false);
    expect(f.render()).toBeNull();
    f.run();
    expect(f.render()).toBeNull();
    f.run();
    expect(f.render()).toBe('deferred');
    expect(f.log).toContain('size 1715');
  });
  it('an in-range section is active at once; out then back in cancels the pending defer', () => {
    const f = fake({ top: 0, bottom: 900 });
    const s = createScene(f.env);
    s.start();
    expect(f.render()).toBe('active');
    s.intersect(false);
    f.run();
    s.intersect(true);
    f.run();
    f.run();
    expect(f.render()).toBe('active');
    expect(s.active()).toBe(true);
  });
  it('leaving the range again defers it after two frames', () => {
    const f = fake({ top: 4085, bottom: 5800 });
    const s = createScene(f.env);
    s.start();
    f.run();
    f.run();
    s.intersect(true);
    expect(f.render()).toBe('active');
    s.intersect(false);
    f.run();
    f.run();
    expect(f.render()).toBe('deferred');
  });
});
