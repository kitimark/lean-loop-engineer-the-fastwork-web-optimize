// I/O of the phone session (never run by the agent that wrote it; see DEVICE.md). `device-serve` serves the probe page on
// the local network and stores every POSTed record; `device-judge` applies devicejudge.mjs to a records file.
// The LAN address is printed to the console at run time only; it is never written to a file or committed.
import { networkInterfaces } from 'node:os';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { loadGen } from '../spec.mjs';
import { gapEdges } from './cells.mjs';
import { judgeDevice } from './devicejudge.mjs';
import { startProbeServer } from './probe.mjs';

const lanAddresses = () => Object.values(networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);

export async function deviceMain(sub, args, outDir) {
  const arg = (n, d) => { const i = args.indexOf(`--${n}`); return i < 0 ? d : args[i + 1]; };
  const { gen } = loadGen();
  if (sub === 'device-serve') {
    const cfg = {
      conditions: gen.conditions.map((c) => ({ tsId: c.tsId, css: c.css, legacyCss: c.legacyCss })),
      neutral: gen.neutral.map((n) => ({ tsId: n.tsId, css: n.css })),
      edges: gapEdges(gen),
    };
    const server = await startProbeServer({ cfg, host: '0.0.0.0', port: Number(arg('port', '8765')) });
    const tok = arg('tok', 'phone');
    mkdirSync(outDir, { recursive: true });
    const file = join(outDir, 'device-records.json');
    console.error(`probe page on port ${server.port}; open  http://<this Mac's address>:${server.port}/probe.html?tok=${tok}  in Safari on the phone`);
    console.error(`  this Mac's addresses (console only): ${lanAddresses().join(', ') || 'none found'}`);
    console.error('  steps: DEVICE.md. Records are saved on every report. Ctrl-C when done, then: gaps device-judge');
    const save = () => writeFileSync(file, JSON.stringify(server.records(tok), null, 1) + '\n');
    const timer = setInterval(save, 2000);
    process.on('SIGINT', () => { clearInterval(timer); save(); console.error(`saved ${server.records(tok).length} records to ${file}`); process.exit(0); });
    await new Promise(() => {});
  } else {
    const deviceFile = arg('device');
    const simFile = arg('sim');
    if (!deviceFile || !simFile) throw new Error('device-judge needs --device FILE and --sim evidence.json');
    const device = JSON.parse(readFileSync(resolve(deviceFile), 'utf8'));
    const ev = JSON.parse(readFileSync(resolve(simFile), 'utf8'));
    const sim = (ev.simulator?.iphone ?? []);
    const res = judgeDevice({ device, sim, gen });
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'device-verdict.json'), JSON.stringify(res, null, 1) + '\n');
    console.log(`${res.pass ? 'PASS' : 'FAIL'}: ${res.checks.map((c) => `${c.ok ? 'ok' : 'NOT ok'} ${c.id}`).join('; ')}`);
    process.exitCode = res.pass ? 0 : 1;
  }
}
