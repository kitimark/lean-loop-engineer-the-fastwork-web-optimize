namespace Adv

def table : List String := (List.range 20000).map fun i => s!"row {i}"

def lazyTable (_ : Unit := ()) : List String := (List.range 30000).map fun i => s!"cell {i}"

def literal : List Nat := [1, 2, 3]

def small : Nat := literal.length + 1

def viaTable : Nat := table.length + 1

def viaLazy : Nat := lazyTable.length + 1

def lazyUse (_ : Unit := ()) : Nat := lazyTable.length + 2

end Adv
