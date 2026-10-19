import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

goldenConformance('morph.mount.dormant', {
  dormant: (i) => logic.dormant(i.mountedV, i.mountedO),
  dormantRun: (i) => {
    let v = false;
    let o = false;
    const out = [{ v, o, d: logic.dormant(v, o) }];
    for (const [near, push, warm] of i.ticks as [boolean, boolean, boolean][]) {
      v = logic.mountNextWarm(v, near, push, warm);
      o = logic.mountNext(o, near, push);
      out.push({ v, o, d: logic.dormant(v, o) });
    }
    return out;
  },
});
