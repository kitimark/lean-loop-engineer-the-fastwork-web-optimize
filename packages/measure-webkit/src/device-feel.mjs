import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/feel.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const FEEL = Object.freeze(GOLDEN.find((l) => l.kind === 'consts'));
export const SAME_ARMS = Object.freeze(GOLDEN.filter((l) => l.kind === 'arm' && l.group === 'same'));
export const LOOK_ARMS = Object.freeze(GOLDEN.filter((l) => l.kind === 'arm' && l.group === 'look'));
export const ARMS = Object.freeze([...SAME_ARMS, ...LOOK_ARMS]);
const ORDERS = GOLDEN.filter((l) => l.kind === 'order');
const VISITS = FEEL.repeats * FEEL.nSame + LOOK_ARMS.length;

export const searchOf = (flags) => (flags.length === 0 ? '' : `?fw=${flags.join(',')}`);
export const validScore = (s) => Number.isInteger(s) && s >= FEEL.scoreMin && s <= FEEL.scoreMax;

export function orderOf(seed) {
  const line = ORDERS.find((o) => o.seed === seed % FEEL.nSame);
  if (!line) throw new Error(`no golden order for seed ${seed}`);
  return { order: line.order, letters: line.letters };
}

export function planOf(seed) {
  const { order, letters } = orderOf(seed);
  const visits = order.map((a, i) => ({
    index: i, group: 'same', arm: a, id: SAME_ARMS[a].id, label: letters[i], round: Math.floor(i / FEEL.nSame),
    flags: SAME_ARMS[a].flags, search: searchOf(SAME_ARMS[a].flags), text: '',
  }));
  LOOK_ARMS.forEach((a, k) => visits.push({
    index: order.length + k, group: 'look', arm: k, id: a.id, label: `L${k + 1}`, round: 0,
    flags: a.flags, search: searchOf(a.flags), text: a.text,
  }));
  return visits;
}

export function armHashes(configs) {
  const have = [], missing = [];
  for (const a of ARMS) {
    const h = configs.bySearch[canonSearch(searchOf(a.flags))];
    if (h && configs.byHash[h]) have.push({ id: a.id, hash: h, file: configs.byHash[h] });
    else missing.push({ id: a.id, search: searchOf(a.flags) });
  }
  return { have, missing };
}

export function cellOf(x, b) {
  if (b + FEEL.margin <= x) return 'better';
  if (x + FEEL.margin <= b) return 'worse';
  return 'same';
}
const agree = (a, b) => (a === b ? a : 'mixed');
export function reduceArm(xs, bs) {
  return xs.length === FEEL.repeats && bs.length === FEEL.repeats ? agree(cellOf(xs[0], bs[0]), cellOf(xs[1], bs[1])) : 'unrated';
}
export const reduceLook = (xs, bs) => (xs.length === 1 ? reduceArm([xs[0], xs[0]], bs) : 'unrated');
export const scoresOf = (order, ratings, a) => order.flatMap((b, i) => (b === a && ratings[i] != null ? [ratings[i]] : []));

export function verdicts(seed, ratings) {
  const { order } = orderOf(seed);
  const n = order.length;
  const base = scoresOf(order, ratings.slice(0, n), FEEL.baseArm);
  const same = SAME_ARMS.map((a, k) => ({ id: a.id, verdict: reduceArm(scoresOf(order, ratings.slice(0, n), k), base), scores: scoresOf(order, ratings.slice(0, n), k) }));
  const look = LOOK_ARMS.map((a, k) => {
    const r = ratings[n + k];
    return { id: a.id, text: a.text, verdict: reduceLook(r == null ? [] : [r], base), scores: r == null ? [] : [r] };
  });
  return { same, look };
}
export const verdictText = (v) => FEEL.texts[v];

export function freshState({ seed, pin, site }) {
  return { schema: 1, seed, pin, site, status: 'starting', pid: null, control: null, opened: 0, ratings: Array(VISITS).fill(null), log: [], plan: planOf(seed).map((v) => ({ index: v.index, group: v.group, id: v.id, label: v.label, search: v.search, text: v.text })) };
}

