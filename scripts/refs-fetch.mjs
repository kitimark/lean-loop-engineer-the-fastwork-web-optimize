#!/usr/bin/env node
// refs-fetch: pinned sparse clones of upstream sources (PLAN section 7.1, CLAUDE.md "Upstream source, not WebFetch").
//
//   node scripts/refs-fetch.mjs                      every entry in refs/upstream/sources.lock.yaml
//   node scripts/refs-fetch.mjs <id|owner/name|name> one entry (or several, space separated)
//   node scripts/refs-fetch.mjs <entry> --paths a,b  also check out extra paths (kept on later runs)
//   node scripts/refs-fetch.mjs --list               print id, repo, sha, dir for every entry
//
// Each entry lands in .cache/upstream/<name>@<sha7>/ (name = repo name, or the entry id when two entries share a
// repo). Strategy: `git init` + `git fetch --depth 1 --filter=blob:none origin <sha>` (one commit, its trees, no
// blobs), `git sparse-checkout set --no-cone /<path>...`, `git checkout --detach <sha>` (blobs of the sparse set are
// fetched on demand). A plain clone is avoided on purpose: even blobless, it downloads every commit and tree of the
// whole history (gigabytes for Chromium and WebKit). Idempotent: an existing dir at the right sha only gains paths.
// Node 24, no dependencies; runs git without a shell; never writes outside .cache/upstream.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const LOCK = join(ROOT, "refs/upstream/sources.lock.yaml");
const CACHE = join(ROOT, ".cache/upstream");

/** Parse the YAML subset used by sources.lock.yaml:
 *  `sources:` then list items `- key: value`, nested `key: value`, flow lists `[a, b]`, block lists `- item`,
 *  `#` comments, single or double quoted scalars. Nothing else (no anchors, no multi-line scalars). */
export function parseLock(text) {
  const entries = [];
  let cur = null;
  let listKey = null;
  let listIndent = -1;
  const scalar = (v) => {
    v = v.trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) return v.slice(1, -1);
    return v;
  };
  const value = (v) => {
    v = v.trim();
    if (v.startsWith("[") && v.endsWith("]")) {
      const inner = v.slice(1, -1).trim();
      return inner === "" ? [] : inner.split(",").map(scalar);
    }
    return scalar(v);
  };
  const stripComment = (line) => {
    let q = null;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (q) { if (c === q) q = null; continue; }
      if (c === '"' || c === "'") q = c;
      else if (c === "#" && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
    }
    return line;
  };
  for (const [n, raw] of text.split("\n").entries()) {
    const line = stripComment(raw).replace(/\s+$/, "");
    if (line.trim() === "") continue;
    const indent = line.length - line.trimStart().length;
    const body = line.trim();
    if (indent === 0) {
      if (body !== "sources:") throw new Error(`lock l.${n + 1}: only a top-level "sources:" key is supported`);
      continue;
    }
    if (listKey && indent > listIndent && body.startsWith("- ")) {
      cur[listKey].push(scalar(body.slice(2)));
      continue;
    }
    listKey = null;
    let kv = body;
    if (body.startsWith("- ")) {
      cur = {};
      entries.push(cur);
      kv = body.slice(2);
    }
    if (!cur) throw new Error(`lock l.${n + 1}: key outside a list item`);
    const m = /^([A-Za-z_][\w-]*):(.*)$/.exec(kv);
    if (!m) throw new Error(`lock l.${n + 1}: expected "key: value"`);
    const [, k, v] = m;
    if (v.trim() === "") {
      cur[k] = [];
      listKey = k;
      listIndent = indent + (body.startsWith("- ") ? 2 : 0);
    } else cur[k] = value(v);
  }
  return entries;
}

function validate(e, i) {
  const where = `sources[${i}] (${e.id ?? e.repo})`;
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(e.repo ?? "")) throw new Error(`${where}: bad repo`);
  if (!/^[0-9a-f]{40}$/.test(e.sha ?? "")) throw new Error(`${where}: sha must be 40 lowercase hex`);
  if (!Array.isArray(e.paths) || e.paths.length === 0) throw new Error(`${where}: paths must be a non-empty list`);
  for (const p of e.paths) checkPath(p, where);
  if (e.id !== undefined && !/^[A-Za-z0-9_.-]+$/.test(e.id)) throw new Error(`${where}: bad id`);
}

