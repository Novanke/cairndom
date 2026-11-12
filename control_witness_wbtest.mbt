///|
fn witness_triples(
  witnesses : Array[ControlWitness],
) -> Array[(Int32, Int32, Int32)] {
  witnesses.map(witness => {
    (witness.controller, witness.successor, witness.dependent)
  })
}

///|
/// Compute finite-exit reachability directly from edges, forbidding blocked.
/// This oracle uses neither immediate postdominators nor their tree walks.
fn witness_exit_paths_without(
  graph : Graph,
  reachable : Array[Bool],
  blocked : Int32,
) -> Array[Bool] {
  let found = Array::make(graph.nodes.length(), false)
  for exit in graph.exits {
    if exit != blocked && reachable[exit] {
      found[exit] = true
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for (from, to) in graph.edges {
      if from != blocked &&
        to != blocked &&
        reachable[from] &&
        found[to] &&
        !found[from] {
        found[from] = true
        changed = true
      }
    }
  }
  found
}

///|
fn witness_definition(graph : Graph) -> Array[(Int32, Int32, Int32)] {
  let n = graph.nodes.length()
  let reachable = Array::make(n, false)
  reachable[graph.entry] = true
  let mut changed = true
  while changed {
    changed = false
    for (from, to) in graph.edges {
      if reachable[from] && !reachable[to] {
        reachable[to] = true
        changed = true
      }
    }
  }
  let exit_paths = witness_exit_paths_without(graph, reachable, -1)
  let postdominates = Array::makei(n, dependent => {
    let avoiding = witness_exit_paths_without(graph, reachable, dependent)
    Array::makei(n, node => exit_paths[node] && !avoiding[node])
  })
  let expected : Array[(Int32, Int32, Int32)] = []
  for controller in 0..<n {
    for successor in 0..<n {
      if !exit_paths[controller] ||
        !exit_paths[successor] ||
        !graph.edges.contains((controller, successor)) {
        continue
      }
      for dependent in 0..<n {
        // The edge requires dependent on every finite exit path from its
        // successor, but dependent must not strictly postdominate controller.
        if postdominates[dependent][successor] &&
          (dependent == controller || !postdominates[dependent][controller]) {
          expected.push((controller, successor, dependent))
        }
      }
    }
  }
  expected
}

///|
fn check_witness_definition(graph : Graph) -> Unit raise {
  let analysis = analyze(graph)
  let (actual, complete) = bounded_control_witnesses_of(analysis)
  assert_true(complete)
  assert_eq(witness_triples(actual), witness_definition(graph))
  let controllers = Array::makei(graph.nodes.length(), _ => [])
  for dependent in 0..<graph.nodes.length() {
    for controller in 0..<graph.nodes.length() {
      if actual.any(witness => {
          witness.controller == controller && witness.dependent == dependent
        }) {
        controllers[dependent].push(controller)
      }
    }
  }
  assert_eq(controllers, analysis.control_dependencies)
}

///|
test "three-way branch preserves distinct inducing edges in stable order" {
  let graph : Graph = {
    nodes: ["entry", "left", "right", "join", "exit"],
    edges: [(3, 4), (0, 3), (2, 4), (0, 2), (1, 3), (0, 1)],
    entry: 0,
    exits: [4],
  }
  let witnesses = control_dependence_witnesses(graph)
  assert_eq(witness_triples(witnesses), [
    (0, 1, 1),
    (0, 1, 3),
    (0, 2, 2),
    (0, 3, 3),
  ])
  let reordered = {
    ..graph,
    edges: Array::makei(graph.edges.length(), index => {
      graph.edges[graph.edges.length() - 1 - index]
    }),
  }
  assert_eq(control_dependence_witnesses(reordered), witnesses)
  assert_eq(bounded_control_witnesses_of(analyze(graph)), (witnesses, true))
  check_witness_definition(graph)
}

///|
test "loop edges preserve self-control for heads and direct self-loops" {
  let graph : Graph = {
    nodes: ["entry", "head", "body", "exit"],
    edges: [(2, 1), (1, 3), (0, 1), (1, 2), (1, 1)],
    entry: 0,
    exits: [3],
  }
  assert_eq(witness_triples(control_dependence_witnesses(graph)), [
    (1, 1, 1),
    (1, 2, 1),
    (1, 2, 2),
  ])
  check_witness_definition(graph)
  let entry_loop : Graph = {
    nodes: ["entry", "exit"],
    edges: [(0, 1), (0, 0)],
    entry: 0,
    exits: [1],
  }
  assert_eq(witness_triples(control_dependence_witnesses(entry_loop)), [
    (0, 0, 0),
  ])
  check_witness_definition(entry_loop)
}

///|
test "declared exits exclude permanent cycles and unreachable inducing edges" {
  let graph : Graph = {
    nodes: ["dead", "entry", "left", "right", "spin", "deadExit"],
    edges: [(0, 5), (0, 2), (1, 4), (4, 4), (1, 3), (1, 2)],
    entry: 1,
    exits: [2, 3, 5],
  }
  assert_eq(witness_triples(control_dependence_witnesses(graph)), [
    (1, 2, 2),
    (1, 3, 3),
  ])
  check_witness_definition(graph)
  let no_exits = { ..graph, exits: [], }
  assert_eq(control_dependence_witnesses(no_exits), [])
  check_witness_definition(no_exits)
  let one_finite_path : Graph = {
    nodes: ["entry", "normal", "exit", "spin"],
    edges: [(0, 1), (1, 2), (0, 3), (3, 3)],
    entry: 0,
    exits: [2],
  }
  assert_eq(control_dependence_witnesses(one_finite_path), [])
  check_witness_definition(one_finite_path)
}

///|
test "witness API validates graph inputs through analysis" {
  let graph : Graph = {
    nodes: ["entry", "exit"],
    edges: [(0, 1)],
    entry: 0,
    exits: [1],
  }
  for
    invalid in [
      { ..graph, entry: -1, },
      { ..graph, edges: [(0, 1), (0, 1)], },
      { ..graph, exits: [0], },
    ] {
    let rejected = try {
      ignore(control_dependence_witnesses(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "all three-node graphs and valid exit subsets match finite-path sets per edge" {
  for mask in 0..<512 {
    let edges : Array[(Int32, Int32)] = []
    let mut bits = mask
    for from in 0..<3 {
      for to in 0..<3 {
        if bits % 2 == 1 {
          edges.push((from, to))
        }
        bits = bits / 2
      }
    }
    for exit_mask in 0..<8 {
      let exits = []
      let mut exit_bits = exit_mask
      let mut valid = true
      for node in 0..<3 {
        if exit_bits % 2 == 1 {
          exits.push(node)
          if edges.any(edge => edge.0 == node) {
            valid = false
          }
        }
        exit_bits = exit_bits / 2
      }
      if valid {
        for entry in 0..<3 {
          check_witness_definition({
            nodes: ["n0", "n1", "n2"],
            edges,
            entry,
            exits,
          })
        }
      }
    }
  }
}

///|
fn witness_overflow_graph() -> Graph {
  let edges = []
  for controller in 1..<49 {
    edges.push((0, controller))
    edges.push((controller, 127))
    for successor in 49..<89 {
      edges.push((controller, successor))
    }
  }
  for node in 49..<127 {
    edges.push((node, node + 1))
  }
  {
    nodes: Array::makei(128, node => "n" + node.to_string()),
    edges,
    entry: 0,
    exits: [127],
  }
}

///|
test "witness overflow returns a deterministic bounded prefix and SDK rejects it" {
  let graph = witness_overflow_graph()
  let analysis = analyze(graph)
  let (witnesses, complete) = bounded_control_witnesses_of(analysis)
  assert_false(complete)
  assert_eq(witnesses.length(), 65536)
  assert_eq(witnesses[0], { controller: 0, successor: 1, dependent: 1, })
  // Entry contributes 48; each controller contributes sum(78..39) = 2340.
  // 48 + 27*2340 + sum(78..40) + 7 reaches this point within edge 28->88.
  assert_eq(witnesses[65535], { controller: 28, successor: 88, dependent: 94, })
  assert_eq(analysis.graph.edges, graph.edges)
  let reordered = {
    ..graph,
    edges: Array::makei(graph.edges.length(), index => {
      graph.edges[graph.edges.length() - 1 - index]
    }),
  }
  let (reversed_witnesses, reversed_complete) = bounded_control_witnesses_of(
    analyze(reordered),
  )
  assert_false(reversed_complete)
  assert_eq(reversed_witnesses, witnesses)
  let rejected = try {
    ignore(control_dependence_witnesses(graph))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
  // Witness truncation never truncates the original node-level relation.
  let all_controllers = Array::makei(48, index => index + 1)
  assert_eq(analysis.control_dependencies[0], [])
  for controller in 1..<49 {
    assert_eq(analysis.control_dependencies[controller], [0])
  }
  for dependent in 49..<127 {
    assert_eq(analysis.control_dependencies[dependent], all_controllers)
  }
  assert_eq(analysis.control_dependencies[127], [])
  assert_false(witnesses.any(witness => witness.controller == 48))
}

///|
test "exactly 65536 witnesses remain complete and accepted by the SDK" {
  let edges = []
  for controller in 1..<33 {
    edges.push((0, controller))
    edges.push((controller, 97))
    for successor in 33..<97 {
      if successor != 64 {
        edges.push((controller, successor))
      }
    }
  }
  for node in 33..<97 {
    edges.push((node, node + 1))
  }
  let graph : Graph = {
    nodes: Array::makei(98, node => "n" + node.to_string()),
    edges,
    entry: 0,
    exits: [97],
  }
  // Each controller contributes 1 + sum(64..1) - 33 = 2048 witnesses.
  let (witnesses, complete) = bounded_control_witnesses_of(analyze(graph))
  assert_true(complete)
  assert_eq(witnesses.length(), 65536)
  assert_eq(witnesses[65535], { controller: 32, successor: 96, dependent: 96, })
  assert_eq(control_dependence_witnesses(graph), witnesses)
  // One self-edge adds one self-control witness without changing exit paths.
  edges.push((1, 1))
  let (overflow, overflow_complete) = bounded_control_witnesses_of(
    analyze(graph),
  )
  assert_false(overflow_complete)
  assert_eq(overflow.length(), 65536)
  let rejected = try {
    ignore(control_dependence_witnesses(graph))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}
