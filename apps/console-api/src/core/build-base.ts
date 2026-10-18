// Which commit was the fwcore binary built from? TS STAND-IN for Fw.Obs.chooseBase (lean/Fw/Obs/Stale.lean: chooseBase,
// theorems chooseBase_accepted, chooseBase_at_iff, chooseBase_mismatch, chooseBase_none, chooseBase_unknown_alerts),
// to be replaced by an fwcore op; test/build-base.test.ts holds the same table as the `#guard`s in that file.
//
// The only source is the build record `<binary>.commit` written by scripts/fwcore-build.sh after a successful build on a
// clean tree: "<sha of HEAD read before the build> <sha256 of the built binary>". It is accepted only when the sha256
// of the binary on disk equals the recorded one. No record, another binary's record, a dirty or mid-merge build: the
// commit is unknown, which is an alert (svc.unknown), never silence and never a guess from file times or the reflog.
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type Base = { sha: string } | { unknown: string };
/** The build record: the commit and the sha256 (hex) of the binary it produced. */
export type BuildRecord = { sha: string; hash: string };

export const SHA = /^[0-9a-f]{40}$/;
const HASH = /^[0-9a-f]{64}$/;
export const CORE_BIN_REL = "lean/.lake/build/bin/fwcore";
export const CORE_COMMIT_REL = `${CORE_BIN_REL}.commit`;
export const BUILD_HINT = "sh scripts/fwcore-build.sh";

/** Same reasons as Fw.Obs.chooseBase. */
export const WHY_MISMATCH = `the build record does not match the binary (rebuilt without scripts/fwcore-build.sh)`;
export const WHY_NO_RECORD = `no build record: build with scripts/fwcore-build.sh`;

export function chooseBase(binHash: string, rec: BuildRecord | null): Base {
  if (rec === null) return { unknown: WHY_NO_RECORD };
  return rec.hash === binHash ? { sha: rec.sha } : { unknown: WHY_MISMATCH };
}

/** `"<sha> <sha256>\n"` -> record; null when malformed. */
export function parseRecord(text: string): BuildRecord | null {
  const m = /^([0-9a-f]{40}) ([0-9a-f]{64})\s*$/.exec(text);
  return m && SHA.test(m[1]!) && HASH.test(m[2]!) ? { sha: m[1]!, hash: m[2]! } : null;
}

/** The record next to the binary, or null when absent or malformed. */
export function readRecord(binPath: string): BuildRecord | null {
  try { return parseRecord(readFileSync(`${binPath}.commit`, "utf8")); } catch { return null; }
}

export const sha256File = (path: string): string => createHash("sha256").update(readFileSync(path)).digest("hex");

export const binIn = (root: string) => join(root, CORE_BIN_REL);

/** The build commit of the binary at `binPath` for the checkout `codeRoot` that runs it. A binary that is not
 *  `<codeRoot>/lean/.lake/build/bin/fwcore` (FW_CORE_BIN, another checkout) with no matching record is unknown, with the
 *  fact said in the reason: another checkout's data is never used. Pure file reads: no git. */
export function buildBase(codeRoot: string, binPath: string): Base {
  if (!existsSync(binPath)) return { unknown: `no fwcore binary (${BUILD_HINT})` };
  let h: string;
  try { h = sha256File(binPath); } catch (e) { return { unknown: `cannot read the fwcore binary: ${(e as Error).message.split("\n")[0]}` }; }
  const b = chooseBase(h, readRecord(binPath));
  if ("sha" in b || binPath === binIn(codeRoot)) return b;
  return { unknown: `${b.unknown}; the binary is not ${CORE_BIN_REL} of the checkout this code runs from` };
}
