///|
fn ssa_json_test_report(
  program : FlowProgram,
) -> Map[String, Json] raise GraphError {
  let value = @json.parse(ssa_plan_json_text(program)) catch {
    _ => raise Invalid("SSA report was not valid JSON")
  }
  fields(value, [
    "schema", "entry", "scope", "use_convention", "status", "variables", "blocks",
    "placements", "entry_values_required", "entry_value_semantics",
  ])
}

///|
fn ssa_json_test_names(value : Json) -> Array[String] raise GraphError {
  let result = []
  for value in items(value, max_nodes) {
    result.push(text(value))
  }
  result
}

///|
fn ssa_json_test_block(value : Json) -> Map[String, Json] raise GraphError {
  fields(value, [
    "id", "reachable", "defines", "uses", "live_in", "live_out", "phi_variables",
  ])
}

///|
fn ssa_json_test_placement(value : Json) -> Map[String, Json] raise GraphError {
  fields(value, [
    "variable", "definition_blocks", "live_in_blocks", "phi_blocks", "requires_entry_value",
  ])
}

///|
test "SSA JSON names live diamond sites and excludes unreachable and dead facts from analysis" {
  let program : FlowProgram = {
    graph: {
      nodes: ["entry", "left", "right", "join", "exit", "dead"],
      entry: 0,
      exits: [4],
      edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (5, 3)],
    },
    variables: ["x", "unused", "parameter"],
    definitions: [[], [1, 0], [0, 1], [], [], [2]],
    uses: [[], [], [], [2, 0], [], [1]],
  }
  let report = ssa_json_test_report(program)
  assert_eq(text(required(report, "schema")), "cairndom.ssa-plan.v1")
  assert_eq(text(required(report, "entry")), "entry")
  assert_eq(text(required(report, "scope")), "entry_reachable_all_paths")
  assert_eq(text(required(report, "use_convention")), "before_local_definition")
  assert_eq(text(required(report, "status")), "locations_only")
  assert_eq(
    ssa_json_test_names(required(report, "variables")),
    program.variables,
  )
  assert_eq(ssa_json_test_names(required(report, "entry_values_required")), [
    "parameter",
  ])
  assert_true(text(required(report, "entry_value_semantics")).length() > 0)
  let blocks = items(required(report, "blocks"), max_nodes)
  assert_eq(blocks.length(), 6)
  for node, name in program.graph.nodes {
    assert_eq(text(required(ssa_json_test_block(blocks[node]), "id")), name)
  }
  let left = ssa_json_test_block(blocks[1])
  assert_eq(ssa_json_test_names(required(left, "defines")), ["x", "unused"])
  assert_eq(program.definitions[1], [1, 0])
  let join = ssa_json_test_block(blocks[3])
  assert_eq(required(join, "reachable").stringify(), "true")
  assert_eq(ssa_json_test_names(required(join, "uses")), ["x", "parameter"])
  assert_eq(ssa_json_test_names(required(join, "live_in")), ["x", "parameter"])
  assert_eq(ssa_json_test_names(required(join, "live_out")), [])
  assert_eq(ssa_json_test_names(required(join, "phi_variables")), ["x"])
  assert_eq(program.uses[3], [2, 0])
  let dead = ssa_json_test_block(blocks[5])
  assert_eq(required(dead, "reachable").stringify(), "false")
  assert_eq(ssa_json_test_names(required(dead, "defines")), ["parameter"])
  assert_eq(ssa_json_test_names(required(dead, "uses")), ["unused"])
  assert_eq(ssa_json_test_names(required(dead, "live_in")), [])
  assert_eq(ssa_json_test_names(required(dead, "live_out")), [])
  assert_eq(ssa_json_test_names(required(dead, "phi_variables")), [])
  let placements = items(required(report, "placements"), max_variables)
  assert_eq(placements.length(), 3)
  let x = ssa_json_test_placement(placements[0])
  assert_eq(text(required(x, "variable")), "x")
  assert_eq(ssa_json_test_names(required(x, "definition_blocks")), [
    "left", "right",
  ])
  assert_eq(ssa_json_test_names(required(x, "live_in_blocks")), ["join"])
  assert_eq(ssa_json_test_names(required(x, "phi_blocks")), ["join"])
  assert_eq(required(x, "requires_entry_value").stringify(), "false")
  let unused = ssa_json_test_placement(placements[1])
  assert_eq(text(required(unused, "variable")), "unused")
  assert_eq(ssa_json_test_names(required(unused, "definition_blocks")), [
    "left", "right",
  ])
  assert_eq(ssa_json_test_names(required(unused, "live_in_blocks")), [])
  assert_eq(ssa_json_test_names(required(unused, "phi_blocks")), [])
  let parameter = ssa_json_test_placement(placements[2])
  assert_eq(text(required(parameter, "variable")), "parameter")
  assert_eq(ssa_json_test_names(required(parameter, "definition_blocks")), [])
  assert_eq(ssa_json_test_names(required(parameter, "live_in_blocks")), [
    "entry", "left", "right", "join",
  ])
  assert_eq(required(parameter, "requires_entry_value").stringify(), "true")
  assert_eq(ssa_plan_json_text(program), ssa_plan_json_text(program))
}

