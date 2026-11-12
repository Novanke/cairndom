///|
fn program_variable_indices(
  names : Map[String, Int32],
  value : Json,
) -> Array[Int32] raise GraphError {
  let result = []
  for value in items(value, max_variables) {
    let name = text(value)
    match names.get(name) {
      Some(index) => result.push(index)
      None => raise Invalid("unknown variable: " + name)
    }
  }
  result
}

///|
/// Parse cairndom.program.v1 with a complete nested cairndom.graph.v1 graph.
/// Each listed block requires node, defines and uses. Omitted nodes have empty
/// facts; duplicate blocks, facts, IDs and unknown fields are rejected. Uses
/// retain the FlowProgram convention of occurring before local definitions.
pub fn parse_program(input : String) -> FlowProgram raise GraphError {
  if input.length() > 2_097_152 {
    raise Invalid("program JSON exceeds 2 MiB")
  }
  let value = @json.parse(
    input,
    max_nesting_depth=12,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise Invalid("invalid JSON, repeated key or excessive nesting")
  }
  let object = fields(value, ["schema", "graph", "variables", "blocks"])
  if text(required(object, "schema")) != "cairndom.program.v1" {
    raise Invalid("schema must be cairndom.program.v1")
  }
  let graph = parse_graph(required(object, "graph").stringify())
  let variables = []
  let variable_names : Map[String, Int32] = Map([])
  for value in items(required(object, "variables"), max_variables) {
    let name = text(value)
    if !valid_id(name) || variable_names.contains(name) {
      raise Invalid("invalid or duplicate variable ID: " + name)
    }
    variable_names[name] = variables.length()
    variables.push(name)
  }
  let node_names : Map[String, Int32] = Map([])
  for node, name in graph.nodes {
    node_names[name] = node
  }
  let n = graph.nodes.length()
  let definitions : Array[Array[Int32]] = Array::makei(n, _ => [])
  let uses : Array[Array[Int32]] = Array::makei(n, _ => [])
  let listed = Array::make(n, false)
  let mut associations = 0
  for value in items(required(object, "blocks"), n) {
    let block = fields(value, ["node", "defines", "uses"])
    let node = node_index(node_names, required(block, "node"))
    if listed[node] {
      raise Invalid("duplicate block node: " + graph.nodes[node])
    }
    listed[node] = true
    let defined = program_variable_indices(
      variable_names,
      required(block, "defines"),
    )
    let used = program_variable_indices(variable_names, required(block, "uses"))
    let count = defined.length() + used.length()
    if count > max_program_associations - associations {
      raise Invalid(
        "program limit is at most 16384 definition/use associations",
      )
    }
    associations += count
    definitions[node] = defined
    uses[node] = used
  }
  let program = { graph, variables, definitions, uses, }
  validate_program(program)
  program
}

///|
/// Serialize a validated FlowProgram as cairndom.program.v1. Every graph node
/// gets a block in node order, and facts follow declared variable order. Sorting
/// uses private copies and never mutates the caller's rows. Exports exceeding
/// the parser's 2 MiB input limit are rejected so successful exports round trip.
pub fn program_json_text(program : FlowProgram) -> String raise GraphError {
  validate_program(program)
  let blocks = []
  for node, name in program.graph.nodes {
    let defined = program.definitions[node].copy()
    let used = program.uses[node].copy()
    defined.sort()
    used.sort()
    blocks.push(
      Json::object(
        Map([
          ("node", Json::string(name)),
          (
            "defines",
            Json::array(
              defined.map(variable => Json::string(program.variables[variable])),
            ),
          ),
          (
            "uses",
            Json::array(
              used.map(variable => Json::string(program.variables[variable])),
            ),
          ),
        ]),
      ),
    )
  }
  let output = Json::object(
    Map([
      ("schema", Json::string("cairndom.program.v1")),
      ("graph", graph_json_value(program.graph)),
      (
        "variables",
        Json::array(program.variables.map(name => Json::string(name))),
      ),
      ("blocks", Json::array(blocks)),
    ]),
  ).stringify(indent=2)
  if output.length() > 2_097_152 {
    raise Invalid("serialized program JSON exceeds 2 MiB")
  }
  output
}
