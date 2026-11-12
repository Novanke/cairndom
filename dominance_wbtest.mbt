///|
fn dominance_test_graph(
  n : Int32,
  edges : Array[(Int32, Int32)],
  entry : Int32,
) -> Graph {
  { nodes: Array::makei(n, i => "n" + i.to_string()), edges, entry, exits: [], }
}

///|
test "diamond has a join frontier and a dominated tail" {
  let graph = dominance_test_graph(
    5,
    [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
    0,
  )
  let result = dominators(graph)
  assert_eq(result.reachable, [true, true, true, true, true])
  assert_eq(result.immediate, [None, Some(0), Some(0), Some(0), Some(3)])
  assert_eq(result.frontiers, [[], [3], [3], [], []])
  assert_true(dominates(result, 0, 4))
  assert_true(dominates(result, 3, 4))
  assert_false(dominates(result, 1, 3))
}

///|
test "entry self-loop includes the entry in its own frontier" {
  let result = dominators(dominance_test_graph(2, [(0, 0), (0, 1)], 0))
  assert_eq(result.immediate, [None, Some(0)])
  assert_eq(result.frontiers, [[0], []])
  let singleton = dominators(dominance_test_graph(1, [(0, 0)], 0))
  assert_eq(singleton.immediate, [None])
  assert_eq(singleton.frontiers, [[0]])
}

///|
test "backedge to entry reaches every dominator on its predecessor chain" {
  let result = dominators(
    dominance_test_graph(4, [(0, 1), (1, 2), (2, 0), (2, 3)], 0),
  )
  assert_eq(result.immediate, [None, Some(0), Some(1), Some(2)])
  assert_eq(result.frontiers, [[0], [0], [0], []])
}

///|
test "unreachable incoming edges and components do not alter dominance" {
  let graph = dominance_test_graph(
    6,
    [(0, 1), (1, 3), (2, 3), (3, 4), (4, 3), (5, 5)],
    2,
  )
  let result = dominators(graph)
  assert_eq(result.reachable, [false, false, true, true, true, false])
  assert_eq(result.immediate, [None, None, None, Some(2), Some(3), None])
  assert_eq(result.frontiers, [[], [], [], [3], [3], []])
  assert_false(dominates(result, 0, 0))
  assert_false(dominates(result, 0, 3))
}

///|
test "irreducible cycle preserves multiple-entry join frontiers" {
  let result = dominators(
    dominance_test_graph(
      6,
      [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1), (3, 2), (3, 4), (4, 5)],
      0,
    ),
  )
  assert_eq(result.immediate, [
    None,
    Some(0),
    Some(0),
    Some(0),
    Some(3),
    Some(4),
  ])
  assert_eq(result.frontiers, [[], [3], [3], [1, 2], [], []])
}

///|
test "nested cycles have stable node-ordered frontiers" {
  let result = dominators(
    dominance_test_graph(
      7,
      [(0, 1), (1, 2), (1, 6), (2, 3), (2, 4), (3, 2), (4, 1), (4, 5), (5, 4)],
      0,
    ),
  )
  assert_eq(result.immediate, [
    None,
    Some(0),
    Some(1),
    Some(2),
    Some(2),
    Some(4),
    Some(1),
  ])
  assert_eq(result.frontiers, [[], [1], [1, 2], [2], [1, 4], [4], []])
}

///|
/// A deliberately independent oracle: removing a node destroys all paths to
/// exactly the nodes that it dominates. It does not use immediate dominators.
fn reachable_without(
  succ : Array[Array[Int32]],
  root : Int32,
  blocked : Int32,
) -> Array[Bool] {
  let found = Array::make(succ.length(), false)
  if root == blocked {
    return found
  }
  let queue = [root]
  found[root] = true
  let mut next = 0
  while next < queue.length() {
    let node = queue[next]
    next = next + 1
    for child in succ[node] {
      if child != blocked && !found[child] {
        found[child] = true
        queue.push(child)
      }
    }
  }
  found
}

///|
test "all three-node digraphs match node-removal dominance and frontier definitions" {
  // Enumerate all directed graphs, including self-loops, for each possible root.
  // These include unreachable nodes, root backedges and irreducible cycles.
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
    for root in 0..<3 {
      let graph = dominance_test_graph(3, edges, root)
      let (succ, pred) = adjacency(graph)
      let expected_reachable = reachable_without(succ, root, -1)
      let dom = Array::makei(3, _ => Array::make(3, false))
      for ancestor in 0..<3 {
        let avoiding = reachable_without(succ, root, ancestor)
        for node in 0..<3 {
          dom[ancestor][node] = expected_reachable[ancestor] &&
            expected_reachable[node] &&
            !avoiding[node]
        }
      }
      let expected_parents : Array[Int32?] = Array::make(3, None)
      for node in 0..<3 {
        if node != root && expected_reachable[node] {
          for candidate in 0..<3 {
            if candidate != node && dom[candidate][node] {
              let mut closest = true
              for other in 0..<3 {
                if other != node &&
                  other != candidate &&
                  dom[other][node] &&
                  !dom[other][candidate] {
                  closest = false
                }
              }
              if closest {
                expected_parents[node] = Some(candidate)
              }
            }
          }
        }
      }
      let expected_frontiers = Array::makei(3, _ => [])
      for ancestor in 0..<3 {
        for target in 0..<3 {
          if expected_reachable[target] &&
            !(ancestor != target && dom[ancestor][target]) {
            let mut has_witness = false
            for predecessor in pred[target] {
              if dom[ancestor][predecessor] {
                has_witness = true
              }
            }
            if has_witness {
              expected_frontiers[ancestor].push(target)
            }
          }
        }
      }
      let result = dominators(graph)
      assert_eq(result.reachable, expected_reachable)
      assert_eq(result.immediate, expected_parents)
      assert_eq(result.frontiers, expected_frontiers)
    }
  }
}
