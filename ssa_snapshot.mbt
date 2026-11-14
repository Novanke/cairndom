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
  let program = plan.program
  let graph = program.graph
  {
    program: {
      graph: {
        nodes: graph.nodes.copy(),
        edges: graph.edges.copy(),
        entry: graph.entry,
        exits: graph.exits.copy(),
      },
      variables: program.variables.copy(),
      definitions: program.definitions.map(row => row.copy()),
      uses: program.uses.map(row => row.copy()),
    },
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
/// liveness or phi planning again. The existing 16 MiB report limit applies.
pub fn SsaSnapshot::json_text(self : Self) -> String raise GraphError {
  bounded_ssa_plan_json_text(self.stored)
}
