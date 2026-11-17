///|
// Build the finite-exit reverse graph explicitly, then apply node-removal
// definitions. No production dominance, loop, SCC or control algorithm is used.
fn postdominance_test_expected(graph : Graph) -> Dominance {
  let n = graph.nodes.length()
  let size = n + 1
  let forward = Array::makei(n, _ => [])
  for (from, to) in graph.edges {
    forward[from].push(to)
  }
  let entry_reachable = reachable_without(forward, graph.entry, -1)
  let reverse = Array::makei(n + 1, _ => [])
  let predecessors = Array::makei(n + 1, _ => [])
  for (from, to) in graph.edges {
    if entry_reachable[from] && entry_reachable[to] {
      reverse[to].push(from)
      predecessors[from].push(to)
    }
  }
  for exit in graph.exits {
    if entry_reachable[exit] {
      reverse[n].push(exit)
      predecessors[exit].push(n)
    }
  }
  let reachable = reachable_without(reverse, n, -1)
  let relation = Array::makei(n + 1, _ => Array::make(n + 1, false))
  for ancestor in 0..<size {
    let avoiding = reachable_without(reverse, n, ancestor)
    for node in 0..<size {
      relation[ancestor][node] = reachable[ancestor] &&
        reachable[node] &&
        !avoiding[node]
    }
  }
  let immediate = Array::makei(n + 1, node => {
    index_test_deepest(
      relation,
      Array::makei(n + 1, ancestor => {
        ancestor != node && relation[ancestor][node]
      }),
    )
  })
  let frontiers = Array::makei(n + 1, _ => [])
  for ancestor in 0..<size {
    for target in 0..<size {
      if reachable[target] &&
        !(ancestor != target && relation[ancestor][target]) &&
        predecessors[target].any(previous => relation[ancestor][previous]) {
        frontiers[ancestor].push(target)
      }
    }
  }
  { root: n, reachable, immediate, frontiers, }
}

///|
test "standalone postdominance matches independent node removal for every three-node graph root and terminal-exit subset" {
  let mut cases = 0
  for mask in 0..<512 {
    let edges : Array[(Int32, Int32)] = []
    let terminal = Array::make(3, true)
    let mut bits = mask
    for from in 0..<3 {
      for to in 0..<3 {
        if bits % 2 == 1 {
          edges.push((from, to))
          terminal[from] = false
        }
        bits /= 2
      }
    }
    for entry in 0..<3 {
      for exit_mask in 0..<8 {
        let exits = []
        let mut valid = true
        let mut selected = exit_mask
        for node in 0..<3 {
          if selected % 2 == 1 {
            if !terminal[node] {
              valid = false
            }
            exits.push(node)
          }
          selected /= 2
        }
        if !valid {
          continue
        }
        let graph = { ..dominance_test_graph(3, edges, entry), exits, }
        let expected = postdominance_test_expected(graph)
        let actual = postdominators(graph)
        assert_eq(actual.root, 3)
        assert_eq(actual.reachable, expected.reachable)
        assert_eq(actual.immediate, expected.immediate)
        assert_eq(actual.frontiers, expected.frontiers)
        let combined = analyze(graph).post
        assert_eq(actual.root, combined.root)
        assert_eq(actual.reachable, combined.reachable)
        assert_eq(actual.immediate, combined.immediate)
        assert_eq(actual.frontiers, combined.frontiers)
        cases += 1
      }
    }
  }
  assert_eq(cases, 2187)
}

