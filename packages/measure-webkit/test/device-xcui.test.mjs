import test from 'node:test';
import assert from 'node:assert/strict';
import { deviceBuildArgs, keychainTeam, teamOfSubject } from '../src/device-xcui.mjs';

test('teamOfSubject reads the OU field and nothing else', () => {
  assert.equal(teamOfSubject('subject=UID=AAAAAAAAAA,  OU=ABCDE12345, O=Someone, C=US'), 'ABCDE12345');
  assert.equal(teamOfSubject('subject=OU=ABCDE12345'), 'ABCDE12345');
  assert.equal(teamOfSubject('subject=CN=x, O=y'), null);
  assert.equal(teamOfSubject('subject=OU=short, O=y'), null);
});

test('deviceBuildArgs signs for one device and names the team', () => {
  const a = deviceBuildArgs({ udid: 'U1', team: 'T123456789', derived: '/d/dd' });
  assert.ok(a.includes('id=U1') && a.includes('DEVELOPMENT_TEAM=T123456789') && a.includes('CODE_SIGNING_ALLOWED=YES'));
  assert.ok(a.includes('-allowProvisioningUpdates'));
  assert.throws(() => deviceBuildArgs({ udid: 'U1', team: null, derived: '/d' }), /team id/);
});

test('keychainTeam is null without a certificate and the OU with one', () => {
  assert.equal(keychainTeam(() => ({ status: 44, stdout: '' })), null);
  const calls = [];
  const run = (cmd) => { calls.push(cmd); return cmd === 'security' ? { status: 0, stdout: 'PEM' } : { status: 0, stdout: 'subject=OU=ABCDE12345, O=x' }; };
  assert.equal(keychainTeam(run), 'ABCDE12345');
  assert.deepEqual(calls, ['security', 'openssl']);
});
