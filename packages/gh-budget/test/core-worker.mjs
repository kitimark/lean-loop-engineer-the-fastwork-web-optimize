// Test helper thread: one long-lived fwcore process, answered through a SharedArrayBuffer so the main thread can
// call it synchronously (the production glue spawns fwcore once per decision; this only makes the replays fast).
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { parentPort, workerData } from "node:worker_threads";

const { bin, sab } = workerData;
const flag = new Int32Array(sab, 0, 2); // [0] 0 idle / 1 reply ready, [1] reply byte length
const data = new Uint8Array(sab, 8);
const child = spawn(bin, [], { env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, stdio: ["pipe", "pipe", "inherit"] });
const rl = createInterface({ input: child.stdout });
rl.on("line", (line) => {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length > data.length) { flag[1] = -1; } else { data.set(bytes); flag[1] = bytes.length; }
  Atomics.store(flag, 0, 1);
  Atomics.notify(flag, 0);
});
parentPort.on("message", (req) => child.stdin.write(req + "\n"));
