///|
fn program_test_source() -> String {
  let source =
    #|{"schema":"cairndom.program.v1","graph":{"schema":"cairndom.graph.v1","nodes":["entry","exit","dead"],"entry":"entry","exits":["exit"],"edges":[["entry","exit"]]},"variables":["z","a"],"blocks":[{"node":"exit","defines":[],"uses":["a","z"]},{"node":"entry","defines":["a"],"uses":[]}]}
  source
}

///|
test "program JSON resolves named facts and supplies independent omitted rows" {
  let program = parse_program(program_test_source())
  assert_eq(program.graph.nodes, ["entry", "exit", "dead"])
  assert_eq(program.graph.edges, [(0, 1)])
  assert_eq(program.graph.entry, 0)
  assert_eq(program.graph.exits, [1])
  assert_eq(program.variables, ["z", "a"])
  assert_eq(program.definitions, [[1], [], []])
  assert_eq(program.uses, [[], [1, 0], []])
  program.definitions[1].push(0)
  assert_eq(program.definitions[2], [])
  program.uses[0].push(1)
  assert_eq(program.uses[2], [])
}

///|
test "program JSON round trips canonically without sharing mutable input rows" {
  let program = parse_program(program_test_source())
  let serialized = program_json_text(program)
  let restored = parse_program(serialized)
  assert_eq(restored.variables, ["z", "a"])
  assert_eq(restored.graph.nodes, program.graph.nodes)
  assert_eq(restored.graph.edges, program.graph.edges)
  assert_eq(restored.graph.entry, program.graph.entry)
  assert_eq(restored.graph.exits, program.graph.exits)
  assert_eq(restored.definitions, [[1], [], []])
  assert_eq(restored.uses, [[], [0, 1], []])
  assert_eq(program.uses[1], [1, 0])
  assert_eq(program_json_text(restored), serialized)
  let value = @json.parse(serialized)
  let object = fields(value, ["schema", "graph", "variables", "blocks"])
  let blocks = items(required(object, "blocks"), 3)
  assert_eq(blocks.length(), 3)
  for node, name in program.graph.nodes {
    let block = fields(blocks[node], ["node", "defines", "uses"])
    assert_eq(text(required(block, "node")), name)
  }
  program.graph.nodes[0] = "changed"
  program.graph.edges.clear()
  program.graph.exits.clear()
  program.variables[0] = "changed_variable"
  program.definitions[0].clear()
  program.uses[1].clear()
  assert_eq(restored.graph.nodes, ["entry", "exit", "dead"])
  assert_eq(restored.graph.edges, [(0, 1)])
  assert_eq(restored.graph.exits, [1])
  assert_eq(restored.variables, ["z", "a"])
  assert_eq(restored.definitions, [[1], [], []])
  assert_eq(restored.uses, [[], [0, 1], []])
}

///|
test "program JSON supports loop programs same-block facts and zero variables" {
  let loop_program = parse_program(
    (
      #|{"schema":"cairndom.program.v1","graph":{"schema":"cairndom.graph.v1","nodes":["start","loop"],"entry":"start","exits":[],"edges":[["start","loop"],["loop","loop"]]},"variables":["x"],"blocks":[{"node":"loop","defines":["x"],"uses":["x"]}]}
    ),
  )
  assert_eq(liveness(loop_program).live_in, [[0], [0]])
  assert_eq(parse_program(program_json_text(loop_program)).uses, [[], [0]])
  let no_variables = parse_program(
    (
      #|{"schema":"cairndom.program.v1","graph":{"schema":"cairndom.graph.v1","nodes":["start","loop"],"entry":"start","exits":[],"edges":[["start","loop"],["loop","loop"]]},"variables":[],"blocks":[]}
    ),
  )
  let restored = parse_program(program_json_text(no_variables))
  assert_eq(restored.variables, [])
  assert_eq(restored.definitions, [[], []])
  assert_eq(restored.uses, [[], []])
  assert_eq(liveness(restored).live_in, [[], []])
}

