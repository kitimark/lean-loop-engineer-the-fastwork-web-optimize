# Serena (code navigation by symbol)

Serena 1.7.0 (`serena`, uv tool). Backend: LSP. Config `~/.serena/serena_config.yml` is untouched.
The MCP server starts with `--project-from-cwd`, so the project follows the agent's working directory.

## Projects
| Project | Path | Language server | Committed |
|---|---|---|---|
| main | repo root | typescript (apps/, packages/) | yes |
| fwcore-lean | `lean/` | lean4 (`lean --server`) | yes |
| upstream-<name> | `.cache/upstream/<name>@<sha7>/` | lean4 / typescript / cpp | no |

- Activate: `activate_project` with the path (or start the agent with that cwd).
- Lean needs its own project because `lake env` must run in the lake root: from the repo root the server
  gets no `LEAN_PATH` for `Fw.*` and returns no symbols. From `lean/` it works (MEASURED, `Fw/Console.lean`).
- Generate the upstream projects after each refs-fetch: `node scripts/serena-upstream.mjs [name ...]`.
  Mapping: lean4 -> lean4; material-ui, emotion, react -> typescript; chromium, webkit -> cpp.
  Chromium and WebKit also get a minimal `compile_commands.json` (`-std=c++20 -I<root>`, first 20000 files).

## Ignore rules
- The main project has `ignore_all_files_in_gitignore: true`, so `.cache/`, `snapshot/`, `.lake/`, `node_modules/`
  are already out of the index; `ignored_paths` repeats `.cache`, `snapshot`, `lean/.lake` explicitly.
- A clone is a separate project (own root), so the root `.gitignore` does not hide it from itself; its yaml sets
  `ignore_all_files_in_gitignore: false` and `read_only: true`.

## What works (MEASURED on stubs; real clones not yet tested)
| Language | Works | Limits |
|---|---|---|
| typescript | `get_symbols_overview`, `find_symbol`, `find_referencing_symbols` | needs `node_modules` for cross-package types; huge repos start slowly |
| lean4 | symbols, find_symbol, references, hover | imports resolve only via `lake env`; the lean4 compiler repo itself has no root lakefile, so `Init` comes from the toolchain, not the clone |
| cpp (clangd) | symbols and references in files named in `compile_commands.json` | the stub flags have no real include paths or generated headers, so cross-file results are partial; clangd indexes in the background |

For Chromium and WebKit, prefer `grep`/`rg` for broad search and use Serena only to read one file's symbols or
one class's references. `serena project health-check` needs a file over 1000 bytes.
