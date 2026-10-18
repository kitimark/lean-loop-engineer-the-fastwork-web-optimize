import Fw.Engine.Core
import Fw.Engine.Visual
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Engine.Lessons
/-!
# The engine model (PLAN §4.7): shared core and the visual observable

Umbrella module: `Fw.Engine.Core` (stages, frames, work, the engine interface, dominance theorems) and
`Fw.Engine.Visual` (scenes, the E and Q relations, path premises). The engine tables `Fw.Engine.Chromium` and
`Fw.Engine.WebKit` build on `Fw.Engine.Core`. `Fw.Engine.Lessons` proves the general lessons L1-L6 of the findings
ledger (why an optimization helps, trades, gives nothing or is worse) over any engine.
-/