///|
test "standalone postdominance preserves finite-exit scope with loops and unreachable exits" {
  let graph : Graph = {
    nodes: [
      "dead", "entry", "branch", "left_exit", "right_exit", "spin", "dead_exit",
    ],
    entry: 1,
    exits: [3, 4, 6],
    edges: [(1, 2), (2, 3), (2, 4), (1, 5), (5, 5), (2, 1), (1, 1), (0, 3)],
  }
  let tree = postdominators(graph)
  assert_eq(tree.root, 7)
  assert_eq(tree.reachable, [false, true, true, true, true, false, false, true])
  assert_eq(tree.immediate, [
    None,
    Some(2),
    Some(7),
    Some(7),
    Some(7),
    None,
    None,
    None,
  ])
  let expected = postdominance_test_expected(graph)
  assert_eq(tree.frontiers, expected.frontiers)
  let index = index_dominance(tree)
  assert_eq(index.nearest_common([3, 4]), Some(7))
  assert_eq(index.nearest_common([1, 2]), Some(2))
  assert_eq(index.nearest_common([1, 5]), None)
  for exits in [[], [6]] {
    let absent = postdominators({ ..graph, exits, })
    assert_eq(absent.reachable, [
      false, false, false, false, false, false, false, true,
    ])
    assert_eq(absent.immediate, Array::make(8, None))
    assert_eq(absent.frontiers, Array::makei(8, _ => []))
  }
  let terminal_entry = postdominators({
    nodes: ["only"],
    edges: [],
    entry: 0,
    exits: [0],
  })
  assert_eq(terminal_entry.root, 1)
  assert_eq(terminal_entry.reachable, [true, true])
  assert_eq(terminal_entry.immediate, [Some(1), None])
  assert_eq(terminal_entry.frontiers, [[], []])
}

///|
test "standalone postdominance retains all 513 slots at the supported maximum" {
  let tree = postdominators({
    nodes: Array::makei(512, node => "n" + node.to_string()),
    entry: 0,
    exits: [511],
    edges: Array::makei(511, node => (node, node + 1)),
  })
  assert_eq(tree.root, 512)
  assert_eq(tree.reachable.length(), 513)
  assert_eq(tree.immediate.length(), 513)
  assert_eq(tree.frontiers.length(), 513)
  for node in 0..<513 {
    assert_true(tree.reachable[node])
    assert_eq(
      tree.immediate[node],
      if node == 512 {
        None
      } else {
        Some(node + 1)
      },
    )
    assert_eq(tree.frontiers[node], [])
  }
  let index = index_dominance(tree)
  assert_eq(index.nearest_common([0, 256, 511]), Some(511))
  assert_eq(index.nearest_common([0, 512]), Some(512))
}

///|
test "standalone postdominance leaves input intact and owns each result independently" {
  let graph : Graph = {
    nodes: ["dead", "entry", "middle", "exit"],
    entry: 1,
    exits: [3],
    edges: [(1, 2), (2, 3), (0, 2)],
  }
  let first = postdominators(graph)
  let second = postdominators(graph)
  assert_eq(graph.nodes, ["dead", "entry", "middle", "exit"])
  assert_eq(graph.edges, [(1, 2), (2, 3), (0, 2)])
  assert_eq(graph.exits, [3])
  first.reachable.clear()
  first.immediate.clear()
  first.frontiers[0].push(999)
  first.frontiers[1].push(-1)
  first.frontiers.clear()
  graph.nodes.clear()
  graph.edges.clear()
  graph.exits.clear()
  assert_eq(second.root, 4)
  assert_eq(second.reachable, [false, true, true, true, true])
  assert_eq(second.immediate, [None, Some(2), Some(3), Some(4), None])
  assert_eq(second.frontiers, [[], [], [], [], []])
  assert_true(index_dominance(second).dominates(3, 1))
}

///|
test "standalone postdominance rejects malformed typed graphs before traversal" {
  let graph : Graph = {
    nodes: ["entry", "exit"],
    entry: 0,
    exits: [1],
    edges: [(0, 1)],
  }
  for
    invalid in [
      { ..graph, entry: -1, },
      { ..graph, entry: 2, },
      { ..graph, nodes: [], },
      { ..graph, nodes: ["same", "same"], },
      { ..graph, edges: [(0, 2)], },
      { ..graph, edges: [(-1, 1)], },
      { ..graph, edges: [(0, 1), (0, 1)], },
      { ..graph, exits: [0], },
      { ..graph, exits: [1, 1], },
      { ..graph, exits: [2], },
      { ..graph, nodes: Array::makei(513, node => "n" + node.to_string()), },
    ] {
    assert_true(
      try {
        ignore(postdominators(invalid))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}
