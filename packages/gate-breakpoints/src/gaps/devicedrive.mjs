// Drives the gaps probe page on the real measurement phone through the Web Inspector (no hand needed for plain loads and the
// 8 meta-viewport variants; aA zoom, landscape and the mouse step of DEVICE.md still need a person and are not done here).
// Device glue lives in packages/measure-webkit/src/device.mjs (phone selection by model + OS, own proxy, LAN page server,
// device ids and the LAN address never logged or stored). Output: device-records.json (what DEVICE.md step 7 expects),
// device-evidence.json (records in the Simulator evidence shape + battery readouts), device-verdict.json (judgeDevice),
// device-cells.json (per cell: phone vs Simulator vs Lean).
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { loadGen } from '../spec.mjs';
import { gapEdges, gapCells, probeVariants } from './cells.mjs';
import { startProbeServer } from './probe.mjs';
import { judgeDevice } from './devicejudge.mjs';
import { deviceCells } from './devicecells.mjs';
import { withPhone } from '../../../measure-webkit/src/device.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function deviceDrive(args, outDir) {
  const arg = (n, d) => { const i = args.indexOf(`--${n}`); return i < 0 ? d : args[i + 1]; };
  const simFile = arg('sim');
  if (!simFile) throw new Error('device-drive needs --sim <evidence.json of a CI macOS gaps run>');
  const { gen } = loadGen();
  const ev = JSON.parse(readFileSync(resolve(simFile), 'utf8'));
  const simIphone = ev.simulator?.iphone ?? [];
  const cfg = {
    conditions: gen.conditions.map((c) => ({ tsId: c.tsId, css: c.css, legacyCss: c.legacyCss })),
    neutral: gen.neutral.map((n) => ({ tsId: n.tsId, css: n.css })),
    edges: gapEdges(gen),
  };
  const variants = probeVariants(gen);
  const plan = [
    { tok: 'phone-load-1', label: 'load-1', query: '', req: { device: 'phone', load: 0 } },
    { tok: 'phone-load-2', label: 'load-2', query: '', req: { device: 'phone', load: 1 } },
    ...variants.map((v) => ({ tok: `phone-${v.id}`, label: v.id, query: v.query, req: { device: 'phone', variant: v.id, aimed: v.aimed } })),
  ];
  const t0 = Date.now();
  let server = null;
  const q = (p) => `/probe.html?tok=${p.tok}&label=${encodeURIComponent(p.label)}${p.query ? `&${p.query}` : ''}`;
  const res = await withPhone(async (ctx) => {
    const readouts = [ctx.readout()];
    const records = [], skipped = {};
    for (const [i, p] of plan.entries()) {
      if (i > 0) await ctx.go(`${ctx.base}${q(p)}`);
      try {
        await server.waitFor(p.tok, 1, 60000);
        await sleep(2000); // trailing resize reports; the last record is the settled page
      } catch (e) { skipped[p.tok] = e.message; continue; }
      const recs = server.records(p.tok);
      records.push({ mech: 'ios-device-safari', port: 'webkit-apple', req: p.req, ...recs[recs.length - 1], later: recs.length - 1 });
      ctx.log(`  ${p.label}: media width ${recs[recs.length - 1].gap?.mediaWidth}`);
    }
    readouts.push(ctx.readout());
    return { device: ctx.device, records, readouts, skipped };
  }, {
    startPath: q(plan[0]),
    serve: async (host) => { server = await startProbeServer({ cfg, host, port: 0 }); return server; },
  });
  const verdict = judgeDevice({ device: res.records.map((r) => ({ ...r, label: r.label })), sim: simIphone, gen });
  const table = deviceCells({ cells: gapCells(gen), device: res.records, sim: simIphone });
  mkdirSync(outDir, { recursive: true });
  const wr = (f, d) => writeFileSync(join(outDir, f), JSON.stringify(d, null, 1) + '\n');
  wr('device-records.json', res.records.map((r) => { const { mech, port, req, later, ...raw } = r; return raw; }));
  wr('device-evidence.json', { device: res.device, readouts: res.readouts, skipped: res.skipped, records: res.records, wallMs: Date.now() - t0 });
  wr('device-verdict.json', verdict);
  wr('device-cells.json', table);
  console.log(`${verdict.pass ? 'PASS' : 'FAIL'}: ${verdict.checks.map((c) => `${c.ok ? 'ok' : 'NOT ok'} ${c.id.split(' ')[0]}`).join('; ')}`);
  console.log(`cells: ${table.agree} agree, ${table.disagree} disagree`);
  for (const c of table.cells) console.log(`  ${c.id}: ${c.agree ? 'agree' : 'DISAGREE ' + c.why.join('; ')}`);
}
