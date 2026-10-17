#!/usr/bin/env node
// A fake `gh` for the glue tests. It never touches the network. It models GitHub as the Lean replay does
// (lean/FwTest/CiBudget.lean): one bucket of 5000 requests per hour counted from `start`, one `HTTP/2.0 200` header
// block per request with x-ratelimit-remaining/-reset, or a 403 with remaining 0 when the bucket is empty; `overrides`
// replace the first answer at or after `at`, `drains` set the bucket's remaining. It prints a GH_DEBUG=api style trace
// (request lines, other headers and a body naming an account, which the glue must drop) on stderr, a JSON run list on
// stdout, and appends one line per invocation to calls.jsonl. Config and clock live in $FAKE_GH_DIR.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.env.FAKE_GH_DIR;
const rd = (f) => (existsSync(join(dir, f)) ? JSON.parse(readFileSync(join(dir, f), "utf8")) : null);
const cfg = rd("config.json") ?? {};
const clockFile = join(dir, "clock");
const t = existsSync(clockFile) ? Number(readFileSync(clockFile, "utf8")) : Math.floor(Date.now() / 1000);
const args = process.argv.slice(2);
const isList = args[0] === "run" && args[1] === "list";
const isView = args[0] === "run" && args[1] === "view";
const cost = process.env.FAKE_GH_COST ? Number(process.env.FAKE_GH_COST) : isList ? (cfg.listCost ?? 2) : isView ? 2 : 1;

const start = cfg.start ?? 0;
const srv = rd("server.json") ?? { hour: 0, used: 0, ov: 0, dr: 0 };
for (const [i, d] of (cfg.drains ?? []).entries()) {
  if (i >= srv.dr && d.at <= t) { srv.used = 5000 - d.remaining; srv.dr = i + 1; }
}
const hour = Math.floor((t - start) / 3600);
if (hour !== srv.hour) { srv.hour = hour; srv.used = 0; }
const reset = start + 3600 * (srv.hour + 1);

let lines;
let refused = false;
let empty = false;
const ov = (cfg.overrides ?? [])[srv.ov];
if (ov && ov.at <= t) {
  lines = ov.lines;
  srv.ov += 1;
  refused = /^HTTP\S* 4(03|29)/.test(ov.lines[0] ?? "");
} else if (5000 < srv.used + cost) {
  lines = ["HTTP/2.0 403 Forbidden", "X-Ratelimit-Remaining: 0", `X-Ratelimit-Reset: ${reset}`];
  refused = true;
  empty = true;
} else {
  lines = [];
  for (let i = 0; i < cost; i++) lines.push("HTTP/2.0 200 OK", `X-Ratelimit-Remaining: ${5000 - (srv.used + i + 1)}`, `X-Ratelimit-Reset: ${reset}`);
  srv.used += cost;
}
writeFileSync(join(dir, "server.json"), JSON.stringify(srv));
appendFileSync(join(dir, "calls.jsonl"), JSON.stringify({ t, args, cost, refused, empty }) + "\n");

// the GH_DEBUG=api style trace
let err = "";
let block = [];
for (const l of lines) {
  if (l.startsWith("HTTP/")) {
    if (block.length) err += block.join("\n") + "\n" + '{"actor":{"login":"someone-private"},"note":"a body the glue must drop"}\n';
    block = ["* Request at 2026-01-01T00:00:00Z", "> GET /repos/someone-private/repo/actions/runs HTTP/1.1", "> Authorization: token ████████", `< ${l}`, "< Content-Type: application/json", "< X-Github-Request-Id: ABCD:1234"];
  } else block.push(`< ${l}`);
}
if (block.length) err += block.join("\n") + "\n" + '{"actor":{"login":"someone-private"}}\n';
if (refused) err += "HTTP 403: API rate limit exceeded (https://api.github.com/repos/someone-private/repo/actions/runs)\n";
process.stderr.write(err);
if (refused) process.exit(1);

const iso = (s) => new Date(s * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
const row = (r) => {
  const done = t >= r.completeAt;
  return { databaseId: r.databaseId, status: done ? "completed" : "in_progress", conclusion: done ? r.conclusion : null,
    headBranch: r.headBranch ?? "ci/x", workflowName: r.workflowName ?? "chromium-counts", headSha: r.headSha ?? "abc", createdAt: iso(r.createdAt) };
};
const runs = cfg.runs ?? [];
if (isList) {
  const ci = args.indexOf("--created");
  const since = ci >= 0 ? Date.parse(args[ci + 1].replace(/^>=/, "")) / 1000 : 0;
  const li = args.indexOf("--limit");
  const limit = li >= 0 ? Number(args[li + 1]) : 20;
  console.log(JSON.stringify(runs.filter((r) => r.createdAt >= since).sort((a, b) => b.databaseId - a.databaseId).slice(0, limit).map(row)));
} else if (isView) {
  const r = runs.find((x) => String(x.databaseId) === args[2]);
  if (!r) { process.stderr.write("HTTP 404: Not Found (https://api.github.com/x)\n"); process.exit(1); }
  console.log(JSON.stringify(row(r)));
} else console.log("[]");
