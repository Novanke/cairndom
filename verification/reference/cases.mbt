///|
fn case_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn make_graph(
  n : Int32,
  edges : Array[(Int32, Int32)],
  entry~ : Int32 = 0,
  exits~ : Array[Int32] = [],
) -> @dom.Graph {
  { nodes: Array::makei(n, node => "n\{node}"), edges, entry, exits, }
}

///|
fn graph_input(graph : @dom.Graph) -> Json {
  object([
    ("schema", Json::string("cairndom.graph.v1")),
    ("nodes", Json::array(graph.nodes.map(Json::string))),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("exits", index_names(graph.nodes, graph.exits)),
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
  ])
}

///|
fn graph_case(name : String, graph : @dom.Graph) -> Json {
  let reference = graph_reference(graph)
  object([
    ("name", Json::string(name)),
    ("input", graph_input(graph)),
    ("expected", case_field(reference, "report")),
    ("dot", case_field(reference, "dot")),
  ])
}

///|
// The small LCG is reproducible on both supported backends. Its products fit
// Int32; this is a deterministic case generator, not a statistical benchmark.
fn next(state : Array[Int32], limit : Int32) -> Int32 {
  state[0] = (state[0] * 25173 + 13849) % 65536
  // Avoid choosing boolean facts from the LCG's alternating lowest bit.
  state[0] / 16 % limit
}

///|
fn shuffle(values : Array[Int32], state : Array[Int32]) -> Unit {
  for offset in 0..<values.length() {
    let index = values.length() - 1 - offset
    let other = next(state, index + 1)
    let value = values[index]
    values[index] = values[other]
    values[other] = value
  }
}

///|
fn random_graph(state : Array[Int32], limit : Int32) -> @dom.Graph {
  let n = 1 + next(state, limit)
  let threshold = 80 + next(state, 401)
  let edges = []
  let terminal = Array::make(n, true)
  for from in 0..<n {
    for to in 0..<n {
      if next(state, 1000) < threshold {
        edges.push((from, to))
        terminal[from] = false
      }
    }
  }
  let exits = []
  for node in 0..<n {
    if terminal[node] && next(state, 3) != 0 {
      exits.push(node)
    }
  }
  make_graph(n, edges, entry=next(state, n), exits~)
}

///|
fn dense_edges() -> Array[(Int32, Int32)] {
  let edges = []
  for from in 0..<512 {
    for offset in 1..<17 {
      edges.push((from, (from + offset) % 512))
    }
  }
  edges
}

///|
/// Portable graphs and independently calculated reports, generated as one
/// batch. The host adds repository examples and real filesystem operations.
pub fn graph_cases() -> Json {
  let fixtures : Array[(String, @dom.Graph)] = [
    ("single-terminal", make_graph(1, [], exits=[0])),
    ("entry-self-loop", make_graph(2, [(0, 0), (0, 1)], exits=[1])),
    (
      "entry-backedge",
      make_graph(4, [(0, 1), (1, 2), (2, 0), (2, 3)], exits=[3]),
    ),
    (
      "unreachable-incoming",
      make_graph(6, [(0, 1), (1, 3), (2, 3), (3, 4), (4, 3), (5, 5)], entry=2),
    ),
    (
      "irreducible",
      make_graph(
        6,
        [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1), (3, 2), (3, 4), (4, 5)],
        exits=[5],
      ),
    ),
    (
      "nested-loops",
      make_graph(
        7,
        [(0, 1), (1, 2), (1, 6), (2, 3), (2, 4), (3, 2), (4, 1), (4, 5), (5, 4)],
        exits=[6],
      ),
    ),
    (
      "multiple-latches",
      make_graph(5, [(0, 1), (1, 2), (1, 3), (2, 1), (3, 1), (1, 4)], exits=[4]),
    ),
    ("finite-path-scope", make_graph(3, [(0, 1), (0, 2), (2, 2)], exits=[1])),
    ("multiple-exits", make_graph(4, [(0, 1), (0, 2), (1, 3)], exits=[2, 3])),
    ("unreachable-declared-exit", make_graph(3, [(0, 1)], exits=[1, 2])),
    ("empty-exit-set", make_graph(2, [(0, 1)])),
  ]
  let cases = fixtures.map(fixture => {
    let (name, graph) = fixture
    graph_case(name, graph)
  })
  let state = [41431]
  for sample in 0..<100 {
    cases.push(graph_case("random-\{sample}", random_graph(state, 12)))
  }
  cases.push(
    graph_case(
      "chain-512",
      make_graph(512, Array::makei(511, node => (node, node + 1)), exits=[511]),
    ),
  )
  cases.push(graph_case("edge-limit-8192", make_graph(512, dense_edges())))
  Json::array(cases)
}

