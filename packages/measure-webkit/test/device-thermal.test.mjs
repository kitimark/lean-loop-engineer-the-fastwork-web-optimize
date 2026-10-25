import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { COOL_S, PAUSE_MAX_S, POLL_S, TEMP_MARGIN_C, blockPasses, gate, lockOf, parseThermalXml, pauseOver, preflight, readLock, readThermal, resume, thermalOfName } from '../src/device-thermal.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/thermal.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const num = (x) => (x === null ? undefined : x);

test('the golden has every kind', () => {
  for (const k of ['consts', 'parse', 'lock', 'gate', 'preflight', 'block', 'pause', 'resume']) assert.ok(of(k).length > 0, k);
});

test('constants and the state names match Lean', () => {
  const [c] = of('consts');
  assert.equal(c.tempMarginC, TEMP_MARGIN_C);
  assert.equal(c.coolS, COOL_S);
  assert.equal(c.pollS, POLL_S);
  assert.equal(c.pauseMaxS, PAUSE_MAX_S);
  for (const p of of('pause')) assert.equal(pauseOver(p.pausedS, p.nowS), p.over, JSON.stringify(p));
  for (const p of of('parse')) assert.equal(thermalOfName(p.text), p.state, JSON.stringify(p.text));
});

test('lock and gate match Lean', () => {
  for (const l of of('lock')) assert.equal(lockOf(l.passcodeRequired), l.lock);
  for (const g of of('gate')) assert.equal(gate(g.state, num(g.tempC), num(g.firstC)), g.verdict, JSON.stringify(g));
  for (const p of of('preflight')) assert.equal(preflight(p.lock, p.state, num(p.tempC), num(p.firstC)), p.verdict, JSON.stringify(p));
});

test('never a go at serious or critical, whatever the battery says', () => {
  for (const s of ['Serious', 'Critical', 'Fair']) for (const t of [undefined, 0, 33, 90]) assert.notEqual(gate(s, t, 33), 'go', `${s} ${t}`);
});

test('blocks and resumes match Lean: at most one pass after the trigger, a cool gap at nominal to resume', () => {
  for (const b of of('block')) {
    const rd = b.readings.map((r) => ({ state: r.state, tempC: num(r.tempC) }));
    assert.deepEqual(rd.map((r) => gate(r.state, r.tempC, b.firstC)), b.verdicts);
    assert.equal(blockPasses(rd, b.firstC), b.passes, JSON.stringify(b));
  }
  for (const r of of('resume')) assert.equal(resume(r.nowS, r.pausedS, r.readings), r.resume, JSON.stringify(r));
});

const XML = (rows) => `<?xml version="1.0"?>\n<trace-query-result>\n<node xpath='//trace-toc[1]/run[1]/data[1]/table[2]'><schema name="device-thermal-state-intervals"></schema>${rows}\n</node></trace-query-result>\n`;
const ROW1 = '<row><start-time id="1" fmt="00:00.000.000">0</start-time><duration id="2" fmt="8.85 s">8847725868</duration><start-time id="3" fmt="00:08.847.725">8847725868</start-time><thermal-state id="4" fmt="Nominal">Nominal</thermal-state><string id="5" fmt="Current">Current</string><boolean id="6" fmt="No">0</boolean><narrative id="7" fmt="Nominal thermal state"><thermal-state ref="4"/><narrative-text id="8" fmt=" thermal state"> thermal state</narrative-text></narrative></row>';
const ROW2 = '<row><start-time id="9" fmt="00:08.847.725">8847725868</start-time><duration id="10" fmt="1 s">1000000000</duration><start-time id="11" fmt="00:09.847.725">9847725868</start-time><thermal-state id="12" fmt="Fair">Fair</thermal-state><string ref="5"/><boolean ref="6"/></row>';
const ROW3 = '<row><start-time ref="11"/><duration ref="10"/><start-time id="13" fmt="00:10">1</start-time><thermal-state ref="4"/><string ref="5"/><boolean ref="6"/></row>';

test('the export parses to the last row, also through a reference to an earlier name', () => {
  assert.equal(parseThermalXml(XML(ROW1)), 'Nominal');
  assert.equal(parseThermalXml(XML(ROW1 + ROW2)), 'Fair');
  assert.equal(parseThermalXml(XML(ROW1 + ROW2 + ROW3)), 'Nominal');
  assert.equal(parseThermalXml(XML('')), null);
  assert.equal(parseThermalXml(XML('<row><thermal-state id="1" fmt="Hot">Hot</thermal-state></row>')), null);
});

// A fake runner: devicectl writes the lock json to --json-output, xctrace record succeeds, export prints the table.
const fake = ({ pr = false, rec = 0, exportXml = XML(ROW1), exportStatus = 0, counts = {} } = {}) => (cmd, args) => {
  const kind = args[0] === 'devicectl' ? 'lock' : `xctrace-${args[1]}`;
  counts[kind] = (counts[kind] ?? 0) + 1;
  if (kind === 'lock') { writeFileSync(args[args.indexOf('--json-output') + 1], JSON.stringify({ result: { passcodeRequired: pr } })); return { status: 0, stdout: '', stderr: '' }; }
  if (args[1] === 'record') return { status: rec, stdout: '', stderr: '' };
  return { status: exportStatus, stdout: exportXml, stderr: '' };
};

test('readThermal reads the lock first, then records and exports once', () => {
  const counts = {};
  const r = readThermal('X', { run: fake({ counts }) });
  assert.equal(r.state, 'Nominal');
  assert.equal(r.lock, 'unlocked');
  assert.equal(r.error, null);
  assert.deepEqual(counts, { lock: 1, 'xctrace-record': 1, 'xctrace-export': 1 });
});

test('readThermal retries once and then names the failure; a locked phone is reported as such', () => {
  const counts = {};
  const r = readThermal('X', { run: fake({ rec: 13, counts }) });
  assert.equal(r.state, null);
  assert.match(r.error, /xctrace record exit 13/);
  assert.equal(counts['xctrace-record'], 2);
  assert.equal(readThermal('X', { run: fake({ exportXml: XML('') }) }).error, 'the thermal-state table has no readable row');
  assert.equal(readThermal('X', { run: fake({ pr: true }) }).lock, 'locked');
  assert.equal(readLock('X', { run: () => ({ status: 1, stdout: '', stderr: '' }) }), 'unknown');
});
