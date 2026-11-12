///|
test "graph wire roundtrip retains nonzero entry and original edge order" {
  for
    graph in [
      {
        nodes: ["late", "entry", "left", "right"],
        entry: 1,
        exits: [3, 0],
        edges: [(1, 2), (2, 0), (1, 3)],
      },
      {
        nodes: ["entry", "loop"],
        entry: 0,
        exits: [],
        edges: [(1, 1), (0, 1)],
      },
      { nodes: ["single"], entry: 0, exits: [0], edges: [], },
    ] {
    let encoded = graph_json_text(graph)
    let decoded = parse_graph(encoded)
    assert_eq(decoded.nodes, graph.nodes)
    assert_eq(decoded.entry, graph.entry)
    assert_eq(decoded.exits, graph.exits)
    assert_eq(decoded.edges, graph.edges)
    assert_eq(graph_json_text(decoded), encoded)
    assert_eq(
      analysis_json_text(analyze(decoded)),
      analysis_json_text(analyze(graph)),
    )
  }
}

///|
test "graph export rejects bad typed indices before serializing" {
  let graph : Graph = {
    nodes: ["entry", "exit"],
    entry: 0,
    exits: [1],
    edges: [(0, 1)],
  }
  for
    bad in [
      { ..graph, entry: 2, },
      { ..graph, edges: [(0, 2)], },
      { ..graph, nodes: ["same", "same"], },
      { ..graph, exits: [0], },
    ] {
    assert_true(
      try {
        ignore(graph_json_text(bad))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  let decoded = parse_graph(graph_json_text(graph))
  decoded.nodes[0] = "changed"
  decoded.edges.clear()
  assert_eq(graph.nodes[0], "entry")
  assert_eq(graph.edges, [(0, 1)])
}
