// Dry run of the phone feel capture with a scripted swipe as the stand-in for the person (task phone-feel-capture). Glue only:
// starts `device-cli.mjs feel start`, opens the first arms, asks the XCUITest push server for swipes while the capture runs, rates,
// stops, and prints which capture fields are populated. It decides nothing; the counts are Lean's.
//   node src/device-feel-dry.mjs --site <dist/aot> --dir <raw dir> --driver <built push driver dir> --seed <n> [--arms 2] [--swipes 3]
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, openSync, readFileSync, readdirSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rawResolveFrom, mainCheckout, worktreeTop } from './device-raw-dir.mjs';
import { ask, driverHolder } from './device-push-run.mjs';
import { loadFeel } from './device-feel.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const CLI = join(here, 'device-cli.mjs');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const resolve = (...s) => rawResolveFrom(mainCheckout(), worktreeTop(), ...s);

/** Which fields of a capture hold a value, and which stay empty (a still page has no long frame; a page without the nav tween has no pin). */
export function populated(capture) {
  const out = { filled: [], empty: [] };
  for (const [k, v] of Object.entries(capture ?? {})) (Array.isArray(v) ? v.some((x) => x > 0) : v > 0) ? out.filled.push(k) : out.empty.push(k);
  return out;
}

async function main() {
  const { values: v } = parseArgs({ options: { site: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, seed: { type: 'string' }, arms: { type: 'string', default: '2' }, swipes: { type: 'string', default: '3' } } });
  if (!v.site || !v.dir || !v.driver || v.seed === undefined) throw new Error('needs --site --dir --driver --seed');
  const dir = resolve(v.dir);
  const log = (s) => console.error(`[dry] ${s}`);
  const cli = (...a) => spawnSync('node', [CLI, ...a], { encoding: 'utf8', timeout: 300000 });
  const logFd = openSync(`${dir}-start.log`, 'a');
  const child = spawn('node', [CLI, 'feel', 'start', '--site', resolve(v.site), '--dir', dir, '--pin', 'Serious', '--seed', v.seed, '--fresh'], { stdio: ['ignore', logFd, logFd] });
  const exited = new Promise((r) => child.once('exit', (code) => r(code)));
  const holder = driverHolder({ dir: resolve(v.driver), log });
  let failure = null;
  try {
    const t0 = Date.now();
    for (;;) {
      let st = null;
      try { st = loadFeel(dir); } catch { /* not written yet */ }
      if (st?.status === 'ready') break;
      if (st?.status === 'failed' || child.exitCode !== null) throw new Error(`feel start ended before ready: ${st?.error ?? `exit ${child.exitCode}`}`);
      if (Date.now() - t0 > 360000) throw new Error('feel start was not ready after 360 s');
      await sleep(2000);
    }
    log(`session ready after ${Math.round((Date.now() - t0) / 1000)} s`);
    const server = await holder.get();
    for (let k = 0; k < Number(v.arms); k++) {
      const r = cli('feel', 'next', '--dir', dir);
      log(`next: ${(r.stdout || r.stderr).split('\n')[0]}`);
      const label = loadFeel(dir).plan[loadFeel(dir).opened - 1]?.label;
      if (!label) throw new Error(`feel next opened no arm: ${(r.stdout || r.stderr).slice(0, 200)}`);
      await sleep(1500);
      for (let s = 0; s < Number(v.swipes); s++) {
        const p = await ask(server);
        log(`swipe ${s + 1} of ${v.swipes} on ${label}: ${p === null ? 'no answer' : `presses ${p.join('/')} ms`}`);
      }
      await sleep(2500);
      const rr = cli('feel', 'rate', label, '3', '--dir', dir);
      log(`rate: ${(rr.stdout || rr.stderr).split('\n')[0]}`);
    }
  } catch (e) {
    failure = e;
    log(`error: ${e.message}`);
  } finally {
    await holder.stop().catch(() => {});
    const s = cli('feel', 'stop', '--dir', dir);
    log(`stop: ${(s.stdout || s.stderr).split('\n').slice(-3).join(' | ')}`);
    const code = await Promise.race([exited, sleep(340000).then(() => 'timeout')]);
    log(`feel start exited with ${code}`);
  }
  const st = loadFeel(dir);
  const files = existsSync(join(dir, 'visits')) ? readdirSync(join(dir, 'visits')) : [];
  const caps = st.captures.map((c, i) => (c ? { visit: st.plan[i].label, ...populated(c), capture: { ...c, zoneWork: c.zoneWork } } : null)).filter(Boolean);
  for (const f of files) {
    const rec = JSON.parse(readFileSync(join(dir, 'visits', f), 'utf8'));
    console.log(JSON.stringify({ file: f, schema: rec.schema, frames: rec.frames.t.length, touches: rec.touches.length, pins: rec.feel.pins.length, starts: rec.feel.starts.length, cards: rec.feel.cardCount, activeFrames: rec.feel.active.filter(Boolean).length, zoneNote: rec.feel.zoneNote }));
  }
  console.log(JSON.stringify({ status: st.status, pinEnd: st.pinEnd, captures: caps }, null, 1));
  if (failure) process.exitCode = 1;
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch((e) => { console.error(e.message); process.exit(1); });
