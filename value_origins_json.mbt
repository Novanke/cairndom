///|
/// Serialize the saved, complete result using original block/variable IDs.
/// Inspection-copy edits cannot change this report. Output is limited to 16 MiB.
pub fn ValueOrigins::json_text(self : Self) -> String raise GraphError {
  let program = self.program
  let graph = program.graph
  let unreachable_nodes = []
  for node, yes in self.reachable {
    if !yes {
      unreachable_nodes.push(node)
    }
  }
  let mut relations = 0
  let uses = self.origins.map(origin => {
    relations += origin.definitions.length()
    if origin.requires_entry_value {
      relations += 1
    }
    Json::object(
      Map([
        ("node", Json::string(graph.nodes[origin.node])),
        ("variable", Json::string(program.variables[origin.variable])),
        ("definition_blocks", names_json(graph, origin.definitions)),
        ("requires_entry_value", Json::boolean(origin.requires_entry_value)),
      ]),
    )
  })
  let output = Json::object(
    Map([
      ("schema", Json::string("cairndom.value-origins.v1")),
      ("entry", Json::string(graph.nodes[graph.entry])),
      ("scope", Json::string("entry_reachable_all_paths")),
      ("use_convention", Json::string("before_local_definition")),
      ("status", Json::string("possible_origins")),
      ("variables", Json::array(program.variables.map(Json::string))),
      ("unreachable_blocks", names_json(graph, unreachable_nodes)),
      ("uses", Json::array(uses)),
      ("source_relation_count", Json::number(relations.to_double())),
      (
        "source_relation_limit",
        Json::number(max_value_origin_relations.to_double()),
      ),
      (
        "incoming_value_semantics",
        Json::string(
          "An incoming value can reach this use; the caller must supply a parameter or initial value, or apply its own missing-initialization rules. This is not proof of an initialization error.",
        ),
      ),
    ]),
  ).stringify(indent=2)
  if output.length() > 16_777_216 {
    raise Invalid("value-origin JSON exceeds 16 MiB")
  }
  output
}
