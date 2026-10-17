// Simulator control for the WKTR lane (xcrun simctl only). Counts only: nothing measured here is phone time.
import { spawnSync } from 'node:child_process';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function run(cmd, args, { timeoutMs = 300000, env } = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024, env: env ? { ...process.env, ...env } : process.env });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
}
export const simctl = (args, opts) => run('xcrun', ['simctl', ...args], opts);
const why = (r) => (r.error ? r.error.code || r.error.message : (r.stderr || r.stdout).trim().split('\n').slice(-3).join(' | '));

/** [{udid, name, state, runtime}] of every available device. */
export function listDevices() {
  const r = simctl(['list', '-j', 'devices']);
  if (r.status !== 0) throw new Error(`simctl list devices failed: ${why(r)}`);
  return Object.entries(JSON.parse(r.stdout).devices).flatMap(([runtime, ds]) =>
    ds.filter((d) => d.isAvailable !== false).map((d) => ({ udid: d.udid, name: d.name, state: d.state, runtime })));
}

/** The runtime identifier and build of an iOS version such as "26.5". */
export function findRuntime(version) {
  const r = simctl(['list', '-j', 'runtimes']);
  if (r.status !== 0) throw new Error(`simctl list runtimes failed: ${why(r)}`);
  const m = JSON.parse(r.stdout).runtimes.filter((x) => x.isAvailable !== false && x.platform === 'iOS' && x.version === version);
  if (m.length !== 1) throw new Error(`expected exactly one available iOS ${version} runtime, found ${m.length}`);
  return { identifier: m[0].identifier, version: m[0].version, buildversion: m[0].buildversion };
}

/** Create the named device (iOS `version`, device type name such as "iPhone 17") unless it exists; return its udid. */
export function ensureDevice({ name, typeName, version }) {
  const rt = findRuntime(version);
  const have = listDevices().filter((d) => d.name === name && d.runtime === rt.identifier);
  if (have.length === 1) return { udid: have[0].udid, runtime: rt, created: false };
  if (have.length > 1) throw new Error(`several devices named ${name}`);
  const types = JSON.parse(simctl(['list', '-j', 'devicetypes']).stdout).devicetypes;
  const t = types.find((x) => x.name === typeName);
  if (!t) throw new Error(`no device type "${typeName}"`);
  const r = simctl(['create', name, t.identifier, rt.identifier]);
  if (r.status !== 0) throw new Error(`simctl create failed: ${why(r)}`);
  return { udid: r.stdout.trim(), runtime: rt, created: true };
}

export function boot(udid) {
  const r = simctl(['boot', udid]);
  if (r.status !== 0 && !/current state: Booted/i.test(r.stderr)) throw new Error(`simctl boot failed: ${why(r)}`);
  const b = simctl(['bootstatus', udid, '-b'], { timeoutMs: 600000 });
  if (b.status !== 0) throw new Error(`simctl bootstatus failed: ${why(b)}`);
}

export function install(udid, appPath) {
  const r = simctl(['install', udid, appPath]);
  if (r.status !== 0) throw new Error(`simctl install failed: ${why(r)}`);
}

export const terminate = (udid, bundleId) => simctl(['terminate', udid, bundleId]);
export const shutdown = (udid) => simctl(['shutdown', udid]);
export const deleteDevice = (udid) => simctl(['delete', udid]);
