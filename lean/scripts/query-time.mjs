// Time fwcore's replay and console.query on a log (local debug timing, not a CI result).
// usage: node lean/scripts/query-time.mjs <fwcore binary> <events.jsonl> [file for the query reply]
import { spawn } from "node:child_process";
import fs from "node:fs";

const [bin, file, outFile] = process.argv.slice(2);
const lines = fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim());
const evs = lines.map((l) => JSON.parse(l));
const seq = Math.max(...evs.map((e) => e.seq ?? 0));
const now = Math.max(...evs.map((e) => e.ts ?? 0)) + 1000;
const child = spawn(bin, ["serve"], { stdio: ["pipe", "pipe", "inherit"] });
let buf = "";
const waiters = [];
child.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const l = buf.slice(0, i);
    buf = buf.slice(i + 1);
    waiters.shift()?.(l);
  }
});
const ask = (s) =>
  new Promise((res) => {
    waiters.push(res);
    child.stdin.write(s + "\n");
  });
let t = performance.now();
let id = 1;
for (let i = 0; i < lines.length; i += 500) {
  const r = await ask(`{"id":${id++},"op":"console.replay","events":[${lines.slice(i, i + 500).join(",")}]}`);
  if (!r.includes('"replayed"')) throw new Error(r.slice(0, 200));
}
const replay = performance.now() - t;
t = performance.now();
const q = await ask(`{"id":${id++},"op":"console.query","now":${now},"seq":${seq}}`);
const query = performance.now() - t;
if (outFile) fs.writeFileSync(outFile, q + "\n");
console.log(JSON.stringify({ events: lines.length, replayMs: Math.round(replay), queryMs: Math.round(query), replyBytes: q.length }));
child.stdin.end();
