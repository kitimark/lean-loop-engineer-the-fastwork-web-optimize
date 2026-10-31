import Fw.Device.SimLayerSweep

def main (args : List String) : IO Unit :=
  if args.contains "--check" then Fw.Device.SimLayerSweep.checkRepo else Fw.Device.SimLayerSweep.writeRepo
