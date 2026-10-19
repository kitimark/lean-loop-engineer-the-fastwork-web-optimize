import Fw.Site.Head

/-- `lake env lean --run HeadgenMain.lean [--check <file>]`: print `head.gen.json`, or check a file against it. -/
def main (args : List String) : IO UInt32 := Fw.Site.Head.run args
