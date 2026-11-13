///|
priv enum ReferenceQuery {
  Dominates(Int32, Int32)
  NearestCommon(Array[Int32])
}

///|
fn query_tree(graph : @dom.Graph, kind : String) -> ReferenceTree {
  let (succ, pred) = adjacency(graph)
  if kind == "forward" {
    return dominance_definition(succ, pred, graph.entry)
  }
  let n = graph.nodes.length()
  let reachable = reach(succ, [graph.entry], -1, Array::make(n, true))
  let reverse = Array::makei(n + 1, _ => [])
  let reverse_pred = Array::makei(n + 1, _ => [])
  for (from, to) in graph.edges {
    if reachable[from] && reachable[to] {
      reverse[to].push(from)
      reverse_pred[from].push(to)
    }
  }
  for terminal in graph.exits {
    if reachable[terminal] {
      reverse[n].push(terminal)
      reverse_pred[terminal].push(n)
    }
  }
  dominance_definition(reverse, reverse_pred, n)
}

///|
fn query_value(graph : @dom.Graph, query : ReferenceQuery) -> Json {
  match query {
    Dominates(ancestor, node) =>
      object([
        ("operation", Json::string("dominates")),
        ("ancestor", Json::string(graph.nodes[ancestor])),
        ("node", Json::string(graph.nodes[node])),
      ])
    NearestCommon(nodes) =>
      object([
        ("operation", Json::string("nearest_common")),
        ("nodes", index_names(graph.nodes, nodes)),
      ])
  }
}

///|
fn query_reference(
  graph : @dom.Graph,
  kind : String,
  queries : Array[ReferenceQuery],
) -> Json {
  let tree = query_tree(graph, kind)
  let answers = queries.map(query => {
    let value = query_value(graph, query)
    match query {
      Dominates(ancestor, node) =>
        replace(
          value,
          "dominates",
          Some(Json::boolean(tree.dominators[node][ancestor])),
        )
      NearestCommon(nodes) => {
        // The deepest member of the intersection of all ancestor sets is the
        // nearest common dominator. Empty/unreachable inputs have no member.
        // This definition uses neither binary lifting nor production indexes.
        let common = Array::make(tree.reachable.length(), !nodes.is_empty())
        for node in nodes {
          for ancestor in 0..<common.length() {
            common[ancestor] = common[ancestor] &&
              tree.dominators[node][ancestor]
          }
        }
        let mut best = -1
        let mut depth = -1
        for ancestor in 0..<common.length() {
          if common[ancestor] {
            let count = tree.dominators[ancestor]
              .filter(selected => selected)
              .length()
            if count > depth {
              depth = count
              best = ancestor
            }
          }
        }
        object([
          ("operation", Json::string("nearest_common")),
          ("nodes", index_names(graph.nodes, nodes)),
          ("found", Json::boolean(best >= 0)),
          ("node", name_or_null(graph.nodes, best)),
          ("virtual_exit", Json::boolean(best == graph.nodes.length())),
        ])
      }
    }
  })
  object([
    ("schema", Json::string("cairndom.answers.v1")),
    ("tree", Json::string(kind)),
    (
      "scope",
      Json::string(
        if kind == "forward" {
          "entry_reachable"
        } else {
          "finite_paths_reaching_declared_exits"
        },
      ),
    ),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("answers", Json::array(answers)),
  ])
}

