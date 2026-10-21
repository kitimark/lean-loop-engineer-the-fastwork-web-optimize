import { spawnSync } from "node:child_process";

export const KEY_SERVICE = "typesafe-api";

export type KeyReader = () => string | null;

export const keychainKey: KeyReader = () => {
  const r = spawnSync("security", ["find-generic-password", "-s", KEY_SERVICE, "-w"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 10_000,
  });
  if (r.status !== 0 || typeof r.stdout !== "string") return null;
  const k = r.stdout.trim();
  return k.length > 0 ? k : null;
};
