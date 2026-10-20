import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** The refusal line when the running Node differs from the pinned one, else null. One line, names both versions and the fix. */
export function nodePinRefusal(running: string, pinned: string | null): string | null {
  if (pinned === null) return null; // no .node-version: nothing to enforce (scripts/ci-paths.mjs --check flags that)
  const want = pinned.trim();
  const have = running.replace(/^v/, "");
  if (have === want) return null;
  return `refusing to start: running Node ${have} but .node-version pins ${want}; run \`nvm install && nvm use\` (or start through \`pnpm\`, which uses the pinned Node) and retry`;
}

/** Read `.node-version` at the repo root (three levels above `apps/<app>/src`), null when absent. */
export function readNodePin(fromDir: string): string | null {
  const f = join(fromDir, "..", "..", "..", ".node-version");
  return existsSync(f) ? readFileSync(f, "utf8").trim() : null;
}

/** Exit 1 with the refusal on stderr when this process runs on another Node than `.node-version`. I/O glue; the decision is `nodePinRefusal`. */
export function enforceNodePin(): void {
  const msg = nodePinRefusal(process.version, readNodePin(dirname(fileURLToPath(import.meta.url))));
  if (msg) {
    console.error(msg);
    process.exit(1);
  }
}