///|
fn make_program(
  graph : @dom.Graph,
  variables : Array[String],
  facts : Array[(Int32, Array[Int32], Array[Int32])],
) -> @dom.FlowProgram {
  let definitions = Array::makei(graph.nodes.length(), _ => [])
  let uses = Array::makei(graph.nodes.length(), _ => [])
  for (node, defined, used) in facts {
    definitions[node] = defined
    uses[node] = used
  }
  { graph, variables, definitions, uses, }
}

///|
fn program_input(program : @dom.FlowProgram) -> Json {
  let blocks = []
  // Sparse blocks preserve the format's empty-facts convention. Reversing
  // their order also verifies that block records are matched by node ID.
  for offset in 0..<program.graph.nodes.length() {
    let node = program.graph.nodes.length() - 1 - offset
    if !program.definitions[node].is_empty() || !program.uses[node].is_empty() {
      blocks.push(
        object([
          ("node", Json::string(program.graph.nodes[node])),
          ("defines", index_names(program.variables, program.definitions[node])),
          ("uses", index_names(program.variables, program.uses[node])),
        ]),
      )
    }
  }
  object([
    ("schema", Json::string("cairndom.program.v1")),
    ("graph", graph_input(program.graph)),
    ("variables", Json::array(program.variables.map(Json::string))),
    ("blocks", Json::array(blocks)),
  ])
}

///|
fn program_case(name : String, program : @dom.FlowProgram) -> Json {
  program_case_input(name, program, program_input(program))
}

///|
fn program_case_input(
  name : String,
  program : @dom.FlowProgram,
  input : Json,
) -> Json {
  object([
    ("name", Json::string(name)),
    ("input", input),
    ("expected", program_reference(program)),
  ])
}

///|
fn program_fixtures() -> Array[(String, @dom.FlowProgram)] {
  [
    (
      "branch-live-dead-and-parameter",
      make_program(
        make_graph(6, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)], exits=[4]),
        ["value", "unused", "parameter"],
        [(2, [1, 0], []), (1, [0, 1], []), (3, [], [2, 0]), (5, [2], [1])],
      ),
    ),
    (
      "loop-carried-input",
      make_program(
        make_graph(4, [(0, 1), (1, 2), (2, 1), (1, 3)], exits=[3]),
        ["counter", "dead"],
        [(1, [], [0]), (2, [1, 0], [0])],
      ),
    ),
    (
      "nonzero-entry-unreachable-incoming",
      make_program(
        make_graph(5, [(2, 1), (1, 3), (0, 1), (4, 4)], entry=2, exits=[3]),
        ["x", "dead_only"],
        [(0, [0], []), (1, [], [0]), (4, [1], [1])],
      ),
    ),
    (
      "same-block-use-before-def",
      make_program(make_graph(1, [], exits=[0]), ["x"], [(0, [0], [0])]),
    ),
    (
      "entry-self-loop",
      make_program(make_graph(1, [(0, 0)]), ["x"], [(0, [0], [0])]),
    ),
    (
      "multiple-exits",
      make_program(
        make_graph(4, [(0, 1), (0, 2), (1, 3)], exits=[2, 3]),
        ["parameter", "local"],
        [(0, [1], []), (2, [], [1, 0]), (3, [], [0, 1])],
      ),
    ),
    (
      "permanent-cycle-is-live",
      make_program(
        make_graph(4, [(0, 1), (0, 2), (2, 3), (3, 2)], exits=[1]),
        ["x", "initialized"],
        [(0, [1], []), (2, [], [0, 1]), (3, [0], [])],
      ),
    ),
    (
      "iterated-join-sites",
      make_program(
        make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1)]),
        ["x"],
        [(2, [0], []), (3, [], [0]), (1, [], [0])],
      ),
    ),
    (
      "irreducible-joins",
      make_program(
        make_graph(
          5,
          [(0, 1), (0, 2), (1, 2), (2, 1), (1, 3), (2, 3), (3, 4)],
          exits=[4],
        ),
        ["x", "y"],
        [(1, [0], [1]), (2, [1], [0]), (3, [], [1, 0])],
      ),
    ),
    ("zero-variables", make_program(make_graph(2, [(0, 1)], exits=[1]), [], [])),
  ]
}

