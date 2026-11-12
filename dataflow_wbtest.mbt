///|
fn flow_test_graph(
  n : Int32,
  edges : Array[(Int32, Int32)],
  entry : Int32,
) -> Graph {
  { nodes: Array::makei(n, i => "n" + i.to_string()), edges, entry, exits: [], }
}

///|
test "liveness tracks sorted variable sets through a diamond and kills definitions" {
  let result = liveness({
    graph: flow_test_graph(5, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)], 0),
    variables: ["x", "y", "unused"],
    definitions: [[1], [0], [0], [], []],
    uses: [[], [], [], [1, 0], []],
  })
  assert_eq(result.reachable, [true, true, true, true, true])
  assert_eq(result.live_in, [[], [1], [1], [0, 1], []])
  assert_eq(result.live_out, [[1], [0, 1], [0, 1], [], []])
}

///|
test "liveness crosses loop backedges and respects a definition before the next iteration" {
  let result = liveness({
    graph: flow_test_graph(4, [(0, 1), (1, 2), (2, 1), (1, 3)], 0),
    variables: ["x", "unused"],
    definitions: [[0], [], [0, 1], []],
    uses: [[], [0], [], []],
  })
  assert_eq(result.live_in, [[], [0], [], []])
  assert_eq(result.live_out, [[0], [], [0], []])
}

///|
test "liveness includes permanent cycles and excludes unreachable incoming facts" {
  let graph : Graph = {
    ..flow_test_graph(6, [(0, 1), (1, 2), (0, 3), (3, 4), (4, 3), (5, 3)], 0),
    exits: [2],
  }
  let result = liveness({
    graph,
    variables: ["x", "y"],
    definitions: [[1], [], [], [], [0], []],
    uses: [[], [], [], [1], [0], [0, 1]],
  })
  assert_eq(result.reachable, [true, true, true, true, true, false])
  assert_eq(result.live_in, [[0], [], [], [0, 1], [0, 1], []])
  assert_eq(result.live_out, [[0, 1], [], [], [0, 1], [0, 1], []])
  let same_block = liveness({
    graph: { nodes: ["only"], edges: [], entry: 0, exits: [0], },
    variables: ["x"],
    definitions: [[0]],
    uses: [[0]],
  })
  assert_eq(same_block.live_in, [[0]])
  assert_eq(same_block.live_out, [[]])
}

///|
test "liveness results own their sets and support programs with no variables" {
  let program : FlowProgram = {
    graph: flow_test_graph(3, [(0, 1), (1, 2)], 0),
    variables: ["x"],
    definitions: [[], [], []],
    uses: [[], [], [0]],
  }
  let result = liveness(program)
  let another = liveness(program)
  program.graph.edges.clear()
  program.graph.nodes.clear()
  program.variables.clear()
  program.definitions.clear()
  program.uses[2].clear()
  program.uses.clear()
  assert_eq(result.reachable, [true, true, true])
  assert_eq(result.live_in, [[0], [0], [0]])
  assert_eq(result.live_out, [[0], [0], []])
  result.live_in[0].clear()
  assert_eq(result.live_in[1], [0])
  assert_eq(result.live_out[0], [0])
  assert_eq(another.live_in, [[0], [0], [0]])
  let empty = liveness({
    graph: flow_test_graph(2, [], 1),
    variables: [],
    definitions: [[], []],
    uses: [[], []],
  })
  assert_eq(empty.reachable, [false, true])
  assert_eq(empty.live_in, [[], []])
  assert_eq(empty.live_out, [[], []])
}

