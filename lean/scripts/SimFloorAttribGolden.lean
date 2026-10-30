import Fw.Device.SimFloorAttrib

def main (args : List String) : IO Unit :=
  if args.contains "--check" then Fw.Device.SimFloorAttrib.checkRepo else Fw.Device.SimFloorAttrib.writeRepo
