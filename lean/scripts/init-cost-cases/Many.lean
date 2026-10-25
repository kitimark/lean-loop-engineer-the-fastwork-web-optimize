import Lean
open Lean Elab Command Meta

namespace Many

run_cmd liftTermElabM do
  let natTy := mkConst ``Nat
  for i in [0:8192] do
    let n := `Many ++ .mkSimple s!"c{i}"
    let v := mkApp3 (mkConst ``List.replicate [.zero]) natTy (mkNatLit 2) (mkNatLit i)
    addAndCompile (.defnDecl (mkDefinitionValEx n [] (mkApp (mkConst ``List [.zero]) natTy) v (.regular 0) .safe [n]))

end Many
