import Fw.Device.SimEndFloor

/-- `lake env lean --run scripts/SimEndFloorGolden.lean` writes the sim-end-floor golden; with `--check` it compares. -/
def main (args : List String) : IO Unit :=
  if args.contains "--check" then Fw.Device.SimEndFloor.checkRepo else Fw.Device.SimEndFloor.writeRepo
