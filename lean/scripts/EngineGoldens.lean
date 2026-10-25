import Fw.Engine.Chromium
import Fw.Engine.TransitionStart
import Fw.Engine.WebKit
import Fw.Parts.HeroCountdownOpt
import Fw.Parts.HeroAccentOpt
import Fw.Parts.HeroExitOpt
import Fw.Parts.HiddenPause
import Fw.Parts.MorphMountOpt
import Fw.Parts.MorphPanelOpt
import Fw.Parts.NavHitTestOpt
import Fw.Parts.PainNotesOpt
import Fw.Parts.PeopleCardOpt
import Fw.Parts.PeopleDeckOpt
import Fw.Engine.ResourceFlags

/-- The Lean generator of each file in `packages/contracts/golden/engine/`, by file name.
One row per committed engine golden; a file without a row, or a row without a file, fails the check. -/
def generators : List (String × String) :=
  [("chromium.jsonl", Fw.Engine.Chromium.goldenText),
   ("countdown-strip.jsonl", Fw.Parts.HeroCountdownOpt.goldenJsonl),
   ("hero-accent.jsonl", Fw.Parts.HeroAccentOpt.goldenJsonl),
   ("hero-exit.jsonl", Fw.Parts.HeroExitOpt.goldenJsonl),
   ("hidden-pause.jsonl", Fw.Parts.HiddenPause.goldenJsonl),
   ("morph-mount.jsonl", Fw.Parts.MorphMountOpt.goldenText),
   ("morph-panel.jsonl", Fw.Parts.MorphPanelOpt.goldenText),
   ("nav-hittest.jsonl", Fw.Parts.NavHitTestOpt.goldenJsonl),
   ("pain-notes.jsonl", Fw.Parts.PainNotesOpt.goldenText),
   ("people-card.jsonl", Fw.Parts.PeopleCardOpt.goldenText),
   ("people-deck.jsonl", Fw.Parts.PeopleDeckOpt.goldenText),
   ("resource.jsonl", Fw.Engine.Resource.Flags.goldenText),
   ("transition-start.jsonl", Fw.Engine.TransitionStart.goldenJsonl ()),
   ("webkit.jsonl", Fw.Engine.WebKit.goldenJsonl)]

/-- Check (or with `--write`, rewrite) `packages/contracts/golden/engine/*.jsonl` against the Lean generators. Run from
`lean/`: `lake env lean --run scripts/EngineGoldens.lean [--write]`. Exit 1 when a file differs from its generator, a
`.jsonl` file has no generator, or a generator's file is missing. -/
def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "engine"
  let write := args.contains "--write"
  let mut bad := 0
  let names := (← dir.readDir).toList.map (·.fileName) |>.filter (·.endsWith ".jsonl")
  for n in names do
    unless generators.any (·.1 == n) do
      IO.println s!"engine-goldens: {n} has no Lean generator in scripts/EngineGoldens.lean"
      bad := bad + 1
  for (n, text) in generators do
    let p := dir / n
    if write then
      IO.FS.writeFile p text
      IO.println s!"engine-goldens: wrote {n}"
    else if !(← p.pathExists) then
      IO.println s!"engine-goldens: {n} is missing (run with --write)"
      bad := bad + 1
    else if (← IO.FS.readFile p) != text then
      IO.println s!"engine-goldens: {n} differs from its Lean generator (run with --write)"
      bad := bad + 1
  if bad == 0 then
    IO.println s!"engine-goldens: {generators.length} files in golden/engine equal the Lean generators"
  return if bad == 0 then 0 else 1
