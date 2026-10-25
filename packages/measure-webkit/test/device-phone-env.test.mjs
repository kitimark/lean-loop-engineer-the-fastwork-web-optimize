import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_SPEC, assertNoForeignProxy, foreignProxies, parsePs, portsOf, readsUsb, specOf, usbEvidence, usbListed, usbReading } from '../src/device-phone-env.mjs';

const UDID = 'AAAA-1111';

const PS = [
  '  101     1 /opt/homebrew/bin/ios_webkit_debug_proxy -c null:9460,:9461 -d',
  '  102     1 /usr/bin/node something.mjs ios_webkit_debug_proxy',
  '  103   100 ios_webkit_debug_proxy -s /tmp/sim.sock',
  '  104     1 /opt/homebrew/bin/ios_webkit_debug_proxy',
].join('\n');

test('parsePs keeps only ios_webkit_debug_proxy processes, by their program name', () => {
  assert.deepEqual(parsePs(PS).map((p) => p.pid), [101, 103, 104]);
  assert.deepEqual(parsePs(PS)[0].args, ['-c', 'null:9460,:9461', '-d']);
});

test('specOf reads -c inline or from a file, -u, and falls back to the default', () => {
  assert.equal(specOf(['-c', 'null:9460,:9461']), 'null:9460,:9461');
  assert.equal(specOf(['--config=x:9300']), 'x:9300');
  assert.equal(specOf(['-c', '/cfg/devices.txt'], (f) => (f === '/cfg/devices.txt' ? 'AAAA-1111:9300' : '')), 'AAAA-1111:9300');
  assert.equal(specOf(['-c', '/missing'], () => { throw new Error('ENOENT'); }), null);
  assert.equal(specOf(['-u', UDID]), `${UDID}:9222`);
  assert.equal(specOf(['--udid', `${UDID}:9300`]), `${UDID}:9300`);
  assert.equal(specOf(['-d']), DEFAULT_SPEC);
});

test('readsUsb is false only for a Simulator proxy; portsOf reads lsof -Fn', () => {
  assert.equal(readsUsb(['-c', 'x']), true);
  assert.equal(readsUsb(['-s', '/tmp/s']), false);
  assert.equal(readsUsb(['--simulator=/tmp/s']), false);
  assert.deepEqual(portsOf('p101\nn*:9460\nn127.0.0.1:9461\nn[::1]:9222\n'), [9460, 9461, 9222]);
});

const fakeRun = (lsof) => (cmd, args) => {
  if (cmd === 'ps') return { status: 0, stdout: PS, stderr: '' };
  if (cmd === 'lsof') return { status: 0, stdout: lsof[args[args.indexOf('-p') + 1]] ?? '', stderr: '' };
  return { status: 1, stdout: '', stderr: '' };
};

test('foreignProxies skips this process and its children, and reports ports, spec and USB use', () => {
  const ps = foreignProxies({ run: fakeRun({ 101: 'n*:9460\nn*:9461\n', 104: 'n*:9222\n' }), self: 100 });
  assert.deepEqual(ps.map((p) => p.pid), [101, 104]);
  assert.deepEqual(ps[0], { pid: 101, ports: [9460, 9461], spec: 'null:9460,:9461', usb: true });
  assert.equal(ps[1].spec, DEFAULT_SPEC);
});

test('assertNoForeignProxy refuses a proxy on the guarded ports and names it; passes when none competes', () => {
  assert.throws(() => assertNoForeignProxy(UDID, { run: fakeRun({ 104: 'n*:9222\n' }), self: 100 }), /another ios_webkit_debug_proxy is running \(pid 101 attached; pid 104 holdsPorts on ports 9222\)/);
  const other = '  105     1 ios_webkit_debug_proxy -c OTHER-2222:9460';
  const ok = assertNoForeignProxy(UDID, { run: (c) => (c === 'ps' ? { status: 0, stdout: other, stderr: '' } : { status: 0, stdout: 'n*:9460\n', stderr: '' }), self: 100 });
  assert.equal(ok.length, 1);
});

test('a failing ps is an error, never a silent "no other proxy"', () => {
  assert.throws(() => foreignProxies({ run: () => ({ status: 1, stdout: '', stderr: '' }) }), /ps failed/);
});

test('usbEvidence keeps usbpowerd terminated/discovered lines as time and word; usbReading gives the Lean verdict', () => {
  const log = [
    '2026-10-25 16:24:38.100 Df usbpowerd[88:1] device terminated',
    '2026-10-25 16:24:39.000 Df usbpowerd[88:1] unrelated chatter',
    '2026-10-25 16:24:40.200 Df usbpowerd[88:1] service discovered',
  ].join('\n');
  const run = (cmd) => {
    if (cmd === '/usr/bin/log') return { status: 0, stdout: log, stderr: '' };
    if (cmd === 'idevice_id') return { status: 0, stdout: '', stderr: '' };
    if (cmd === 'ioreg') return { status: 0, stdout: '| iPhone', stderr: '' };
    return { status: 1, stdout: '', stderr: '' };
  };
  assert.deepEqual(usbEvidence(0, { run }), [{ at: '2026-10-25 16:24:38', what: 'usbpowerd terminated' }, { at: '2026-10-25 16:24:40', what: 'usbpowerd discovered' }]);
  const r = usbReading(UDID, 0, { run });
  assert.equal(r.verdict, 'reset');
  assert.equal(r.listed, false);
  assert.equal(r.onBus, true);
  assert.equal(usbListed(UDID, { run: () => ({ stdout: `${UDID}\n` }) }), true);
});

test('with no log evidence and the phone listed the reading is ok', () => {
  const run = (cmd) => ({ status: cmd === '/usr/bin/log' ? 1 : 0, stdout: cmd === 'idevice_id' ? `${UDID}\n` : cmd === 'ioreg' ? 'iPhone' : '', stderr: '' });
  assert.equal(usbReading(UDID, 0, { run }).verdict, 'ok');
});
