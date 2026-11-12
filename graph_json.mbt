///|
// Requires a graph already checked by snapshot_graph.
fn graph_json_value(graph : Graph) -> Json {
  Json::object(
    Map([
      ("schema", Json::string("cairndom.graph.v1")),
      ("nodes", Json::array(graph.nodes.map(Json::string))),
      ("entry", Json::string(graph.nodes[graph.entry])),
      ("exits", names_json(graph, graph.exits)),
      (
        "edges",
        Json::array(
          graph.edges.map(edge => {
            let (from, to) = edge
            Json::array([
              Json::string(graph.nodes[from]),
              Json::string(graph.nodes[to]),
            ])
          }),
        ),
      ),
    ]),
  )
}

///|
/// Serialize a validated graph to cairndom.graph.v1. Node, edge and exit order
/// is preserved so SDK-built/edited graphs can be saved and consumed by the CLI.
pub fn graph_json_text(graph : Graph) -> String raise GraphError {
  graph_json_value(snapshot_graph(graph)).stringify(indent=2)
}
