// The API key, read from the macOS keychain at call time and nowhere else. Never cached, logged, written to a file,
// put in the environment, or included in an error: callers pass errors through `scrub` (./scrub.ts).
import { spawnSync } from "node:child_process";

/** The keychain service name the user stores the key under (see docs/team/tools/oracle.md). */
export const KEY_SERVICE = "typesafe-api";

/** Reads a secret; `null` when absent. Tests pass a fake. */
export type KeyReader = () => string | null;

/** `security find-generic-password -s typesafe-api -w`: stdout is the key, stderr is discarded (it can name the
 *  keychain item). A non-zero exit, a missing `security` binary or an empty output is `null` (failure `noKey`). */
export const keychainKey: KeyReader = () => {
  const r = spawnSync("security", ["find-generic-password", "-s", KEY_SERVICE, "-w"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 10_000,
  });
  if (r.status !== 0 || typeof r.stdout !== "string") return null;
  const k = r.stdout.trim();
  return k.length > 0 ? k : null;
};
