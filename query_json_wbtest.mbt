///|
fn query_test_request(
  graph : Graph,
  tree : String,
  queries : Array[Json],
) -> String {
  Json::object(
    Map([
      ("schema", Json::string("cairndom.queries.v1")),
      ("graph", graph_json_value(graph)),
      ("tree", Json::string(tree)),
      ("queries", Json::array(queries)),
    ]),
  ).stringify()
}

///|
fn query_test_dominates(ancestor : String, node : String) -> Json {
  Json::object(
    Map([
      ("operation", Json::string("dominates")),
      ("ancestor", Json::string(ancestor)),
      ("node", Json::string(node)),
    ]),
  )
}

///|
fn query_test_nearest(nodes : Array[String]) -> Json {
  Json::object(
    Map([
      ("operation", Json::string("nearest_common")),
      ("nodes", Json::array(nodes.map(Json::string))),
    ]),
  )
}

///|
fn query_test_report(input : String) -> Map[String, Json] raise GraphError {
  let value = @json.parse(query_json_text(input)) catch {
    _ => raise Invalid("query answers were not valid JSON")
  }
  fields(value, ["schema", "tree", "scope", "entry", "answers"])
}

///|
fn query_test_check_dominates(
  value : Json,
  ancestor : String,
  node : String,
  answer : Bool,
) -> Unit raise {
  let object = fields(value, ["operation", "ancestor", "node", "dominates"])
  assert_eq(text(required(object, "operation")), "dominates")
  assert_eq(text(required(object, "ancestor")), ancestor)
  assert_eq(text(required(object, "node")), node)
  assert_eq(
    required(object, "dominates").stringify(),
    Json::boolean(answer).stringify(),
  )
}

///|
fn query_test_check_nearest(
  value : Json,
  nodes : Array[String],
  found : Bool,
  node : String?,
  virtual_exit : Bool,
) -> Unit raise {
  let object = fields(value, [
    "operation", "nodes", "found", "node", "virtual_exit",
  ])
  assert_eq(text(required(object, "operation")), "nearest_common")
  let actual_nodes = []
  for value in items(required(object, "nodes"), 512) {
    actual_nodes.push(text(value))
  }
  assert_eq(actual_nodes, nodes)
  assert_eq(
    required(object, "found").stringify(),
    Json::boolean(found).stringify(),
  )
  let expected_node = match node {
    Some(name) => Json::string(name)
    None => Json::null()
  }
  assert_eq(required(object, "node").stringify(), expected_node.stringify())
  assert_eq(
    required(object, "virtual_exit").stringify(),
    Json::boolean(virtual_exit).stringify(),
  )
}

