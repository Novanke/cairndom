///|
/// Possible last-definition blocks for a use before the block's local defs.
/// requires_entry_value records a possible caller-supplied incoming value;
/// it does not establish a source-language missing-initialization error.
#derive(Eq, Debug)
pub(all) struct UseOrigins {
  node : Int32
  variable : Int32
  definitions : Array[Int32]
  requires_entry_value : Bool
}

///|
pub extend UseOrigins with Eq::{equal, not_equal}

///|
pub extend UseOrigins with Debug::{to_repr}

///|
/// Privately owned input and complete per-use results. Inspection methods
/// return defensive copies so later caller edits cannot alter saved answers.
struct ValueOrigins {
  program : FlowProgram
  reachable : Array[Bool]
  origins : Array[UseOrigins]
  source_relation_count : Int32
}

///|
let max_value_origin_relations : Int32 = 65536

///|
let value_origin_limit_message = "value-origin relation limit of 65536 exceeded"

///|
priv struct ValueOriginGraph {
  entry : Int32
  reachable : Array[Bool]
  predecessors : Array[Array[Int32]]
}

///|
fn value_origin_graph(graph : Graph) -> ValueOriginGraph {
  let (successors, predecessors) = adjacency(graph)
  let reachable = Array::make(graph.nodes.length(), false)
  let visit = [graph.entry]
  reachable[graph.entry] = true
  let mut next = 0
  while next < visit.length() {
    let node = visit[next]
    next += 1
    for child in successors[node] {
      if !reachable[child] {
        reachable[child] = true
        visit.push(child)
      }
    }
  }
  { entry: graph.entry, reachable, predecessors, }
}

///|
fn ValueOriginGraph::definition_sites(
  self : Self,
  program : FlowProgram,
  variable : Int32,
) -> Array[Bool] {
  Array::makei(self.reachable.length(), node => {
    self.reachable[node] && program.definitions[node].contains(variable)
  })
}

///|
// Walk reachable predecessors until the first definition on each route. The
// budget includes the incoming-value marker, as in the full report.
fn ValueOriginGraph::find_origins(
  self : Self,
  node : Int32,
  variable : Int32,
  defined : Array[Bool],
  budget : Int32,
) -> (UseOrigins, Int32) raise GraphError {
  let seen = Array::make(self.reachable.length(), false)
  let sources = Array::make(self.reachable.length(), false)
  let work = [node]
  seen[node] = true
  let mut cursor = 0
  let mut relations = 0
  let mut requires_entry_value = false
  while cursor < work.length() {
    let current = work[cursor]
    cursor += 1
    if current == self.entry {
      if relations == budget {
        raise Invalid(value_origin_limit_message)
      }
      relations += 1
      requires_entry_value = true
    }
    for previous in self.predecessors[current] {
      if !self.reachable[previous] {
        continue
      }
      // Test definitions before seen: an already visited use block can
      // supply its local definition through a self-edge or another cycle.
      if defined[previous] {
        if !sources[previous] {
          if relations == budget {
            raise Invalid(value_origin_limit_message)
          }
          relations += 1
          sources[previous] = true
        }
      } else if !seen[previous] {
        seen[previous] = true
        work.push(previous)
      }
    }
  }
  let definitions = []
  for source, yes in sources {
    if yes {
      definitions.push(source)
    }
  }
  ({ node, variable, definitions, requires_entry_value, }, relations)
}

///|
/// Explain one declared use before local definitions, using block and variable
/// indices into program. The result matches the corresponding trace_values row
/// and its definitions are owned. Return None for a declared unreachable use.
/// Invalid indices, malformed program facts, or a pair absent from the block's
/// uses row raise GraphError. The aggregate result limit does not apply here.
pub fn trace_use(
  program : FlowProgram,
  node : Int32,
  variable : Int32,
) -> UseOrigins? raise GraphError {
  validate_program(program)
  trace_use_checked(program, node, variable)
}

