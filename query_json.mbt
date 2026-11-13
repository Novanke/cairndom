///|
let max_batch_queries : Int32 = 4096

///|
let max_query_operands : Int32 = 16384

///|
priv enum BatchQuery {
  Dominates(Int32, Int32)
  NearestCommon(Array[Int32])
}

///|
fn parse_batch_query(
  value : Json,
  names : Map[String, Int32],
) -> (BatchQuery, Int32) raise GraphError {
  let object = fields(value, ["operation", "ancestor", "node", "nodes"])
  match text(required(object, "operation")) {
    "dominates" => {
      let object = fields(value, ["operation", "ancestor", "node"])
      let ancestor = node_index(names, required(object, "ancestor"))
      let node = node_index(names, required(object, "node"))
      (Dominates(ancestor, node), 2)
    }
    "nearest_common" => {
      let object = fields(value, ["operation", "nodes"])
      let nodes = []
      for value in items(required(object, "nodes"), max_nodes) {
        nodes.push(node_index(names, value))
      }
      (NearestCommon(nodes), nodes.length())
    }
    _ => raise Invalid("query operation must be dominates or nearest_common")
  }
}

///|
fn batch_answer_json(
  query : BatchQuery,
  graph : Graph,
  index : DominanceIndex,
) -> Json raise GraphError {
  match query {
    Dominates(ancestor, node) =>
      Json::object(
        Map([
          ("operation", Json::string("dominates")),
          ("ancestor", Json::string(graph.nodes[ancestor])),
          ("node", Json::string(graph.nodes[node])),
          ("dominates", Json::boolean(index.dominates(ancestor, node))),
        ]),
      )
    NearestCommon(nodes) => {
      let common = index.nearest_common(nodes)
      Json::object(
        Map([
          ("operation", Json::string("nearest_common")),
          ("nodes", names_json(graph, nodes)),
          ("found", Json::boolean(common is Some(_))),
          ("node", parent_json(graph, common)),
          ("virtual_exit", Json::boolean(common == Some(graph.nodes.length()))),
        ]),
      )
    }
  }
}

///|
/// Answer a named cairndom.queries.v1 batch with one immutable tree index.
/// Every query is checked before execution. Only original graph IDs are valid
/// operands; a common virtual postdominator is reported with found=true,
/// node=null and virtual_exit=true. Empty or unreachable sets have found=false.
/// Input is limited to 2 MiB, 4096 queries and 16384 total node operands; each
/// nearest_common list may contain at most 512 IDs, preserving order/duplicates.
pub fn query_json_text(input : String) -> String raise GraphError {
  if input.length() > 2_097_152 {
    raise Invalid("query JSON exceeds 2 MiB")
  }
  let value = @json.parse(
    input,
    max_nesting_depth=12,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise Invalid("invalid JSON, repeated key or excessive nesting")
  }
  let object = fields(value, ["schema", "graph", "tree", "queries"])
  if text(required(object, "schema")) != "cairndom.queries.v1" {
    raise Invalid("schema must be cairndom.queries.v1")
  }
  let tree_kind = text(required(object, "tree"))
  if tree_kind != "forward" && tree_kind != "post" {
    raise Invalid("query tree must be forward or post")
  }
  let graph = parse_graph(required(object, "graph").stringify())
  let names : Map[String, Int32] = Map([])
  for node, name in graph.nodes {
    names[name] = node
  }
  let queries : Array[BatchQuery] = []
  let mut operands = 0
  for value in items(required(object, "queries"), max_batch_queries) {
    let (query, count) = parse_batch_query(value, names)
    if count > max_query_operands - operands {
      raise Invalid("query limit is at most 16384 node operands")
    }
    operands += count
    queries.push(query)
  }
  let tree = if tree_kind == "forward" {
    dominators(graph)
  } else {
    analyze(graph).post
  }
  let index = index_dominance(tree)
  let answers = []
  for query in queries {
    answers.push(batch_answer_json(query, graph, index))
  }
  let output = Json::object(
    Map([
      ("schema", Json::string("cairndom.answers.v1")),
      ("tree", Json::string(tree_kind)),
      (
        "scope",
        Json::string(
          if tree_kind == "forward" {
            "entry_reachable"
          } else {
            "finite_paths_reaching_declared_exits"
          },
        ),
      ),
      ("entry", Json::string(graph.nodes[graph.entry])),
      ("answers", Json::array(answers)),
    ]),
  ).stringify(indent=2)
  if output.length() > 16_777_216 {
    raise Invalid("query answer JSON exceeds 16 MiB")
  }
  output
}
