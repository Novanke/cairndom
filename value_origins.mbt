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
}

///|
let max_value_origin_relations : Int32 = 65536

///|
/// Explain each entry-reachable use over all finite entry-to-use paths,
/// including uses in permanent loops. Uses precede local definitions; a block's
/// own definition can reach its use through a previous loop iteration.
/// Results are ordered by node then variable, with definition blocks sorted by
/// node index. At most 65,536 source/use relations are returned, counting each
/// incoming-value flag as one source. Oversized complete results raise an error
/// rather than returning a partial list. Each reverse search uses O(n) scratch
/// space and O(n + e) work, without a block/variable/source state matrix.
pub fn trace_values(input : FlowProgram) -> ValueOrigins raise GraphError {
  validate_program(input)
  let program : FlowProgram = {
    graph: snapshot_graph(input.graph),
    variables: input.variables.copy(),
    definitions: input.definitions.map(row => row.copy()),
    uses: input.uses.map(row => row.copy()),
  }
  let graph = program.graph
  let n = graph.nodes.length()
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
  let use_sites : Array[Array[Int32]] = Array::makei(
    program.variables.length(),
    _ => [],
  )
  for node in 0..<n {
    if reachable[node] {
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
    let defined = Array::makei(n, node => {
      reachable[node] && program.definitions[node].contains(variable)
    })
    for node in sites {
      let seen = Array::make(n, false)
      let sources = Array::make(n, false)
      let work = [node]
      seen[node] = true
      let mut cursor = 0
      let mut requires_entry_value = false
      while cursor < work.length() {
        let current = work[cursor]
        cursor += 1
        if current == graph.entry && !requires_entry_value {
          if relations == max_value_origin_relations {
            raise Invalid("value-origin relation limit of 65536 exceeded")
          }
          relations += 1
          requires_entry_value = true
        }
        for previous in pred[current] {
          if !reachable[previous] {
            continue
          }
          // Test definitions before seen: an already visited use block can
          // supply its local definition through a self-edge or another cycle.
          if defined[previous] {
            if !sources[previous] {
              if relations == max_value_origin_relations {
                raise Invalid("value-origin relation limit of 65536 exceeded")
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
      origins.push({ node, variable, definitions, requires_entry_value, })
    }
  }
  origins.sort_by(fn(left, right) {
    if left.node != right.node {
      left.node.compare(right.node)
    } else {
      left.variable.compare(right.variable)
    }
  })
  { program, reachable, origins, }
}

///|
/// Return an independently mutable input snapshot, including all graph arrays
/// and nested definition/use rows. Editing it cannot change these origins.
pub fn ValueOrigins::program(self : Self) -> FlowProgram {
  let program = self.program
  let graph = program.graph
  {
    graph: {
      nodes: graph.nodes.copy(),
      edges: graph.edges.copy(),
      entry: graph.entry,
      exits: graph.exits.copy(),
    },
    variables: program.variables.copy(),
    definitions: program.definitions.map(row => row.copy()),
    uses: program.uses.map(row => row.copy()),
  }
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
