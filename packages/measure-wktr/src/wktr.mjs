// One WebKitTestRunnerApp process driven from Node, replacing webkitpy's SimulatorProcess.
//
// Protocol (read from the WebKit sources, cited as path:line@862f17d; the archive is e1c510bc, 15 commits' worth of
// trunk away, and the same files are unchanged in the parts used here unless the run proves otherwise):
//  - The app is started with `xcrun simctl launch <udid> <bundle id> <args> -` and the environment variables prefixed
//    SIMCTL_CHILD_ (Tools/Scripts/webkitpy/xcode/simulated_device.py:716-749). The trailing `-` makes it read test
//    commands from stdin (webkitpy/port/driver.py:615).
//  - When $PORT is set the app connects three times to 127.0.0.1:$PORT and dup2()s the sockets over stdin, stdout and
//    stderr, in that order (Tools/TestRunnerShared/IOSLayoutTestCommunication.cpp:51-78). We listen and take them in
//    that order (webkitpy/port/simulator_process.py:98-118).
//  - One command per line: `<url>'--additional-header'<k=v k=v ...>` (arguments separated by an apostrophe,
//    Tools/TestRunnerShared/TestCommand.cpp:35-120). The header is the content of a `webkit-test-runner [ ... ]` test
//    header (TestFeatures.cpp featureFromAdditionalHeaderOption).
//  - The reply on stdout is `Content-Type: text/plain\n<text>#EOF\n` and then a second `#EOF\n` for the (absent) pixel
//    block; stderr gets `#EOF\n` (Tools/WebKitTestRunner/TestInvocation.cpp:258-269,333).
//  - DYLD_FRAMEWORK_PATH / DYLD_LIBRARY_PATH (and the __XPC_ copies for the child processes) point at the extracted
//    build root, so the app uses the archive's WebKit.framework and libWebCoreTestSupport.dylib
//    (webkitpy/port/driver.py:464-471, embedded_port.py:121-123).
import net from 'node:net';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { terminate } from './sim.mjs';
import { recorder } from './spans.mjs';

const EOF2 = '#EOF\n#EOF\n';

/** Environment for the app (before the SIMCTL_CHILD_ prefix). */
export function childEnv({ port, root, tempDir }) {
  const e = {
    PORT: String(port),
    DYLD_FRAMEWORK_PATH: root, __XPC_DYLD_FRAMEWORK_PATH: root,
    DYLD_LIBRARY_PATH: root, __XPC_DYLD_LIBRARY_PATH: root,
    CA_DISABLE_GENERIC_SHADERS: '1', __XPC_CA_DISABLE_GENERIC_SHADERS: '1',
    JSC_useKernTCSM: 'false', __XPC_JSC_useKernTCSM: 'false',
    SQLITE_EXEMPT_PATH_FROM_VNODE_GUARDS: '/', __XPC_SQLITE_EXEMPT_PATH_FROM_VNODE_GUARDS: '/',
    TZ: 'US/Pacific',
    DUMPRENDERTREE_TEMP: tempDir, LOCAL_RESOURCE_ROOT: tempDir,
  };
  return Object.fromEntries(Object.entries(e).map(([k, v]) => ['SIMCTL_CHILD_' + k, v]));
}

/** The test header: a flexible viewport takes the device screen (innerWidth 402, dpr 2 on the iPhone 17 simulator; MEASURED locally). */
export const DEFAULT_HEADER = 'useFlexibleViewport=true';

/**
 * Launch the app, run one test URL, return its stdout/stderr text, then terminate the app (a fresh process per pass).
 * `spans` (wall ms): prep (temp dir, listening socket), connect (simctl launch spawned until the app's three sockets are up: the
 * launch), run (command sent until the end marker: page load, settle, scroll steps), teardown (sockets, simctl terminate, temp dir).
 * @returns {Promise<{stdout:string, stderr:string, launch:string, ms:number, spans:object}>}
 */
export async function runOnce({ udid, root, bundleId, url, header = DEFAULT_HEADER, extraArgs = [], timeoutMs = 240000, connectMs = 120000 }) {
  const rec = recorder();
  const tempDir = mkdtempSync(join(tmpdir(), 'fw-wktr-tmp-'));
  const server = net.createServer();
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); });
  const port = server.address().port;
  const socks = [];
  const sockWait = new Promise((ok) => server.on('connection', (s) => { socks.push(s); if (socks.length === 3) ok(); }));
  const args = ['simctl', 'launch', udid, bundleId, '--no-timeout', '--no-enable-all-experimental-features', ...extraArgs, '-'];
  const launch = spawn('xcrun', args, { env: { ...process.env, ...childEnv({ port, root, tempDir }) } });
  let launchOut = '';
  launch.stdout.on('data', (d) => { launchOut += d; });
  launch.stderr.on('data', (d) => { launchOut += d; });
  rec.mark('prep');
  const t0 = Date.now();
  let result = null;
  let stdout = '', stderr = '';
  try {
    const timeout = (ms, what) => new Promise((_, bad) => setTimeout(() => bad(new Error(`timeout (${ms} ms): ${what}; launch said: ${launchOut.trim()}`)), ms).unref());
    await Promise.race([sockWait, timeout(connectMs, 'the app did not connect its three sockets')]);
    rec.mark('connect');
    const [sin, sout, serr] = socks;
    sout.setEncoding('utf8'); serr.setEncoding('utf8');
    serr.on('data', (d) => { stderr += d; });
    const done = new Promise((ok, bad) => {
      sout.on('data', (d) => { stdout += d; if (stdout.endsWith(EOF2)) ok(); });
      sout.on('close', () => bad(new Error(`stdout closed before the end marker; got ${stdout.length} bytes; stderr tail: ${stderr.slice(-400)}`)));
      sout.on('error', bad);
    });
    done.catch(() => {});
    sin.write(`${url}'--additional-header'${header}\n`);
    await Promise.race([done, timeout(timeoutMs, 'the test did not finish')]);
    rec.mark('run');
    result = { stdout, stderr, launch: launchOut.trim(), ms: Date.now() - t0 };
    return result;
  } finally {
    for (const s of socks) s.destroy();
    terminate(udid, bundleId);
    server.close();
    rmSync(tempDir, { recursive: true, force: true });
    rec.mark('teardown');
    if (result) result.spans = rec.spans();
  }
}
