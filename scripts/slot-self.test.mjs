import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { plan } from "./slot-self.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const top = join(here, "..");
const helper = join(here, "slot-self.mjs");

test("plan: bare call routes through slot run with its kind, in this process", () => {
  const p = plan({}, ["test", "--", "pnpm", "run", "test:run"]);
  assert.equal(p.routed, true);
  assert.deepEqual(p.slot, ["run", "--kind", "test", "--", "pnpm", "run", "test:run"]);
  assert.equal(p.argv, undefined);
});

test("plan: a live parent token, CI and FW_SLOT_SELF=off run the command directly", () => {
  assert.deepEqual(plan({ FW_SLOT_TOKEN: "T" }, ["check", "--", "sh", "x"], true), { argv: ["sh", "x"], routed: false });
  for (const env of [{ CI: "true" }, { FW_SLOT_SELF: "off" }]) {
    assert.deepEqual(plan(env, ["check", "--", "sh", "x"]), { argv: ["sh", "x"], routed: false });
  }
});

test("plan: FW_SLOT_HELD without a live token queues", () => {
  assert.equal(plan({ FW_SLOT_HELD: "1" }, ["check", "--", "sh", "x"]).routed, true);
  assert.equal(plan({ FW_SLOT_HELD: "1", FW_SLOT_TOKEN: "T" }, ["check", "--", "sh", "x"], false).routed, true);
});

test("plan: bad usage is an error", () => {
  for (const a of [[], ["test"], ["lint", "--", "x"], ["test", "--"]]) assert.ok(plan({}, a).error);
});

test("nested call under a live parent token of another kind starts at once; a dead token queues", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-nest-"));
  const base = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "nest-test" };
  delete base.CI; delete base.FW_SLOT_SELF; delete base.FW_SLOT_HELD; delete base.FW_SLOT_TOKEN;
  const fw = join(top, "apps", "runner", "src", "fw.ts");
  const held = spawnSync(process.execPath, [fw, "slot", "acquire", "--kind", "land", "--lease", "120"], { env: base, encoding: "utf8", cwd: top });
  assert.equal(held.status, 0, held.stderr);
  const token = held.stdout.trim();
  const code = "console.log('ran', process.env.FW_SLOT_TOKEN); process.exit(4)";
  try {
    const live = spawnSync(process.execPath, [helper, "check", "--", process.execPath, "-e", code],
      { env: { ...base, FW_SLOT_HELD: "1", FW_SLOT_TOKEN: token }, encoding: "utf8", cwd: top });
    assert.equal(live.status, 4, live.stderr);
    assert.equal(live.stdout.trim(), `ran ${token}`);
    const dead = spawnSync(process.execPath, [helper, "check", "--", process.execPath, "-e", code],
      { env: { ...base, FW_SLOT_DIR: mkdtempSync(join(tmpdir(), "slot-dead-")), FW_SLOT_HELD: "1", FW_SLOT_TOKEN: "no-such-token" }, encoding: "utf8", cwd: top });
    assert.equal(dead.status, 4, dead.stderr);
    assert.doesNotMatch(dead.stdout, /ran no-such-token/);
  } finally {
    spawnSync(process.execPath, [fw, "slot", "release", "--token", token], { env: base, cwd: top });
  }
});

test("bare call queues: it goes through the slot (state written, child sees FW_SLOT_HELD)", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-self-"));
  const env = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "slot-self-test" };
  delete env.FW_SLOT_HELD; delete env.CI; delete env.FW_SLOT_SELF;
  const r = spawnSync(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('held', process.env.FW_SLOT_HELD, process.env.FW_SLOT_OWNER)"],
    { env, encoding: "utf8", cwd: top });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /held 1 slot-self-test/);
  assert.ok(readdirSync(dir).length > 0, "slot state written");
});

