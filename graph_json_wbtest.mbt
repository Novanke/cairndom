///|
test "graph wire roundtrip retains order and owns its parsed arrays" {
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
    let saved = analyze(decoded)
    assert_eq(analysis_json_text(saved), analysis_json_text(analyze(graph)))
    let second_parse = parse_graph(encoded)
    decoded.nodes[0] = "changed"
    decoded.edges.clear()
    decoded.exits.clear()
    assert_eq(graph_json_text(graph), encoded)
    assert_eq(graph_json_text(second_parse), encoded)
    assert_eq(graph_json_text(saved.graph), encoded)
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
    (bad, detail) in [
      (
        { ..graph, entry: 2, nodes: ["same", "same"], },
        "entry index is outside the graph",
      ),
      (
        { ..graph, edges: [(0, 2)], exits: [0], },
        "edge index is outside the graph",
      ),
      (
        { ..graph, nodes: ["same", "same"], edges: [(0, 2)], },
        "invalid or duplicate node ID: same",
      ),
      ({ ..graph, exits: [0], }, "declared exits must have no outgoing edges"),
    ] {
    let error = try {
      ignore(graph_json_text(bad))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(error, detail)
  }
}

///|
test "graph wire errors keep decode and structural validation order" {
  let good =
    #|{"schema":"cairndom.graph.v1","nodes":["entry","exit"],"edges":[["entry","exit"]],"exits":["exit"],"entry":"entry"}
  let duplicate_edge = good.replace(
    old="[[\"entry\",\"exit\"]]",
    new="[[\"entry\",\"exit\"],[\"entry\",\"exit\"]]",
  )
  for
    (invalid, detail) in [
      (
        duplicate_edge.replace(old=",\"entry\":\"entry\"", new=""),
        "missing field: entry",
      ),
      (
        duplicate_edge.replace(
          old="\"entry\":\"entry\"",
          new="\"entry\":\"absent\"",
        ),
        "unknown node: absent",
      ),
      (
        duplicate_edge.replace(
          old="\"exits\":[\"exit\"]",
          new="\"exits\":[\"entry\",\"entry\"]",
        ),
        "duplicate edge",
      ),
      (
        duplicate_edge.replace(
          old="]],\"exits\"",
          new="],[\"entry\",\"absent\"]],\"exits\"",
        ),
        "unknown node: absent",
      ),
      (
        good.replace(
          old="\"nodes\":[\"entry\",\"exit\"]",
          new="\"nodes\":[\"entry\",\"entry\",\"bad id\"]",
        ),
        "invalid or duplicate node ID: entry",
      ),
    ] {
    let error = try {
      ignore(parse_graph(invalid))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(error, detail)
  }
}
