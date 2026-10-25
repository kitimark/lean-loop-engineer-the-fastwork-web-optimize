import Fw.Lint.InitCostScan
import Main
/-! `lake env lean scripts/InitCostLint.lean` from `lean/`: the start-cost lint over `fwcore` (`Fw.Lint.InitCost`). -/

set_option maxHeartbeats 0 in
set_option maxRecDepth 100000 in
run_cmd Fw.Lint.InitCostScan.scan [`Main] [".lake/build/ir"]
