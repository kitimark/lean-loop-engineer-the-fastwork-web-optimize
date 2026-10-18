import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('nav', {
  pastHero: (i) => L.pastHero({ present: i.present as boolean, reduced: i.reduced as boolean, top: i.top as number, height: i.height as number, vh: i.vh as number }),
  progress: (i) => L.progress({ top: i.top as number, height: i.height as number, vh: i.vh as number }),
  stuck: (i) =>
    L.stuck({
      present: i.present as boolean,
      isSticky: i.isSticky as boolean,
      hasSection: i.hasSection as boolean,
      top: i.top as number | null,
      itemTop: i.itemTop as number,
      itemBottom: i.itemBottom as number,
      sectionBottom: i.sectionBottom as number,
    }),
  view: (i) => L.view({ past: i.past as boolean, ready: i.ready as boolean, localeOpen: i.localeOpen as boolean, hit: i.hit as boolean, stuck: i.stuck as boolean, m: i.m as number }),
  earn: (i) => L.earn({ heroPill: i.heroPill as boolean, m: i.m as number }),
  readyInit: (i) => L.readyInit({ reduced: i.reduced as boolean, phone: i.phone as boolean }),
  readyChange: (i) => L.readyChange({ ready: i.ready as boolean, reduced: i.reduced as boolean, phone: i.phone as boolean, splash: i.splash as boolean }),
  readyAt: (i) => L.readyAt({ t: i.t as number }),
});

describe('nav logic', () => {
  it('the pill leaves the hero state exactly at 72 % of the track', () => {
    expect(L.pastHero({ present: true, reduced: false, top: -864, height: 2000, vh: 800 })).toBe(true);
    expect(L.pastHero({ present: true, reduced: false, top: -863, height: 2000, vh: 800 })).toBe(false);
  });
  it('the hero pill and morphing exclude each other; expanded forces dark', () => {
    const v = L.view({ past: false, ready: true, localeOpen: false, hit: false, stuck: false, m: 0.5 });
    expect(v.heroPill).toBe(false);
    expect(v.morphing).toBe(true);
    expect(L.view({ past: false, ready: true, localeOpen: false, hit: false, stuck: false, m: 0.93 })).toMatchObject({ expanded: true, onDark: true });
  });
  it('chrome ready follows the 1140 ms rule', () => {
    expect(L.readyAt({ t: 1139 })).toBe(false);
    expect(L.readyAt({ t: 1140 })).toBe(true);
    expect(L.readyChange({ ready: true, reduced: false, phone: false, splash: false })).toBe(true);
  });
});
