///|
fn fields(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise GraphError {
  let object = match value {
    Object(object) => object
    _ => raise Invalid("expected a JSON object")
  }
  for key, _ in object {
    if !allowed.contains(key) {
      raise Invalid("unknown field: " + key)
    }
  }
  object
}

///|
fn text(value : Json) -> String raise GraphError {
  match value {
    String(value) => value
    _ => raise Invalid("expected a node ID string")
  }
}

///|
fn required(object : Map[String, Json], name : String) -> Json raise GraphError {
  match object.get(name) {
    Some(value) => value
    None => raise Invalid("missing field: " + name)
  }
}

///|
fn items(value : Json, limit : Int32) -> Array[Json] raise GraphError {
  match value {
    Array(values) if values.length() <= limit => values
    _ => raise Invalid("expected a bounded JSON array")
  }
}

///|
fn node_index(
  names : Map[String, Int32],
  value : Json,
) -> Int32 raise GraphError {
  let name = text(value)
  match names.get(name) {
    Some(index) => index
    None => raise Invalid("unknown node: " + name)
  }
}

///|
/// Parse cairndom.graph.v1 with string node IDs and strict JSON keys.
pub fn parse_graph(input : String) -> Graph raise GraphError {
  let (graph, _) = parse_graph_with_names(input)
  graph
}

///|
fn parse_graph_with_names(
  input : String,
) -> (Graph, Map[String, Int32]) raise GraphError {
  if input.length() > 2_097_152 {
    raise Invalid("graph JSON exceeds 2 MiB")
  }
  let value = @json.parse(
    input,
    max_nesting_depth=8,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise Invalid("invalid JSON, repeated key or excessive nesting")
  }
  decode_graph(value)
}

///|
fn decode_graph(value : Json) -> (Graph, Map[String, Int32]) raise GraphError {
  let object = fields(value, ["schema", "nodes", "edges", "entry", "exits"])
  if text(required(object, "schema")) != "cairndom.graph.v1" {
    raise Invalid("schema must be cairndom.graph.v1")
  }
  let nodes = []
  let names : Map[String, Int32] = Map([])
  for value in items(required(object, "nodes"), max_nodes) {
    let name = text(value)
    if !valid_id(name) || names.contains(name) {
      raise Invalid("invalid or duplicate node ID: " + name)
    }
    names[name] = nodes.length()
    nodes.push(name)
  }
  let edges = []
  for value in items(required(object, "edges"), max_edges) {
    let edge = items(value, 2)
    if edge.length() != 2 {
      raise Invalid("each edge must contain two node IDs")
    }
    edges.push((node_index(names, edge[0]), node_index(names, edge[1])))
  }
  let exits = []
  for value in items(required(object, "exits"), max_nodes) {
    exits.push(node_index(names, value))
  }
  let graph : Graph = {
    nodes,
    edges,
    exits,
    entry: node_index(names, required(object, "entry")),
  }
  validate_graph_connections(graph)
  (graph, names)
}

///|
fn decode_nested_graph(
  value : Json,
) -> (Graph, Map[String, Int32]) raise GraphError {
  // The outer parser already rejected recursive duplicate keys. A successfully
  // decoded graph has bounded arrays of validated ASCII IDs and cannot exceed
  // the legacy compact-text size or depth limits. Preserve their precedence
  // over schema errors on malformed input by using the old wire path there.
  decode_graph(value) catch {
    Invalid(_) => parse_graph_with_names(value.stringify())
  }
}

///|
fn names_json(graph : Graph, nodes : Array[Int32]) -> Json {
  Json::array(nodes.map(index => Json::string(graph.nodes[index])))
}

///|
fn parent_json(graph : Graph, parent : Int32?) -> Json {
  match parent {
    Some(node) if node < graph.nodes.length() => Json::string(graph.nodes[node])
    _ => Json::null()
  }
}

///|
fn analysis_node_value(result : Analysis, index : Int32) -> Json {
  let graph = result.graph
  let post_parent = result.post.immediate[index]
  Json::object(
    Map([
      ("id", Json::string(graph.nodes[index])),
      ("reachable", Json::boolean(result.forward.reachable[index])),
      ("can_reach_exit", Json::boolean(result.post.reachable[index])),
      (
        "immediate_dominator",
        parent_json(graph, result.forward.immediate[index]),
      ),
      ("dominance_frontier", names_json(graph, result.forward.frontiers[index])),
      ("immediate_postdominator", parent_json(graph, post_parent)),
      (
        "postdominator_is_virtual_exit",
        Json::boolean(post_parent == Some(graph.nodes.length())),
      ),
      (
        "control_dependencies",
        names_json(graph, result.control_dependencies[index]),
      ),
    ]),
  )
}

///|
fn analysis_loop_value(result : Analysis, index : Int32) -> Json {
  let graph = result.graph
  let natural_loop = result.loops[index]
  Json::object(
    Map([
      ("header", Json::string(graph.nodes[natural_loop.header])),
      ("latches", names_json(graph, natural_loop.latches)),
      ("members", names_json(graph, natural_loop.members)),
      (
        "parent_header",
        match natural_loop.parent {
          Some(parent) => Json::string(graph.nodes[result.loops[parent].header])
          None => Json::null()
        },
      ),
    ]),
  )
}

///|
fn analysis_component_value(result : Analysis, index : Int32) -> Json {
  let graph = result.graph
  let component = result.components[index]
  Json::object(
    Map([
      ("members", names_json(graph, component.members)),
      ("entry_nodes", names_json(graph, component.entry_nodes)),
      ("cyclic", Json::boolean(component.cyclic)),
      ("multiple_entries", Json::boolean(component.multiple_entries)),
    ]),
  )
}

///|
fn analysis_report_fields(
  result : Analysis,
  schema : String,
) -> Array[(String, Json)] {
  [
    ("schema", Json::string(schema)),
    ("entry", Json::string(result.graph.nodes[result.graph.entry])),
    ("exits", names_json(result.graph, result.graph.exits)),
    (
      "postdominator_scope",
      Json::string("finite_paths_reaching_declared_exits"),
    ),
  ]
}

///|
fn analysis_report_sections(
  result : Analysis,
) -> Array[(String, Int32, (Int32) -> Json)] {
  [
    (
      "nodes",
      result.graph.nodes.length(),
      index => analysis_node_value(result, index),
    ),
    (
      "natural_loops",
      result.loops.length(),
      index => analysis_loop_value(result, index),
    ),
    (
      "components",
      result.components.length(),
      index => analysis_component_value(result, index),
    ),
  ]
}

///|
fn analysis_witness_value(graph : Graph, witness : ControlWitness) -> Json {
  Json::object(
    Map([
      ("controller", Json::string(graph.nodes[witness.controller])),
      ("successor", Json::string(graph.nodes[witness.successor])),
      ("dependent", Json::string(graph.nodes[witness.dependent])),
    ]),
  )
}

///|
fn analysis_report_value(result : Analysis) -> Json {
  let report = Map(analysis_report_fields(result, "cairndom.analysis.v1"))
  for (name, count, row) in analysis_report_sections(result) {
    report[name] = Json::array(Array::makei(count, row))
  }
  let (witnesses, complete) = bounded_control_witnesses_of(result)
  report["control_witnesses_complete"] = Json::boolean(complete)
  report["control_witness_limit"] = Json::number(
    max_control_witnesses.to_double(),
  )
  report["control_witnesses"] = Json::array(
    witnesses.map(witness => analysis_witness_value(result.graph, witness)),
  )
  Json::object(report)
}

///|
/// Report indices as original string IDs, with explicit reachability and exit
/// scope. A virtual postdominator parent is distinguished from no exit path.
pub fn analysis_json_text(result : Analysis) -> String {
  analysis_report_value(result).stringify(indent=2)
}

///|
/// A DOT graph showing original edges and dashed immediate-dominator edges.
/// Node IDs use the validated ASCII identifier grammar.
pub fn analysis_dot(result : Analysis) -> String {
  render_dominance_dot(result.graph, result.forward.parent_tree())
}

///|
/// Validate a graph and export DOT with entry reachability and immediate
/// dominators. Output matches analysis_dot(analyze(graph)).
pub fn graph_dot(input : Graph) -> String raise GraphError {
  validate_graph(input)
  let (succ, pred) = adjacency(input)
  render_dominance_dot(input, compute_dominator_tree(succ, pred, input.entry))
}

///|
fn render_dominance_dot(graph : Graph, forward : DominatorTree) -> String {
  let out = StringBuilder()
  out.write_string("digraph CairnDom {\n  rankdir=TB;\n")
  for index, name in graph.nodes {
    let style = if forward.reachable[index] { "solid" } else { "dotted" }
    out.write_string("  \"\{name}\" [style=\{style}];\n")
  }
  for (from, to) in graph.edges {
    out.write_string("  \"\{graph.nodes[from]}\" -> \"\{graph.nodes[to]}\";\n")
  }
  for index, parent in forward.immediate {
    if parent is Some(dominator) {
      out.write_string(
        "  \"\{graph.nodes[dominator]}\" -> \"\{graph.nodes[index]}\" [style=dashed,color=blue,label=\"idom\"];\n",
      )
    }
  }
  out.write_string("}\n")
  out.to_string()
}
