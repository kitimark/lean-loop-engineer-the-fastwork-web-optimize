import { join } from 'node:path';
import { parseToc, countRows, errorLines, verdictOf } from './parse.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function attempt({ guard, lease, target, template, recordArgs, during, limitS, settleMs = 2500, wait = sleep, log = () => {} }) {
  if (!lease || !lease.token) throw new Error('xctrace records only while a sim or measure slot is held');
  if (!guard.roomOk()) return { target, template, skipped: 'not enough free disk to record', recorded: false };
  const trace = join(guard.workDir, `${target}-${template.replace(/\W+/g, '-')}.trace`);
  try {
    log(`xctrace ${target} ${template}`);
    const rec = guard.exec('xctrace', ['record', '--template', template, ...recordArgs, '--time-limit', `${limitS}s`, '--output', trace, '--no-prompt'], { limitS });
    rec.catch(() => {});
    await wait(settleMs);
    let note = '';
    await during().catch((e) => { note = `\n[during] ${e.message}`; });
    const r = await rec;
    const tocRun = await guard.exec('xctrace', ['export', '--input', trace, '--toc'], { limitS: 120 });
    const toc = parseToc(tocRun.out);
    const hitchSchemas = toc.schemas.filter((s) => /hitch/i.test(s));
    let rows = 0;
    const tables = {};
    for (const s of hitchSchemas) {
      const t = await guard.exec('xctrace', ['export', '--input', trace, '--xpath', `/trace-toc/run[1]/data/table[@schema="${s}"]`], { limitS: 300 });
      tables[s] = countRows(t.out); rows += tables[s];
    }
    return {
      target, template, exit: r.code, ...verdictOf({ toc, rows }), hitchSchemas, tables, maxTraceMB: r.maxMB,
      ...(r.killed ? { killedAt: r.killed } : {}), refusal: errorLines(r.out + r.err + note + '\n' + tocRun.err),
    };
  } finally { guard.wipe(); }
}
