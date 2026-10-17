#!/usr/bin/env node
// Writes an untracked Serena project (<clone>/.serena/project.yml) into every upstream clone under
// .cache/upstream/<name>@<sha7>/, so agents can activate the clone by path. Re-run after refs-fetch.
// C/C++ clones also get a minimal compile_commands.json (no build system in a sparse clone).
// Usage: node scripts/serena-upstream.mjs [name ...]   (no args: all clones, lean4 and material-ui first)
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const store = join(root, ".cache", "upstream");
const languageOf = {
  lean4: "lean4",
  "material-ui": "typescript",
  emotion: "typescript",
  react: "typescript",
  chromium: "cpp",
  webkit: "cpp",
};
const order = ["lean4", "material-ui", "emotion", "react", "chromium", "webkit"];
const cppExt = /\.(cc|cpp|cxx|c)$/;
const skipDir = new Set([".git", "node_modules", ".serena"]);
const cppCap = 20000;

function* walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (skipDir.has(entry.name)) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else yield path;
  }
}

function compileCommands(dir) {
  const commands = [];
  for (const file of walk(dir)) {
    if (!cppExt.test(file)) continue;
    const std = file.endsWith(".c") ? [] : ["-std=c++20"];
    commands.push({ directory: dir, file, arguments: ["clang", ...std, `-I${dir}`, "-c", file] });
    if (commands.length >= cppCap) break;
  }
  writeFileSync(join(dir, "compile_commands.json"), JSON.stringify(commands));
  return commands.length;
}

function projectYaml(name, language) {
  return [
    `project_name: "upstream-${name}"`,
    `language_servers:`,
    `- ${language}`,
    `encoding: "utf-8"`,
    `ignore_all_files_in_gitignore: false`,
    `ignored_paths:`,
    `- "**/node_modules/**"`,
    `- "**/.git/**"`,
    `read_only: true`,
    ``,
  ].join("\n");
}

if (!existsSync(store)) {
  console.error(`no ${relative(root, store)}: run the upstream fetch first`);
  process.exit(1);
}
const wanted = process.argv.slice(2);
const clones = readdirSync(store)
  .filter((d) => d.includes("@") && statSync(join(store, d)).isDirectory())
  .map((d) => ({ dir: join(store, d), name: d.slice(0, d.indexOf("@")) }))
  .filter((c) => wanted.length === 0 || wanted.includes(c.name))
  .sort((a, b) => order.indexOf(a.name.toLowerCase()) - order.indexOf(b.name.toLowerCase()));

for (const { dir, name } of clones) {
  const language = languageOf[name.toLowerCase()];
  if (!language) {
    console.log(`skip ${name}: no language mapping`);
    continue;
  }
  mkdirSync(join(dir, ".serena"), { recursive: true });
  writeFileSync(join(dir, ".serena", "project.yml"), projectYaml(name, language));
  const extra = language === "cpp" ? `, ${compileCommands(dir)} compile commands` : "";
  console.log(`${relative(root, dir)}: ${language}${extra}`);
}
