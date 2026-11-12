///|
fn structure_tree(graph : Graph, immediate : Array[Int32?]) -> Dominance {
  {
    root: graph.entry,
    reachable: Array::makei(graph.nodes.length(), fn(node) {
      node == graph.entry || immediate[node] is Some(_)
    }),
    immediate,
    frontiers: Array::makei(graph.nodes.length(), _ => []),
  }
}

///|
test "self loop stays at its header and excludes unreachable predecessors" {
  let graph : Graph = {
    nodes: ["start", "spin", "exit", "dead"],
    edges: [(3, 1), (1, 2), (1, 1), (0, 1), (3, 3)],
    entry: 0,
    exits: [2],
  }
  let (loops, components) = graph_structure(
    graph,
    structure_tree(graph, [None, Some(0), Some(1), None]),
  )
  assert_eq(loops.length(), 1)
  assert_eq(loops[0].header, 1)
  assert_eq(loops[0].latches, [1])
  assert_eq(loops[0].members, [1])
  assert_eq(loops[0].parent, None)
  assert_eq(components.map(component => component.members), [[0], [1], [2]])
  assert_eq(components.map(component => component.entry_nodes), [[0], [1], [2]])
  assert_eq(components.map(component => component.cyclic), [false, true, false])
  assert_true(components.all(component => !component.multiple_entries))
}

///|
test "natural loops merge latches and point to the smallest enclosing loop" {
  let graph : Graph = {
    nodes: ["entry", "outer", "inner", "body", "latchA", "latchB", "exit"],
    edges: [
      (5, 1),
      (2, 5),
      (3, 2),
      (1, 6),
      (4, 1),
      (2, 4),
      (2, 3),
      (1, 2),
      (0, 1),
    ],
    entry: 0,
    exits: [6],
  }
  let immediate = [None, Some(0), Some(1), Some(2), Some(2), Some(2), Some(1)]
  let (loops, components) = graph_structure(
    graph,
    structure_tree(graph, immediate),
  )
  assert_eq(loops.map(natural_loop => natural_loop.header), [1, 2])
  assert_eq(loops[0].latches, [4, 5])
  assert_eq(loops[0].members, [1, 2, 3, 4, 5])
  assert_eq(loops[0].parent, None)
  assert_eq(loops[1].latches, [3])
  assert_eq(loops[1].members, [2, 3])
  assert_eq(loops[1].parent, Some(0))
  assert_eq(components.map(component => component.members), [
    [0],
    [1, 2, 3, 4, 5],
    [6],
  ])
  assert_eq(components[1].entry_nodes, [1])
  assert_true(components[1].cyclic && !components[1].multiple_entries)
}

///|
test "multiple-entry SCC has no invented dominating loop header" {
  let graph : Graph = {
    nodes: ["entry", "left", "right", "join", "exit"],
    edges: [(0, 2), (3, 4), (3, 2), (2, 3), (1, 3), (3, 1), (0, 1)],
    entry: 0,
    exits: [4],
  }
  let (loops, components) = graph_structure(
    graph,
    structure_tree(graph, [None, Some(0), Some(0), Some(0), Some(3)]),
  )
  assert_true(loops.is_empty())
  assert_eq(components.map(component => component.members), [
    [0],
    [1, 2, 3],
    [4],
  ])
  assert_eq(components[1].entry_nodes, [1, 2])
  assert_true(components[1].cyclic && components[1].multiple_entries)
}

///|
test "graph entry counts as the entry of a cyclic component" {
  let graph : Graph = {
    nodes: ["root", "body", "exit"],
    edges: [(1, 0), (0, 2), (0, 1)],
    entry: 0,
    exits: [2],
  }
  let (loops, components) = graph_structure(
    graph,
    structure_tree(graph, [None, Some(0), Some(0)]),
  )
  assert_eq(loops[0].header, 0)
  assert_eq(loops[0].members, [0, 1])
  assert_eq(components[0].members, [0, 1])
  assert_eq(components[0].entry_nodes, [0])
  assert_true(components[0].cyclic && !components[0].multiple_entries)
}

///|
test "three nested loops choose the nearest containing parent" {
  let graph : Graph = {
    nodes: [
      "entry", "outer", "middle", "inner", "innerLatch", "middleLatch", "outerLatch",
      "exit",
    ],
    edges: [
      (0, 1),
      (1, 2),
      (1, 7),
      (2, 3),
      (2, 6),
      (3, 4),
      (3, 5),
      (4, 3),
      (5, 2),
      (6, 1),
    ],
    entry: 0,
    exits: [7],
  }
  let (loops, _) = graph_structure(
    graph,
    structure_tree(graph, [
      None,
      Some(0),
      Some(1),
      Some(2),
      Some(3),
      Some(3),
      Some(2),
      Some(1),
    ]),
  )
  assert_eq(loops.map(natural_loop => natural_loop.header), [1, 2, 3])
  assert_eq(loops[0].members, [1, 2, 3, 4, 5, 6])
  assert_eq(loops[1].members, [2, 3, 4, 5])
  assert_eq(loops[2].members, [3, 4])
  assert_eq(loops[0].parent, None)
  assert_eq(loops[1].parent, Some(0))
  assert_eq(loops[2].parent, Some(1))
}