///|
test "typed program validation rejects invalid identifiers rows indices and graph first" {
  let program : FlowProgram = {
    graph: flow_test_graph(1, [], 0),
    variables: ["x"],
    definitions: [[]],
    uses: [[]],
  }
  for
    invalid in [
      { ..program, variables: [""], },
      { ..program, variables: ["bad name"], },
      { ..program, variables: ["变量"], },
      {
        ..program,
        variables: [
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ],
      },
      { ..program, variables: ["x", "x"], },
      { ..program, variables: Array::makei(513, i => "v" + i.to_string()), },
      { ..program, definitions: [], },
      { ..program, uses: [[], []], },
      { ..program, definitions: [[-1]], },
      { ..program, definitions: [[1]], },
      { ..program, uses: [[-1]], },
      { ..program, uses: [[1]], },
      { ..program, definitions: [[0, 0]], },
      { ..program, uses: [[0, 0]], },
      { ..program, graph: { ..program.graph, entry: 1, }, },
    ] {
    let rejected = try {
      ignore(liveness(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  let first_error = try {
    validate_program({
      ..program,
      graph: { ..program.graph, entry: -1, },
      variables: ["", ""],
    })
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(first_error, "entry index is outside the graph")
}

///|
test "program association and variable limits accept the exact boundary" {
  let program : FlowProgram = {
    graph: flow_test_graph(512, [], 0),
    variables: Array::makei(512, i => "v" + i.to_string()),
    definitions: Array::makei(512, node => {
      if node < 32 {
        Array::makei(512, variable => variable)
      } else {
        []
      }
    }),
    uses: Array::makei(512, _ => []),
  }
  let result = liveness(program)
  assert_eq(result.live_in[0], [])
  assert_eq(result.live_out[0], [])
  assert_eq(result.reachable[511], false)
  program.uses[0].push(0)
  let rejected = try {
    ignore(liveness(program))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}

///|
/// Independent finite-path witness search: a use encountered before the first
/// definition makes the variable live. Checking a use before a definition at
/// the same node implements the documented within-block convention.
fn flow_test_use_path(
  program : FlowProgram,
  starts : Array[Int32],
  variable : Int32,
) -> Bool {
  let visited = Array::make(program.graph.nodes.length(), false)
  let queue = starts.copy()
  let mut cursor = 0
  while cursor < queue.length() {
    let node = queue[cursor]
    cursor += 1
    if visited[node] {
      continue
    }
    visited[node] = true
    if program.uses[node].contains(variable) {
      return true
    }
    if program.definitions[node].contains(variable) {
      continue
    }
    for (from, to) in program.graph.edges {
      if from == node && !visited[to] {
        queue.push(to)
      }
    }
  }
  false
}

///|
test "all three-node graphs and single-variable block facts match finite-path witnesses" {
  // 512 graphs * 3 entries * 64 independent definition/use assignments. This
  // includes self-loops, unreachable predecessors and cycles without exits.
  for edge_mask in 0..<512 {
    let edges : Array[(Int32, Int32)] = []
    let mut edge_bits = edge_mask
    for from in 0..<3 {
      for to in 0..<3 {
        if edge_bits % 2 == 1 {
          edges.push((from, to))
        }
        edge_bits /= 2
      }
    }
    for entry in 0..<3 {
      let graph = flow_test_graph(3, edges, entry)
      let expected_reachable = Array::make(3, false)
      expected_reachable[entry] = true
      // Any reachable vertex has a simple entry path of at most n - 1 edges.
      for _ in 0..<2 {
        for (from, to) in edges {
          if expected_reachable[from] {
            expected_reachable[to] = true
          }
        }
      }
      for fact_mask in 0..<64 {
        let definitions : Array[Array[Int32]] = [[], [], []]
        let uses : Array[Array[Int32]] = [[], [], []]
        let mut fact_bits = fact_mask
        for node in 0..<3 {
          if fact_bits % 2 == 1 {
            definitions[node].push(0)
          }
          fact_bits /= 2
          if fact_bits % 2 == 1 {
            uses[node].push(0)
          }
          fact_bits /= 2
        }
        let program : FlowProgram = {
          graph,
          variables: ["x"],
          definitions,
          uses,
        }
        let expected_in : Array[Array[Int32]] = [[], [], []]
        let expected_out : Array[Array[Int32]] = [[], [], []]
        for node in 0..<3 {
          if expected_reachable[node] {
            if flow_test_use_path(program, [node], 0) {
              expected_in[node].push(0)
            }
            let successors = []
            for (from, to) in edges {
              if from == node {
                successors.push(to)
              }
            }
            if flow_test_use_path(program, successors, 0) {
              expected_out[node].push(0)
            }
          }
        }
        let result = liveness(program)
        assert_eq(result.reachable, expected_reachable)
        assert_eq(result.live_in, expected_in)
        assert_eq(result.live_out, expected_out)
      }
    }
  }
}
