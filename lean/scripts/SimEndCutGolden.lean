import Fw.Device.SimEndCut

def main (args : List String) : IO Unit :=
  if args.contains "--check" then Fw.Device.SimEndCut.checkRepo else Fw.Device.SimEndCut.writeRepo
