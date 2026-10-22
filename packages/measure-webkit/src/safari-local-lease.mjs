// The exclusive lease of the local lane: a `sim` slot held through `fw slot acquire`, renewed while the lane runs, released at the end.
// The slot daemon has no `measure` kind; a `sim` holder makes it admit no other builder next to it, and Lean's quiet rule (holders)
// refuses any pass during which another holder is live. Glue only: no decision.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const fw = (cwd, args, timeout = 1900000) => exec('pnpm', ['-s', 'fw', 'slot', ...args], { cwd, timeout, maxBuffer: 8 << 20 });

/** Pull the token out of `fw slot acquire --json` output (the last JSON line that has one). */
export function tokenOf(stdout) {
  for (const line of String(stdout).split('\n').reverse()) {
    try { const j = JSON.parse(line); if (j && typeof j.token === 'string') return j.token; } catch { /* not JSON */ }
  }
  const m = /\b([0-9a-f]{8}-[0-9a-f]{3})\b/.exec(String(stdout));
  return m ? m[1] : null;
}

/** Hold a sim slot: `{token, release()}`; the lease is renewed every `renewEveryS` seconds in the background. */
export async function holdSimSlot({ cwd, leaseS = 120, waitS = 1800, renewEveryS = 40, owner = 'mac-safari-measure', log = () => {} }) {
  const { stdout } = await fw(cwd, ['acquire', '--kind', 'sim', '--lease', String(leaseS), '--wait', String(waitS), '--owner', owner, '--json']);
  const token = tokenOf(stdout);
  if (!token) throw new Error('fw slot acquire printed no token');
  log(`sim slot held (lease ${leaseS} s)`);
  const timer = setInterval(() => { fw(cwd, ['renew', '--token', token, '--lease', String(leaseS), '--owner', owner], 60000).catch((e) => log(`renew failed: ${e.message}`)); }, renewEveryS * 1000);
  timer.unref();
  let released = false;
  return {
    token,
    async release() {
      if (released) return; released = true;
      clearInterval(timer);
      try { await fw(cwd, ['release', '--token', token, '--owner', owner], 60000); log('sim slot released'); } catch (e) { log(`release failed: ${e.message}`); }
    },
  };
}
