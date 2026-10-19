#!/usr/bin/env node
// Runs the preview e2e suite (src/suite.mjs) on one engine against its own rig (src/rig.mjs) and writes out/<engine>.json.
//
//   node src/run.mjs --engine chromium|playwright-webkit [--out out] [--no-lan]
//
// Chromium: $CHROME_PATH (the pinned Chrome Headless Shell the gate-engine action installs), else $E2E_CHROMIUM_CHANNEL
// (e.g. `chrome`, for a debug run on a Mac), else Playwright's own build. WebKit: Playwright's build.
// Exit code 0 only when every check passed (a failed check is a product finding, never a pass with a note).
import { chromium, webkit } from "playwright-core";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { TEST_PASSPHRASE, lanAddress, startRig } from "./rig.mjs";
import { runEngine } from "./suite.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(`--${name}`); return i >= 0 && args[i + 1] ? args[i + 1] : dflt; };
const engineArg = opt("engine", "chromium");
const engine = engineArg === "playwright-webkit" || engineArg === "webkit" ? "webkit" : engineArg === "chromium" ? "chromium" : null;
if (!engine) { console.error("usage: node src/run.mjs --engine chromium|playwright-webkit [--out dir] [--no-lan]"); process.exit(64); }
const out = resolve(opt("out", join(here, "..", "out")));

const lan = args.includes("--no-lan") ? null : await lanAddress();
process.stderr.write("# starting rig\n");
const rig = await startRig({ lan });
process.stderr.write(`# rig up ${JSON.stringify(rig.ports)}\n`);
let checks = [];
let version = "unknown";
let browser = null;
try {
  browser = engine === "webkit"
    ? await webkit.launch()
    : await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}), ...(process.env.E2E_CHROMIUM_CHANNEL ? { channel: process.env.E2E_CHROMIUM_CHANNEL } : {}) });
  version = browser.version();
  checks = await runEngine(browser, rig, engine, { passphrase: TEST_PASSPHRASE });
} catch (e) {
  checks = [{ id: `${engine}/harness`, ok: false, detail: String(e?.message ?? e).split("\n")[0] }];
} finally {
  await browser?.close().catch(() => undefined);
  await rig.close(); // also stops the preview server process this run started
}
for (const c of checks) console.log(`${c.ok ? "ok  " : "FAIL"} ${c.id}${c.detail ? `  (${c.detail})` : ""}`);
const failed = checks.filter((c) => !c.ok);
const doc = { schema: 1, engine, browser: version, playwrightCore: "1.64.1", lanHost: lan !== null, checks };
mkdirSync(out, { recursive: true });
writeFileSync(join(out, `${engine}.json`), `${JSON.stringify(doc, null, 2)}\n`);
console.log(`${engine} ${version}: ${checks.length - failed.length}/${checks.length} checks passed${lan ? "" : " (no LAN address: LAN-mode login not run)"}`);
process.exit(failed.length ? 1 : 0);
