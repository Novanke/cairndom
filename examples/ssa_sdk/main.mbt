///|
fn main raise {
  let program : @dom.FlowProgram = {
    graph: {
      nodes: ["entry", "left", "right", "join", "exit"],
      entry: 0,
      exits: [4],
      edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
    },
    variables: ["value", "unused", "parameter"],
    definitions: [[], [0, 1], [0, 1], [], []],
    uses: [[], [], [], [0, 2], []],
  }
  let plan = @dom.plan_ssa(program)
  assert_eq(plan.placements[0].phi_nodes, [3])
  assert_eq(plan.placements[1].phi_nodes, [])
  assert_true(plan.placements[2].requires_entry_value)
  assert_eq(
    @dom.parse_program(@dom.program_json_text(program)).variables,
    program.variables,
  )
  assert_eq(
    @dom.parse_graph(@dom.graph_json_text(program.graph)).edges,
    program.graph.edges,
  )
  let witnesses = @dom.control_dependence_witnesses(program.graph)
  assert_true(
    witnesses.contains({ controller: 0, successor: 1, dependent: 1, }),
  )
  println(@dom.ssa_plan_json_text(program))
}