function checkPath(p, where) {
  if (typeof p !== "string" || p === "" || p.startsWith("/") || p.split("/").includes("..") || /[\0\n*?[\]!]/.test(p))
    throw new Error(`${where}: bad sparse path ${JSON.stringify(p)}`);
}

function git(cwd, args, opts = {}) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: opts.quiet ? ["ignore", "pipe", "pipe"] : ["ignore", "pipe", "inherit"],
    env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
  }).trim();
}

function dirFor(e, all) {
  const name = e.repo.split("/")[1];
  const shared = all.filter((x) => x.repo === e.repo).length > 1;
  const dir = resolve(CACHE, `${shared && e.id ? e.id : name}@${e.sha.slice(0, 7)}`);
  if (!dir.startsWith(CACHE + sep)) throw new Error(`refusing to write outside ${CACHE}: ${dir}`);
  return dir;
}

function fetchOne(e, all, extra) {
  const dir = dirFor(e, all);
  const url = `https://github.com/${e.repo}.git`;
  if (!existsSync(join(dir, ".git"))) {
    mkdirSync(dir, { recursive: true });
    git(dir, ["init", "--quiet"]);
    git(dir, ["remote", "add", "origin", url]);
  } else {
    const have = git(dir, ["config", "--get", "remote.origin.url"], { quiet: true });
    if (have !== url) throw new Error(`${dir}: origin is ${have}, lock says ${url}`);
  }
  const hasCommit = (() => {
    try { git(dir, ["cat-file", "-e", `${e.sha}^{commit}`], { quiet: true }); return true; } catch { return false; }
  })();
  if (!hasCommit) git(dir, ["fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", e.sha]);
  // Union of what is already checked out, the lock paths and --paths, so added paths survive later runs.
  let current = [];
  try { current = git(dir, ["sparse-checkout", "list"], { quiet: true }).split("\n").filter(Boolean); } catch {}
  const want = [...new Set([...current, ...[...e.paths, ...extra].map((p) => `/${p.replace(/\/+$/, "")}`)])].sort();
  const same = want.length === current.length && [...current].sort().every((p, i) => p === want[i]);
  if (!same) git(dir, ["sparse-checkout", "set", "--no-cone", ...want]);
  let head = "";
  try { head = git(dir, ["rev-parse", "HEAD"], { quiet: true }); } catch {}
  if (head !== e.sha) git(dir, ["-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", e.sha]);
  return dir;
}

function main(argv) {
  const names = [];
  const extra = [];
  let list = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--paths") extra.push(...(argv[++i] ?? "").split(",").map((s) => s.trim()).filter(Boolean));
    else if (a.startsWith("--paths=")) extra.push(...a.slice(8).split(",").map((s) => s.trim()).filter(Boolean));
    else if (a === "--list") list = true;
    else if (a === "-h" || a === "--help") {
      console.log("usage: node scripts/refs-fetch.mjs [<id|owner/name|name>...] [--paths a,b] [--list]");
      return;
    } else names.push(a);
  }
  for (const p of extra) checkPath(p, "--paths");
  const all = parseLock(readFileSync(LOCK, "utf8"));
  all.forEach(validate);
  const pick = names.length === 0 ? all : names.flatMap((n) => {
    const hit = all.filter((e) => e.id === n || e.repo === n || e.repo.split("/")[1] === n);
    if (hit.length === 0) throw new Error(`no lock entry matches ${n}`);
    return hit;
  });
  if (extra.length && pick.length !== 1) throw new Error("--paths needs exactly one entry");
  if (list) {
    for (const e of pick) console.log([e.id ?? "-", e.repo, e.sha, dirFor(e, all)].join("\t"));
    return;
  }
  for (const e of pick) console.log(fetchOne(e, all, extra));
}

try {
  main(process.argv.slice(2));
} catch (err) {
  console.error(`refs-fetch: ${err.message}`);
  process.exit(1);
}
