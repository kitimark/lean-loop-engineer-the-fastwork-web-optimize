import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { GUARDED_PORTS, proxiesClear, proxyVerdict, usbLine, usbVerdict } from './device-faults.mjs';

const sh = (cmd, args, timeoutMs = 20000) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
};

const IWDP = /(^|\/)ios_webkit_debug_proxy$/;
export const DEFAULT_SPEC = 'null:9221,:9222-9322';

export function parsePs(out) {
  const rows = [];
  for (const l of out.split('\n')) {
    const m = /^\s*(\d+)\s+(\d+)\s+(\S+)(.*)$/.exec(l);
    if (m && IWDP.test(m[3])) rows.push({ pid: Number(m[1]), ppid: Number(m[2]), args: m[4].trim().split(/\s+/).filter(Boolean) });
  }
  return rows;
}

export function specOf(args, readFile = (f) => readFileSync(f, 'utf8')) {
  const val = (short, long) => {
    const i = args.findIndex((a) => a === short || a === long);
    if (i >= 0) return args[i + 1] ?? '';
    const eq = args.find((a) => a.startsWith(`${long}=`));
    return eq ? eq.slice(long.length + 1) : null;
  };
  const c = val('-c', '--config');
  if (c !== null) {
    if (!c.includes('/')) return c;
    try { return readFile(c); } catch { return null; }
  }
  const u = val('-u', '--udid');
  return u !== null ? (u.includes(':') ? u : `${u}:9222`) : DEFAULT_SPEC;
}

export const readsUsb = (args) => !args.some((a) => a === '-s' || a === '--simulator' || a.startsWith('--simulator='));

export const portsOf = (lsofOut) => [...lsofOut.matchAll(/^n.*:(\d+)$/gm)].map((m) => Number(m[1]));

export function foreignProxies({ run = sh, readFile, self = process.pid } = {}) {
  const ps = run('ps', ['-axo', 'pid=,ppid=,command=']);
  if (ps.status !== 0) throw new Error('ps failed: cannot tell whether another ios_webkit_debug_proxy runs');
  return parsePs(ps.stdout).filter((p) => p.pid !== self && p.ppid !== self).map((p) => {
    const l = run('lsof', ['-nP', '-a', '-p', String(p.pid), '-iTCP', '-sTCP:LISTEN', '-Fn']);
    return { pid: p.pid, ports: portsOf(l.stdout), spec: specOf(p.args, readFile), usb: readsUsb(p.args) };
  });
}

export function assertNoForeignProxy(udid, deps = {}) {
  const ps = foreignProxies(deps);
  if (proxiesClear(ps, udid)) return ps;
  const bad = ps.filter((p) => proxyVerdict(p, udid) !== 'clear').map((p) => `pid ${p.pid} ${proxyVerdict(p, udid)}${p.ports.length ? ` on ports ${p.ports.join(',')}` : ''}`);
  throw new Error(`another ios_webkit_debug_proxy is running (${bad.join('; ')}); one phone run at a time, ports ${GUARDED_PORTS.join('/')} are not ours`);
}

const stamp = (d) => {
  const z = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())} ${z(d.getHours())}:${z(d.getMinutes())}:${z(d.getSeconds())}`;
};

export function usbEvidence(sinceMs, { run = sh } = {}) {
  const r = run('/usr/bin/log', ['show', '--style', 'compact', '--start', stamp(new Date(sinceMs)), '--predicate', 'process == "usbpowerd"'], 60000);
  if (r.status !== 0) return [];
  return r.stdout.split('\n').filter(usbLine).map((l) => ({ at: /^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)/.exec(l)?.[1] ?? null, what: l.includes('terminated') ? 'usbpowerd terminated' : 'usbpowerd discovered' }));
}

export const usbListed = (udid, { run = sh } = {}) => run('idevice_id', ['-l']).stdout.split('\n').map((s) => s.trim()).includes(udid);

export function usbReading(udid, sinceMs, { run = sh } = {}) {
  const listed = usbListed(udid, { run });
  const onBus = run('ioreg', ['-p', 'IOUSB', '-w0']).stdout.includes('iPhone');
  const evidence = usbEvidence(sinceMs, { run });
  return { listed, onBus, evidence, verdict: usbVerdict({ listed, onBus, evidence: evidence.length > 0 }) };
}
