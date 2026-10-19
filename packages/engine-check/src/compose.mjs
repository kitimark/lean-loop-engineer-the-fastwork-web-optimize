// engine-check --compose: loads measured counts runs into `measure.compose` requests and renders the Lean verdicts
// (Fw.Measure.Compose). Glue only: reading run dirs, the class table and the reply; every verdict comes from fwcore.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/** One counts run dir as `{variants, zones}` (counts.json meta and zones.json). */
export function loadRun(dir) {
  const counts = JSON.parse(readFileSync(join(dir, 'counts.json'), 'utf8'));
  const zones = JSON.parse(readFileSync(join(dir, 'zones.json'), 'utf8')).zones;
  return { variants: counts.meta?.rewrite?.config?.variants ?? {}, zones };
}

/** The run dirs of one CI run and arm: `<runs>/<id>/chromium-counts-<arm>-r<n>`, in name order. */
export function armDirs(runsDir, id, arm) {
  const d = join(runsDir, id);
  if (!existsSync(d)) throw new Error(`run ${id}: not downloaded under ${runsDir}`);
  const prefix = `chromium-counts-${arm}-r`;
  return readdirSync(d).filter((n) => n.startsWith(prefix)).sort().map((n) => join(d, n));
}

/** A comparison `{id, baseId, base, arm}` from a plan entry `{run, base}`. */
export function comparison(runsDir, arm, { run, base }) {
  return { id: run, baseId: base, base: armDirs(runsDir, base, arm).map(loadRun), arm: armDirs(runsDir, run, arm).map(loadRun) };
}

/** The class table `{type: {class, k, t}}` of a profile and arm in classes.frozen.json. */
export function classTable(frozen, profile, arm) {
  const types = frozen.profiles?.[profile]?.arms?.[arm]?.types;
  if (!types) throw new Error(`classes: no profile ${profile} arm ${arm}`);
  return Object.fromEntries(Object.entries(types).map(([ty, e]) => [ty, { class: e.class, k: e.k, t: e.t }]));
}

/** The `measure.compose` request of one plan comparison. */
export function request(plan, cmp, classes, runsDir) {
  return {
    op: 'measure.compose',
    classes,
    combined: comparison(runsDir, plan.arm, cmp.combined),
    singles: plan.singles.map((s) => comparison(runsDir, plan.arm, s)),
  };
}

const why = (r) => r.why === 'missing' ? `missing ${r.missing.join(', ')}` : r.why;
const cls = (c) => c.class === 'stable' ? `stable(${c.k},${c.t})` : c.class;
const part = (p) => p.run === null ? `${p.flag}: none` : `${p.flag}: ${p.delta} (${p.run})`;

/** One markdown table line of a reply row. */
export function rowLine(r) {
  const verdict = r.verdict === 'coupled' ? `coupled (${r.named.join(', ') || 'no single acts'})`
    : r.verdict === 'not-comparable' ? `not comparable: ${why(r)}` : r.verdict;
  return `| ${r.stage} | ${r.type} | ${r.zone} | ${cls(r.class)} | ${r.combined.delta} (${r.combined.run}) | ${r.parts.map(part).join('; ')} | ${r.residual} | ${r.margin} | ${verdict} |`;
}

/** The markdown table of a reply; `reported` pass rows only for the whole run. */
export function render(name, reply) {
  const head = ['| stage | type | zone | class | combined Δ (run) | single Δ (run) | residual | margin | verdict |',
    '|---|---|---|---|---|---|---|---|---|'];
  const rows = reply.rows.filter((r) => r.verdict !== 'reported' || r.zone === 'run');
  const t = reply.tally;
  return [`### ${name}`, '',
    `combined ${reply.combined.id} (base ${reply.combined.baseId}), flags ${reply.combined.flags.join(', ')}`,
    `tally: ${t.composes} composes, ${t.coupled} coupled, ${t.notComparable} not comparable, ${t.reported} reported`, '',
    ...head, ...rows.map(rowLine), ''].join('\n');
}
