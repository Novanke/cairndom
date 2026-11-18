///|
// Walk forward states (block entry, last definition), recording a use before
// applying a local definition. Production searches backward from each use;
// this reference uses neither that search nor any production analysis result.
fn value_origins_reference(
  program : @dom.FlowProgram,
) -> Json raise @dom.GraphError {
  let graph = program.graph
  let n = graph.nodes.length()
  let (succ, _) = adjacency(graph)
  let reachable = reach(succ, [graph.entry], -1, Array::make(n, true))
  let uses : Array[(Int32, Int32, Json)] = []
  let mut relation_count = 0
  for variable, name in program.variables {
    let seen = Array::makei(n, _ => Array::make(n + 1, false))
    let sources = Array::makei(n, _ => Array::make(n + 1, false))
    // Slot n is a synthetic original incoming value, not a defining block.
    let work = [(graph.entry, n)]
    seen[graph.entry][n] = true
    let mut cursor = 0
    while cursor < work.length() {
      let (node, source) = work[cursor]
      cursor += 1
      if program.uses[node].contains(variable) {
        sources[node][source] = true
      }
      let outgoing = if program.definitions[node].contains(variable) {
        node
      } else {
        source
      }
      for child in succ[node] {
        if !seen[child][outgoing] {
          seen[child][outgoing] = true
          work.push((child, outgoing))
        }
      }
    }
    for node in 0..<n {
      if !reachable[node] || !program.uses[node].contains(variable) {
        continue
      }
      for present in sources[node] {
        if present {
          relation_count += 1
        }
      }
      if relation_count > 65536 {
        raise @dom.Invalid("value-origin relation limit of 65536 exceeded")
      }
      uses.push(
        (
          node,
          variable,
          object([
            ("node", Json::string(graph.nodes[node])),
            ("variable", Json::string(name)),
            ("definition_blocks", selected_names(graph.nodes, sources[node])),
            ("requires_entry_value", Json::boolean(sources[node][n])),
          ]),
        ),
      )
    }
  }
  uses.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  object([
    ("schema", Json::string("cairndom.value-origins.v1")),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("scope", Json::string("entry_reachable_all_paths")),
    ("use_convention", Json::string("before_local_definition")),
    ("status", Json::string("possible_origins")),
    ("variables", Json::array(program.variables.map(Json::string))),
    (
      "unreachable_blocks",
      selected_names(graph.nodes, reachable.map(value => !value)),
    ),
    ("uses", Json::array(uses.map(value => value.2))),
    ("source_relation_count", Json::number(relation_count.to_double())),
    ("source_relation_limit", Json::number(65536)),
    (
      "incoming_value_semantics",
      Json::string(
        "An incoming value can reach this use; the caller must supply a parameter or initial value, or apply its own missing-initialization rules. This is not proof of an initialization error.",
      ),
    ),
  ])
}

///|
pub fn value_origins_expected(input : Json) -> Json raise @dom.GraphError {
  value_origins_reference(@dom.parse_program(input.stringify()))
}

///|
fn value_origins_case(
  name : String,
  program : @dom.FlowProgram,
) -> Json raise @dom.GraphError {
  object([
    ("name", Json::string(name)),
    ("input", program_input(program)),
    ("expected", value_origins_reference(program)),
  ])
}

///|
pub fn value_origins_cases() -> Json raise @dom.GraphError {
  let cases = []
  // The existing fixtures include no variables, shuffled/sparse facts, loops,
  // permanent cycles, nonzero entries, multiple exits and unreachable facts.
  if program_cases() is Array(programs) {
    for fixture in programs {
      let input = case_field(fixture, "input")
      cases.push(
        object([
          ("name", case_field(fixture, "name")),
          ("input", input),
          ("expected", value_origins_expected(input)),
        ]),
      )
    }
  }
  let focused : Array[(String, @dom.FlowProgram)] = [
    (
      "one-branch-leaves-incoming-value",
      make_program(
        make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3]),
        ["value"],
        [(1, [0], []), (3, [], [0])],
      ),
    ),
    (
      "overwriting-definition-kills-older-source",
      make_program(
        make_graph(4, [(0, 1), (1, 2), (2, 3)], exits=[3]),
        ["value"],
        [(0, [0], []), (1, [0], [0]), (2, [0], []), (3, [], [0])],
      ),
    ),
    (
      "entry-use-sees-incoming-and-returning-definition",
      make_program(
        make_graph(3, [(0, 1), (1, 0), (1, 2)], exits=[2]),
        ["value"],
        [(0, [0], [0]), (1, [0], [])],
      ),
    ),
  ]
  for (name, program) in focused {
    cases.push(value_origins_case(name, program))
  }
  Json::array(cases)
}

///|
/// A combinatorial capacity fixture, without running the forward-state oracle:
/// 255 x-uses each see 256 last definitions; 256 y-uses each see an incoming
/// value. One extra y-use adds exactly one relation beyond the 65,536 limit.
pub fn value_origin_limit_cases() -> Json {
  let edges : Array[(Int32, Int32)] = []
  for node in 256..<512 {
    edges.push((0, node))
    edges.push((node, 1))
  }
  for node in 1..<256 {
    edges.push((node, if node == 255 { 0 } else { node + 1 }))
  }
  let program : @dom.FlowProgram = {
    graph: make_graph(512, edges),
    variables: ["x", "y"],
    definitions: Array::makei(512, node => if node >= 256 { [0] } else { [] }),
    uses: Array::makei(512, node => {
      if node == 0 {
        [1]
      } else if node < 256 {
        [0, 1]
      } else {
        []
      }
    }),
  }
  let at_limit = program_input(program)
  program.uses[256].push(1)
  object([("at_limit", at_limit), ("over_limit", program_input(program))])
}
