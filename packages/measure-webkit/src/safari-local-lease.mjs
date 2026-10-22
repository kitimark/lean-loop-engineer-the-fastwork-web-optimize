// The exclusive lease of the local lane, held through `fw slot acquire`, renewed while the lane runs, released at the end.
// macOS Safari and the macOS probe hold a `measure` slot and ask for an exclusive pass around each measured window (`fw slot pass start|stop`);
// the Simulator holds a `sim` slot, because the slot daemon shuts a booted device down 600 s after its last sim holder. Glue only: no decision.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const realFw = (cwd, args, timeout = 1900000) => exec('pnpm', ['-s', 'fw', 'slot', ...args], { cwd, timeout, maxBuffer: 8 << 20 });

/** Pull the token out of `fw slot acquire --json` output (the last JSON line that has one). */
export function tokenOf(stdout) {
  for (const line of String(stdout).split('\n').reverse()) {
    try { const j = JSON.parse(line); if (j && typeof j.token === 'string') return j.token; } catch { /* not JSON */ }
  }
  const m = /\b([0-9a-f]{8}-[0-9a-f]{3})\b/.exec(String(stdout));
  return m ? m[1] : null;
}

const EXIT_WAIT = 75;
const failedWith = (e, code) => e && (e.code === code || e.status === code);

/** Hold a slot of `kind`: `{token, kind, release()}`; the lease is renewed every `renewEveryS` seconds in the background. */
async function hold({ kind, cwd, leaseS, waitS, renewEveryS, owner, log, extra = [], fw = realFw }) {
  const { stdout } = await fw(cwd, ['acquire', '--kind', kind, '--lease', String(leaseS), '--wait', String(waitS), '--owner', owner, ...extra, '--json']);
  const token = tokenOf(stdout);
  if (!token) throw new Error('fw slot acquire printed no token');
  log(`${kind} slot held (lease ${leaseS} s)`);
  const timer = setInterval(() => { fw(cwd, ['renew', '--token', token, '--lease', String(leaseS), '--owner', owner], 60000).catch((e) => log(`renew failed: ${e.message}`)); }, renewEveryS * 1000);
  timer.unref();
  let released = false;
  const stop = async () => { clearInterval(timer); };
  return {
    token, kind, owner, stop,
    async release(before = async () => {}) {
      if (released) return; released = true;
      clearInterval(timer);
      try { await before(); } catch (e) { log(`before release: ${e.message}`); }
      try { await fw(cwd, ['release', '--token', token, '--owner', owner], 60000); log(`${kind} slot released`); } catch (e) { log(`release failed: ${e.message}`); }
    },
  };
}

/** Hold a sim slot (the Simulator lane). */
export async function holdSimSlot({ cwd, leaseS = 120, waitS = 1800, renewEveryS = 40, owner = 'mac-safari-measure', log = () => {} }) {
  return hold({ kind: 'sim', cwd, leaseS, waitS, renewEveryS, owner, log });
}

/**
 * Hold a measure slot (the macOS lane). `pass.start(forS, waitS)` asks for an exclusive pass: true when it started, false when other holders
 * were still live after `waitS`; it throws when the lease is gone. `pass.stop(nextS)` ends it and opens a gap. `release()` ends a live pass first.
 */
export async function holdMeasureSlot({ cwd, leaseS = 3600, waitS = 1800, renewEveryS = 40, owner = 'mac-safari-measure', nextS = 0, log = () => {}, fw = realFw }) {
  const h = await hold({ kind: 'measure', cwd, leaseS, waitS, renewEveryS, owner, log, extra: ['--next', String(nextS)], fw });
  let live = false;
  const pass = {
    async start(forS = 900, passWaitS = 300) {
      try {
        await fw(cwd, ['pass', 'start', '--token', h.token, '--for', String(forS), '--wait', String(passWaitS), '--owner', owner], (passWaitS + 120) * 1000);
        live = true; return true;
      } catch (e) {
        if (failedWith(e, EXIT_WAIT)) return false;
        throw new Error(`fw slot pass start failed: ${e.message}`);
      }
    },
    async stop(gapS = 60) {
      if (!live) return; live = false;
      await fw(cwd, ['pass', 'stop', '--token', h.token, '--next', String(gapS), '--owner', owner], 60000);
    },
    get live() { return live; },
  };
  return { ...h, pass, release: () => h.release(() => pass.stop(0)) };
}