///|
pub fn program_cases() -> Json {
  let cases = program_fixtures().map(fixture => {
    let (name, program) = fixture
    program_case(name, program)
  })
  let state = [23381]
  for sample in 0..<30 {
    let graph = random_graph(state, 10)
    let count = next(state, 7)
    let order = Array::makei(count, variable => variable)
    shuffle(order, state)
    let variables = order.map(variable => "v\{variable}")
    let facts = []
    for node in 0..<graph.nodes.length() {
      let defined = []
      let used = []
      for variable in 0..<count {
        if next(state, 100) < 38 {
          defined.push(variable)
        }
        if next(state, 100) < 32 && !(sample % 7 == 0 && variable == count - 1) {
          used.push(variable)
        }
      }
      shuffle(defined, state)
      shuffle(used, state)
      facts.push((node, defined, used))
    }
    let program = make_program(graph, variables, facts)
    let node_order = Array::makei(graph.nodes.length(), node => node)
    shuffle(node_order, state)
    let blocks = []
    for node in node_order {
      if !program.definitions[node].is_empty() ||
        !program.uses[node].is_empty() ||
        next(state, 2) != 0 {
        blocks.push(
          object([
            ("node", Json::string(graph.nodes[node])),
            ("defines", index_names(variables, program.definitions[node])),
            ("uses", index_names(variables, program.uses[node])),
          ]),
        )
      }
    }
    let input = replace(
      program_input(program),
      "blocks",
      Some(Json::array(blocks)),
    )
    cases.push(program_case_input("random-program-\{sample}", program, input))
  }
  Json::array(cases)
}

///|
fn replace(value : Json, key : String, replacement : Json?) -> Json {
  let fields : Map[String, Json] = Map([])
  if value is Object(original) {
    for name, item in original {
      if name != key {
        fields[name] = item
      }
    }
  }
  if replacement is Some(item) {
    fields[key] = item
  }
  Json::object(fields)
}

///|
fn invalid_case(name : String, command : String, payload : Json) -> Json {
  raw_invalid_case(name, command, payload.stringify())
}

///|
fn raw_invalid_case(name : String, command : String, payload : String) -> Json {
  object([
    ("name", Json::string(name)),
    ("command", Json::string(command)),
    ("payload", Json::string(payload)),
  ])
}

///|
fn block(node : String, defined : Array[String], used : Array[String]) -> Json {
  object([
    ("node", Json::string(node)),
    ("defines", Json::array(defined.map(Json::string))),
    ("uses", Json::array(used.map(Json::string))),
  ])
}

///|
/// Language/schema errors travel as raw UTF-8 text. Invalid UTF-8, byte-size
/// limits, symlinks and host failures remain the filesystem adapter's tests.
pub fn invalid_cases() -> Json {
  let graph = graph_input(
    make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3]),
  )
  let mutations : Array[(String, String, Json?)] = [
    ("wrong-schema", "schema", Some(Json::string("other"))),
    ("unknown-field", "surprise", Some(Json::boolean(true))),
    ("empty-nodes", "nodes", Some(Json::array([]))),
    (
      "duplicate-node",
      "nodes",
      Some(Json::array(["n0", "n1", "n2", "n3", "n0"].map(Json::string))),
    ),
    (
      "invalid-node",
      "nodes",
      Some(Json::array(["invalid id", "n1", "n2", "n3"].map(Json::string))),
    ),
    ("unknown-entry", "entry", Some(Json::string("absent"))),
    ("non-string-entry", "entry", Some(Json::number(0))),
    (
      "unknown-edge",
      "edges",
      Some(
        Json::array([Json::array([Json::string("n0"), Json::string("absent")])]),
      ),
    ),
    (
      "duplicate-edge",
      "edges",
      Some(
        Json::array([
          Json::array([Json::string("n0"), Json::string("n1")]),
          Json::array([Json::string("n0"), Json::string("n1")]),
        ]),
      ),
    ),
    (
      "bad-edge-arity",
      "edges",
      Some(Json::array([Json::array(["n0", "n1", "n2"].map(Json::string))])),
    ),
    ("nonterminal-exit", "exits", Some(Json::array([Json::string("n0")]))),
    (
      "duplicate-exit",
      "exits",
      Some(Json::array([Json::string("n3"), Json::string("n3")])),
    ),
    ("non-array-exits", "exits", Some(Json::string("n3"))),
    ("missing-exits", "exits", None),
  ]
  let cases = mutations.map(mutation => {
    let (name, key, value) = mutation
    invalid_case(name, "analyze", replace(graph, key, value))
  })
  let excessive_edges = dense_edges()
  excessive_edges.push((0, 0))
  cases.push(
    invalid_case(
      "too-many-edges",
      "analyze",
      graph_input(make_graph(512, excessive_edges)),
    ),
  )
  cases.push(
    invalid_case("too-many-nodes", "analyze", graph_input(make_graph(513, []))),
  )
  cases.push(raw_invalid_case("json", "analyze", "{not JSON}"))
  cases.push(
    raw_invalid_case(
      "duplicate-key", "analyze", "{\"schema\":\"cairndom.graph.v1\",\"nodes\":[\"n0\"],\"entry\":\"n0\",\"entry\":\"n0\",\"exits\":[],\"edges\":[]}",
    ),
  )
  let (_, fixture) = program_fixtures()[0]
  let program = program_input(fixture)
  let program_mutations : Array[(String, String, Json)] = [
    ("wrong-program-schema", "schema", Json::string("other")),
    (
      "wrong-nested-graph-schema",
      "graph",
      replace(
        graph_input(fixture.graph),
        "schema",
        Some(Json::string("cairndom.graph.v999")),
      ),
    ),
    ("unknown-variable", "blocks", Json::array([block("n1", [], ["absent"])])),
    (
      "unknown-defined-variable",
      "blocks",
      Json::array([block("n1", ["absent"], [])]),
    ),
    (
      "duplicate-variable",
      "variables",
      Json::array([Json::string("x"), Json::string("x")]),
    ),
    (
      "duplicate-fact",
      "blocks",
      Json::array([block("n1", [], ["value", "value"])]),
    ),
    (
      "duplicate-block",
      "blocks",
      Json::array([block("n1", [], []), block("n1", [], [])]),
    ),
    ("unknown-block", "blocks", Json::array([block("absent", [], [])])),
    ("unknown-field", "surprise", Json::boolean(true)),
    (
      "missing-facts",
      "blocks",
      Json::array([
        object([("node", Json::string("n1")), ("uses", Json::array([]))]),
      ]),
    ),
  ]
  cases.push(
    invalid_case(
      "graph-instead-of-program",
      "plan-ssa",
      graph_input(fixture.graph),
    ),
  )
  for (name, key, value) in program_mutations {
    cases.push(
      invalid_case(name, "plan-ssa", replace(program, key, Some(value))),
    )
  }
  cases.push(raw_invalid_case("json", "plan-ssa", "{not JSON}"))
  cases.push(
    raw_invalid_case(
      "duplicate-key", "plan-ssa", "{\"schema\":\"cairndom.program.v1\",\"graph\":{\"schema\":\"cairndom.graph.v1\",\"nodes\":[\"n0\"],\"entry\":\"n0\",\"exits\":[],\"edges\":[]},\"variables\":[],\"blocks\":[],\"schema\":\"cairndom.program.v1\"}",
    ),
  )
  Json::array(cases)
}

