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
      ({ ..graph, exits: [0, 0], }, "invalid or duplicate exit"),
      ({ ..graph, exits: [0, 2], }, "invalid or duplicate exit"),
      ({ ..graph, edges: [(1, 0), (0, 1), (1, 0), (0, 2)], }, "duplicate edge"),
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
test "directed edge validation separates sources and destination words" {
  let graph : Graph = {
    nodes: Array::makei(512, i => "n" + i.to_string()),
    entry: 0,
    exits: [63],
    edges: [(0, 31), (0, 32), (0, 63), (0, 511), (511, 31), (511, 511)],
  }
  assert_eq(parse_graph(graph_json_text(graph)).edges, graph.edges)
  let last = graph.edges.length()
  graph.edges.push((0, 0))
  for target in [31, 32, 63, 511] {
    graph.edges[last] = (0, target)
    let error = try {
      ignore(graph_json_text(graph))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(error, "duplicate edge")
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

///|
test "JSON depth limit counts containers outside quoted strings" {
  let value = "quote \" and backslash \\ [[[{{{]]]"
  let string = Json::string(value).stringify()
  let at_limit = "{\"x\":" + "[".repeat(7) + string + "]".repeat(7) + "}"
  assert_eq(parse_bounded_json(at_limit, 8).stringify(), at_limit)
  for
    input in [
      "[" + at_limit + "]",
      "{\"x\":" + "[".repeat(8) + "]".repeat(8) + "}",
      (
        #|{"x":1,"\u0078":2}
      ),
    ] {
    let detail = try {
      ignore(parse_graph(input))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(detail, "invalid JSON, repeated key or excessive nesting")
  }
}