export const stateFile = (dir) => join(dir, 'feel.json');
export function loadFeel(dir) {
  const f = stateFile(dir);
  if (!existsSync(f)) throw new Error(`no feel session state in ${dir}`);
  return JSON.parse(readFileSync(f, 'utf8'));
}
export function saveFeel(dir, st) {
  mkdirSync(dir, { recursive: true });
  const tmp = join(dir, 'feel.json.tmp');
  writeFileSync(tmp, JSON.stringify(st, null, 1) + '\n');
  renameSync(tmp, stateFile(dir));
}

const total = (st) => st.plan.length;
const current = (st) => (st.opened > 0 ? st.plan[st.opened - 1] : null);
const progress = (st, v) => `visit ${v.index + 1} of ${total(st)}`;
const rated = (st) => st.ratings.filter((r) => r != null).length;

export function visitText(st, v) {
  const head = v.group === 'look' ? `${v.label} (${progress(st, v)}), a look change: ${v.text}` : `${v.label} (${progress(st, v)})`;
  return `${head}\n${FEEL.doText}\n${FEEL.rateText}`;
}

export async function cmdNext(st, deps) {
  const cur = current(st);
  if (cur && st.ratings[cur.index] == null) return { ok: false, text: `rate the open arm first: ${cur.label}` };
  if (st.opened >= total(st)) return { ok: false, text: 'all arms are done; run feel stop' };
  const g = await deps.gate();
  if (!g.ok) return { ok: false, text: `arm not opened: ${g.why}` };
  const v = st.plan[st.opened];
  const o = await deps.open(v);
  if (!o.ok) return { ok: false, text: `arm not opened: ${o.error}` };
  st.opened += 1;
  st.log.push({ index: v.index, openedAt: new Date(deps.now()).toISOString(), thermal: g.reading ?? null, page: o.info });
  return { ok: true, text: visitText(st, v), label: v.label };
}

export function cmdRate(st, label, rating, now = Date.now) {
  const cur = current(st);
  if (!cur) return { ok: false, text: 'no arm is open; run feel next' };
  if (String(label).toUpperCase() !== cur.label) return { ok: false, text: `the open arm is ${cur.label}, not ${label}` };
  const n = Number(rating);
  if (!validScore(n)) return { ok: false, text: `rating must be a whole number ${FEEL.scoreMin} to ${FEEL.scoreMax}` };
  st.ratings[cur.index] = n;
  st.log.find((l) => l.index === cur.index).ratedAt = new Date(now()).toISOString();
  return { ok: true, text: `recorded ${cur.label} = ${n} (${rated(st)} of ${total(st)} rated)` };
}

export function cmdStatus(st, { reveal = false } = {}) {
  const cur = current(st);
  const lines = [`status ${st.status}; ${st.opened} of ${total(st)} arms opened, ${rated(st)} rated`];
  if (st.pinReading) lines.push(`pin ${st.pin}: reads ${st.pinReading.state ?? 'unreadable'} at ${st.pinReading.at}`);
  if (cur) lines.push(`open: ${cur.label}${st.ratings[cur.index] == null ? ' (not rated yet)' : ` = ${st.ratings[cur.index]}`}`);
  lines.push(`ratings: ${st.plan.map((v) => `${v.label}=${st.ratings[v.index] ?? '-'}`).join(' ')}`);
  if (reveal) lines.push(`arms: ${st.plan.map((v) => `${v.label}:${v.id}`).join(' ')}`);
  return { ok: true, text: lines.join('\n') };
}

export function summaryText(st) {
  const v = verdicts(st.seed, st.ratings);
  const row = (a) => `${a.id}: ${verdictText(a.verdict)} (scores ${a.scores.join(', ') || '-'})`;
  return ['same look, against base:', ...v.same.map(row), 'look change, against base:', ...v.look.map(row)].join('\n');
}
