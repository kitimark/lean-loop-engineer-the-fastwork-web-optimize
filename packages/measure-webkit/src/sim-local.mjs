// Mobile Safari in the iOS Simulator on this Mac (mac-safari-measure, engine B). The window flow is sim-cadence.mjs `readWindow`
// (same recorder, same hero and end scripts, same Timeline zone binning); what is new is that each window runs inside the quiet
// check of safari-local-run.mjs, on a device of its own (FW_SIM_NAME, set by sim-local-cli.mjs before this file is imported).
import { withSession } from './session.mjs';
import { loadFresh, pageInfo } from './page.mjs';
import { startTimeline } from './timeline.mjs';
import { findDevice, listDevices, simctl } from './sim.mjs';
import { reconnect } from './wip.mjs';
import { T } from './timeouts.mjs';
import { RECORDER_SRC, TO_END_JS, heroJs, endJs, pageOf, intervalsOf } from './profile/recorder.mjs';
import { profileWindow, toHundredths } from './profile/reduce.mjs';
import { HERO_BURST, END_PUSH } from '../../gate-breakpoints/src/smooth/schedule.mjs';
import { runCheck } from '../../gate-breakpoints/src/trajectory/reduce.mjs';
import { cadenceOf, runCells, ZONE_OF } from './safari-local-run.mjs';

/** The real simctl calls `ensureDevice` makes; a test passes its own. */
const realSim = {
  list: listDevices,
  specOf(from) {
    const src = JSON.parse(simctl(['list', '-j', 'devices']).stdout);
    for (const [runtime, ds] of Object.entries(src.devices)) for (const d of ds) if (d.name === from) return { type: d.deviceTypeIdentifier, runtime };
    return null;
  },
  create: (name, type, runtime) => simctl(['create', name, type, runtime]),
};

/**
 * The lane's own device, made once and kept: reused when one with this name exists, created (same type and runtime as `from`) only when none does.
 * Several with the name is an error. The lane boots and shuts it down and never deletes it: each first boot of a fresh device costs minutes of load.
 * Returns `{name, created}`.
 */
export function ensureDevice(name, from = 'fw-iphone-27', sim = realSim) {
  const have = sim.list().filter((d) => d.name === name);
  if (have.length > 1) throw new Error(`${have.length} Simulator devices are named "${name}": delete the extra ones by hand, the lane creates one device and reuses it`);
  if (have.length === 1) return { name, created: false };
  const spec = sim.specOf(from);
  if (!spec) throw new Error(`no device "${from}" to copy the type and runtime from`);
  const r = sim.create(name, spec.type, spec.runtime);
  if (r.status !== 0) throw new Error(`simctl create failed: ${(r.stderr || r.stdout).trim()}`);
  return { name, created: true };
}

/** The simulator window flow of one arm and one window, from a fresh load. */
export const simWindow = (ctx, { settleMs, log }) => async (arm, win) => {
  ctx.setArm(arm.id);
  await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + arm.search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
  await loadFresh(ctx.c, { clock: 'pinned', settleMs });
  const info = await pageInfo(ctx.c);
  const config = info.fw?.configHash ?? null;
  if (runCheck([{ site: arm.site, want: ctx.armHash(arm.id), config, mode: info.fw?.mode ?? null }]) !== 'ok') {
    log(`sim ${arm.id} ${win}: the page is not the arm asked for (${JSON.stringify(info.fw)})`);
    throw new Error(`arm ${arm.id}: wrong page (config ${config})`);
  }
  await ctx.c.evaluate(RECORDER_SRC);
  if (win === 'end') await ctx.c.runAsync(TO_END_JS);
  const tl = await startTimeline(ctx.c, { stopMs: T(7500) });
  const rec = await ctx.c.runAsync(win === 'hero' ? heroJs(HERO_BURST) : endJs(END_PUSH), { pollMs: 250 });
  await tl.stop();
  const pw = profileWindow(pageOf(rec, toHundredths), tl.top);
  const z = pw.profiles?.[ZONE_OF[win]] ?? null;
  const cellOf = (k) => z?.cells.find((c) => c[0] === k) ?? [k, 0, 0];
  return {
    ...cadenceOf(rec.ts, intervalsOf), config, ua: info.ua, vw: info.vw,
    profile: z ? { ok: pw.ok, frames: z.frames, work: z.work, paintN: cellOf('Paint')[1], paintHund: cellOf('Paint')[2], compositeN: cellOf('Composite')[1], records: tl.top.length } : { ok: false, reason: pw.reason ?? null },
  };
};

/**
 * Run the Simulator lane: one session, every arm on one origin. After the boot the lane settles, takes the idle floor with the Simulator booted and idle
 * (`takeBase({boot})`, Lean `simFloor`), and runs passes under the quiet rule at that floor; no steady floor means no pass.
 * Returns `{rows, baseline, device, ua}`.
 */
export async function runSimLocal({ arms, read, takeBase, passes, maxRounds, deadlineMs, waitMs, everyMs, onRow, settleMs = 2500, log = (s) => console.error(s) }) {
  let ua = '', vw = null;
  const device = findDevice();
  let baseline = null;
  const rows = await withSession(async (ctx) => {
    baseline = await takeBase({ boot: Math.floor(Date.now() / 1000) });
    if (baseline.floorCenti === null) return [];
    const win = simWindow(ctx, { settleMs, log });
    const byId = Object.fromEntries(arms.map((a) => [a.id, a]));
    return runCells({
      engine: 'sim', arms, passes, maxRounds, deadlineMs, read, floorCenti: baseline.floorCenti, waitMs, everyMs, onRow, log,
      readWindow: async (id, w) => { const { ua: u, vw: x, ...v } = await win(byId[id], w); ua = u; vw = x; return v; },
      onError: async (e) => { log(`reconnecting after: ${e.message}`); await reconnect(ctx, { log }); },
    });
  }, { keep: false, arms: Object.fromEntries(arms.map((a) => [a.id, a.tree])), log });
  return { rows, baseline, device: device.name, runtime: device.runtime, ua, vw };
}
