// The browser-free half of leaving the grant landing page: the wait for every request the page asked for to end. A fake context
// emits the three events the real one does (request, requestfinished, requestfailed); each branch of the wait is exercised.
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { describe, it } from "node:test";
import { leavePage, openFailure, trackOpen } from "../src/suite.mjs";

describe("trackOpen", () => {
  it("is idle at once when nothing is open", async () => {
    assert.equal(await trackOpen(new EventEmitter()).idle(50), true);
  });
  it("waits for a finished request", async () => {
    const ctx = new EventEmitter(); const t = trackOpen(ctx); const r = {};
    ctx.emit("request", r);
    assert.equal(t.open.size, 1);
    const idle = t.idle(1000);
    ctx.emit("requestfinished", r);
    assert.equal(await idle, true);
    assert.equal(t.open.size, 0);
  });
  it("counts a cancelled request as ended (a failure ends it)", async () => {
    const ctx = new EventEmitter(); const t = trackOpen(ctx); const r = {};
    ctx.emit("request", r);
    const idle = t.idle(1000);
    ctx.emit("requestfailed", r);
    assert.equal(await idle, true);
  });
  it("is idle only after the last of several requests ends", async () => {
    const ctx = new EventEmitter(); const t = trackOpen(ctx); const [a, b] = [{}, {}];
    ctx.emit("request", a); ctx.emit("request", b);
    let done = false;
    const idle = t.idle(1000).then((v) => { done = true; return v; });
    ctx.emit("requestfinished", a);
    await new Promise((r) => setImmediate(r));
    assert.equal(done, false);
    ctx.emit("requestfailed", b);
    assert.equal(await idle, true);
  });
  it("gives up with false when a request never ends", async () => {
    const ctx = new EventEmitter(); const t = trackOpen(ctx);
    ctx.emit("request", {});
    assert.equal(await t.idle(20), false);
  });
});

describe("leavePage", () => {
  it("navigates to a blank document, then waits for the open requests", async () => {
    const ctx = new EventEmitter(); const t = trackOpen(ctx); const r = {};
    const gone = [];
    const page = { goto: async (u) => { gone.push(u); ctx.emit("request", r); setTimeout(() => ctx.emit("requestfailed", r), 10); } };
    assert.equal(await leavePage(page, t), true);
    assert.deepEqual(gone, ["about:blank"]);
    assert.equal(t.open.size, 0);
  });
});

describe("openFailure (controlLoad keeps leavePage's result)", () => {
  it("is null when every request ended", () => { assert.equal(openFailure(true, { open: new Set() }), null); });
  it("names the still-open requests as a cancellation, which the control counts", () => {
    const line = openFailure(false, { open: new Set([{}, {}]) });
    assert.match(line, /2 request\(s\) still open/);
    assert.match(line, /cancel/i);
  });
});
