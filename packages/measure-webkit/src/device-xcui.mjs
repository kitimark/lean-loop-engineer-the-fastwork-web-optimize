import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { runGroup, findDriver } from './throttle/driver.mjs';
import { fileURLToPath } from 'node:url';

const DRIVER_SRC = fileURLToPath(new URL('./throttle/driver/', import.meta.url));

/** The development team id in the subject of a signing certificate (`OU=` field of `openssl x509 -subject`), or null. */
export const teamOfSubject = (subject) => /(?:^|[^A-Za-z])OU\s*=\s*([A-Z0-9]{10})(?:[,/\s]|$)/.exec(subject)?.[1] ?? null;

/** The xcodebuild arguments that build the push driver for one real device and sign it with `team` (project.yml turns signing off for the Simulator). */
export function deviceBuildArgs({ udid, team, derived }) {
  if (!udid || !team) throw new Error('deviceBuildArgs needs a device id and a team id');
  return ['build-for-testing', '-project', 'FwThrottleDriver.xcodeproj', '-scheme', 'FwThrottleDriver', '-destination', `id=${udid}`,
    '-derivedDataPath', derived, '-allowProvisioningUpdates', `DEVELOPMENT_TEAM=${team}`, 'CODE_SIGN_STYLE=Automatic',
    'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGNING_REQUIRED=YES'];
}

/** The team of the first Apple Development certificate in the keychain (null when there is none). */
export function keychainTeam(run = spawnSync) {
  const pem = run('security', ['find-certificate', '-c', 'Apple Development', '-p'], { encoding: 'utf8' });
  if (pem.status !== 0) return null;
  const sub = run('openssl', ['x509', '-noout', '-subject'], { input: pem.stdout, encoding: 'utf8' });
  return sub.status === 0 ? teamOfSubject(sub.stdout) : null;
}

/** Build and sign the push driver for a real device into `dir`; returns {dir, xctestrun} like throttle/driver.mjs buildDriver. */
export async function buildDeviceDriver({ udid, dir, team = keychainTeam(), log = () => {}, timeoutMs = 600000 }) {
  mkdirSync(dir, { recursive: true });
  cpSync(DRIVER_SRC, dir, { recursive: true });
  const gen = spawnSync('xcodegen', ['generate'], { cwd: dir, encoding: 'utf8' });
  if (gen.status !== 0) throw new Error(`xcodegen failed: ${(gen.stderr || gen.stdout || '').slice(-400)}`);
  const logFile = join(dir, 'build.log');
  const t0 = Date.now();
  const r = await runGroup('xcodebuild', deviceBuildArgs({ udid, team, derived: join(dir, 'dd') }), { cwd: dir, timeoutMs, logFile });
  if (r.code !== 0) throw new Error(`xcodebuild build-for-testing failed (code ${r.code}${r.timedOut ? ', timed out' : ''}); log tail in ${logFile}`);
  log(`device driver built in ${Math.round((Date.now() - t0) / 1000)} s`);
  return findDriver(dir);
}
