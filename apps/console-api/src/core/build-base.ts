// Which commit was the fwcore binary built from? TS STAND-IN for Fw.Obs.chooseBase (lean/Fw/Obs/Stale.lean: chooseBase,
// theorems chooseBase_accepted, chooseBase_at_iff, chooseBase_mismatch, chooseBase_none, chooseBase_unknown_alerts),
// to be replaced by an fwcore op; test/build-base.test.ts holds the same table as the `#guard`s in that file.
//
// The only source is the build record `<binary>.commit` written by scripts/fwcore-build.sh after a successful build whose
// files equal the index: "tree <tree id of the index read before the build> <sha256 of the built binary>" (an older
// script wrote "<sha of HEAD> <sha256>"; still read). It is accepted only when the sha256 of the binary on disk equals
// the recorded one; a tree record resolves to the newest commit of `main` with that tree (Fw.Obs.chooseBaseTree: the
// commit that lands a merged tree has the tree that was built). No record, another binary's record, a dirty build, a
// tree no commit of `main` has: the commit is unknown, which is an alert (svc.unknown), never silence and never a
// guess from file times or the reflog.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type Base = { sha: string } | { unknown: string };
/** The build record: the commit (older script) or the tree (`tree <id>`) and the sha256 (hex) of the binary it produced. */
export type BuildRecord = { sha: string; hash: string } | { tree: string; hash: string };
/** Commits of `main`, newest first, each with its tree id (Lean `Fw.Obs.CommitLog`). */
export type CommitLog = [commit: string, tree: string][];

export const SHA = /^[0-9a-f]{40}$/;
const HASH = /^[0-9a-f]{64}$/;
export const CORE_BIN_REL = "lean/.lake/build/bin/fwcore";
export const CORE_COMMIT_REL = `${CORE_BIN_REL}.commit`;
export const BUILD_HINT = "sh scripts/fwcore-build.sh";

/** Same reasons as Fw.Obs.chooseBase. */
export const WHY_MISMATCH = `the build record does not match the binary (rebuilt without scripts/fwcore-build.sh)`;
export const WHY_NO_RECORD = `no build record: build with scripts/fwcore-build.sh`;

export const WHY_NOT_LANDED = "the built tree is on no commit of main (a land in progress, or the build was never landed)";

export function chooseBase(binHash: string, rec: BuildRecord | null, log: CommitLog = []): Base {
  if (rec === null) return { unknown: WHY_NO_RECORD };
  if (rec.hash !== binHash) return { unknown: WHY_MISMATCH };
  if ("sha" in rec) return { sha: rec.sha };
  return chooseBaseTree(binHash, rec.tree, rec.hash, log);
}

/** `Fw.Obs.chooseBaseTree`: the newest commit with the recorded tree, for the binary's own record. */
export function chooseBaseTree(binHash: string, tree: string, hash: string, log: CommitLog): Base {
  if (hash !== binHash) return { unknown: WHY_MISMATCH };
  const c = log.find(([, t]) => t === tree);
  return c ? { sha: c[0] } : { unknown: WHY_NOT_LANDED };
}

/** `"tree <id> <sha256>\n"` or the older `"<sha> <sha256>\n"` -> record; null when malformed. */
export function parseRecord(text: string): BuildRecord | null {
  const t = /^tree ([0-9a-f]{40}) ([0-9a-f]{64})\s*$/.exec(text);
  if (t) return { tree: t[1]!, hash: t[2]! };
  const m = /^([0-9a-f]{40}) ([0-9a-f]{64})\s*$/.exec(text);
  return m && SHA.test(m[1]!) && HASH.test(m[2]!) ? { sha: m[1]!, hash: m[2]! } : null;
}

/** The commits of `main` (newest first, first-parent, at most 1000) with their trees, read from the checkout `codeRoot`;
 *  empty when git fails (the tree then resolves to unknown, never to a guess). */
export function mainLog(codeRoot: string): CommitLog {
  try {
    const out = execFileSync("git", ["log", "--first-parent", "-n", "1000", "--format=%H %T", "main"], { cwd: codeRoot, encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
    return out.split("\n").flatMap((l) => { const m = /^([0-9a-f]{40}) ([0-9a-f]{40})$/.exec(l); return m ? [[m[1]!, m[2]!] as [string, string]] : []; });
  } catch { return []; }
}

/** The record next to the binary, or null when absent or malformed. */
export function readRecord(binPath: string): BuildRecord | null {
  try { return parseRecord(readFileSync(`${binPath}.commit`, "utf8")); } catch { return null; }
}

export const sha256File = (path: string): string => createHash("sha256").update(readFileSync(path)).digest("hex");

export const binIn = (root: string) => join(root, CORE_BIN_REL);

/** The build commit of the binary at `binPath` for the checkout `codeRoot` that runs it. A binary that is not
 *  `<codeRoot>/lean/.lake/build/bin/fwcore` (FW_CORE_BIN, another checkout) with no matching record is unknown, with the
 *  fact said in the reason: another checkout's data is never used. File reads, and one `git log` for a tree record. */
export function buildBase(codeRoot: string, binPath: string, log: (codeRoot: string) => CommitLog = mainLog): Base {
  if (!existsSync(binPath)) return { unknown: `no fwcore binary (${BUILD_HINT})` };
  let h: string;
  try { h = sha256File(binPath); } catch (e) { return { unknown: `cannot read the fwcore binary: ${(e as Error).message.split("\n")[0]}` }; }
  const rec = readRecord(binPath);
  const b = chooseBase(h, rec, rec !== null && "tree" in rec ? log(codeRoot) : []);
  if ("sha" in b || binPath === binIn(codeRoot)) return b;
  return { unknown: `${b.unknown}; the binary is not ${CORE_BIN_REL} of the checkout this code runs from` };
}
