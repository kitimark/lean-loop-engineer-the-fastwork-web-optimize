// The part of the preview e2e suite that needs no browser: the detector of double module evaluation, and the rig itself over
// plain HTTP (grant, gate, the arm origins, no redirect for a root-absolute module request). The browser half is src/run.mjs, run by
// the preview-e2e lane (.github/workflows/preview-e2e.yml) on Chromium and WebKit.
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { PREVIEW_ID, startRig } from "../src/rig.mjs";
import { documentUrl, ENTRY_SEARCH, evalReport, PATHS, REVIEW_SEARCH } from "../src/suite.mjs";

describe("evalReport", () => {
  it("a module evaluated once per file is clean", () => {
    const r = evalReport(["http://h:1/_app/immutable/entry/start.A.js", "http://h:1/_app/immutable/chunks/b.js"]);
    assert.deepEqual(r, { total: 2, files: 2, duplicates: [] });
  });
  it("the same file under two URLs is two instances (the failure the suite looks for)", () => {
    const r = evalReport(["http://h:1/_app/immutable/entry/start.A.js", "http://h:2/other/_app/immutable/entry/start.A.js"]);
    assert.equal(r.total, 2);
    assert.equal(r.files, 1);
    assert.equal(r.duplicates.length, 1);
    assert.match(r.duplicates[0], /start\.A\.js x2/);
  });
});

describe("the suite covers the task arm, the original arm and the side-by-side page", () => {
  it("paths", () => assert.deepEqual(PATHS.map((p) => p.id), ["r", "o", "compare", "entry-r", "entry-o", "entry-review-flag"]));
  it("an arm's document is its own origin; the side-by-side page is on the preview port", () => {
    const host = { origin: "http://h:10", arm: { r: "http://h:11", o: "http://h:12" } };
    assert.equal(documentUrl(host, PATHS[0]), "http://h:11/");
    assert.equal(documentUrl(host, PATHS[1]), "http://h:12/");
    assert.equal(documentUrl(host, PATHS[2]), `http://h:10/preview/${PREVIEW_ID}/compare`);
  });
  it("the entry targets open the Builds link shape on the preview port, with a search", () => {
    const host = { origin: "http://h:10", arm: { r: "http://h:11", o: "http://h:12" } };
    assert.equal(documentUrl(host, PATHS[3]), `http://h:10/preview/${PREVIEW_ID}/r/${ENTRY_SEARCH}`);
    assert.equal(documentUrl(host, PATHS[4]), `http://h:10/preview/${PREVIEW_ID}/o/${ENTRY_SEARCH}`);
    assert.match(ENTRY_SEARCH, /^\?.+=/);
  });
  it("the review flag target opens the flag arm of a review card: ?fw=<flag key> on the entry path, kept by the hop to the arm origin", () => {
    const host = { origin: "http://h:10", arm: { r: "http://h:11", o: "http://h:12" } };
    assert.equal(REVIEW_SEARCH, "?fw=nav:earn-no-transition");
    assert.equal(documentUrl(host, PATHS[5]), `http://h:10/preview/${PREVIEW_ID}/r/${REVIEW_SEARCH}`);
    assert.equal(PATHS[5].arm, "r");
  });
});

