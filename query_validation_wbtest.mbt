///|
test "all public queries reject cyclic and disconnected mutable trees" {
  let valid = dominators({
    nodes: ["entry", "middle", "exit"],
    edges: [(0, 1), (1, 2)],
    entry: 0,
    exits: [2],
  })
  let cyclic = { ..valid, immediate: [None, Some(2), Some(1)], }
  let invalid = [
    cyclic,
    { ..valid, root: -1, },
    { ..valid, root: 3, },
    { ..valid, immediate: [Some(0), Some(0), Some(1)], },
    { ..valid, immediate: [None, None, Some(1)], },
    { ..valid, immediate: [None, Some(3), Some(1)], },
    { ..valid, reachable: [false, true, true], },
    { ..valid, reachable: [true, false, true], },
    { ..valid, frontiers: [[], [], [3]], },
    { ..valid, frontiers: [[], [], [1, 1]], },
    { ..valid, frontiers: [[], []], },
  ]
  for tree in invalid {
    // Even a reflexive query, empty IDF worklist or unrelated query must check
    // the entire structure before it can return a plausible-looking result.
    for (left, right) in [(1, 1), (1, 2), (2, 1), (0, 2)] {
      let rejected = try {
        ignore(dominates(tree, left, right))
        false
      } catch {
        Invalid(_) => true
      }
      assert_true(rejected)
    }
    let rejected = try {
      ignore(iterated_frontier(tree, []))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  assert_true(dominates(valid, 0, 2))
  assert_eq(iterated_frontier(valid, [1]), [])
}

///|
test "mutating an actual analysis is rejected without changing other results" {
  let result = analyze({
    nodes: ["entry", "left", "right", "join"],
    edges: [(0, 1), (0, 2), (1, 3), (2, 3)],
    entry: 0,
    exits: [3],
  })
  result.forward.immediate[1] = Some(2)
  result.forward.immediate[2] = Some(1)
  assert_true(
    try {
      ignore(dominates(result.forward, 1, 2))
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      ignore(iterated_frontier(result.forward, [1]))
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(dominates(result.post, 3, 0))
}
