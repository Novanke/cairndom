///|
test "postdominance explicitly conditions on paths reaching an exit" {
  let result = analyze({
    nodes: ["entry", "normal", "exit", "spin", "unreachable"],
    edges: [(0, 1), (1, 2), (0, 3), (3, 3), (4, 2)],
    entry: 0,
    exits: [2],
  })
  assert_eq(result.forward.reachable, [true, true, true, true, false])
  assert_eq(result.post.reachable, [true, true, true, false, false, true])
  assert_eq(result.post.immediate[0], Some(1))
  assert_eq(result.post.immediate[2], Some(5))
  assert_eq(result.post.immediate[3], None)
  assert_eq(result.components.length(), 4)
  assert_eq(result.loops[0].members, [3])
  assert_eq(result.control_dependencies[1], [])
}

///|
test "multiple exits and no exits retain distinct virtual root semantics" {
  let graph : Graph = {
    nodes: ["entry", "a", "b"],
    edges: [(0, 1), (0, 2)],
    entry: 0,
    exits: [1, 2],
  }
  let result = analyze(graph)
  assert_eq(result.post.immediate[0], Some(3))
  assert_eq(result.control_dependencies[1], [0])
  assert_eq(result.control_dependencies[2], [0])
  let no_exits = analyze({ ..graph, exits: [], })
  assert_eq(no_exits.post.reachable, [false, false, false, true])
  assert_eq(no_exits.post.immediate, [None, None, None, None])
}

///|
test "iterated frontiers find loop-carried phi sites and accept liveness pruning" {
  let result = analyze({
    nodes: ["entry", "head", "left", "right", "join", "exit"],
    edges: [(0, 1), (1, 2), (1, 3), (2, 4), (3, 4), (4, 1), (1, 5)],
    entry: 0,
    exits: [5],
  })
  assert_eq(iterated_frontier(result.forward, [2]), [1, 4])
  assert_eq(iterated_frontier(result.forward, [2, 2], live_in=Some([4])), [4])
  assert_eq(iterated_frontier(result.forward, []), [])
  assert_eq(iterated_frontier(result.forward, [2], live_in=Some([])), [])
}

///|
test "typed graph validation and analysis do not share mutable input arrays" {
  let graph : Graph = {
    nodes: ["entry", "exit"],
    edges: [(0, 1)],
    entry: 0,
    exits: [1],
  }
  let result = analyze(graph)
  graph.edges.clear()
  graph.nodes[0] = "changed"
  graph.exits.clear()
  assert_eq(result.graph.nodes, ["entry", "exit"])
  assert_eq(result.graph.edges, [(0, 1)])
  assert_eq(result.graph.exits, [1])
  for
    invalid in [
      { ..result.graph, entry: -1, },
      { ..result.graph, edges: [(0, 3)], },
      { ..result.graph, edges: [(0, 1), (0, 1)], },
      { ..result.graph, exits: [0], },
      { ..result.graph, nodes: ["same", "same"], },
    ] {
    let rejected = try {
      ignore(analyze(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "JSON parser rejects ambiguous inputs and unknown identifiers" {
  let good =
    #|{"schema":"cairndom.graph.v1","nodes":["a"],"edges":[],"entry":"a","exits":["a"]}
  assert_eq(parse_graph(good).entry, 0)
  for
    invalid in [
      good.replace(old="}", new=",\"entry\":\"a\"}"),
      good.replace(old="\"edges\":[]", new="\"edges\":[[\"a\",\"missing\"]]"),
      good.replace(old="\"a\"]", new="\"a\",\"a\"]"),
      good.replace(old="\"entry\":\"a\"", new="\"typo\":\"a\""),
    ] {
    let rejected = try {
      ignore(parse_graph(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}
