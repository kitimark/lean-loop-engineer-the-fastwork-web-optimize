import { useEffect } from 'react';
import { matchList } from '../nav/media';
import { createGeomDriver, type AnimHandle, type GeomEnv } from './driver';
import { enter, find, leave } from './tree';
import type { Eng } from './tracks';
import { createTimedGeom, type TimedAnim } from '../morph.tween/geom-timed.driver';
import { timedBus } from '../morph.tween/geom-timed.bus';
import './geom.css';

export const GEOM_ON = 'on';
const NAV = '[data-fw="nav"]';

export function probeEngine(): Eng {
  const e = document.createElement('div');
  e.style.cssText = 'position:fixed;visibility:hidden;padding-inline:0;transition:padding-inline 1s';
  document.body.append(e);
  void getComputedStyle(e).paddingLeft;
  e.style.paddingInline = '8px';
  void getComputedStyle(e).paddingLeft;
  const started = e.getAnimations().length > 0;
  e.remove();
  return started ? 'chromium' : 'webkit';
}

const CAMEL: Record<string, string> = { 'backdrop-filter': 'backdropFilter' };

let goalStyle: HTMLStyleElement | null = null;

/** The goal rules as the base style of the root (attribute `data-mg-goal`), or removed. */
function setGoal(rules: string | null): void {
  const root = document.documentElement;
  if (rules === null) {
    root.removeAttribute('data-mg-goal');
    goalStyle?.remove();
    goalStyle = null;
    return;
  }
  if (!goalStyle) {
    goalStyle = document.createElement('style');
    document.head.append(goalStyle);
  }
  if (goalStyle.textContent !== rules) goalStyle.textContent = rules;
  root.setAttribute('data-mg-goal', '');
}

export function MorphGeom() {
  useEffect(() => {
    if (window.__fw?.config.variants['morph.geom'] !== GEOM_ON) return;
    const nav = document.querySelector<HTMLElement>(NAV);
    if (!nav) return;
    const reduce = matchList('mq.rm-reduce');
    const eng = probeEngine();
    const env: GeomEnv = {
      allowed: () => nav.classList.contains('is-on-dark') && !(reduce?.matches ?? false),
      enter: () => enter(nav, eng),
      leave: () => leave(nav),
      animate: (a, kf, duration) => {
        const target = find(a);
        if (!target) return null;
        const frames = kf.map((f) => Object.fromEntries(Object.entries(f).map(([k, v]) => [CAMEL[k] ?? k, v])));
        const anim = target.animate(frames, { duration, fill: 'both', easing: 'linear' });
        anim.pause();
        return anim as AnimHandle;
      },
    };
    if (window.__fw?.config.variants['morph.tween'] === 'geom-timed') {
      // morph.tween:geom-timed drives the geometry by the push, not by the published value: no observer
      const timed = createTimedGeom({
        ...env,
        animate: (a, kf, opts) => {
          const target = find(a);
          if (!target) return null;
          const frames = kf.map((f) => Object.fromEntries(Object.entries(f).map(([k, v]) => [CAMEL[k] ?? k, v])));
          return target.animate(frames, opts) as unknown as TimedAnim;
        },
        goal: (rules) => setGoal(rules),
      });
      timedBus.set(timed);
      return () => {
        timedBus.set(null);
        timed.dispose();
        setGoal(null);
      };
    }
    const driver = createGeomDriver(env);
    const read = () => {
      const m = Number.parseFloat(nav.dataset.fwMorph ?? '');
      driver.apply(Number.isFinite(m) ? m : 0);
    };
    const mo = new MutationObserver(read);
    mo.observe(nav, { attributes: true, attributeFilter: ['data-fw-morph'] });
    read();
    return () => {
      mo.disconnect();
      driver.dispose();
    };
  }, []);
  return null;
}
