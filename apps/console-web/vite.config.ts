import { readFileSync } from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// The dev server proxies /api to console-api. Its port is free-picked, so read it from
// <main checkout>/.fw-console/api.json (or FW_API).
function apiTarget(): string {
  if (process.env.FW_API) return process.env.FW_API;
  try {
    const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"]).toString().trim();
    const dir = process.env.FW_CONSOLE_DIR ?? path.join(path.dirname(common), ".fw-console");
    return `http://127.0.0.1:${JSON.parse(readFileSync(path.join(dir, "api.json"), "utf8")).port}`;
  } catch {
    return "http://127.0.0.1:8787";
  }
}

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  server: { proxy: { "/api": { target: apiTarget(), changeOrigin: true } } },
});