///|
fn query_fields(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise @dom.GraphError {
  let fields = match value {
    Object(fields) => fields
    _ => raise @dom.Invalid("reference query expects an object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise @dom.Invalid("unknown reference query field: " + key)
    }
  }
  fields
}

///|
fn query_required(
  fields : Map[String, Json],
  key : String,
) -> Json raise @dom.GraphError {
  match fields.get(key) {
    Some(value) => value
    None => raise @dom.Invalid("missing reference query field: " + key)
  }
}

///|
fn query_text(value : Json) -> String raise @dom.GraphError {
  match value {
    String(value) => value
    _ => raise @dom.Invalid("reference query expects a string")
  }
}

///|
fn query_items(
  value : Json,
  limit : Int32,
) -> Array[Json] raise @dom.GraphError {
  match value {
    Array(values) if values.length() <= limit => values
    _ => raise @dom.Invalid("reference query expects a bounded array")
  }
}

///|
fn query_node(
  names : Map[String, Int32],
  value : Json,
) -> Int32 raise @dom.GraphError {
  match names.get(query_text(value)) {
    Some(node) => node
    None => raise @dom.Invalid("unknown reference query node")
  }
}

///|
/// Parse only the graph through the SDK; independently interpret query records
/// and calculate answers from node-removal relations rather than SDK queries.
pub fn query_expected(input : Json) -> Json raise @dom.GraphError {
  let fields = query_fields(input, ["schema", "graph", "tree", "queries"])
  if query_text(query_required(fields, "schema")) != "cairndom.queries.v1" {
    raise @dom.Invalid("reference query schema must be cairndom.queries.v1")
  }
  let kind = query_text(query_required(fields, "tree"))
  if kind != "forward" && kind != "post" {
    raise @dom.Invalid("reference tree must be forward or post")
  }
  let graph = @dom.parse_graph(query_required(fields, "graph").stringify())
  let names : Map[String, Int32] = Map([])
  for node, name in graph.nodes {
    names[name] = node
  }
  let queries = []
  let mut operands = 0
  for value in query_items(query_required(fields, "queries"), 4096) {
    let row = query_fields(value, ["operation", "ancestor", "node", "nodes"])
    match query_text(query_required(row, "operation")) {
      "dominates" => {
        let row = query_fields(value, ["operation", "ancestor", "node"])
        queries.push(
          Dominates(
            query_node(names, query_required(row, "ancestor")),
            query_node(names, query_required(row, "node")),
          ),
        )
        operands += 2
      }
      "nearest_common" => {
        let row = query_fields(value, ["operation", "nodes"])
        let nodes = query_items(query_required(row, "nodes"), 512).map(value => {
          query_node(names, value)
        })
        operands += nodes.length()
        queries.push(NearestCommon(nodes))
      }
      _ => raise @dom.Invalid("unknown reference query operation")
    }
    if operands > 16384 {
      raise @dom.Invalid("reference query operand limit exceeded")
    }
  }
  query_reference(graph, kind, queries)
}

///|
fn query_input(
  graph : @dom.Graph,
  kind : String,
  queries : Array[ReferenceQuery],
) -> Json {
  object([
    ("schema", Json::string("cairndom.queries.v1")),
    ("graph", graph_input(graph)),
    ("tree", Json::string(kind)),
    ("queries", Json::array(queries.map(query => query_value(graph, query)))),
  ])
}

///|
fn query_case(name : String, graph : @dom.Graph, kind : String) -> Json {
  let n = graph.nodes.length()
  let queries = []
  for ancestor in 0..<n {
    for node in 0..<n {
      queries.push(Dominates(ancestor, node))
    }
  }
  // Exhaust all subsets only on the small semantic fixtures below, including
  // the empty set. One reversed repeated list checks operand order and copies.
  for mask in 0..<(1 << n) {
    let nodes = []
    for node in 0..<n {
      if (mask & (1 << node)) != 0 {
        nodes.push(node)
      }
    }
    queries.push(NearestCommon(nodes))
  }
  let repeated = Array::makei(n, offset => n - 1 - offset)
  repeated.push(n - 1)
  queries.push(NearestCommon(repeated))
  queries.push(NearestCommon([graph.entry, graph.entry]))
  object([
    ("name", Json::string(name)),
    ("input", query_input(graph, kind, queries)),
    ("expected", query_reference(graph, kind, queries)),
  ])
}

///|
pub fn query_cases() -> Json {
  let diamond = make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3])
  let multiple = make_graph(6, [(0, 1), (0, 2), (1, 3), (2, 4)], exits=[3, 4])
  let nonzero = make_graph(
    5,
    [(2, 0), (2, 1), (0, 3), (1, 3), (4, 2)],
    entry=2,
    exits=[3],
  )
  let permanent = make_graph(4, [(0, 1), (0, 2), (2, 3), (3, 2)], exits=[1])
  let reordered : @dom.Graph = {
    nodes: ["end", "start", "right", "left", "dead"],
    edges: [(1, 2), (1, 3), (2, 0), (3, 0)],
    entry: 1,
    exits: [0],
  }
  Json::array([
    query_case("forward-diamond", diamond, "forward"),
    query_case("post-diamond", diamond, "post"),
    query_case("post-multiple-exits-and-unreachable", multiple, "post"),
    query_case("forward-nonzero-root", nonzero, "forward"),
    query_case("post-nonzero-root", nonzero, "post"),
    query_case("forward-permanent-cycle", permanent, "forward"),
    query_case("post-permanent-cycle", permanent, "post"),
    query_case("post-no-declared-exit", make_graph(2, [(0, 1), (1, 1)]), "post"),
    query_case("forward-reordered-node-ids", reordered, "forward"),
    object([
      ("name", Json::string("post-empty-query-batch")),
      ("input", query_input(multiple, "post", [])),
      ("expected", query_reference(multiple, "post", [])),
    ]),
  ])
}

///|
pub fn query_invalid_cases() -> Json {
  let graph = make_graph(2, [(0, 1)], exits=[1])
  let base = query_input(graph, "forward", [Dominates(0, 1)])
  let mutations : Array[(String, String, Json?)] = [
    ("schema", "schema", Some(Json::string("other"))),
    ("field", "surprise", Some(Json::boolean(true))),
    ("tree", "tree", Some(Json::string("reverse"))),
    ("missing-tree", "tree", None),
    ("queries-type", "queries", Some(Json::string("not an array"))),
    (
      "unknown-node",
      "queries",
      Some(
        Json::array([
          object([
            ("operation", Json::string("dominates")),
            ("ancestor", Json::string("absent")),
            ("node", Json::string("n1")),
          ]),
        ]),
      ),
    ),
    (
      "unknown-operation",
      "queries",
      Some(Json::array([object([("operation", Json::string("other"))])])),
    ),
    (
      "unknown-query-field",
      "queries",
      Some(
        Json::array([
          object([
            ("operation", Json::string("nearest_common")),
            ("nodes", Json::array([])),
            ("node", Json::string("n0")),
          ]),
        ]),
      ),
    ),
    (
      "missing-query-nodes",
      "queries",
      Some(
        Json::array([object([("operation", Json::string("nearest_common"))])]),
      ),
    ),
  ]
  let cases = mutations.map(mutation => {
    let (name, key, value) = mutation
    invalid_case("query-" + name, "query", replace(base, key, value))
  })
  cases.push(
    raw_invalid_case(
      "query-duplicate-key", "query", "{\"schema\":\"cairndom.queries.v1\",\"graph\":{\"schema\":\"cairndom.graph.v1\",\"nodes\":[\"n0\"],\"entry\":\"n0\",\"exits\":[],\"edges\":[]},\"tree\":\"forward\",\"tree\":\"post\",\"queries\":[]}",
    ),
  )
  Json::array(cases)
}
