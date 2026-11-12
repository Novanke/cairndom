///|
/// Direct edge closure, with no use of dominance trees or natural-loop members.
fn boundary_paths_without(
  graph : Graph,
  root : Int32,
  blocked : Int32,
) -> Array[Bool] {
  let found = Array::make(graph.nodes.length(), false)
  if root == blocked {
    return found
  }
  found[root] = true
  let mut changed = true
  while changed {
    changed = false
    for (from, to) in graph.edges {
      if found[from] && to != blocked && !found[to] {
        found[to] = true
        changed = true
      }
    }
  }
  found
}

///|
fn boundary_definition(graph : Graph) -> Array[LoopBoundary] {
  let n = graph.nodes.length()
  let reachable = boundary_paths_without(graph, graph.entry, -1)
  let expected : Array[LoopBoundary] = []
  for header in 0..<n {
    if !reachable[header] {
      continue
    }
    let avoiding_header = boundary_paths_without(graph, graph.entry, header)
    let dominated = Array::makei(n, node => {
      reachable[node] && !avoiding_header[node]
    })
    let latches = []
    for node in 0..<n {
      if dominated[node] && graph.edges.contains((node, header)) {
        latches.push(node)
      }
    }
    if latches.is_empty() {
      continue
    }
    let members = Array::make(n, false)
    members[header] = true
    for node in 0..<n {
      if node != header && dominated[node] {
        // A member can reach a latch along a path that avoids the header.
        // This forward path definition is independent of predecessor closure.
        let paths = boundary_paths_without(graph, node, header)
        members[node] = latches.any(latch => paths[latch])
      }
    }
    let entering_edges = []
    let leaving_edges = []
    let back_edges = []
    for from in 0..<n {
      for to in 0..<n {
        if !reachable[from] ||
          !reachable[to] ||
          !graph.edges.contains((from, to)) {
          continue
        }
        if !members[from] && members[to] {
          entering_edges.push((from, to))
        }
        if members[from] && !members[to] {
          leaving_edges.push((from, to))
        }
        if to == header && latches.contains(from) {
          back_edges.push((from, to))
        }
      }
    }
    expected.push({ header, entering_edges, leaving_edges, back_edges, })
  }
  expected
}

