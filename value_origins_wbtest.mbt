///|
// Independent forward state exploration: record a use before replacing the
// current source with this block's definition, then follow successor edges.
// The extra source index denotes the caller-supplied value at first entry.
fn value_origins_test_expected(program : FlowProgram) -> Array[UseOrigins] {
  let n = program.graph.nodes.length()
  let source_count = n + 1
  let rows : Array[Array[UseOrigins]] = Array::makei(n, _ => [])
  for variable in 0..<program.variables.length() {
    let seen = Array::makei(n, _ => Array::make(source_count, false))
    let found = Array::makei(n, _ => Array::make(source_count, false))
    let work = [(program.graph.entry, n)]
    seen[program.graph.entry][n] = true
    let mut cursor = 0
    while cursor < work.length() {
      let (node, source) = work[cursor]
      cursor += 1
      if program.uses[node].contains(variable) {
        found[node][source] = true
      }
      let next_source = if program.definitions[node].contains(variable) {
        node
      } else {
        source
      }
      for (from, to) in program.graph.edges {
        if from == node && !seen[to][next_source] {
          seen[to][next_source] = true
          work.push((to, next_source))
        }
      }
    }
    for node in 0..<n {
      if !found[node].any(present => present) {
        continue
      }
      let definitions = []
      for source in 0..<n {
        if found[node][source] {
          definitions.push(source)
        }
      }
      rows[node].push({
        node,
        variable,
        definitions,
        requires_entry_value: found[node][n],
      })
    }
  }
  let expected = []
  for row in rows {
    for origin in row {
      expected.push(origin)
    }
  }
  expected
}

///|
fn value_origins_test_equal(
  actual : Array[UseOrigins],
  expected : Array[UseOrigins],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for index, origin in actual {
    assert_eq(origin.node, expected[index].node)
    assert_eq(origin.variable, expected[index].variable)
    assert_eq(origin.definitions, expected[index].definitions)
    assert_eq(origin.requires_entry_value, expected[index].requires_entry_value)
  }
}

///|
test "value origins match forward source states on every three-node graph entry and definition subset" {
  let mut cases = 0
  for edge_mask in 0..<512 {
    let edges : Array[(Int32, Int32)] = []
    let mut bits = edge_mask
    for from in 0..<3 {
      for to in 0..<3 {
        if bits % 2 == 1 {
          edges.push((from, to))
        }
        bits /= 2
      }
    }
    for entry in 0..<3 {
      for definition_mask in 0..<8 {
        let program : FlowProgram = {
          graph: { nodes: ["a", "b", "c"], edges, entry, exits: [], },
          variables: ["x"],
          definitions: Array::makei(3, node => {
            if (definition_mask & (1 << node)) != 0 {
              [0]
            } else {
              []
            }
          }),
          // Uses do not affect transfer. Testing a use at every block checks
          // the answer for each possible use independently in one run.
          uses: [[0], [0], [0]],
        }
        let expected = value_origins_test_expected(program)
        value_origins_test_equal(trace_values(program).uses(), expected)
        let by_node : Array[UseOrigins?] = Array::make(3, None)
        for origin in expected {
          by_node[origin.node] = Some(origin)
        }
        for node in 0..<3 {
          assert_eq(trace_use(program, node, 0), by_node[node])
        }
        cases += 1
      }
    }
  }
  assert_eq(cases, 12288)
}

