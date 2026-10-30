import Fw.Device.SimEndFloor

def main (args : List String) : IO Unit :=
  if args.contains "--check" then Fw.Device.SimEndFloor.checkRepo else Fw.Device.SimEndFloor.writeRepo
