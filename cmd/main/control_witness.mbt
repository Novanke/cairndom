///|
fn control_witness_report(
  graph : @cairn.Graph,
  controller : String,
  successor : String,
) -> String raise @cairn.GraphError {
  let from = match graph.nodes.search(controller) {
    Some(index) => index
    None =>
      raise @cairn.Invalid("unknown control witness controller: " + controller)
  }
  let to = match graph.nodes.search(successor) {
    Some(index) => index
    None =>
      raise @cairn.Invalid("unknown control witness successor: " + successor)
  }
  let witnesses = @cairn.control_dependence_witnesses_at(graph, from, to)
  Json::object(
    Map([
      ("schema", Json::string("cairndom.control-witness.v1")),
      ("controller", Json::string(controller)),
      ("successor", Json::string(successor)),
      (
        "dependents",
        Json::array(
          witnesses.map(witness => Json::string(graph.nodes[witness.dependent])),
        ),
      ),
    ]),
  ).stringify(indent=2)
}
