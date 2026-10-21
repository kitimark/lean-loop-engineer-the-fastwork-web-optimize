// node --test scripts/run-cite.test.mjs (task run-cite-check)
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  armsOf, cli, coreCall, fetchFacts, gatherFacts, ledgerCites, loadCache, NO_ARTIFACT, NOT_FOUND, noteCites, request, top,
} from "./run-cite.mjs";

const bin = process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore");
const golden = readFileSync(join(top, "packages/contracts/golden/gate/run-cite.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

test("every golden line: fwcore answers the recorded response", () => {
  const input = golden.map((g, i) => JSON.stringify({ ...g.request, id: i })).join("\n") + "\n";
  const r = spawnSync(bin, [], { input, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  const replies = r.stdout.trim().split("\n").map((l) => JSON.parse(l));
  assert.equal(replies.length, golden.length);
  golden.forEach((g, i) => {
    const { id, ...rest } = replies[i];
    assert.equal(id, i);
    assert.deepEqual(rest, g.response, g.name);
  });
});

function scratch(body) {
  const d = mkdtempSync(join(tmpdir(), "run-cite-test-"));
  try { return body(d); } finally { rmSync(d, { recursive: true, force: true }); }
}

const put = (dir, name, file, data) => {
  mkdirSync(join(dir, name), { recursive: true });
  writeFileSync(join(dir, name, file), JSON.stringify(data));
};

/** Artifact directories of a trajectory run with candidate search `cand`, as `gh run download -p` lays them out. */
const trajectoryRun = (cand) => (_run, dir) => {
  put(dir, "trajectory-chromium", "raw-chromium.json", { search: cand, runs: [{ search: "" }, { search: "" }, { search: cand }] });
  writeFileSync(join(dir, "trajectory-chromium", "summary-chromium.md"), "x");
  return { ok: true };
};

test("armsOf reads the search of every arm from each artifact kind", () => scratch((d) => {
  put(d, "trajectory-apple", "raw-webkit-apple.json", { runs: [{ search: "" }, { search: "?fw=a:b" }] });
  put(d, "chromium-counts-rewrite-r1", "counts.json", { meta: { target: "rewrite", search: "?fw=c:d" } });
  put(d, "chromium-counts-original-r1", "counts.json", { meta: { target: "original", search: "" } });
  put(d, "gate-chromium-j0", "chromium.json", { header: { flags: { search: "?preset=v2-proved" } } });
  put(d, "webkit-sim-v1", "v1-session-1.json", { site: null });
  put(d, "webkit-sim-v2", "v2-session-1.json", { site: { search: "?fw=e:f" } });
  put(d, "webkit-sim-v2", "v2-quiet.json", { site: { search: "?fw=x:y" } });
  put(d, "site-dist", "a.json", { search: "?fw=x:y" });
  const s = (n) => armsOf(n, join(d, n)).map((a) => a.search);
  assert.deepEqual(s("trajectory-apple"), ["", "?fw=a:b"]);
  assert.deepEqual(armsOf("trajectory-apple", join(d, "trajectory-apple"))[1], { artifact: "trajectory-apple", file: "raw-webkit-apple.json", search: "?fw=a:b" });
  assert.deepEqual(s("chromium-counts-rewrite-r1"), ["?fw=c:d"]);
  assert.deepEqual(s("chromium-counts-original-r1"), [""]);
  assert.deepEqual(s("gate-chromium-j0"), ["?preset=v2-proved"]);
  assert.deepEqual(s("webkit-sim-v1"), [""]);
  assert.deepEqual(s("webkit-sim-v2"), ["?fw=e:f"]);
  assert.deepEqual(s("site-dist"), []);
}));

test("citations: every run id of a flag row's evidence; explicit '<run> <flag>' pairs in a note", () => {
  const ledger = { findings: [
    { id: "r1", flag: "a:b", evidence: "runs 39457767229 and 39462241403 (A/A 39466378530); again 39457767229" },
    { id: "r2", evidence: "run 39000000000" },
    { id: "r3", flag: "c:d" },
  ] };
  assert.deepEqual(ledgerCites(ledger).map((c) => `${c.run} ${c.flag} ${c.source}`),
    ["39457767229 a:b ledger:r1", "39462241403 a:b ledger:r1", "39466378530 a:b ledger:r1"]);
  assert.deepEqual(noteCites("see 39457767229 morph.tween:waapi. Also 39457767229 morph.tween:waapi and 39462241403 hero.exit:faithful@plain, run 1 a:b", "n.md"),
    [{ run: "39457767229", flag: "morph.tween:waapi", source: "n.md" }, { run: "39462241403", flag: "hero.exit:faithful@plain", source: "n.md" }]);
});

test("fetchFacts: arms, a missing artifact or run is unknown, any other gh failure throws", () => {
  assert.deepEqual(fetchFacts("1", trajectoryRun("?fw=a:b")).arms.map((a) => a.search), ["", "", "?fw=a:b"]);
  assert.deepEqual(fetchFacts("2", () => ({ ok: false, status: 1, stderr: "no valid artifacts found to download\n" })), { run: "2", missing: NO_ARTIFACT });
  assert.deepEqual(fetchFacts("3", () => ({ ok: false, status: 1, stderr: "HTTP 404: Not Found\n" })), { run: "3", missing: NOT_FOUND });
  assert.deepEqual(fetchFacts("4", () => ({ ok: true })), { run: "4", missing: NO_ARTIFACT });
  assert.throws(() => fetchFacts("5", () => ({ ok: false, status: 1, stderr: "HTTP 403: API rate limit exceeded\n" })), /not retried/);
});

test("the cache: a repeat check downloads nothing; a failed download caches nothing and is not retried", () => scratch((d) => {
  const cacheFile = join(d, "cache", "runs.json");
  const calls = [];
  const download = (run, dir) => { calls.push(run); return run === "9" ? { ok: false, status: 1, stderr: "HTTP 403\n" } : trajectoryRun("?fw=a:b")(run, dir); };
  assert.equal(gatherFacts(["1", "2"], cacheFile, { download }).fetched, 2);
  assert.equal(gatherFacts(["1", "2"], cacheFile, { download }).fetched, 0);
  assert.deepEqual(calls, ["1", "2"]);
  assert.throws(() => gatherFacts(["1", "9"], cacheFile, { download }), /403/);
  assert.deepEqual(calls, ["1", "2", "9"]);
  assert.deepEqual(Object.keys(loadCache(cacheFile)), ["1", "2"]);
  assert.equal(gatherFacts(["1"], cacheFile, { download, refresh: ["1"] }).fetched, 1);
}));

test("cli: the incident citation is a mismatch with the flag the run carried (exit 1); a carried flag matches (exit 0)", () => scratch((d) => {
  const core = coreCall(bin);
  const note = join(d, "note.md");
  writeFileSync(note, "evidence: 39457767229 morph.tween:waapi\n");
  const lines = [];
  const opts = { core, cacheFile: join(d, "runs.json"), download: trajectoryRun("?fw=morph.tween:waapi-scoped"), log: (l) => lines.push(l) };
  assert.equal(cli(["--note", note], opts), 1);
  assert.match(lines[0], /^mismatch 39457767229 morph\.tween:waapi .*carried: morph\.tween:waapi-scoped$/);
  writeFileSync(note, "evidence: 39457767229 morph.tween:waapi-scoped\n");
  assert.equal(cli(["--note", note, "--json"], { ...opts, download: () => assert.fail("cached run downloaded again") }), 0);
  assert.equal(JSON.parse(lines.at(-1))[0].verdict, "match");
  assert.equal(cli(["--bogus"], opts), 2);
}));

test("request: arms go as their searches, a missing run as its reason", () => {
  assert.deepEqual(request([{ run: "1", arms: [{ artifact: "a", file: "f", search: "?fw=a:b" }] }, { run: "2", missing: "m" }], [{ run: "1", flag: "a:b", source: "s" }]),
    { op: "gate.runCite", runs: [{ run: "1", arms: ["?fw=a:b"] }, { run: "2", missing: "m" }], cites: [{ run: "1", flag: "a:b" }] });
});
