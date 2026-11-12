///|
/// Locations for one variable, not renamed instructions or executable SSA.
/// requires_entry_value means the variable is live before the first block's
/// local definitions: the caller must supply a parameter/initial value or report
/// a missing initialization according to the source language's own rules.
pub(all) struct PhiPlacement {
  variable : Int32
  definitions : Array[Int32]
  live_in : Array[Int32]
  phi_nodes : Array[Int32]
  requires_entry_value : Bool
}

///|
/// A self-contained input snapshot plus backward liveness and pruned IDF sites.
pub(all) struct SsaPlan {
  program : FlowProgram
  liveness : Liveness
  placements : Array[PhiPlacement]
}

///|
/// Plan live-in-pruned phi sites on entry-reachable blocks. Unreachable facts
/// are validated but do not affect the plan. Blocks' uses precede local defs.
/// This does not infer statement ordering, rename variables or rewrite an IR.
pub fn plan_ssa(input : FlowProgram) -> SsaPlan raise GraphError {
  validate_program(input)
  let program : FlowProgram = {
    graph: snapshot_graph(input.graph),
    variables: input.variables.copy(),
    definitions: input.definitions.map(row => row.copy()),
    uses: input.uses.map(row => row.copy()),
  }
  let live = liveness(program)
  let tree = dominators(program.graph)
  let placements : Array[PhiPlacement] = []
  for variable in 0..<program.variables.length() {
    let definitions = []
    let live_in = []
    for node in 0..<program.graph.nodes.length() {
      if live.reachable[node] && program.definitions[node].contains(variable) {
        definitions.push(node)
      }
      if live.live_in[node].contains(variable) {
        live_in.push(node)
      }
    }
    placements.push({
      variable,
      definitions,
      live_in,
      phi_nodes: iterated_frontier_validated(
        tree,
        definitions,
        live_in=Some(live_in),
      ),
      requires_entry_value: live.live_in[program.graph.entry].contains(variable),
    })
  }
  { program, liveness: live, placements, }
}
