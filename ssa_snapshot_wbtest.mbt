///|
fn ssa_snapshot_test_program() -> FlowProgram {
  {
    graph: {
      nodes: ["dead", "entry", "left", "right", "join", "exit"],
      entry: 1,
      exits: [5],
      edges: [(1, 2), (1, 3), (2, 4), (3, 4), (4, 5), (0, 4)],
    },
    variables: ["x", "parameter", "unused"],
    definitions: [[2], [], [0, 2], [0, 2], [], []],
    uses: [[0], [], [], [], [1, 0], []],
  }
}

///|
test "SSA snapshot preserves one report after input and every exported array are corrupted" {
  let input = ssa_snapshot_test_program()
  let snapshot = prepare_ssa(input)
  let before = snapshot.json_text()
  assert_eq(before, ssa_plan_json_text(input))
  let exported = snapshot.plan()
  assert_eq(exported.placements[0].definitions, [2, 3])
  assert_eq(exported.placements[0].phi_nodes, [4])
  assert_false(exported.placements[0].requires_entry_value)
  assert_true(exported.placements[1].requires_entry_value)
  assert_eq(exported.placements[2].phi_nodes, [])
  let entry_values = match @json.parse(before) {
    Object(object) => required(object, "entry_values_required")
    _ => Json::null()
  }
  assert_eq(entry_values.stringify(), "[\"parameter\"]")
  for program in [input, exported.program] {
    program.graph.nodes.clear()
    program.graph.edges.clear()
    program.graph.exits.clear()
    program.variables.clear()
    for rows in [program.definitions, program.uses] {
      for row in rows {
        row.clear()
      }
      rows.clear()
    }
  }
  exported.liveness.reachable.clear()
  for rows in [exported.liveness.live_in, exported.liveness.live_out] {
    for row in rows {
      row.clear()
    }
    rows.clear()
  }
  for placement in exported.placements {
    placement.definitions.clear()
    placement.live_in.clear()
    placement.phi_nodes.clear()
  }
  exported.placements[0] = {
    ..exported.placements[0],
    variable: 999,
    requires_entry_value: true,
  }
  exported.placements.clear()
  assert_eq(snapshot.json_text(), before)
  let fresh = snapshot.plan()
  assert_eq(fresh.program.graph.nodes, [
    "dead", "entry", "left", "right", "join", "exit",
  ])
  assert_eq(fresh.program.graph.entry, 1)
  assert_eq(fresh.program.graph.exits, [5])
  assert_eq(fresh.program.graph.edges, [
    (1, 2),
    (1, 3),
    (2, 4),
    (3, 4),
    (4, 5),
    (0, 4),
  ])
  assert_eq(fresh.program.definitions, [[2], [], [0, 2], [0, 2], [], []])
  assert_eq(fresh.program.uses, [[0], [], [], [], [1, 0], []])
  assert_eq(fresh.placements[0].variable, 0)
  assert_false(fresh.placements[0].requires_entry_value)
  assert_eq(ssa_plan_json_value(fresh).stringify(indent=2), before)
}

///|
test "SSA snapshot plan reads and coincident fact sets never share mutable arrays" {
  let snapshot = prepare_ssa({
    graph: { nodes: ["entry"], entry: 0, exits: [], edges: [(0, 0)], },
    variables: ["x"],
    definitions: [[0]],
    uses: [[0]],
  })
  let before = snapshot.json_text()
  let first = snapshot.plan()
  let second = snapshot.plan()
  assert_eq(first.placements[0].phi_nodes, [0])
  first.program.graph.nodes[0] = "changed"
  first.program.definitions[0].clear()
  assert_eq(first.program.uses[0], [0])
  assert_eq(first.placements[0].definitions, [0])
  first.placements[0].definitions.clear()
  assert_eq(first.placements[0].live_in, [0])
  assert_eq(first.placements[0].phi_nodes, [0])
  first.liveness.live_in[0].clear()
  assert_eq(first.liveness.live_out[0], [0])
  assert_eq(first.placements[0].live_in, [0])
  assert_eq(first.program.uses[0], [0])
  first.placements[0].live_in.clear()
  first.placements[0].phi_nodes.clear()
  first.liveness.live_out[0].clear()
  first.liveness.reachable[0] = false
  first.program.uses[0].clear()
  assert_eq(second.program.graph.nodes, ["entry"])
  assert_eq(second.program.definitions, [[0]])
  assert_eq(second.program.uses, [[0]])
  assert_eq(second.liveness.reachable, [true])
  assert_eq(second.liveness.live_in, [[0]])
  assert_eq(second.liveness.live_out, [[0]])
  assert_eq(second.placements[0].definitions, [0])
  assert_eq(second.placements[0].live_in, [0])
  assert_eq(second.placements[0].phi_nodes, [0])
  assert_eq(snapshot.json_text(), before)
}

///|
test "SSA snapshots retain zero variables nonzero entries and live permanent loops" {
  let empty = prepare_ssa({
    graph: { nodes: ["dead", "start"], entry: 1, exits: [0], edges: [(1, 1)], },
    variables: [],
    definitions: [[], []],
    uses: [[], []],
  })
  let empty_plan = empty.plan()
  assert_eq(empty_plan.placements.length(), 0)
  assert_eq(empty_plan.liveness.reachable, [false, true])
  assert_eq(empty_plan.liveness.live_in, [[], []])
  assert_eq(empty.json_text(), ssa_plan_json_text(empty_plan.program))
  let snapshot = prepare_ssa({
    graph: {
      nodes: ["dead", "entry", "forever", "exit"],
      entry: 1,
      exits: [3],
      edges: [(0, 2), (1, 2), (1, 3), (2, 2)],
    },
    variables: ["incoming", "initialized", "dead_only"],
    definitions: [[2], [1], [0], []],
    uses: [[2], [], [0, 1], []],
  })
  let plan = snapshot.plan()
  assert_eq(plan.liveness.reachable, [false, true, true, true])
  assert_eq(plan.liveness.live_in, [[], [0], [0, 1], []])
  assert_eq(plan.liveness.live_out, [[], [0, 1], [0, 1], []])
  assert_eq(plan.placements[0].phi_nodes, [2])
  assert_true(plan.placements[0].requires_entry_value)
  assert_false(plan.placements[1].requires_entry_value)
  assert_eq(plan.placements[2].definitions, [])
  assert_eq(plan.placements[2].live_in, [])
  assert_eq(plan.placements[2].phi_nodes, [])
  assert_eq(snapshot.json_text(), ssa_plan_json_text(plan.program))
}

///|
test "SSA snapshot preparation rejects malformed graphs and facts including unreachable rows" {
  let program = ssa_snapshot_test_program()
  for
    invalid in [
      { ..program, graph: { ..program.graph, entry: -1, }, },
      { ..program, variables: ["x", "x"], },
      { ..program, definitions: [], },
      { ..program, uses: [[-1], [], [], [], [], []], },
      { ..program, definitions: [[0, 0], [], [], [], [], []], },
    ] {
    assert_true(
      try {
        ignore(prepare_ssa(invalid))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}