///|
test "SSA JSON reports incoming values for loop uses before local definitions" {
  let report = ssa_json_test_report({
    graph: {
      nodes: ["entry", "head", "body"],
      entry: 0,
      exits: [],
      edges: [(0, 1), (1, 2), (2, 1)],
    },
    variables: ["counter"],
    definitions: [[], [], [0]],
    uses: [[], [0], [0]],
  })
  assert_eq(ssa_json_test_names(required(report, "entry_values_required")), [
    "counter",
  ])
  let placements = items(required(report, "placements"), max_variables)
  let counter = ssa_json_test_placement(placements[0])
  assert_eq(ssa_json_test_names(required(counter, "definition_blocks")), [
    "body",
  ])
  assert_eq(ssa_json_test_names(required(counter, "live_in_blocks")), [
    "entry", "head", "body",
  ])
  assert_eq(ssa_json_test_names(required(counter, "phi_blocks")), ["head"])
  assert_eq(required(counter, "requires_entry_value").stringify(), "true")
  let blocks = items(required(report, "blocks"), max_nodes)
  let head = ssa_json_test_block(blocks[1])
  assert_eq(ssa_json_test_names(required(head, "phi_variables")), ["counter"])
  let body = ssa_json_test_block(blocks[2])
  assert_eq(ssa_json_test_names(required(body, "defines")), ["counter"])
  assert_eq(ssa_json_test_names(required(body, "uses")), ["counter"])
  assert_eq(ssa_json_test_names(required(body, "live_in")), ["counter"])
}

///|
test "SSA JSON handles zero variables and rejects malformed mutated programs" {
  let program : FlowProgram = {
    graph: { nodes: ["only"], edges: [], entry: 0, exits: [0], },
    variables: [],
    definitions: [[]],
    uses: [[]],
  }
  let report = ssa_json_test_report(program)
  assert_eq(ssa_json_test_names(required(report, "variables")), [])
  assert_eq(ssa_json_test_names(required(report, "entry_values_required")), [])
  assert_eq(items(required(report, "placements"), max_variables).length(), 0)
  let blocks = items(required(report, "blocks"), max_nodes)
  assert_eq(blocks.length(), 1)
  let block = ssa_json_test_block(blocks[0])
  assert_eq(required(block, "reachable").stringify(), "true")
  assert_eq(ssa_json_test_names(required(block, "phi_variables")), [])
  for
    invalid in [
      { ..program, uses: [[0]], },
      { ..program, definitions: [], },
      { ..program, graph: { ..program.graph, entry: -1, }, },
    ] {
    let rejected = try {
      ignore(ssa_plan_json_text(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  let with_variable : FlowProgram = {
    ..program,
    variables: ["x"],
    definitions: [[]],
    uses: [[0]],
  }
  let before_mutation = ssa_json_test_report(with_variable)
  assert_eq(
    ssa_json_test_names(required(before_mutation, "entry_values_required")),
    ["x"],
  )
  with_variable.uses[0].push(0)
  let rejected = try {
    ignore(ssa_plan_json_text(with_variable))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "SSA JSON refuses reports exceeding sixteen MiB" {
  let prefix = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012345678"
  let program : FlowProgram = {
    graph: {
      nodes: Array::makei(256, node => prefix + node.to_string()),
      edges: Array::makei(256, node => (node, (node + 1) % 256)),
      entry: 0,
      exits: [],
    },
    variables: Array::makei(320, variable => prefix + variable.to_string()),
    definitions: Array::makei(256, _ => []),
    uses: Array::makei(256, node => {
      if node == 0 {
        Array::makei(320, variable => variable)
      } else {
        []
      }
    }),
  }
  let saved = prepare_ssa(program)
  assert_eq(saved.plan().placements.length(), 320)
  let error = try {
    ignore(saved.json_text())
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(error, "SSA plan JSON exceeds 16 MiB")
}
