///|
fn named_boundary_edges(
  graph : @cairn.Graph,
  edges : Array[(Int32, Int32)],
) -> Json {
  Json::array(
    edges.map(pair => {
      let (source, target) = pair
      Json::array([
        Json::string(graph.nodes[source]),
        Json::string(graph.nodes[target]),
      ])
    }),
  )
}

///|
fn loop_boundary_report(
  graph : @cairn.Graph,
  header : String,
) -> String raise @cairn.GraphError {
  let index = match graph.nodes.search(header) {
    Some(index) => index
    None => raise @cairn.Invalid("unknown loop header: " + header)
  }
  let boundary = @cairn.loop_boundary_at(graph, index)
  let (entering, leaving, back) = match boundary {
    Some(edges) => (edges.entering_edges, edges.leaving_edges, edges.back_edges)
    None => ([], [], [])
  }
  Json::object(
    Map([
      ("schema", Json::string("cairndom.loop-boundary.v1")),
      ("header", Json::string(header)),
      ("found", Json::boolean(boundary is Some(_))),
      ("entering_edges", named_boundary_edges(graph, entering)),
      ("leaving_edges", named_boundary_edges(graph, leaving)),
      ("back_edges", named_boundary_edges(graph, back)),
    ]),
  ).stringify(indent=2)
}