///|
test "program JSON rejects unknown duplicate missing and mistyped schema facts" {
  let good =
    #|{"schema":"cairndom.program.v1","graph":{"schema":"cairndom.graph.v1","nodes":["n","other"],"entry":"n","exits":["other"],"edges":[["n","other"]]},"variables":["x"],"blocks":[{"node":"n","defines":[],"uses":[]}]}
  for
    invalid in [
      "{}",
      "[]",
      good.replace(old="cairndom.program.v1", new="cairndom.program.v2"),
      good.replace(old="\"blocks\":", new="\"extra\":0,\"blocks\":"),
      good.replace(
        old="\"nodes\":[\"n\",\"other\"]",
        new="\"nodes\":[\"n\",\"other\"],\"extra\":0",
      ),
      good.replace(old="\"defines\":[]", new="\"defines\":[],\"extra\":0"),
      good.replace(old="\"variables\":[\"x\"],", new=""),
      good.replace(old=",\"uses\":[]", new=""),
      good.replace(old="\"variables\":[\"x\"]", new="\"variables\":null"),
      good.replace(
        old="\"blocks\":[{\"node\":\"n\",\"defines\":[],\"uses\":[]}]",
        new="\"blocks\":null",
      ),
      good.replace(old="\"defines\":[]", new="\"defines\":null"),
      good.replace(old="\"uses\":[]", new="\"uses\":[0]"),
      good.replace(old="\"node\":\"n\"", new="\"node\":\"missing\""),
      good.replace(old="\"defines\":[]", new="\"defines\":[\"unknown\"]"),
      good.replace(old="\"uses\":[]", new="\"uses\":[\"unknown\"]"),
      good.replace(old="\"defines\":[]", new="\"defines\":[\"x\",\"x\"]"),
      good.replace(old="\"uses\":[]", new="\"uses\":[\"x\",\"x\"]"),
      good.replace(
        old="\"variables\":[\"x\"]",
        new="\"variables\":[\"x\",\"x\"]",
      ),
      good.replace(
        old="\"variables\":[\"x\"]",
        new="\"variables\":[\"bad name\"]",
      ),
      good.replace(
        old="\"blocks\":[",
        new="\"blocks\":[{\"node\":\"n\",\"defines\":[],\"uses\":[]},",
      ),
      good.replace(old="\"node\":\"n\"", new="\"node\":\"n\",\"node\":\"n\""),
      good.replace(old="\"entry\":\"n\"", new="\"entry\":\"n\",\"entry\":\"n\""),
      good.replace(
        old="\"variables\":[\"x\"]",
        new="\"variables\":[\"x\"],\"variables\":[\"x\"]",
      ),
      good.replace(old="\"nodes\":[\"n\",\"other\"]", new="\"nodes\":[]"),
    ] {
    let rejected = try {
      ignore(parse_program(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "program JSON refuses oversized exports of otherwise valid maximum programs" {
  let prefix = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012345678"
  let names = Array::makei(512, index => prefix + index.to_string())
  let edges : Array[(Int32, Int32)] = []
  for from in 0..<16 {
    for to in 0..<512 {
      edges.push((from, to))
    }
  }
  let program : FlowProgram = {
    graph: { nodes: names, edges, entry: 0, exits: [], },
    variables: names.copy(),
    definitions: Array::makei(512, node => {
      if node < 32 {
        Array::makei(512, variable => variable)
      } else {
        []
      }
    }),
    uses: Array::makei(512, _ => []),
  }
  validate_program(program)
  let error = try {
    ignore(program_json_text(program))
    "accepted"
  } catch {
    Invalid(message) => message
  }
  assert_eq(error, "serialized program JSON exceeds 2 MiB")
}

///|
test "program JSON enforces association limits during parsing and validates serialization" {
  let program : FlowProgram = {
    graph: {
      nodes: Array::makei(32, node => "n" + node.to_string()),
      edges: [],
      entry: 0,
      exits: [],
    },
    variables: Array::makei(512, variable => "v" + variable.to_string()),
    definitions: Array::makei(32, _ => Array::makei(512, variable => variable)),
    uses: Array::makei(32, _ => []),
  }
  let serialized = program_json_text(program)
  let restored = parse_program(serialized)
  assert_eq(restored.variables.length(), 512)
  assert_eq(restored.definitions[31].length(), 512)
  let too_many = serialized.replace(
    old="\"uses\": []",
    new="\"uses\": [\"v0\"]",
  )
  assert_true(too_many != serialized)
  let parse_rejected = try {
    ignore(parse_program(too_many))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(parse_rejected)
  for
    invalid in [
      { ..program, graph: { ..program.graph, entry: -1, }, },
      { ..program, definitions: [], },
      { ..program, variables: [], },
      { ..program, uses: Array::makei(32, _ => [0]), },
    ] {
    let rejected = try {
      ignore(program_json_text(invalid))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}