///|
fn arguments(cases : Array[Array[String]]) -> Json {
  Json::array(cases.map(values => Json::array(values.map(Json::string))))
}

///|
fn json_arguments(command : String) -> Json {
  arguments([
    [command],
    [command, "$input", "$input"],
    [command, "$input", "--out"],
    [command, "$input", "--format"],
    [command, "$input", "--unknown"],
    [command, "$input", "--format", "yaml"],
    [command, "$input", "--format", "json", "--format", "json"],
    [command, "$input", "--format", "dot"],
    [command, "$input", "--out", "a", "--out", "b"],
  ])
}

///|
/// Inputs and option matrices for the real-file/process adapter. This package
/// owns portable cases; the adapter owns paths, processes and fault injection.
pub fn host_cases() -> Json {
  let graph = graph_input(
    make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3]),
  )
  let (_, program) = program_fixtures()[0]
  let single : @dom.Graph = {
    nodes: ["entry"],
    edges: [],
    entry: 0,
    exits: [0],
  }
  let suffix = StringBuilder()
  for _ in 0..<59 {
    suffix.write_string("a")
  }
  let suffix = suffix.to_string()
  let nodes = Array::makei(128, node => {
    let padding = if node < 10 { "00" } else if node < 100 { "0" } else { "" }
    "n" + padding + node.to_string() + "_" + suffix
  })
  let edges = []
  for from in 0..<128 {
    for to in (from + 1)..<128 {
      edges.push((from, to))
    }
  }
  let large : @dom.Graph = { nodes, edges, entry: 0, exits: [127], }
  object([
    ("graph", graph),
    ("program", program_input(program)),
    ("stdout_graph", graph_input(single)),
    ("stdout_program", program_input(make_program(single, [], []))),
    ("large_stdout_graph", graph_input(large)),
    (
      "bad_arguments",
      object([
        (
          "analyze",
          arguments([
            ["unknown"],
            ["analyze"],
            ["analyze", "$input", "$input"],
            ["analyze", "$input", "--format"],
            ["analyze", "$input", "--out"],
            ["analyze", "$input", "--format", "yaml"],
            ["analyze", "$input", "--unknown"],
            ["analyze", "$input", "--format", "json", "--format", "dot"],
            ["analyze", "$input", "--out", "a", "--out", "b"],
          ]),
        ),
        ("plan-ssa", json_arguments("plan-ssa")),
        ("query", json_arguments("query")),
      ]),
    ),
  ])
}
