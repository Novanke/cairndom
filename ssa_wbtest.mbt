///|
test "pruned phi planning keeps used branch variable and removes dead one" {
  let program : FlowProgram = {
    graph: {
      nodes: ["entry", "left", "right", "join", "exit", "dead"],
      entry: 0,
      exits: [4],
      edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (5, 3)],
    },
    variables: ["x", "unused", "parameter"],
    definitions: [[], [0, 1], [0, 1], [], [], [2]],
    uses: [[], [], [], [0, 2], [], []],
  }
  let plan = plan_ssa(program)
  assert_eq(plan.placements.length(), 3)
  assert_eq(plan.placements[0].definitions, [1, 2])
  assert_eq(plan.placements[0].phi_nodes, [3])
  assert_false(plan.placements[0].requires_entry_value)
  assert_eq(plan.placements[1].phi_nodes, [])
  assert_eq(plan.placements[2].definitions, [])
  assert_eq(plan.placements[2].phi_nodes, [])
  assert_true(plan.placements[2].requires_entry_value)
  assert_eq(plan.liveness.live_in[5], [])
  program.variables[0] = "changed"
  program.definitions[1].clear()
  program.graph.edges.clear()
  assert_eq(plan.program.variables[0], "x")
  assert_eq(plan.program.definitions[1], [0, 1])
  assert_eq(plan.program.graph.edges.length(), 6)
}

///|
test "loop-carried variable and use-before-def require incoming value" {
  let plan = plan_ssa({
    graph: {
      nodes: ["entry", "head", "body", "exit"],
      entry: 0,
      exits: [3],
      edges: [(0, 1), (1, 2), (2, 1), (1, 3)],
    },
    variables: ["counter"],
    definitions: [[], [], [0], []],
    uses: [[], [0], [0], []],
  })
  assert_eq(plan.placements[0].phi_nodes, [1])
  assert_true(plan.placements[0].requires_entry_value)
  let self_loop = plan_ssa({
    graph: { nodes: ["entry"], entry: 0, exits: [], edges: [(0, 0)], },
    variables: ["x"],
    definitions: [[0]],
    uses: [[0]],
  })
  assert_eq(self_loop.placements[0].phi_nodes, [0])
  assert_true(self_loop.placements[0].requires_entry_value)
}

///|
test "SSA planning accepts zero variables and rejects malformed facts" {
  let program : FlowProgram = {
    graph: { nodes: ["only"], edges: [], entry: 0, exits: [0], },
    variables: [],
    definitions: [[]],
    uses: [[]],
  }
  assert_eq(plan_ssa(program).placements.length(), 0)
  assert_true(
    try {
      ignore(plan_ssa({ ..program, uses: [[0]], }))
      false
    } catch {
      Invalid(_) => true
    },
  )
}
