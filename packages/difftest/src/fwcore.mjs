// One long-lived fwcore child per test file (wire protocol: lean/Fw/Wire.lean, one JSON line in, one out, in order).
// `batch` writes all requests with one write and resolves when every reply is back; `call` is a batch of one.
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO = resolve(HERE, '../../..');

/** FW_CORE_BIN, else lean/.lake/build/bin/fwcore of this checkout. Throws with the build hint when missing. */
export function fwcoreBin(env = process.env) {
  const bin = env.FW_CORE_BIN ?? resolve(REPO, 'lean/.lake/build/bin/fwcore');
  if (!existsSync(bin)) throw new Error(`fwcore not found at ${bin}; build it with: cd lean && lake build fwcore (or set FW_CORE_BIN)`);
  return bin;
}

export class FwCore {
  constructor(bin = fwcoreBin()) {
    this.child = spawn(bin, [], { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' } });
    this.pending = new Map();
    this.next = 0;
    this.buf = '';
    this.stderr = '';
    this.dead = null;
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (d) => this.onData(d));
    this.child.stderr.on('data', (d) => { this.stderr += d; });
    this.child.on('exit', (code, sig) => {
      this.dead = new Error(`fwcore exited (${code ?? sig}): ${this.stderr.slice(0, 500)}`);
      for (const p of this.pending.values()) p.reject(this.dead);
      this.pending.clear();
    });
    this.child.stdin.on('error', () => {});
  }

  onData(d) {
    this.buf += d;
    let i;
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i);
      this.buf = this.buf.slice(i + 1);
      if (!line) continue;
      const { id, ...rest } = JSON.parse(line);
      const p = this.pending.get(id);
      if (p) { this.pending.delete(id); p.resolve(rest); }
    }
  }

  /** Replies (without ids) in request order. A reply with an `error` field is a refusal, not a rejection. */
  batch(requests) {
    if (this.dead) return Promise.reject(this.dead);
    const proms = requests.map((r) => new Promise((resolveP, reject) => {
      const id = this.next++;
      this.pending.set(id, { resolve: resolveP, reject });
      r.__id = id;
    }));
    const text = requests.map((r) => { const id = r.__id; delete r.__id; return JSON.stringify({ ...r, id }); }).join('\n') + '\n';
    this.child.stdin.write(text);
    return Promise.all(proms);
  }

  async call(request) { return (await this.batch([request]))[0]; }

  close() { this.child.stdin.end(); return new Promise((r) => { if (this.child.exitCode !== null) r(); else this.child.on('exit', () => r()); }); }
}
