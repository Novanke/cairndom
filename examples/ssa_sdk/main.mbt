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
  let saved = @dom.prepare_ssa(program)
  let plan = saved.plan()
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
  let report = saved.json_text()
  // A UI may edit its input and inspection copy after reviewing this plan.
  // Saving the snapshot still exports the exact result that was reviewed.
  program.uses[3].clear()
  plan.placements[0].phi_nodes.clear()
  assert_eq(@dom.plan_ssa(program).placements[0].phi_nodes, [])
  assert_eq(saved.plan().placements[0].phi_nodes, [3])
  assert_true(saved.plan().placements[2].requires_entry_value)
  assert_eq(saved.json_text(), report)
  println(report)
}