///|
test "value origins explain uncovered branches overwrites and prior loop iterations" {
  let branch : FlowProgram = {
    graph: {
      nodes: ["entry", "left", "right", "join", "tail"],
      edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
      entry: 0,
      exits: [4],
    },
    variables: ["x"],
    definitions: [[], [0], [], [0], []],
    uses: [[], [], [], [0], [0]],
  }
  value_origins_test_equal(trace_values(branch).uses(), [
    { node: 3, variable: 0, definitions: [1], requires_entry_value: true, },
    { node: 4, variable: 0, definitions: [3], requires_entry_value: false, },
  ])
  let initialized : FlowProgram = {
    ..branch,
    definitions: [[0], [0], [], [0], []],
  }
  value_origins_test_equal(trace_values(initialized).uses(), [
    { node: 3, variable: 0, definitions: [0, 1], requires_entry_value: false, },
    { node: 4, variable: 0, definitions: [3], requires_entry_value: false, },
  ])
  let self_loop : FlowProgram = {
    graph: { nodes: ["entry"], edges: [(0, 0)], entry: 0, exits: [], },
    variables: ["x"],
    definitions: [[0]],
    uses: [[0]],
  }
  value_origins_test_equal(trace_values(self_loop).uses(), [
    { node: 0, variable: 0, definitions: [0], requires_entry_value: true, },
  ])
  let back_to_entry : FlowProgram = {
    graph: {
      nodes: ["dead", "entry", "body", "latch", "exit"],
      edges: [(1, 2), (2, 3), (3, 1), (1, 4), (0, 2)],
      entry: 1,
      exits: [4],
    },
    variables: ["x"],
    definitions: [[0], [0], [], [0], []],
    uses: [[], [0], [0], [], []],
  }
  value_origins_test_equal(trace_values(back_to_entry).uses(), [
    { node: 1, variable: 0, definitions: [3], requires_entry_value: true, },
    { node: 2, variable: 0, definitions: [1], requires_entry_value: false, },
  ])
  let permanent : FlowProgram = {
    graph: {
      nodes: ["entry", "exit", "head", "latch", "dead"],
      edges: [(0, 1), (0, 2), (2, 3), (3, 2), (4, 2)],
      entry: 0,
      exits: [1],
    },
    variables: ["x"],
    definitions: [[], [], [], [0], [0]],
    uses: [[], [], [0], [], [0]],
  }
  value_origins_test_equal(trace_values(permanent).uses(), [
    { node: 2, variable: 0, definitions: [3], requires_entry_value: true, },
  ])
  for fixture in [branch, initialized, self_loop, back_to_entry, permanent] {
    value_origins_test_equal(
      trace_values(fixture).uses(),
      value_origins_test_expected(fixture),
    )
  }
}

///|
test "value origins own their input every inspection copy and the saved report" {
  let input : FlowProgram = {
    graph: {
      nodes: ["entry", "left", "right", "join", "later", "exit", "dead"],
      edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (4, 5), (6, 3)],
      entry: 0,
      exits: [5],
    },
    variables: ["x", "parameter"],
    definitions: [[], [0], [], [], [], [], [0]],
    uses: [[], [], [], [1, 0], [0], [], [1]],
  }
  let saved = trace_values(input)
  let expected = value_origins_test_expected(input)
  let report = saved.json_text()
  let first = saved.uses()
  let second = saved.uses()
  value_origins_test_equal(first, expected)
  assert_eq(first[0].variable, 0)
  assert_eq(first[1].variable, 1)
  let point = trace_use(input, 3, 0).unwrap()
  assert_eq(point, first[0])
  assert_eq(trace_use(input, 3, 1), Some(first[1]))
  point.definitions.clear()
  assert_eq(trace_use(input, 3, 0), Some(first[0]))
  first[0].definitions.clear()
  assert_eq(first[2].definitions, [1])
  first[0] = {
    ..first[0],
    node: -1,
    variable: 999,
    requires_entry_value: false,
  }
  first.clear()
  value_origins_test_equal(second, expected)
  let inspected = saved.program()
  let retained = saved.program()
  for program in [input, inspected] {
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
  assert_eq(retained.graph.nodes, [
    "entry", "left", "right", "join", "later", "exit", "dead",
  ])
  assert_eq(retained.definitions[1], [0])
  assert_eq(retained.uses[3], [1, 0])
  assert_eq(saved.program().variables, ["x", "parameter"])
  assert_eq(saved.program().graph.exits, [5])
  assert_eq(saved.program().graph.edges.length(), 7)
  assert_eq(saved.program().uses[3], [1, 0])
  value_origins_test_equal(saved.uses(), expected)
  assert_eq(saved.json_text(), report)
  assert_true(saved.is_reachable(0))
  assert_true(saved.is_reachable(5))
  assert_false(saved.is_reachable(6))
}