///|
fn boundary_nested_graph() -> Graph {
  {
    nodes: [
      "entry", "outer", "inner", "body", "latchA", "latchB", "exit", "dead",
    ],
    edges: [
      (7, 2),
      (5, 1),
      (2, 5),
      (3, 2),
      (7, 7),
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
}

///|
test "nested loop boundaries retain inner exits to the outer loop and merged latches" {
  let graph = boundary_nested_graph()
  let boundaries = loop_boundaries(graph)
  assert_eq(boundaries, [
    {
      header: 1,
      entering_edges: [(0, 1)],
      leaving_edges: [(1, 6)],
      back_edges: [(4, 1), (5, 1)],
    },
    {
      header: 2,
      entering_edges: [(1, 2)],
      leaving_edges: [(2, 4), (2, 5)],
      back_edges: [(3, 2)],
    },
  ])
  assert_eq(boundaries, boundary_definition(graph))
  assert_eq(boundaries, loop_boundaries_of(analyze(graph)))
  let reordered = {
    ..graph,
    edges: Array::makei(graph.edges.length(), index => {
      graph.edges[graph.edges.length() - 1 - index]
    }),
  }
  assert_eq(boundaries, loop_boundaries(reordered))
}

///|
test "entry loops have no synthetic entering edge and self-loops remain back edges" {
  let graph : Graph = {
    nodes: ["entry", "body", "exit", "dead"],
    edges: [(3, 0), (1, 0), (0, 2), (0, 1), (0, 0)],
    entry: 0,
    exits: [2],
  }
  assert_eq(loop_boundaries(graph), [
    {
      header: 0,
      entering_edges: [],
      leaving_edges: [(0, 2)],
      back_edges: [(0, 0), (1, 0)],
    },
  ])
  assert_eq(loop_boundaries(graph), boundary_definition(graph))
  let permanent : Graph = {
    nodes: ["entry", "dead"],
    edges: [(1, 0), (0, 0)],
    entry: 0,
    exits: [],
  }
  assert_eq(loop_boundaries(permanent), [
    { header: 0, entering_edges: [], leaving_edges: [], back_edges: [(0, 0)], },
  ])
  assert_eq(loop_boundaries(permanent), boundary_definition(permanent))
}

///|
test "irreducible cycles without natural loops have no invented loop boundaries" {
  let graph : Graph = {
    nodes: ["entry", "left", "right", "join", "exit"],
    edges: [(0, 2), (3, 4), (3, 2), (2, 3), (1, 3), (3, 1), (0, 1)],
    entry: 0,
    exits: [4],
  }
  assert_eq(loop_boundaries(graph), [])
  assert_eq(loop_boundaries(graph), boundary_definition(graph))
}

///|
test "boundary edge arrays are owned independently of input and analysis arrays" {
  let graph = boundary_nested_graph()
  let analysis = analyze(graph)
  let boundaries = loop_boundaries_of(analysis)
  let independent = loop_boundaries(graph)
  graph.edges.clear()
  graph.nodes[0] = "changed"
  graph.exits.clear()
  analysis.graph.edges.clear()
  analysis.loops[0].members.clear()
  analysis.loops[0].latches.clear()
  for node in 0..<analysis.forward.reachable.length() {
    analysis.forward.reachable[node] = false
  }
  assert_eq(boundaries, independent)
  boundaries[0].entering_edges.clear()
  boundaries[0].leaving_edges.clear()
  boundaries[0].back_edges.clear()
  assert_eq(independent[0].entering_edges, [(0, 1)])
  assert_eq(independent[0].leaving_edges, [(1, 6)])
  assert_eq(independent[0].back_edges, [(4, 1), (5, 1)])
  assert_eq(boundaries[1], independent[1])
}

///|
test "loop boundary API validates typed graphs" {
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
      ignore(loop_boundaries(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "all three-node graph boundaries match node-removal and forward-path definitions" {
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
    for entry in 0..<3 {
      let graph : Graph = {
        nodes: ["n0", "n1", "n2"],
        edges,
        entry,
        exits: [],
      }
      assert_eq(loop_boundaries_of(analyze(graph)), boundary_definition(graph))
    }
  }
}

///|
test "dense nested loops reject global boundary edge expansion before returning arrays" {
  let edges = []
  for node in 0..<119 {
    edges.push((node, node + 1))
  }
  for from in 0..<120 {
    for to in 0..<from {
      edges.push((from, to))
    }
  }
  let graph : Graph = {
    nodes: Array::makei(120, node => "n" + node.to_string()),
    edges,
    entry: 0,
    exits: [],
  }
  assert_eq(graph.edges.length(), 7259)
  let analysis = analyze(graph)
  assert_eq(analysis.loops.length(), 119)
  let mut expected_pairs = 0
  for header, natural_loop in analysis.loops {
    assert_eq(natural_loop.header, header)
    assert_eq(
      natural_loop.members,
      Array::makei(120 - header, offset => header + offset),
    )
    // For members header..119: one entering chain edge except at entry;
    // (120-header)*header backward edges leave; 119-header return to header.
    expected_pairs += (if header == 0 { 0 } else { 1 }) +
      (120 - header) * header +
      119 -
      header
  }
  assert_eq(expected_pairs, 295119)
  let internal_error = try {
    ignore(loop_boundaries_of(analysis))
    ""
  } catch {
    Invalid(message) => message
  }
  assert_eq(internal_error, "loop boundary edge limit of 65536 exceeded")
  let public_error = try {
    ignore(loop_boundaries(graph))
    ""
  } catch {
    Invalid(message) => message
  }
  assert_eq(public_error, "loop boundary edge limit of 65536 exceeded")
}