describe("rig over plain HTTP", () => {
  let rig;
  before(async () => { rig = await startRig(); });
  after(async () => { await rig?.close(); });

  it("a preview path or an arm origin without a grant is refused", async () => {
    const h = rig.hosts.loopback;
    assert.equal((await fetch(`${h.origin}/preview/${PREVIEW_ID}/compare`, { headers: { accept: "text/html" } })).status, 401);
    assert.equal((await fetch(`${h.arm.o}/`, { headers: { accept: "text/html" } })).status, 401);
    assert.equal((await fetch(`${h.arm.r}/_app/immutable/entry/start.fix1.js`)).status, 401);
  });

  it("a grant link opens the arms; a root-absolute module request is answered in place by its own arm, never redirected", async () => {
    const h = rig.hosts.loopback;
    const link = await rig.grantUrl(h.origin, "o");
    const red = await fetch(link, { redirect: "manual" });
    assert.equal(red.status, 302);
    const cookie = (red.headers.get("set-cookie") ?? "").split(";")[0];
    assert.match(cookie, /^fw_grant=/);
    assert.equal(red.headers.get("location"), `/preview/${PREVIEW_ID}/o/`);
    const get = (base, path, headers = {}) => fetch(`${base}${path}`, { redirect: "manual", headers: { cookie, ...headers } });
    // the entry path is a page-level hop to the arm's origin (with the query), not a proxy
    for (const arm of ["o", "r"]) {
      const hop = await get(h.origin, `/preview/${PREVIEW_ID}/${arm}/${ENTRY_SEARCH}`);
      assert.equal(hop.status, 302);
      assert.equal(hop.headers.get("location"), `${h.arm[arm]}/${ENTRY_SEARCH}`);
    }
    // a review card's flag query arrives on the arm origin unchanged (the colon of the flag key included)
    const flagHop = await get(h.origin, `/preview/${PREVIEW_ID}/r/${REVIEW_SEARCH}`);
    assert.equal(flagHop.status, 302);
    assert.equal(flagHop.headers.get("location"), `${h.arm.r}/${REVIEW_SEARCH}`);
    for (const arm of ["o", "r"]) {
      const doc = await get(h.arm[arm], "/");
      assert.equal(doc.status, 200, arm);
      assert.match(await doc.text(), /\/_app\//); // root-absolute paths stay as built
    }
    assert.equal((await get(h.origin, `/preview/${PREVIEW_ID}/compare`)).status, 200);
    // a module path as the browser sends it, on its own arm: no redirect, no Referer needed
    const mod = await get(h.arm.r, "/_app/immutable/entry/start.fix1.js");
    assert.equal(mod.status, 200);
    assert.match(await mod.text(), /__fwEvals/); // the evaluation counter is in front of every module
    const other = await get(h.arm.o, "/_app/immutable/entry/start.fix1.js", { referer: `${h.arm.r}/` });
    assert.equal(other.status, 404); // the original arm has no such file, whatever the Referer says: identity is the port
    // the arm origins are not served on the preview port
    assert.equal((await get(h.origin, "/_app/immutable/entry/start.fix1.js")).status, 401);
  });

  it("a grant link is single use", async () => {
    const link = await rig.grantUrl(rig.hosts.loopback.origin, "r");
    assert.equal((await fetch(link, { redirect: "manual" })).status, 302);
    assert.equal((await fetch(link, { redirect: "manual" })).status, 403);
  });
});

describe("two rig runs in one process never collide on ports (the land lane runs both engines in one job)", () => {
  it("a second rig starts after the first closed, and two rigs open together get disjoint ports; none is left listening", async () => {
    const { createServer } = await import("node:net");
    const bindable = (port) => new Promise((res) => { const s = createServer(); s.once("error", () => res(false)); s.listen(port, "127.0.0.1", () => s.close(() => res(true))); });
    const used = (r) => Object.entries(r.ports).filter(([k]) => k !== "proxy").map(([, v]) => v);
    const first = await startRig();
    const firstPorts = used(first);
    await first.close();
    for (const p of firstPorts) assert.equal(await bindable(p), true, `port ${p} still listening after close`);
    const second = await startRig(); // chromium run then webkit run: same process, same sequence
    const third = await startRig(); // overlapping runs: disjoint ports
    try {
      const all = [...used(second), ...used(third)];
      assert.equal(new Set(all).size, all.length, "ports of two live rigs overlap");
      for (const r of [second, third]) {
        assert.ok(r.backendOff > 0, "backendOff comes from Lean");
        assert.equal(r.ports.brp, r.ports.rp + r.backendOff);
        assert.ok(r.ports.rp + r.backendOff <= 65535 && r.ports.op + r.backendOff <= 65535, "private arm port above the Lean bound");
      }
    } finally { await second.close(); await third.close(); }
    for (const p of used(second).concat(used(third))) assert.equal(await bindable(p), true, `port ${p} still listening after close`);
  });
});
