///|
// Verification-only definitions. The production package is used for typed
// inputs and parsing, never for expected analysis, dataflow or serialization.
fn object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map(fields))
}

///|
fn selected_names(names : Array[String], selected : Array[Bool]) -> Json {
  let values = []
  for index, name in names {
    if selected[index] {
      values.push(Json::string(name))
    }
  }
  Json::array(values)
}

///|
fn index_names(names : Array[String], indices : Array[Int32]) -> Json {
  Json::array(indices.map(index => Json::string(names[index])))
}

///|
fn name_or_null(names : Array[String], index : Int32) -> Json {
  if index < 0 || index >= names.length() {
    Json::null()
  } else {
    Json::string(names[index])
  }
}

///|
fn adjacency(graph : @dom.Graph) -> (Array[Array[Int32]], Array[Array[Int32]]) {
  let succ = Array::makei(graph.nodes.length(), _ => [])
  let pred = Array::makei(graph.nodes.length(), _ => [])
  for (from, to) in graph.edges {
    succ[from].push(to)
    pred[to].push(from)
  }
  (succ, pred)
}

///|
fn reach(
  edges : Array[Array[Int32]],
  starts : Array[Int32],
  removed : Int32,
  allowed : Array[Bool],
) -> Array[Bool] {
  let found = Array::make(edges.length(), false)
  let pending = starts.copy()
  let mut cursor = 0
  while cursor < pending.length() {
    let node = pending[cursor]
    cursor += 1
    if node == removed || found[node] || !allowed[node] {
      continue
    }
    found[node] = true
    for child in edges[node] {
      pending.push(child)
    }
  }
  found
}

///|
priv struct ReferenceTree {
  reachable : Array[Bool]
  dominators : Array[Array[Bool]]
  parents : Array[Int32]
  frontiers : Array[Array[Bool]]
}

///|
// Removing d destroys every root-to-v path exactly when d dominates v.
// Counting strict ancestors selects the immediate parent without CHK, RPO,
// production tree traversal or any production graph helper.
fn dominance_definition(
  succ : Array[Array[Int32]],
  pred : Array[Array[Int32]],
  root : Int32,
) -> ReferenceTree {
  let n = succ.length()
  let allowed = Array::make(n, true)
  let reachable = reach(succ, [root], -1, allowed)
  let dominators = Array::makei(n, _ => Array::make(n, false))
  for removed in 0..<n {
    if reachable[removed] {
      let surviving = reach(succ, [root], removed, allowed)
      for node in 0..<n {
        dominators[node][removed] = reachable[node] && !surviving[node]
      }
    }
  }
  let depths = dominators.map(row => row.filter(value => value).length())
  let parents = Array::make(n, -1)
  let frontiers = Array::makei(n, _ => Array::make(n, false))
  for node in 0..<n {
    if !reachable[node] {
      continue
    }
    if node != root {
      for ancestor in 0..<n {
        if ancestor != node &&
          dominators[node][ancestor] &&
          (parents[node] < 0 || depths[ancestor] > depths[parents[node]]) {
          parents[node] = ancestor
        }
      }
    }
    for ancestor in 0..<n {
      if ancestor != node && dominators[node][ancestor] {
        continue
      }
      for predecessor in pred[node] {
        if reachable[predecessor] && dominators[predecessor][ancestor] {
          frontiers[ancestor][node] = true
        }
      }
    }
  }
  { reachable, dominators, parents, frontiers, }
}