///|
test "value origins accept empty facts and reject malformed unreachable facts and invalid reachability indices" {
  let empty : FlowProgram = {
    graph: { nodes: ["dead", "entry"], edges: [], entry: 1, exits: [1], },
    variables: [],
    definitions: [[], []],
    uses: [[], []],
  }
  let result = trace_values(empty)
  assert_eq(result.uses().length(), 0)
  assert_false(result.is_reachable(0))
  assert_true(result.is_reachable(1))
  for node in [-1, 2] {
    assert_true(
      try {
        ignore(result.is_reachable(node))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  let program : FlowProgram = {
    ..empty,
    variables: ["x"],
    definitions: [[], []],
    uses: [[], [0]],
  }
  let uses_in_dead_block : FlowProgram = {
    ..program,
    variables: ["x", "unused"],
    uses: [[0], [0]],
  }
  assert_eq(trace_use(uses_in_dead_block, 0, 0), None)
  for (node, variable) in [(-1, 0), (2, 0), (1, -1), (1, 2), (1, 1), (0, 1)] {
    assert_true(
      try {
        ignore(trace_use(uses_in_dead_block, node, variable))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  for
    invalid in [
      { ..program, graph: { ..program.graph, entry: -1, }, },
      { ..program, graph: { ..program.graph, edges: [(0, 2)], }, },
      { ..program, variables: ["x", "x"], },
      { ..program, definitions: [], },
      { ..program, uses: [[1], [0]], },
      { ..program, definitions: [[0, 0], []], },
      { ..program, uses: [[-1], [0]], },
    ] {
    assert_true(
      try {
        ignore(trace_values(invalid))
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_true(
      try {
        ignore(trace_use(invalid, 1, 0))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "value origins accept exactly 65536 source relations and reject the next incoming token" {
  let edges : Array[(Int32, Int32)] = []
  for source in 256..<512 {
    edges.push((0, source))
    edges.push((source, 1))
  }
  for node in 1..<255 {
    edges.push((node, node + 1))
  }
  edges.push((255, 0))
  let program : FlowProgram = {
    graph: {
      nodes: Array::makei(512, node => "n" + node.to_string()),
      edges,
      entry: 0,
      exits: [],
    },
    variables: ["x", "incoming"],
    definitions: Array::makei(512, node => if node >= 256 { [0] } else { [] }),
    uses: Array::makei(512, node => {
      if node == 0 {
        [1]
      } else if node < 256 {
        [1, 0]
      } else {
        []
      }
    }),
  }
  let exact = trace_values(program)
  let origins = exact.uses()
  assert_eq(origins.length(), 511)
  let mut relations = 0
  for origin in origins {
    if origin.variable == 0 {
      assert_eq(origin.definitions, Array::makei(256, source => source + 256))
      assert_false(origin.requires_entry_value)
    } else {
      assert_eq(origin.definitions, [])
      assert_true(origin.requires_entry_value)
    }
    relations += origin.definitions.length()
    if origin.requires_entry_value {
      relations += 1
    }
  }
  assert_eq(relations, 65536)
  program.uses[256].push(1)
  let error = try {
    ignore(trace_values(program))
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(error, "value-origin relation limit of 65536 exceeded")
  assert_eq(
    trace_use(program, 255, 0),
    Some({
      node: 255,
      variable: 0,
      definitions: Array::makei(256, source => source + 256),
      requires_entry_value: false,
    }),
  )
  assert_eq(
    trace_use(program, 256, 1),
    Some({
      node: 256,
      variable: 1,
      definitions: [],
      requires_entry_value: true,
    }),
  )
  // A failed second computation cannot damage an already accepted snapshot.
  assert_eq(exact.uses().length(), 511)
}
