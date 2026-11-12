///|
/// Reachability with one vertex removed gives dominance directly, without
/// constructing immediate dominators or using any production graph helper.
fn ssa_oracle_reachable(graph : Graph, removed : Int32) -> Array[Bool] {
  let found = Array::make(graph.nodes.length(), false)
  let pending = [graph.entry]
  let mut cursor = 0
  while cursor < pending.length() {
    let node = pending[cursor]
    cursor += 1
    if node == removed || found[node] {
      continue
    }
    found[node] = true
    for (from, to) in graph.edges {
      if from == node && to != removed && !found[to] {
        pending.push(to)
      }
    }
  }
  found
}

///|
/// A frontier contains y when the ancestor dominates a predecessor of y but
/// does not strictly dominate y. This oracle uses node deletion, not CHK or
/// parent-chain walks, and keeps its result as a boolean relation.
fn ssa_oracle_frontiers(graph : Graph) -> Array[Array[Bool]] {
  let n = graph.nodes.length()
  let reachable = ssa_oracle_reachable(graph, -1)
  let dom = Array::makei(n, _ => Array::make(n, false))
  for ancestor in 0..<n {
    let avoiding = ssa_oracle_reachable(graph, ancestor)
    for node in 0..<n {
      dom[ancestor][node] = reachable[ancestor] &&
        reachable[node] &&
        !avoiding[node]
    }
  }
  let frontiers = Array::makei(n, _ => Array::make(n, false))
  for ancestor in 0..<n {
    for (previous, target) in graph.edges {
      if reachable[target] &&
        dom[ancestor][previous] &&
        !(ancestor != target && dom[ancestor][target]) {
        frontiers[ancestor][target] = true
      }
    }
  }
  frontiers
}

///|
fn ssa_oracle_check(program : FlowProgram) -> Unit raise {
  let n = program.graph.nodes.length()
  let reachable = ssa_oracle_reachable(program.graph, -1)
  let frontiers = ssa_oracle_frontiers(program.graph)
  let expected_in : Array[Array[Int32]] = Array::makei(n, _ => [])
  let expected_out : Array[Array[Int32]] = Array::makei(n, _ => [])
  let plan = plan_ssa(program)
  assert_eq(plan.placements.length(), program.variables.length())
  assert_eq(plan.liveness.reachable, reachable)
  for variable in 0..<program.variables.length() {
    let definitions = []
    let live_nodes = []
    let live = Array::make(n, false)
    for node in 0..<n {
      if !reachable[node] {
        continue
      }
      if program.definitions[node].contains(variable) {
        definitions.push(node)
      }
      // The non-production path oracle checks uses before definitions in the
      // same block and stops at a definition, including on permanent cycles.
      if flow_test_use_path(program, [node], variable) {
        live[node] = true
        live_nodes.push(node)
        expected_in[node].push(variable)
      }
      let successors = []
      for (from, to) in program.graph.edges {
        if from == node {
          successors.push(to)
        }
      }
      if flow_test_use_path(program, successors, variable) {
        expected_out[node].push(variable)
      }
    }
    // Solve the mathematical least closure by repeated full relation scans,
    // independently of the production IDF work queue and dominance tree.
    let selected = Array::make(n, false)
    let mut changed = true
    while changed {
      changed = false
      for source in 0..<n {
        if reachable[source] &&
          (definitions.contains(source) || selected[source]) {
          for target in 0..<n {
            if frontiers[source][target] && live[target] && !selected[target] {
              selected[target] = true
              changed = true
            }
          }
        }
      }
    }
    let phi_nodes = []
    for node in 0..<n {
      if selected[node] {
        phi_nodes.push(node)
      }
    }
    let placement = plan.placements[variable]
    assert_eq(placement.variable, variable)
    assert_eq(placement.definitions, definitions)
    assert_eq(placement.live_in, live_nodes)
    assert_eq(placement.phi_nodes, phi_nodes)
    assert_eq(
      placement.requires_entry_value,
      flow_test_use_path(program, [program.graph.entry], variable),
    )
  }
  assert_eq(plan.liveness.live_in, expected_in)
  assert_eq(plan.liveness.live_out, expected_out)
}

///|
/// Two variables have complementary block facts, so each graph/fact assignment
/// also checks that variable indices do not leak into one another's results.
/// A third variable has definitions but no uses and must never need a phi site.
fn ssa_oracle_program(graph : Graph, fact_mask : Int32) -> FlowProgram {
  let n = graph.nodes.length()
  let definitions : Array[Array[Int32]] = Array::makei(n, _ => [])
  let uses : Array[Array[Int32]] = Array::makei(n, _ => [])
  let mut bits = fact_mask
  for node in 0..<n {
    definitions[node].push(if bits % 2 == 1 { 0 } else { 1 })
    bits /= 2
    uses[node].push(if bits % 2 == 1 { 0 } else { 1 })
    bits /= 2
    if node % 2 == 1 {
      definitions[node].push(2)
    }
  }
  { graph, variables: ["x", "y", "unused"], definitions, uses, }
}

///|
test "pruned phi definition agrees across three-node control-flow families and block facts" {
  // Enumerate block facts on representative shapes rather than repeating the
  // liveness suite's exhaustive graph enumeration. Rotating the entry covers
  // nonzero roots, dead definitions, incoming unreachable edges and root loops.
  let families : Array[Array[(Int32, Int32)]] = [
    [],
    [(0, 1), (1, 2)],
    [(0, 1), (0, 2), (1, 2)],
    [(0, 0), (0, 1), (1, 2)],
    [(0, 1), (1, 2), (2, 0)],
    [(0, 1), (0, 2), (1, 2), (2, 1)],
  ]
  for edges in families {
    for entry in 0..<3 {
      let graph : Graph = { nodes: ["a", "b", "c"], edges, entry, exits: [], }
      for fact_mask in 0..<64 {
        ssa_oracle_check(ssa_oracle_program(graph, fact_mask))
      }
    }
  }
}

///|
test "pruned phi definition handles four-node joins iterated sites and exit-independent cycles" {
  // Each family's block facts include use-before-def in one block. The joins
  // followed by backedges require closure beyond the original definition sites.
  let families : Array[Array[(Int32, Int32)]] = [
    [(0, 1), (0, 2), (1, 3), (2, 3)],
    [(0, 1), (1, 2), (2, 1), (1, 3)],
    [(0, 1), (1, 2), (3, 1)],
    [(0, 1), (0, 2), (1, 2), (2, 1), (1, 3), (2, 3)],
    [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1)],
    [(0, 1), (0, 2), (1, 3), (2, 3), (3, 0)],
    [(0, 1), (0, 2), (2, 2)],
  ]
  for edges in families {
    let exits = []
    for node in 0..<4 {
      let mut terminal = true
      for (from, _) in edges {
        if from == node {
          terminal = false
        }
      }
      if terminal {
        exits.push(node)
      }
    }
    let graph : Graph = {
      nodes: ["entry", "a", "b", "end"],
      edges,
      entry: 0,
      exits,
    }
    for fact_mask in 0..<256 {
      ssa_oracle_check(ssa_oracle_program(graph, fact_mask))
    }
  }
}
