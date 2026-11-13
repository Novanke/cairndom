///|
// Removing a vertex disconnects exactly the reachable nodes it dominates.
// This reference does not inspect any production dominator parent or interval.
fn index_test_reachable(graph : Graph, removed : Int32) -> Array[Bool] {
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
fn index_test_dominance(graph : Graph) -> Array[Array[Bool]] {
  let n = graph.nodes.length()
  let reachable = index_test_reachable(graph, -1)
  let relation = Array::makei(n, _ => Array::make(n, false))
  for ancestor in 0..<n {
    let avoiding = index_test_reachable(graph, ancestor)
    for node in 0..<n {
      relation[ancestor][node] = reachable[ancestor] &&
        reachable[node] &&
        !avoiding[node]
    }
  }
  relation
}

///|
// The deepest candidate is dominated by every other candidate. This checks
// nearest-common answers without walking parents or using an LCA algorithm.
fn index_test_deepest(
  relation : Array[Array[Bool]],
  candidates : Array[Bool],
) -> Int32? {
  for candidate in 0..<candidates.length() {
    if candidates[candidate] {
      let mut deepest = true
      for ancestor in 0..<candidates.length() {
        if candidates[ancestor] && !relation[ancestor][candidate] {
          deepest = false
        }
      }
      if deepest {
        return Some(candidate)
      }
    }
  }
  None
}

///|
fn index_test_common(
  relation : Array[Array[Bool]],
  nodes : Array[Int32],
) -> Int32? {
  if nodes.is_empty() {
    return None
  }
  let candidates = Array::makei(relation.length(), ancestor => {
    nodes.all(node => relation[ancestor][node])
  })
  index_test_deepest(relation, candidates)
}

///|
test "indexed dominance and nearest common match node removal on all three-node graphs" {
  // Include self-loops and rotate the root: reachable cycles, dead predecessors
  // and nonzero roots use the same independent mathematical reference.
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
      let graph : Graph = { nodes: ["a", "b", "c"], edges, entry, exits: [], }
      let relation = index_test_dominance(graph)
      let reachable = index_test_reachable(graph, -1)
      let index = index_dominance(dominators(graph))
      assert_eq(index.node_count(), 3)
      assert_eq(index.root(), entry)
      assert_eq(index.nearest_common([]), None)
      for node in 0..<3 {
        assert_eq(index.is_reachable(node), reachable[node])
        let strict_ancestors = Array::makei(3, ancestor => {
          ancestor != node && relation[ancestor][node]
        })
        assert_eq(
          index.immediate_parent(node),
          index_test_deepest(relation, strict_ancestors),
        )
        assert_eq(
          index.nearest_common([node]),
          if reachable[node] {
            Some(node)
          } else {
            None
          },
        )
        for other in 0..<3 {
          assert_eq(index.dominates(node, other), relation[node][other])
          let expected = index_test_common(relation, [node, other])
          assert_eq(index.nearest_common([node, other]), expected)
          // Reordering and duplicates must not change a common ancestor.
          assert_eq(index.nearest_common([other, node, node, other]), expected)
        }
      }
      for subset in 0..<8 {
        let nodes : Array[Int32] = []
        let mut selected = subset
        // Deliberately pass descending indices instead of canonical set order.
        for offset in 0..<3 {
          if selected % 2 == 1 {
            nodes.push(2 - offset)
          }
          selected /= 2
        }
        assert_eq(
          index.nearest_common(nodes),
          index_test_common(relation, nodes),
        )
      }
    }
  }
}

