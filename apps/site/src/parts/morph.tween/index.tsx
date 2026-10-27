import { useEffect } from 'react';
import { getClock } from '../../engine/clock';
import { registerScroll } from '../../engine/scroll';
import { createThreadedFade, fadedBus, type FadeEl } from '../platform/fade.driver';
import { isBand } from '../morph.mount/listen.logic';
import { touchHub, type TouchClient, type TouchHub } from '../morph.mount/listen';
import { REST_VARIANT, setRest } from '../morph.panel/rest.logic';
import { THREADED } from '../morph.panel/threaded.logic';
import { createPanelEffects, createTweenDriver, type PanelEl, type TweenDriver, type TweenEnv } from './driver';
import { cfgOf, hooksOf } from './end.hooks';
import { timedBus } from './geom-timed.bus';
import { active } from './logic';
import { matchList } from './media';
import { hoverNoneOf, lockAllowed, overlayOf } from './scroll-lock.logic';
import { createWaapiDriver, type AnimLike, type AnimTarget, type WaapiEnv } from './waapi.driver';
import { fadeCss, PROP_MORPH, registrationsOf, type WaapiArm } from './waapi.logic';

export const MORPH_PIN_ORDER = 110;
export const GEOM_TIMED = 'geom-timed';

export interface MorphTweenProps {
  variant: string;
  impl?: 'mui' | 'plain';
  platformSelector?: string;
  navSelector?: string;
  platformFade?: boolean;
  platformFadedPause?: boolean;
}

export function MorphTween({ variant, platformSelector = '.start-selling-platform, [data-fw="platform"]', navSelector = '[data-fw="nav"]', platformFade = false, platformFadedPause = false }: MorphTweenProps) {
  useEffect(() => {
    const root = document.documentElement;
    const platformRest = window.__fw?.config.variants['morph.panel'] === REST_VARIANT;
    root.setAttribute('data-fw-morph-tween', '');
    const reduce = matchList('mq.rm-reduce');
    const platform = () => document.querySelector<HTMLElement>(platformSelector);
    const env: TweenEnv = {
      clock: getClock(),
      now: () => performance.now(),
      reduced: () => reduce?.matches ?? false,
      viewportHeight: () => window.visualViewport?.height ?? window.innerHeight,
      platform,
      scrollY: () => window.scrollY,
      maxScrollY: () => Math.max(0, root.scrollHeight - window.innerHeight),
      hooks: hooksOf(cfgOf(window.__fw?.config.variants ?? {})),
      scrollToInstant: (top) => window.scrollTo({ top, behavior: 'instant' }),
      addListener: (type, fn, passive) => window.addEventListener(type, fn as EventListener, { passive, capture: true }),
      removeListener: (type, fn) => window.removeEventListener(type, fn as EventListener, true),
      publish: (value) => {
        const nav = document.querySelector<HTMLElement>(navSelector);
        if (!nav) return;
        nav.style.setProperty('--morph', String(value));
        nav.dataset.fwMorph = String(value);
      },
      lock: scrollLockOf(variant, root),
      rest: platformRest,
      faded: platformFadedPause ? (zero) => fadedBus.set(zero) : undefined,
      fade: platformFade ? createThreadedFade(() => platform() as unknown as FadeEl | null) : undefined,
      panel:
        window.__fw?.config.variants['morph.panel'] === THREADED
          ? createPanelEffects(() => document.querySelector<HTMLElement>('[data-fw="morph-panel"]') as unknown as PanelEl | null)
          : undefined,
    };
    if (variant === GEOM_TIMED) env.timed = timedBus.sink;
    let tween: TweenDriver | undefined;
    const hub = isBand(variant) ? touchHub() : undefined;
    const unband = hub ? bandEnv(env, hub, () => (tween ? active(tween.state()) : false)) : undefined;
    const arm: WaapiArm | null = variant === 'waapi' || variant === 'waapi-scoped' ? variant : null;
    const driver = arm ? createWaapiDriver(waapiEnv(env, platform, navSelector, arm), arm) : (tween = createTweenDriver(env));
    const target = platform();
    if (platformRest && tween && target) setRest(target, tween.state().value); // the section starts at rest unless the page loaded mid-morph
    const stopBand = hub && target ? hub.observe(target) : undefined;
    const io = target ? new IntersectionObserver(([entry]) => driver.setNear(!!entry?.isIntersecting), { rootMargin: '200% 0px' }) : undefined;
    if (target && io) io.observe(target);
    const off = registerScroll('morph.tween', MORPH_PIN_ORDER, () => driver.pin());
    return () => {
      off();
      io?.disconnect();
      driver.dispose();
      stopBand?.();
      unband?.();
      root.removeAttribute('data-fw-morph-tween');
    };
  }, [variant, platformSelector, navSelector, platformFade, platformFadedPause]);
  return null;
}