///|
fn query_test_rejected(input : String) -> Bool {
  try {
    ignore(query_json_text(input))
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "named query batches return diamond regions in request order" {
  let graph : Graph = {
    nodes: ["entry", "left", "right", "join", "exit", "dead"],
    entry: 0,
    exits: [4],
    edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (5, 3)],
  }
  let input = query_test_request(graph, "forward", [
    query_test_dominates("entry", "exit"),
    query_test_dominates("left", "join"),
    query_test_nearest(["left", "right"]),
    query_test_nearest(["exit", "join", "exit"]),
    query_test_dominates("dead", "dead"),
    query_test_nearest(["exit", "dead"]),
    query_test_nearest([]),
  ])
  let report = query_test_report(input)
  assert_eq(text(required(report, "schema")), "cairndom.answers.v1")
  assert_eq(text(required(report, "tree")), "forward")
  assert_eq(text(required(report, "scope")), "entry_reachable")
  assert_eq(text(required(report, "entry")), "entry")
  let answers = items(required(report, "answers"), 4096)
  assert_eq(answers.length(), 7)
  query_test_check_dominates(answers[0], "entry", "exit", true)
  query_test_check_dominates(answers[1], "left", "join", false)
  query_test_check_nearest(
    answers[2],
    ["left", "right"],
    true,
    Some("entry"),
    false,
  )
  query_test_check_nearest(
    answers[3],
    ["exit", "join", "exit"],
    true,
    Some("join"),
    false,
  )
  query_test_check_dominates(answers[4], "dead", "dead", false)
  query_test_check_nearest(answers[5], ["exit", "dead"], false, None, false)
  query_test_check_nearest(answers[6], [], false, None, false)
  assert_eq(query_json_text(input), query_json_text(input))
  let post = query_test_report(
    query_test_request(graph, "post", [
      query_test_nearest(["right", "left", "right"]),
      query_test_dominates("join", "entry"),
    ]),
  )
  let post_answers = items(required(post, "answers"), 4096)
  query_test_check_nearest(
    post_answers[0],
    ["right", "left", "right"],
    true,
    Some("join"),
    false,
  )
  query_test_check_dominates(post_answers[1], "join", "entry", true)
}

///|
test "post query answers distinguish virtual exit from empty and unreachable regions" {
  let graph : Graph = {
    nodes: ["entry", "left_exit", "right_exit", "forever", "dead"],
    entry: 0,
    exits: [1, 2],
    edges: [(0, 1), (0, 2), (0, 3), (3, 3)],
  }
  let report = query_test_report(
    query_test_request(graph, "post", [
      query_test_nearest(["right_exit", "left_exit", "right_exit"]),
      query_test_nearest(["left_exit", "forever"]),
      query_test_nearest([]),
      query_test_nearest(["left_exit", "left_exit"]),
      query_test_nearest(["entry", "left_exit"]),
      query_test_dominates("left_exit", "entry"),
      query_test_dominates("forever", "forever"),
      query_test_nearest(["dead"]),
    ]),
  )
  assert_eq(text(required(report, "tree")), "post")
  assert_eq(
    text(required(report, "scope")),
    "finite_paths_reaching_declared_exits",
  )
  let answers = items(required(report, "answers"), 4096)
  assert_eq(answers.length(), 8)
  query_test_check_nearest(
    answers[0],
    ["right_exit", "left_exit", "right_exit"],
    true,
    None,
    true,
  )
  query_test_check_nearest(
    answers[1],
    ["left_exit", "forever"],
    false,
    None,
    false,
  )
  query_test_check_nearest(answers[2], [], false, None, false)
  query_test_check_nearest(
    answers[3],
    ["left_exit", "left_exit"],
    true,
    Some("left_exit"),
    false,
  )
  query_test_check_nearest(answers[4], ["entry", "left_exit"], true, None, true)
  query_test_check_dominates(answers[5], "left_exit", "entry", false)
  query_test_check_dominates(answers[6], "forever", "forever", false)
  query_test_check_nearest(answers[7], ["dead"], false, None, false)
}

///|
test "query parsing rejects missing extra duplicate mistyped and late invalid operands" {
  let good =
    #|{"schema":"cairndom.queries.v1","graph":{"schema":"cairndom.graph.v1","nodes":["n","other","dead"],"entry":"n","exits":["other"],"edges":[["n","other"]]},"tree":"forward","queries":[{"operation":"dominates","ancestor":"n","node":"other"},{"operation":"nearest_common","nodes":["other","n","other"]}]}
  for
    invalid in [
      "{}",
      "[]",
      "not JSON",
      good.replace(old="cairndom.queries.v1", new="cairndom.queries.v2"),
      good.replace(old="\"tree\":\"forward\",", new=""),
      good.replace(old="\"tree\":\"forward\"", new="\"tree\":\"reverse\""),
      good.replace(old="\"tree\":\"forward\"", new="\"tree\":null"),
      good.replace(old="\"queries\":[", new="\"extra\":0,\"queries\":["),
      good.replace(old="\"queries\":[", new="\"queries\":null,\"old\":["),
      good.replace(old="\"entry\":\"n\"", new="\"entry\":\"n\",\"extra\":0"),
      good.replace(old="\"entry\":\"n\"", new="\"entry\":\"n\",\"entry\":\"n\""),
      good.replace(old="\"operation\":\"dominates\",", new=""),
      good.replace(old="\"ancestor\":\"n\",", new=""),
      good.replace(old=",\"node\":\"other\"", new=""),
      good.replace(old="\"ancestor\":\"n\"", new="\"ancestor\":null"),
      good.replace(old="\"node\":\"other\"", new="\"node\":\"missing\""),
      good.replace(old="\"ancestor\":\"n\"", new="\"ancestor\":\"missing\""),
      good.replace(
        old="\"operation\":\"dominates\"",
        new="\"operation\":\"unknown\"",
      ),
      good.replace(old="\"operation\":\"dominates\"", new="\"operation\":0"),
      good.replace(
        old="\"node\":\"other\"",
        new="\"node\":\"other\",\"nodes\":[]",
      ),
      good.replace(
        old="\"operation\":\"dominates\"",
        new="\"operation\":\"dominates\",\"operation\":\"dominates\"",
      ),
      good.replace(old=",\"nodes\":[\"other\",\"n\",\"other\"]", new=""),
      good.replace(
        old="\"nodes\":[\"other\",\"n\",\"other\"]",
        new="\"nodes\":null",
      ),
      good.replace(
        old="\"nodes\":[\"other\",\"n\",\"other\"]",
        new="\"nodes\":[0]",
      ),
      good.replace(
        old="\"nodes\":[\"other\",\"n\",\"other\"]",
        new="\"nodes\":[\"dead\",\"missing\"]",
      ),
      good.replace(
        old="\"nodes\":[\"other\",\"n\",\"other\"]",
        new="\"nodes\":[\"3\"]",
      ),
      good.replace(
        old="\"nodes\":[\"other\",\"n\",\"other\"]",
        new="\"nodes\":[\"n\"],\"nodes\":[\"n\"]",
      ),
      good.replace(
        old="\"operation\":\"nearest_common\"",
        new="\"operation\":\"nearest_common\",\"ancestor\":\"n\"",
      ),
      good.replace(
        old="\"schema\":\"cairndom.queries.v1\"",
        new="\"schema\":\"cairndom.queries.v1\",\"schema\":\"cairndom.queries.v1\"",
      ),
    ] {
    assert_true(query_test_rejected(invalid))
  }
  let empty =
    #|{"schema":"cairndom.queries.v1","graph":{"schema":"cairndom.graph.v1","nodes":["n"],"entry":"n","exits":["n"],"edges":[]},"tree":"forward","queries":[]}
  assert_true(
    query_test_rejected(
      empty.replace(old="\"queries\":[]", new="\"queries\":null"),
    ),
  )
  assert_true(
    query_test_rejected(
      empty.replace(old="\"queries\":[]", new="\"queries\":[null]"),
    ),
  )
  assert_true(query_test_rejected(empty.replace(old=",\"queries\":[]", new="")))
  assert_true(
    query_test_rejected(
      empty.replace(old="\"schema\":\"cairndom.queries.v1\",", new=""),
    ),
  )
  assert_true(
    query_test_rejected(
      (
        #|{"schema":"cairndom.queries.v1","tree":"forward","queries":[]}
      ),
    ),
  )
}

///|
test "query batches enforce per-list aggregate and text limits at their boundaries" {
  let graph : Graph = { nodes: ["n"], entry: 0, exits: [0], edges: [], }
  let nodes = Array::make(512, "n")
  let maximum_list = query_test_report(
    query_test_request(graph, "forward", [query_test_nearest(nodes)]),
  )
  let list_answers = items(required(maximum_list, "answers"), 4096)
  query_test_check_nearest(list_answers[0], nodes, true, Some("n"), false)
  assert_true(
    query_test_rejected(
      query_test_request(graph, "forward", [
        query_test_nearest(Array::make(513, "n")),
      ]),
    ),
  )
  let queries = Array::make(32, query_test_nearest(nodes))
  let exact_operands = query_test_report(
    query_test_request(graph, "forward", queries),
  )
  assert_eq(items(required(exact_operands, "answers"), 4096).length(), 32)
  queries.push(query_test_nearest(["n"]))
  let operand_error = try {
    ignore(query_json_text(query_test_request(graph, "forward", queries)))
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(operand_error, "query limit is at most 16384 node operands")
  let padding = Array::make(2048, Array::make(1024, " ").join("")).join("")
  let text_error = try {
    ignore(query_json_text(query_test_request(graph, "forward", []) + padding))
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(text_error, "query JSON exceeds 2 MiB")
}

///|
test "maximum query count reuses a tiny graph with stable mixed answers" {
  let graph : Graph = { nodes: ["n"], entry: 0, exits: [0], edges: [], }
  let queries = Array::makei(4096, query => {
    if query % 2 == 0 {
      query_test_dominates("n", "n")
    } else {
      query_test_nearest(["n", "n"])
    }
  })
  let input = query_test_request(graph, "forward", queries)
  let report = query_test_report(input)
  let answers = items(required(report, "answers"), 4096)
  assert_eq(answers.length(), 4096)
  for answer, value in answers {
    if answer % 2 == 0 {
      query_test_check_dominates(value, "n", "n", true)
    } else {
      query_test_check_nearest(value, ["n", "n"], true, Some("n"), false)
    }
  }
  assert_eq(query_json_text(input), query_json_text(input))
  queries.push(query_test_nearest([]))
  assert_true(
    query_test_rejected(query_test_request(graph, "forward", queries)),
  )
  let empty = query_test_report(query_test_request(graph, "post", []))
  assert_eq(items(required(empty, "answers"), 4096).length(), 0)
}
