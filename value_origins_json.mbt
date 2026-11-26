///|
fn value_origin_row(program : FlowProgram, origin : UseOrigins) -> Json {
  Json::object(
    Map([
      ("node", Json::string(program.graph.nodes[origin.node])),
      ("variable", Json::string(program.variables[origin.variable])),
      ("definition_blocks", names_json(program.graph, origin.definitions)),
      ("requires_entry_value", Json::boolean(origin.requires_entry_value)),
    ]),
  )
}

///|
/// Serialize one declared use by its original block and variable IDs.
/// The origin is the matching full-report row, or null for an unreachable use.
/// Unknown IDs and undeclared uses are errors. The full-report cap is independent.
pub fn trace_use_json_text(
  program : FlowProgram,
  node : String,
  variable : String,
) -> String raise GraphError {
  validate_program(program)
  let node_index = match program.graph.nodes.search(node) {
    Some(index) => index
    None => raise Invalid("unknown value-origin node: " + node)
  }
  let variable_index = match program.variables.search(variable) {
    Some(index) => index
    None => raise Invalid("unknown value-origin variable: " + variable)
  }
  let origin = match trace_use_checked(program, node_index, variable_index) {
    Some(result) => value_origin_row(program, result)
    None => Json::null()
  }
  Json::object(
    Map([
      ("schema", Json::string("cairndom.use-origin.v1")),
      ("node", Json::string(node)),
      ("variable", Json::string(variable)),
      ("origin", origin),
    ]),
  ).stringify(indent=2)
}

///|
// Reuse quoted identifiers in full reports. Emit the same fields and
// indentation as value_origin_row, with one temporary row at a time.
fn BoundedJsonWriter::value_origin_rows(
  self : Self,
  saved : ValueOrigins,
) -> Unit raise GraphError {
  self.field("uses")
  self.append("[")
  if !saved.origins.is_empty() {
    let names = saved.program.graph.nodes.map(name => {
      Json::string(name).stringify()
    })
    let variables = saved.program.variables.map(name => {
      Json::string(name).stringify()
    })
    let definition_lines = names.map(name => "\n        \{name}")
    let row = StringBuilder()
    for index, origin in saved.origins {
      if index > 0 {
        self.append(",")
      }
      row.reset()
      row.write_string(
        "\n    {\n      \"node\": \{names[origin.node]},\n      \"variable\": \{variables[origin.variable]},\n      \"definition_blocks\": [",
      )
      for position, definition in origin.definitions {
        if position > 0 {
          row.write_string(",")
        }
        row.write_string(definition_lines[definition])
      }
      if !origin.definitions.is_empty() {
        row.write_string("\n      ")
      }
      let incoming = if origin.requires_entry_value { "true" } else { "false" }
      row.write_string("],\n      \"requires_entry_value\": \{incoming}\n    }")
      self.append(row.to_string()[:])
    }
    self.append("\n  ")
  }
  self.append("]")
}

///|
/// Serialize the saved, complete result using original block/variable IDs.
/// Inspection-copy edits cannot change this report. Output is limited to 16 MiB.
pub fn ValueOrigins::json_text(self : Self) -> String raise GraphError {
  let program = self.program
  let graph = program.graph
  let out : BoundedJsonWriter = {
    buffer: StringBuilder(),
    remaining: max_report_json_bytes,
    overflow_detail: "value-origin JSON exceeds 16 MiB",
  }
  let unreachable_nodes = []
  for node, yes in self.reachable {
    if !yes {
      unreachable_nodes.push(node)
    }
  }
  let header = [
    ("schema", Json::string("cairndom.value-origins.v1")),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("scope", Json::string("entry_reachable_all_paths")),
    ("use_convention", Json::string("before_local_definition")),
    ("status", Json::string("possible_origins")),
    ("variables", Json::array(program.variables.map(Json::string))),
    ("unreachable_blocks", names_json(graph, unreachable_nodes)),
  ]
  out.append("{\n")
  for (name, value) in header {
    out.field(name)
    out.value(value, "  ")
    out.append(",\n")
  }
  out.value_origin_rows(self)
  let footer = [
    (
      "source_relation_count",
      Json::number(self.source_relation_count.to_double()),
    ),
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
  ]
  for (name, value) in footer {
    out.append(",\n")
    out.field(name)
    out.value(value, "  ")
  }
  out.append("\n}")
  out.buffer.to_string()
}
