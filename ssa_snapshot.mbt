///|
/// An owned SSA planning result. Only defensive copies are exposed; JSON export
/// always describes the original computation, not edits to an inspection copy.
struct SsaSnapshot {
  stored : SsaPlan
}

///|
/// Validate and compute once, then retain the complete plan privately. Changes
/// to the input program after construction do not affect this snapshot.
pub fn prepare_ssa(program : FlowProgram) -> SsaSnapshot raise GraphError {
  { stored: plan_ssa(program), }
}

///|
/// Return an independently mutable inspection copy. Every nested array is
/// copied, including the graph, facts, liveness and per-variable placements.
/// Editing this value neither changes later reads nor the exported report.
pub fn SsaSnapshot::plan(self : Self) -> SsaPlan {
  let plan = self.stored
  {
    program: copy_program(plan.program),
    liveness: {
      reachable: plan.liveness.reachable.copy(),
      live_in: plan.liveness.live_in.map(row => row.copy()),
      live_out: plan.liveness.live_out.map(row => row.copy()),
    },
    placements: plan.placements.map(placement => {
      variable: placement.variable,
      definitions: placement.definitions.copy(),
      live_in: placement.live_in.copy(),
      phi_nodes: placement.phi_nodes.copy(),
      requires_entry_value: placement.requires_entry_value,
    }),
  }
}

///|
/// Export this exact saved computation as cairndom.ssa-plan.v1 without running
/// liveness or phi planning again. Serialization stops at the first fragment
/// that would exceed 16 MiB. The budget excludes a caller's final newline.
pub fn SsaSnapshot::json_text(self : Self) -> String raise GraphError {
  bounded_ssa_plan_json_text(self.stored)
}