///|
fn trace_use_checked(
  program : FlowProgram,
  node : Int32,
  variable : Int32,
) -> UseOrigins? raise GraphError {
  if node < 0 || node >= program.graph.nodes.length() {
    raise Invalid("value-origin node index is outside the graph")
  }
  if variable < 0 || variable >= program.variables.length() {
    raise Invalid("value-origin variable index is outside the program")
  }
  if !program.uses[node].contains(variable) {
    raise Invalid("value-origin use is not declared in the block")
  }
  let search = value_origin_graph(program.graph)
  if !search.reachable[node] {
    return None
  }
  let defined = search.definition_sites(program, variable)
  // One use has at most one source per node plus one incoming-value marker.
  let (origin, _) = search.find_origins(
    node,
    variable,
    defined,
    search.reachable.length() + 1,
  )
  Some(origin)
}

///|
/// Explain each entry-reachable use over all finite entry-to-use paths,
/// including uses in permanent loops. Uses precede local definitions; a block's
/// own definition can reach its use through a previous loop iteration.
/// Results are ordered by node then variable, with definition blocks sorted by
/// node index. At most 65,536 source/use relations are returned, counting each
/// incoming-value flag as one source. Oversized complete results raise an error
/// rather than returning a partial list. Variables without reachable
/// definitions need no reverse search. Each other reverse search uses O(n)
/// scratch space and O(n + e) work.
pub fn trace_values(input : FlowProgram) -> ValueOrigins raise GraphError {
  validate_program(input)
  let program = copy_program(input)
  let search = value_origin_graph(program.graph)
  let use_sites : Array[Array[Int32]] = Array::makei(
    program.variables.length(),
    _ => [],
  )
  let has_definition = Array::make(program.variables.length(), false)
  for node, reachable in search.reachable {
    if reachable {
      for variable in program.definitions[node] {
        has_definition[variable] = true
      }
      for variable in program.uses[node] {
        use_sites[variable].push(node)
      }
    }
  }
  let origins : Array[UseOrigins] = []
  let mut relations = 0
  for variable, sites in use_sites {
    if sites.is_empty() {
      continue
    }
    // Every reachable use has an entry path. With no reachable definition,
    // the incoming value is its only possible source.
    if !has_definition[variable] {
      if sites.length() > max_value_origin_relations - relations {
        raise Invalid(value_origin_limit_message)
      }
      relations += sites.length()
      for node in sites {
        origins.push({
          node,
          variable,
          definitions: [],
          requires_entry_value: true,
        })
      }
      continue
    }
    let defined = search.definition_sites(program, variable)
    for node in sites {
      let (origin, count) = search.find_origins(
        node,
        variable,
        defined,
        max_value_origin_relations - relations,
      )
      origins.push(origin)
      relations += count
    }
  }
  origins.sort_by(fn(left, right) {
    if left.node != right.node {
      left.node.compare(right.node)
    } else {
      left.variable.compare(right.variable)
    }
  })
  {
    program,
    reachable: search.reachable,
    origins,
    source_relation_count: relations,
  }
}

///|
/// Return an independently mutable input snapshot, including all graph arrays
/// and nested definition/use rows. Editing it cannot change these origins.
pub fn ValueOrigins::program(self : Self) -> FlowProgram {
  copy_program(self.program)
}

///|
/// Return complete origins in node/variable order, copying each definitions
/// array as well as the outer list. Unreachable uses are absent.
pub fn ValueOrigins::uses(self : Self) -> Array[UseOrigins] {
  self.origins.map(origin => {
    ..origin,
    definitions: origin.definitions.copy(),
  })
}

///|
/// Entry reachability, independent of declared exits or eventual termination.
pub fn ValueOrigins::is_reachable(
  self : Self,
  node : Int32,
) -> Bool raise GraphError {
  if node < 0 || node >= self.reachable.length() {
    raise Invalid("value-origin node index is outside the graph")
  }
  self.reachable[node]
}
