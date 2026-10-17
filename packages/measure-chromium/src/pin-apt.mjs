// Writes docker/apt-manifest.txt: every installed Debian package of the image as "name=version" (sorted), plus prints the
// apt sources and the oldest/newest package dates facts used to choose the snapshot.debian.org timestamp.
//   node src/pin-apt.mjs [image]
// The Dockerfile installs the DIRECT packages with these exact versions from a dated snapshot.debian.org mirror and
// checks at build time that dpkg's full list equals the manifest (fails the build otherwise).
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const image = process.argv[2] ?? 'fw-measure-chromium:1';
const run = (cmd) => spawnSync('docker', ['run', '--rm', '--entrypoint', '/bin/sh', image, '-c', cmd], { encoding: 'utf8' }).stdout;
const list = run("dpkg-query -W -f='${Package}=${Version}\\n'").trim().split('\n').sort();
writeFileSync(join(PKG, 'docker', 'apt-manifest.txt'), list.join('\n') + '\n');
console.log(`${list.length} packages -> docker/apt-manifest.txt`);
console.log(run('cat /etc/apt/sources.list.d/* /etc/apt/sources.list 2>/dev/null; cat /etc/debian_version'));
