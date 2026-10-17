// Writes docker/driver/package.json + package-lock.json from the npm tree that is installed in an image (the tree that
// produced the recorded counts), so the Dockerfile can `npm ci` the identical tree.
//   node src/pin-npm.mjs [image]
import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const image = process.argv[2] ?? 'fw-measure-chromium:1';
const dest = join(PKG, 'docker', 'driver');
mkdirSync(dest, { recursive: true });
const r = spawnSync('docker', ['run', '--rm', '-v', `${dest}:/outd`, '--entrypoint', '/bin/sh', image, '-c',
  'cd /opt/driver && npm install --package-lock-only --ignore-scripts --no-audit --no-fund && cp package.json package-lock.json /outd/'], { stdio: 'inherit' });
process.exit(r.status ?? 1);