test("waiter: one node process, no second fw process, starts only after the holder releases", async () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-wait-"));
  const env = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "wait-test" };
  delete env.FW_SLOT_HELD; delete env.CI; delete env.FW_SLOT_SELF;
  const fw = join(top, "apps", "runner", "src", "fw.ts");
  const held = spawnSync(process.execPath, [fw, "slot", "acquire", "--kind", "test", "--lease", "120"], { env: { ...env, FW_SLOT_OWNER: "holder" }, encoding: "utf8", cwd: top });
  assert.equal(held.status, 0, held.stderr);
  const token = held.stdout.trim();
  const w = spawn(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('started')"], { env, cwd: top });
  let out = "", err = "";
  w.stdout.on("data", (b) => { out += b; });
  w.stderr.on("data", (b) => { err += b; });
  const exited = new Promise((res) => w.on("close", res));
  try {
    await new Promise((r) => setTimeout(r, 3000));
    assert.equal(out, "", "the command must not start while the slot is held");
    assert.match(err, /slot test: waiting/);
    const kids = spawnSync("pgrep", ["-P", String(w.pid)], { encoding: "utf8" }).stdout.trim();
    assert.equal(kids, "", "the waiting process has no child process");
  } finally {
    spawnSync(process.execPath, [fw, "slot", "release", "--token", token], { env: { ...env, FW_SLOT_OWNER: "holder" }, cwd: top });
  }
  assert.equal(await exited, 0);
  assert.match(out, /started/);
});

test("fw.ts slot: usage error exits 64 with the usage text, like fw-main.ts", () => {
  const fw = join(top, "apps", "runner", "src", "fw.ts");
  const r = spawnSync(process.execPath, [fw, "slot", "run", "--kind", "test"], { encoding: "utf8", cwd: top, env: { ...process.env, FW_LOCK_EVENTS: "off" } });
  assert.equal(r.status, 64);
  assert.match(r.stderr, /usage: fw slot run/);
});

// The guard line of lean/scripts/check.sh, run in a scratch tree whose script body only prints "ran".
const guardTree = () => {
  const line = readFileSync(join(top, "lean", "scripts", "check.sh"), "utf8").split("\n").find((l) => l.includes("slot-self.mjs check"));
  assert.ok(line, "check.sh has the slot-self guard line");
  const root = mkdtempSync(join(tmpdir(), "slot-guard-"));
  mkdirSync(join(root, "lean", "scripts"), { recursive: true });
  symlinkSync(here, join(root, "scripts"));
  writeFileSync(join(root, "lean", "scripts", "check.sh"), `${line}\necho ran\n`);
  return join(root, "lean");
};
const cleanEnv = (dir) => {
  const e = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "guard-test" };
  for (const k of ["CI", "FW_SLOT_SELF", "FW_SLOT_SELF_IN", "FW_SLOT_HELD", "FW_SLOT_TOKEN"]) delete e[k];
  return e;
};

test("check.sh guard, no token: an inherited FW_SLOT_HELD alone still queues through a check slot", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-guard-state-"));
  const r = spawnSync("sh", ["scripts/check.sh"], { cwd: guardTree(), env: { ...cleanEnv(dir), FW_SLOT_HELD: "1" }, encoding: "utf8", timeout: 60000 });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /ran/);
  assert.ok(readdirSync(dir).length > 0, "slot state written: it took its own slot");
});

test("check.sh guard, no recursion: an exported owner and token without FW_SLOT_HELD runs the script once", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-guard-state-"));
  const base = cleanEnv(dir);
  const fw = join(top, "apps", "runner", "src", "fw.ts");
  const held = spawnSync(process.execPath, [fw, "slot", "acquire", "--kind", "sim", "--lease", "120"], { env: base, encoding: "utf8", cwd: top });
  assert.equal(held.status, 0, held.stderr);
  const token = held.stdout.trim();
  try {
    const r = spawnSync("sh", ["scripts/check.sh"], { cwd: guardTree(), env: { ...base, FW_SLOT_TOKEN: token }, encoding: "utf8", timeout: 30000 });
    assert.equal(r.status, 0, `${r.error ?? ""}${r.stderr}`);
    assert.equal(r.stdout, "ran\n");
  } finally {
    spawnSync(process.execPath, [fw, "slot", "release", "--token", token], { env: base, cwd: top });
  }
});

test("slot-self direct path sets FW_SLOT_SELF_IN for the child", () => {
  const r = spawnSync(process.execPath, [helper, "check", "--", process.execPath, "-e", "console.log(process.env.FW_SLOT_SELF_IN)"],
    { env: { ...cleanEnv(mkdtempSync(join(tmpdir(), "slot-direct-"))), FW_SLOT_SELF: "off" }, encoding: "utf8", cwd: top });
  assert.equal(r.stdout.trim(), "1");
});