///|
test "dominance index keeps its snapshot after source arrays are corrupted" {
  let tree = dominators({
    nodes: ["dead", "entry", "middle", "exit"],
    entry: 1,
    exits: [3],
    edges: [(1, 2), (2, 3)],
  })
  let index = index_dominance(tree)
  tree.reachable[1] = false
  tree.immediate[2] = Some(2)
  tree.frontiers[3].push(999)
  tree.reachable.clear()
  tree.immediate.clear()
  for row in tree.frontiers {
    row.clear()
  }
  tree.frontiers.clear()
  assert_eq(index.node_count(), 4)
  assert_eq(index.root(), 1)
  assert_true(index.is_reachable(1))
  assert_false(index.is_reachable(0))
  assert_eq(index.immediate_parent(1), None)
  assert_eq(index.immediate_parent(2), Some(1))
  assert_eq(index.immediate_parent(3), Some(2))
  assert_eq(index.immediate_parent(0), None)
  assert_true(index.dominates(1, 3))
  assert_true(index.dominates(2, 3))
  assert_false(index.dominates(3, 2))
  assert_false(index.dominates(0, 0))
  assert_eq(index.nearest_common([3, 2, 3]), Some(2))
  assert_eq(index.nearest_common([3, 0]), None)
  assert_true(
    try {
      ignore(index_dominance(tree))
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "index constructor rejects malformed parents frontiers roots and dimensions" {
  let valid : Dominance = {
    root: 1,
    reachable: [false, true, true, true],
    immediate: [None, None, Some(1), Some(2)],
    frontiers: [[], [], [], []],
  }
  let invalid = [
    { ..valid, root: -1, },
    { ..valid, root: 4, },
    { ..valid, root: 0, },
    { ..valid, immediate: [None, Some(1), Some(1), Some(2)], },
    { ..valid, immediate: [None, None, None, Some(2)], },
    { ..valid, immediate: [None, None, Some(4), Some(2)], },
    { ..valid, immediate: [None, None, Some(0), Some(2)], },
    { ..valid, immediate: [None, None, Some(3), Some(2)], },
    { ..valid, immediate: [Some(1), None, Some(1), Some(2)], },
    { ..valid, reachable: [false, true, true, false], },
    { ..valid, frontiers: [[1], [], [], []], },
    { ..valid, frontiers: [[], [], [4], []], },
    { ..valid, frontiers: [[], [], [-1], []], },
    { ..valid, frontiers: [[], [], [0], []], },
    { ..valid, frontiers: [[], [], [3, 3], []], },
    { ..valid, frontiers: [[], [], [1, 2, 3, 1, 2], []], },
    { ..valid, immediate: [None, None, Some(1)], },
    { ..valid, frontiers: [[], [], []], },
    { ..valid, reachable: [], immediate: [], frontiers: [], },
    {
      root: 0,
      reachable: Array::make(514, true),
      immediate: Array::makei(514, node => {
        if node == 0 {
          None
        } else {
          Some(node - 1)
        }
      }),
      frontiers: Array::makei(514, _ => []),
    },
  ]
  for tree in invalid {
    assert_true(
      try {
        ignore(index_dominance(tree))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "indexed queries check every bound before returning for unreachable nodes" {
  let index = index_dominance(
    dominators({
      nodes: ["dead", "entry", "exit"],
      entry: 1,
      exits: [2],
      edges: [(1, 2)],
    }),
  )
  assert_eq(index.nearest_common([]), None)
  assert_eq(index.nearest_common([0]), None)
  assert_eq(index.nearest_common([2, 0, 1]), None)
  assert_false(index.dominates(0, 2))
  assert_false(index.dominates(2, 0))
  for (ancestor, node) in [(-1, 1), (1, 3), (0, 3), (3, 0), (0, -1), (-1, 0)] {
    assert_true(
      try {
        ignore(index.dominates(ancestor, node))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  for nodes in [[-1], [3], [0, 3], [3, 0], [0, -1], [-1, 0], [2, 0, 3]] {
    assert_true(
      try {
        ignore(index.nearest_common(nodes))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  for node in [-1, 3] {
    assert_true(
      try {
        ignore(index.is_reachable(node))
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_true(
      try {
        ignore(index.immediate_parent(node))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "postdominance index preserves virtual common ancestors and finite-exit scope" {
  let result = analyze({
    nodes: ["entry", "left_exit", "right_exit", "forever", "dead"],
    entry: 0,
    exits: [1, 2],
    edges: [(0, 1), (0, 2), (0, 3), (3, 3)],
  })
  let index = index_dominance(result.post)
  assert_eq(index.node_count(), 6)
  assert_eq(index.root(), 5)
  assert_eq(index.immediate_parent(5), None)
  assert_eq(index.immediate_parent(0), Some(5))
  assert_true(index.is_reachable(5))
  assert_true(index.dominates(5, 0))
  assert_false(index.is_reachable(3))
  assert_false(index.is_reachable(4))
  assert_false(index.dominates(5, 3))
  assert_eq(index.nearest_common([1, 2]), Some(5))
  assert_eq(index.nearest_common([2, 0, 1, 2]), Some(5))
  assert_eq(index.nearest_common([5, 1]), Some(5))
  assert_eq(index.nearest_common([1, 3]), None)
}

///|
test "maximum postdominance chain and long sibling branch keep high ancestors" {
  let graph : Graph = {
    nodes: Array::makei(512, node => "n" + node.to_string()),
    entry: 0,
    exits: [511],
    edges: Array::makei(511, node => (node, node + 1)),
  }
  let index = index_dominance(analyze(graph).post)
  assert_eq(index.node_count(), 513)
  assert_eq(index.root(), 512)
  for node in 0..<513 {
    assert_true(index.is_reachable(node))
    assert_eq(
      index.immediate_parent(node),
      if node == 512 {
        None
      } else {
        Some(node + 1)
      },
    )
    assert_true(index.dominates(512, node))
  }
  assert_true(index.dominates(511, 0))
  assert_false(index.dominates(0, 511))
  assert_eq(index.nearest_common([0, 256, 511]), Some(511))
  assert_eq(index.nearest_common([0, 512]), Some(512))
  // A deep node and a shallow sibling require substantial ancestor alignment,
  // unlike two nodes on the same chain, whose common node is an operand.
  let branch = index_dominance({
    root: 0,
    reachable: Array::make(513, true),
    immediate: Array::makei(513, node => {
      if node == 0 {
        None
      } else if node == 512 {
        Some(0)
      } else {
        Some(node - 1)
      }
    }),
    frontiers: Array::makei(513, _ => []),
  })
  assert_eq(branch.nearest_common([511, 512]), Some(0))
  assert_eq(branch.nearest_common([512, 250, 511]), Some(0))
  assert_eq(branch.nearest_common([511, 250, 511]), Some(250))
  assert_true(branch.dominates(250, 511))
  assert_false(branch.dominates(250, 512))
}
