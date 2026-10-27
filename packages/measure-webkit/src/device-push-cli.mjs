import { parseArgs } from 'node:util';
import { resolve } from 'node:path';
import { runBlock, realDeps, phoneSense } from './device-phone-run.mjs';
import { pinnedSession } from './device-phone-pin.mjs';
import { ConditionOwner } from './device-thermal-pin.mjs';
import { PUSH, PUSH_ARMS, noRepeat, pushOk, pushRounds } from './device-push.mjs';
import { driverHolder, pushVisit, readVisits, summarize, valuesOf, writeJson } from './device-push-run.mjs';
import { pushTables } from './device-push-tables.mjs';

const [cmd, ...rest] = process.argv.slice(2).filter((a) => a !== '--');
const { values: v } = parseArgs({
  args: rest, allowNegative: true, allowPositionals: true,
  options: {
    site: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, out: { type: 'string' }, pin: { type: 'string' },
    only: { type: 'string' }, rounds: { type: 'string', default: String(PUSH.minVisits) }, 'max-visits': { type: 'string', default: '4' },
    all: { type: 'boolean', default: false }, settle: { type: 'string', default: '6000' }, clock: { type: 'string', default: 'pinned' }, gap: { type: 'string', default: '100' },
  },
});
const log = (s) => console.error(s);

const sessionOf = () => {
  const order = v.only ? v.only.split(',').map((id) => PUSH_ARMS.find((a) => a.id === id) ?? (() => { throw new Error(`unknown arm ${id}`); })()) : pushRounds(Number(v.rounds));
  if (!v.only && !(pushOk(order) && noRepeat(order))) throw new Error('the session does not satisfy the visit rule');
  return order;
};

async function main() {
  if (cmd === 'plan') {
    console.log(sessionOf().map((a, i) => `visit ${i}: ${a.id}`).join('\n'));
    return;
  }
  if (cmd === 'run') {
    if (!v.site || !v.dir || !v.driver) throw new Error('run needs --site <dist/aot>, --dir <raw dir> and --driver <driver dir>');
    const holder = driverHolder({ dir: resolve(v.driver), log });
    const deps = { ...realDeps(), visit: pushVisit({ server: holder.get, gapPx: Number(v.gap) }) };
    const session = sessionOf();
    const body = async (pin) => {
      for (;;) {
        const r = await runBlock({ site: resolve(v.site), dir: resolve(v.dir), log, clock: v.clock, settle: Number(v.settle), session, pin, deps, arms: PUSH_ARMS, values: valuesOf, visitS: 240, maxVisits: Number(v['max-visits']) });
        console.log(JSON.stringify({ ran: r.ran.length, remaining: r.remaining, stopped: r.stopped }));
        if (r.stopped) { process.exitCode = 3; break; }
        if (!v.all || r.remaining <= 0 || r.ran.length === 0) break;
      }
    };
    try {
      if (v.pin) await pinnedSession({ target: v.pin, dir: resolve(v.dir), log, owner: new ConditionOwner({ dir: resolve(v.dir), log }), sense: phoneSense(), body });
      else await body(null);
    } catch (e) { log(`error: ${e.message}`); process.exitCode = 1; } finally { await holder.stop(); }
    process.exit(process.exitCode ?? 0);
  }
  if (cmd === 'reduce') {
    if (!v.dir || !v.out) throw new Error('reduce needs --dir <raw dir> and --out <results dir>');
    const { st, rows, lost } = readVisits(resolve(v.dir));
    const arms = summarize(rows);
    const summary = {
      schema: 'fw.phone.push/1', consts: { minVisits: PUSH.minVisits, pushes: PUSH.pushes, asks: PUSH.patternAsks + PUSH.burstAsks, overLimitCentiMs: PUSH.overLimit, metrics: PUSH.metrics },
      order: st.session ?? [], visits: rows.map(({ vals, ...r }) => ({ ...r, vals })), notRun: lost, arms,
      thermal: st.thermal ?? [], firstTempC: st.firstTemp ?? null, pin: st.pin ?? null,
    };
    writeJson(resolve(v.out, 'summary.json'), summary);
    const { writeFileSync } = await import('node:fs');
    writeFileSync(resolve(v.out, 'tables.md'), pushTables(summary));
    console.log(JSON.stringify({ visits: rows.length, arms: arms.map((a) => `${a.id}:${a.n}:${a.label}`) }));
    return;
  }
  throw new Error('commands: plan | run | reduce');
}

main().catch((e) => { console.error(e.message); process.exit(1); });
