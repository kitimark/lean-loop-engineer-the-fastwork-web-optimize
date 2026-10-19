// Owner link secrecy (Lean `Fw.Console.Preview`: linkSink, no_file_sink, linkPlan_ok; golden console.previewLink).
// A console started as a background task has its stdout in a file; the token must never reach it.
import { spawn } from "node:child_process";
import { closeSync, mkdtempSync, openSync, readFileSync, existsSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { announceLink, reissueLink, signalConsole, NO_TTY_MESSAGE, TOO_SOON_MESSAGE, type LinkClock, type Tty } from "../src/preview/link.ts";
import { OwnerAuth } from "../src/preview/owner.ts";

const here = dirname(fileURLToPath(import.meta.url));
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe("announceLink (Lean console.previewLink decides the sink)", () => {
  const core = selectCore(process.env);
  it("a terminal gets the link and nothing else does", async () => {
    const owner = new OwnerAuth();
    const tty: string[] = []; const said: string[] = []; let closed = false;
    const fake: Tty = { write: (s) => { tty.push(s); }, close: () => { closed = true; } };
    const where = await announceLink(core, () => `http://127.0.0.1:1/owner?t=${owner.token()}`, (m) => said.push(m), () => fake);
    expect(where).toBe("tty");
    expect(tty.join("")).toContain(`t=${owner.token()}`);
    expect(said).toEqual([]);
    expect(closed).toBe(true);
  });

  it("no terminal: no link is written anywhere; the message holds no token", async () => {
    const owner = new OwnerAuth();
    const said: string[] = [];
    const where = await announceLink(core, () => `http://127.0.0.1:1/owner?t=${owner.token()}`, (m) => said.push(m), () => null);
    expect(where).toBe("none");
    expect(said).toEqual([NO_TTY_MESSAGE]);
    expect(said.join("")).not.toContain(owner.token()!);
  });

  it("console-daemon: with no terminal the link is never even built, so no log or output can hold the token", async () => {
    const owner = new OwnerAuth();
    const token = owner.token()!;
    let built = 0; const said: string[] = [];
    await announceLink(core, () => { built++; return `http://127.0.0.1:1/owner?t=${token}`; }, (m) => said.push(m), () => null);
    expect(built).toBe(0);
    expect(said.join("\n")).not.toContain(token);
    expect(said.join("\n")).toContain("/owner/login");
  });

  it("reissue replaces the unused link; the old one no longer redeems", () => {
    const owner = new OwnerAuth();
    const old = owner.token()!;
    const fresh = owner.reissue();
    expect(fresh).not.toBe(old);
    expect(owner.redeem(old)).toBeNull();
    expect(owner.redeem(fresh)).not.toBeNull();
  });
});

describe("reissue is rate-limited by Lean mayReissue (one link a minute)", () => {
  const core = selectCore(process.env);
  it("a second request inside the minute changes nothing: the unused link stays valid", async () => {
    const owner = new OwnerAuth();
    const first = owner.token()!;
    const clock: LinkClock = { last: 1000 }; // the startup link was written at t = 1 s
    const tty: string[] = []; const said: string[] = [];
    const open = (): Tty => ({ write: (s) => { tty.push(s); }, close: () => undefined });
    const r = await reissueLink(core, clock, 30_000, () => `u?t=${owner.reissue()}`, (m) => said.push(m), open);
    expect(r).toBe("tooSoon");
    expect(said).toEqual([TOO_SOON_MESSAGE]);
    expect(tty).toEqual([]);
    expect(owner.redeem(first)).not.toBeNull(); // not invalidated
  });
  it("a request a minute after the last link issues a new one and restarts the clock", async () => {
    const owner = new OwnerAuth();
    const first = owner.token()!;
    const clock: LinkClock = { last: 1000 };
    const tty: string[] = [];
    const open = (): Tty => ({ write: (s) => { tty.push(s); }, close: () => undefined });
    const r = await reissueLink(core, clock, 61_000, () => `u?t=${owner.reissue()}`, () => undefined, open);
    expect(r).toBe("tty");
    expect(clock.last).toBe(61_000);
    expect(owner.redeem(first)).toBeNull();
    expect(tty.join("")).toContain("t=");
    const again = await reissueLink(core, clock, 62_000, () => `u?t=${owner.reissue()}`, () => undefined, open);
    expect(again).toBe("tooSoon");
  });
});

describe("owner-link signals only a process that answers as the console", () => {
  const sent: [number, string][] = [];
  const kill = (pid: number, sig: string) => { sent.push([pid, sig]); };
  it("the same pid answers: SIGUSR2 is sent", async () => {
    sent.length = 0;
    const r = await signalConsole({ port: 47001, pid: 4242 }, { get: async () => "4242", kill });
    expect(r).toEqual({ ok: true });
    expect(sent).toEqual([[4242, "SIGUSR2"]]);
  });
  it("another pid answers on the port (stale api.json): refused, nothing signalled", async () => {
    sent.length = 0;
    expect(await signalConsole({ port: 47001, pid: 4242 }, { get: async () => "999", kill })).toEqual({ ok: false, reason: "pidMismatch" });
    expect(sent).toEqual([]);
  });
  it("nothing answers, or the answer has no pid: refused", async () => {
    sent.length = 0;
    expect(await signalConsole({ port: 47001, pid: 4242 }, { get: async () => null, kill })).toEqual({ ok: false, reason: "noAnswer" });
    expect(await signalConsole({ port: 47001, pid: 4242 }, { get: async () => { throw new Error("refused"); }, kill })).toEqual({ ok: false, reason: "noAnswer" });
    expect(await signalConsole({ port: 47001, pid: 4242 }, { get: async () => "", kill })).toEqual({ ok: false, reason: "pidMismatch" });
    expect(sent).toEqual([]);
  });
  it("a bad record is refused before any request (pid 1, no port)", async () => {
    let asked = false;
    const io = { get: async () => { asked = true; return "1"; }, kill };
    expect(await signalConsole({ port: 0, pid: 1 }, io)).toEqual({ ok: false, reason: "badInfo" });
    expect(asked).toBe(false);
  });
});

describe("main.ts started as a background task (stdout and stderr are files, no controlling terminal)", () => {
  it("the output files contain no owner token and no link; the console says how to get one", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-ol-"));
    const out = join(dir, "out.log");
    const fd = openSync(out, "w");
    // detached = its own session: no controlling terminal, as for a harness background task
    const child = spawn(process.execPath, [join(here, "../src/main.ts")], {
      cwd: join(here, ".."), detached: true, stdio: ["ignore", fd, fd],
      env: { ...process.env, FW_CONSOLE_DIR: join(dir, ".fw-console"), PORT: "0", FW_CONSOLE_KEYCHAIN: "off" },
    });
    closeSync(fd);
    try {
      let text = "";
      for (;;) { // poll until the "listening" line and the owner-link message appear; the test timeout catches a hang
        await wait(100);
        text = readFileSync(out, "utf8");
        if (text.includes("listening on") && text.includes("no controlling terminal")) break;
      }
      expect(text).toContain("listening on");
      expect(text).toContain("no controlling terminal");
      expect(text).not.toMatch(/owner\?t=/);
      expect(text).not.toMatch(/owner link \(open once/);
      expect(text).not.toMatch(/(?<![\/\w.-])[A-Za-z0-9_-]{32}(?![\/\w.-])/); // a 24-byte base64url token is 32 characters
      // nothing under the console dir holds a token either
      const files: string[] = [];
      const walk = (d: string) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); e.isDirectory() ? walk(p) : files.push(p); } };
      walk(join(dir, ".fw-console"));
      for (const f of files) expect(readFileSync(f, "utf8"), f).not.toMatch(/owner\?t=/);
      // SIGUSR2 (what `owner-link` sends) also writes nothing to the files
      process.kill(child.pid!, "SIGUSR2");
      await wait(500);
      expect(readFileSync(out, "utf8")).not.toMatch(/owner\?t=/);
      expect(existsSync(join(dir, ".fw-console", "api.json"))).toBe(true);
    } finally {
      try { process.kill(-child.pid!, "SIGTERM"); } catch { /* already gone */ } // the group this test started
      await wait(300);
      rmSync(dir, { recursive: true, force: true });
    }
  }, 30_000);
});