///|
fn graph_reference(graph : @dom.Graph) -> Json {
  let names = graph.nodes
  let n = names.length()
  let (succ, pred) = adjacency(graph)
  let forward = dominance_definition(succ, pred, graph.entry)
  let reverse = Array::makei(n + 1, _ => [])
  let reverse_pred = Array::makei(n + 1, _ => [])
  for (from, to) in graph.edges {
    if forward.reachable[from] && forward.reachable[to] {
      reverse[to].push(from)
      reverse_pred[from].push(to)
    }
  }
  for terminal in graph.exits {
    if forward.reachable[terminal] {
      reverse[n].push(terminal)
      reverse_pred[terminal].push(n)
    }
  }
  let post = dominance_definition(reverse, reverse_pred, n)
  let controls = Array::makei(n, _ => Array::make(n, false))
  let witnesses = []
  let mut witness_count = 0
  let ordered_edges = graph.edges.copy()
  ordered_edges.sort()
  for (controller, successor) in ordered_edges {
    if !post.reachable[controller] || !post.reachable[successor] {
      continue
    }
    for dependent in 0..<n {
      if post.dominators[successor][dependent] &&
        !(dependent != controller && post.dominators[controller][dependent]) {
        controls[dependent][controller] = true
        witness_count += 1
        if witnesses.length() < 65536 {
          witnesses.push(
            object([
              ("controller", Json::string(names[controller])),
              ("successor", Json::string(names[successor])),
              ("dependent", Json::string(names[dependent])),
            ]),
          )
        }
      }
    }
  }
  // Mutual reachability defines SCC equivalence classes, independently of the
  // production finishing-order algorithm. The first remaining index orders SCCs.
  let closures = Array::makei(n, node => {
    reach(succ, [node], -1, forward.reachable)
  })
  let remaining = forward.reachable.copy()
  let components = []
  for first in 0..<n {
    if !remaining[first] {
      continue
    }
    let members = Array::make(n, false)
    for node in 0..<n {
      members[node] = remaining[node] &&
        closures[first][node] &&
        closures[node][first]
      if members[node] {
        remaining[node] = false
      }
    }
    let entries = Array::make(n, false)
    for node in 0..<n {
      if members[node] {
        entries[node] = node == graph.entry
        for previous in pred[node] {
          if forward.reachable[previous] && !members[previous] {
            entries[node] = true
          }
        }
      }
    }
    components.push(
      object([
        ("members", selected_names(names, members)),
        ("entry_nodes", selected_names(names, entries)),
        (
          "cyclic",
          Json::boolean(
            members.filter(value => value).length() > 1 ||
            succ[first].contains(first),
          ),
        ),
        (
          "multiple_entries",
          Json::boolean(entries.filter(value => value).length() > 1),
        ),
      ]),
    )
  }
  let latches = Array::makei(n, _ => Array::make(n, false))
  for (latch, header) in graph.edges {
    if forward.reachable[latch] && forward.dominators[latch][header] {
      latches[header][latch] = true
    }
  }
  let loop_sets = Array::makei(n, _ => Array::make(n, false))
  let sizes = Array::make(n, 0)
  for header in 0..<n {
    let starts = []
    for latch in 0..<n {
      if latches[header][latch] && latch != header {
        starts.push(latch)
      }
    }
    if latches[header].contains(true) {
      loop_sets[header] = reach(pred, starts, header, forward.reachable)
      loop_sets[header][header] = true
      sizes[header] = loop_sets[header].filter(value => value).length()
    }
  }
  let loops = []
  for header in 0..<n {
    if sizes[header] == 0 {
      continue
    }
    let mut parent = -1
    for other in 0..<n {
      if sizes[other] <= sizes[header] ||
        (parent >= 0 && sizes[other] >= sizes[parent]) {
        continue
      }
      let mut contains = true
      for node in 0..<n {
        if loop_sets[header][node] && !loop_sets[other][node] {
          contains = false
        }
      }
      if contains {
        parent = other
      }
    }
    loops.push(
      object([
        ("header", Json::string(names[header])),
        ("latches", selected_names(names, latches[header])),
        ("members", selected_names(names, loop_sets[header])),
        ("parent_header", name_or_null(names, parent)),
      ]),
    )
  }
  let nodes = []
  let dot = StringBuilder()
  dot.write_string("digraph CairnDom {\n  rankdir=TB;\n")
  for node, name in names {
    let style = if forward.reachable[node] { "solid" } else { "dotted" }
    dot.write_string("  \"\{name}\" [style=\{style}];\n")
    nodes.push(
      object([
        ("id", Json::string(name)),
        ("reachable", Json::boolean(forward.reachable[node])),
        ("can_reach_exit", Json::boolean(post.reachable[node])),
        ("immediate_dominator", name_or_null(names, forward.parents[node])),
        ("dominance_frontier", selected_names(names, forward.frontiers[node])),
        ("immediate_postdominator", name_or_null(names, post.parents[node])),
        (
          "postdominator_is_virtual_exit",
          Json::boolean(post.parents[node] == n),
        ),
        ("control_dependencies", selected_names(names, controls[node])),
      ]),
    )
  }
  for (from, to) in graph.edges {
    dot.write_string("  \"\{names[from]}\" -> \"\{names[to]}\";\n")
  }
  for node, parent in forward.parents {
    if parent >= 0 {
      dot.write_string(
        "  \"\{names[parent]}\" -> \"\{names[node]}\" [style=dashed,color=blue,label=\"idom\"];\n",
      )
    }
  }
  dot.write_string("}\n")
  object([
    (
      "report",
      object([
        ("schema", Json::string("cairndom.analysis.v1")),
        ("entry", Json::string(names[graph.entry])),
        ("exits", index_names(names, graph.exits)),
        (
          "postdominator_scope",
          Json::string("finite_paths_reaching_declared_exits"),
        ),
        ("nodes", Json::array(nodes)),
        ("natural_loops", Json::array(loops)),
        ("components", Json::array(components)),
        ("control_witnesses", Json::array(witnesses)),
        ("control_witnesses_complete", Json::boolean(witness_count <= 65536)),
        ("control_witness_limit", Json::number(65536)),
      ]),
    ),
    ("dot", Json::string(dot.to_string())),
  ])
}

