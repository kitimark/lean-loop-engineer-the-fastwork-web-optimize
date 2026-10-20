# Serena (code navigation by symbol, on demand)

Policy (user decision 2026-10-20):
- **Serena is off by default.** It stays configured in `.mcp.json` (`serena-agent==2.0.0`, `--project .`), but the
  user keeps it disabled in local settings. Turn it on for a session with `/mcp` when symbol navigation in
  TypeScript or an upstream clone is worth the start-up cost. Agents must not assume Serena tools exist; `grep`/`rg`
  and Read are the default.
- **serena-lean is gone.** Lean lookups use the `lean-lsp` MCP server (`lean-lsp-mcp`), which follows the caller's
  worktree. Tools: `lean_local_search`, `lean_hover_info`, `lean_goal`, `lean_term_goal`,
  `lean_diagnostic_messages`, `lean_declaration_file`, `lean_references`, `lean_file_outline`.

## Projects (when Serena is on)
| Project | Path | Language server | Committed |
|---|---|---|---|
| main | repo root | typescript (apps/, packages/) | yes |
| upstream-<name> | `.cache/upstream/<name>@<sha7>/` | lean4 / typescript / cpp | no |

- Activate: `activate_project` with the path.
- Generate the upstream projects after each refs-fetch: `node scripts/serena-upstream.mjs [name ...]`.
  Mapping: lean4 -> lean4; material-ui, emotion, react -> typescript; chromium, webkit -> cpp.
  Chromium and WebKit also get a minimal `compile_commands.json` (`-std=c++20 -I<root>`, first 20000 files).
- Our own Lean code (`lean/`) goes through lean-lsp, not Serena.

## Ignore rules
- The main project has `ignore_all_files_in_gitignore: true`, so `.cache/`, `snapshot/`, `.lake/`, `node_modules/`
  are already out of the index; `ignored_paths` repeats `.cache`, `snapshot`, `lean/.lake` explicitly.
- A clone is a separate project (own root), so the root `.gitignore` does not hide it from itself; its yaml sets
  `ignore_all_files_in_gitignore: false` and `read_only: true`.

## What works (MEASURED on stubs; real clones not yet tested)
| Language | Works | Limits |
|---|---|---|
| typescript | `get_symbols_overview`, `find_symbol`, `find_referencing_symbols` | needs `node_modules` for cross-package types; huge repos start slowly |
| lean4 (upstream clones) | symbols, find_symbol, references, hover | imports resolve only via `lake env`; the lean4 compiler repo has no root lakefile, so `Init` comes from the toolchain, not the clone |
| cpp (clangd) | symbols and references in files named in `compile_commands.json` | the stub flags have no real include paths or generated headers, so cross-file results are partial; clangd indexes in the background |

For Chromium and WebKit, prefer `grep`/`rg` for broad search and use Serena only to read one file's symbols or
one class's references. `serena project health-check` needs a file over 1000 bytes.
