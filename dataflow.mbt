///|
/// Block-level variable facts indexed by graph node, with variable indices into
/// variables. A use is a use before any local definition of that variable. Thus
/// a variable may appear in both a block's uses and definitions.
pub(all) struct FlowProgram {
  graph : Graph
  variables : Array[String]
  definitions : Array[Array[Int32]]
  uses : Array[Array[Int32]]
}

///|
/// Backward may-liveness on all entry-reachable paths, including paths in
/// permanent cycles. Unreachable blocks have empty sets. Sets contain variable
/// indices in input variable order, and all result arrays are independently owned.
pub(all) struct Liveness {
  reachable : Array[Bool]
  live_in : Array[Array[Int32]]
  live_out : Array[Array[Int32]]
}

///|
let max_variables : Int32 = 512

///|
let max_program_associations : Int32 = 16384

///|
/// Validate the graph before checking the block facts. Every block has exactly
/// one definitions row and one uses row, including unreachable blocks.
fn validate_program(program : FlowProgram) -> Unit raise GraphError {
  ignore(snapshot_graph(program.graph))
  let variable_count = program.variables.length()
  if variable_count > max_variables {
    raise Invalid("program limit is at most 512 variables")
  }
  let names : Map[String, Bool] = Map([])
  for name in program.variables {
    if !valid_id(name) || names.contains(name) {
      raise Invalid("invalid or duplicate variable ID: " + name)
    }
    names[name] = true
  }
  let node_count = program.graph.nodes.length()
  if program.definitions.length() != node_count ||
    program.uses.length() != node_count {
    raise Invalid("definitions and uses must each have one row per graph node")
  }
  let mut associations = 0
  for rows in [program.definitions, program.uses] {
    for row in rows {
      if row.length() > max_program_associations - associations {
        raise Invalid(
          "program limit is at most 16384 definition/use associations",
        )
      }
      associations += row.length()
      let seen = Array::make(variable_count, false)
      for variable in row {
        if variable < 0 || variable >= variable_count {
          raise Invalid(
            "definition or use variable index is outside the program",
          )
        }
        if seen[variable] {
          raise Invalid("duplicate variable in a definition or use row")
        }
        seen[variable] = true
      }
    }
  }
}

///|
/// Compute the least fixed point live_out[b] = union live_in[successor] and
/// live_in[b] = uses[b] union (live_out[b] minus definitions[b]). Only reachable
/// successors participate; declared exits do not restrict this analysis.
/// The solver uses iterative backward propagation, with at most one queued
/// propagation per reachable block and variable, and never recurses.
pub fn liveness(program : FlowProgram) -> Liveness raise GraphError {
  validate_program(program)
  let graph = program.graph
  let n = graph.nodes.length()
  let m = program.variables.length()
  let (succ, pred) = adjacency(graph)
  let reachable = Array::make(n, false)
  let visit = [graph.entry]
  reachable[graph.entry] = true
  let mut next = 0
  while next < visit.length() {
    let node = visit[next]
    next += 1
    for child in succ[node] {
      if !reachable[child] {
        reachable[child] = true
        visit.push(child)
      }
    }
  }
  let definitions = Array::makei(n, _ => Array::make(m, false))
  let use_sites : Array[Array[Int32]] = Array::makei(m, _ => [])
  for node in 0..<n {
    if reachable[node] {
      for variable in program.definitions[node] {
        definitions[node][variable] = true
      }
      for variable in program.uses[node] {
        use_sites[variable].push(node)
      }
    }
  }
  let in_marks = Array::makei(n, _ => Array::make(m, false))
  let out_marks = Array::makei(n, _ => Array::make(m, false))
  for variable in 0..<m {
    let work = use_sites[variable].copy()
    for node in work {
      in_marks[node][variable] = true
    }
    let mut cursor = 0
    while cursor < work.length() {
      let node = work[cursor]
      cursor += 1
      for previous in pred[node] {
        if reachable[previous] && !out_marks[previous][variable] {
          out_marks[previous][variable] = true
          if !definitions[previous][variable] && !in_marks[previous][variable] {
            in_marks[previous][variable] = true
            work.push(previous)
          }
        }
      }
    }
  }
  let live_in : Array[Array[Int32]] = Array::makei(n, _ => [])
  let live_out : Array[Array[Int32]] = Array::makei(n, _ => [])
  for node in 0..<n {
    for variable in 0..<m {
      if in_marks[node][variable] {
        live_in[node].push(variable)
      }
      if out_marks[node][variable] {
        live_out[node].push(variable)
      }
    }
  }
  { reachable, live_in, live_out, }
}