///|
pub fn graph_expected(input : Json) -> Json raise @dom.GraphError {
  graph_reference(@dom.parse_graph(input.stringify()))
}

///|
fn program_reference(program : @dom.FlowProgram) -> Json {
  let graph = program.graph
  let n = graph.nodes.length()
  let count = program.variables.length()
  let (succ, pred) = adjacency(graph)
  let forward = dominance_definition(succ, pred, graph.entry)
  let live_in = Array::makei(n, _ => Array::make(count, false))
  let live_out = Array::makei(n, _ => Array::make(count, false))
  // Starting empty and scanning whole-block set equations finds their least
  // fixed point. This differs from production's per-variable predecessor work.
  let mut changed = true
  while changed {
    changed = false
    for reverse_node in 0..<n {
      let node = n - 1 - reverse_node
      if !forward.reachable[node] {
        continue
      }
      for variable in 0..<count {
        let mut outgoing = false
        for child in succ[node] {
          outgoing = outgoing || live_in[child][variable]
        }
        let incoming = program.uses[node].contains(variable) ||
          (outgoing && !program.definitions[node].contains(variable))
        if outgoing != live_out[node][variable] ||
          incoming != live_in[node][variable] {
          changed = true
          live_out[node][variable] = outgoing
          live_in[node][variable] = incoming
        }
      }
    }
  }
  let phi_variables = Array::makei(n, _ => Array::make(count, false))
  let placements = []
  for variable, name in program.variables {
    let definitions = Array::makei(n, node => {
      forward.reachable[node] && program.definitions[node].contains(variable)
    })
    let live = Array::makei(n, node => live_in[node][variable])
    let selected = Array::make(n, false)
    let mut changed = true
    while changed {
      changed = false
      for source in 0..<n {
        if definitions[source] || selected[source] {
          for target in 0..<n {
            if forward.frontiers[source][target] &&
              live[target] &&
              !selected[target] {
              selected[target] = true
              changed = true
            }
          }
        }
      }
    }
    for node in 0..<n {
      phi_variables[node][variable] = selected[node]
    }
    placements.push(
      object([
        ("variable", Json::string(name)),
        ("definition_blocks", selected_names(graph.nodes, definitions)),
        ("live_in_blocks", selected_names(graph.nodes, live)),
        ("phi_blocks", selected_names(graph.nodes, selected)),
        ("requires_entry_value", Json::boolean(live_in[graph.entry][variable])),
      ]),
    )
  }
  let blocks = []
  for node, name in graph.nodes {
    let defined = Array::makei(count, variable => {
      program.definitions[node].contains(variable)
    })
    let used = Array::makei(count, variable => {
      program.uses[node].contains(variable)
    })
    blocks.push(
      object([
        ("id", Json::string(name)),
        ("reachable", Json::boolean(forward.reachable[node])),
        ("defines", selected_names(program.variables, defined)),
        ("uses", selected_names(program.variables, used)),
        ("live_in", selected_names(program.variables, live_in[node])),
        ("live_out", selected_names(program.variables, live_out[node])),
        (
          "phi_variables",
          selected_names(program.variables, phi_variables[node]),
        ),
      ]),
    )
  }
  object([
    ("schema", Json::string("cairndom.ssa-plan.v1")),
    ("status", Json::string("locations_only")),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("scope", Json::string("entry_reachable_all_paths")),
    ("use_convention", Json::string("before_local_definition")),
    ("variables", Json::array(program.variables.map(Json::string))),
    ("blocks", Json::array(blocks)),
    ("placements", Json::array(placements)),
    (
      "entry_values_required",
      selected_names(program.variables, live_in[graph.entry]),
    ),
    (
      "entry_value_semantics",
      Json::string(
        "Variables live before entry local definitions require a caller-supplied parameter or initial value, or a missing-initialization diagnostic under the source language's rules.",
      ),
    ),
  ])
}

///|
pub fn program_expected(input : Json) -> Json raise @dom.GraphError {
  program_reference(@dom.parse_program(input.stringify()))
}