function bandEnv(env: TweenEnv, hub: TouchHub, isActive: () => boolean): () => void {
  const noop = () => {};
  const client: TouchClient = { touchstart: noop, touchmove: noop, active: isActive };
  const { addListener, removeListener, publish } = env;
  env.addListener = (type, fn, passive) => {
    if (type === 'wheel') return addListener(type, fn, passive);
    client[type] = fn as (e: TouchEvent) => void;
    if (type === 'touchmove') hub.attach(client);
  };
  env.removeListener = (type, fn) => {
    if (type === 'wheel') return removeListener(type, fn);
    hub.detach(client);
  };
  env.publish = (value) => {
    publish(value);
    hub.refresh();
  };
  return () => hub.detach(client);
}

export function scrollLockOf(variant: string, root: HTMLElement): TweenEnv['lock'] {
  if (variant !== 'scroll-lock') return undefined;
  const hoverNone = matchList('mq.hover-none');
  if (!lockAllowed(hoverNoneOf(hoverNone ? hoverNone.matches : null))) return undefined;
  return {
    overlay: () => overlayOf(window.innerWidth, root.clientWidth),
    set: (on) => void (root.style.overflow = on ? 'hidden' : ''),
  };
}

function registerProperties(arm: WaapiArm): void {
  for (const r of registrationsOf(arm)) {
    try {
      CSS.registerProperty({ ...r });
    } catch {
    }
  }
}

function waapiEnv(base: TweenEnv, platform: () => HTMLElement | null, navSelector: string, arm: WaapiArm): WaapiEnv {
  registerProperties(arm);
  const fade = fadeCss(arm);
  const nav = () => document.querySelector<HTMLElement>(navSelector);
  return {
    timelineNow: () => {
      const t = document.timeline.currentTime;
      return t === null ? null : Number(t);
    },
    reduced: base.reduced,
    viewportHeight: base.viewportHeight,
    nav: () => nav() as unknown as AnimTarget | null,
    platform: () => platform() as unknown as ReturnType<WaapiEnv['platform']>,
    scrollY: base.scrollY,
    scrollToInstant: base.scrollToInstant,
    addListener: base.addListener,
    removeListener: base.removeListener,
    hint: (value) => {
      const n = nav();
      if (n) n.dataset.fwMorph = String(value);
    },
    base: (value) => nav()?.style.setProperty(PROP_MORPH, String(value)),
    marker: (durationMs, startTime) => {
      const a = new Animation(new KeyframeEffect(null, null, { duration: durationMs }), document.timeline);
      if (startTime === null) a.play();
      else a.startTime = startTime;
      return a as unknown as AnimLike;
    },
    everyFrame: (cb) => base.clock.subscribe(() => cb()),
    settle: (value, props) => {
      const n = nav();
      if (n) {
        for (const [k, v] of Object.entries(props.nav)) n.style.setProperty(k, v);
        n.dataset.fwMorph = String(value);
      }
      const p = platform();
      if (p) {
        for (const [k, v] of Object.entries(props.platform)) p.style.setProperty(k, v);
        p.style.pointerEvents = props.pointerEvents;
      }
    },
    preparePlatform: () => {
      const p = platform();
      if (p && p.style.getPropertyValue('--morph-fade') !== fade) p.style.setProperty('--morph-fade', fade);
    },
    onActivate: base.onActivate,
  };
}
