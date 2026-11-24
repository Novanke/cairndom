///|
/// An original edge controller -> successor makes dependent control-dependent
/// on controller. Indices refer to the analyzed graph's nodes.
#derive(Eq, Debug)
pub(all) struct ControlWitness {
  controller : Int32
  successor : Int32
  dependent : Int32
}

///|
pub extend ControlWitness with Eq::{equal, not_equal}

///|
pub extend ControlWitness with Debug::{to_repr}

///|
let max_control_witnesses : Int32 = 65536

///|
// A false visitor result stops the walk before the remaining dependents.
fn visit_witness_dependents(
  post : DominatorTree,
  controller : Int32,
  successor : Int32,
  node_count : Int32,
  visit : (Int32) -> Bool,
) -> Bool {
  if !post.reachable[controller] || !post.reachable[successor] {
    return true
  }
  // Start at the parent so a self-edge can retain its self-control witness.
  let stop = post.immediate[controller]
  let mut ancestor = stop
  while ancestor is Some(node) {
    if node == successor {
      return true
    }
    ancestor = post.immediate[node]
  }
  let mut cursor : Int32? = Some(successor)
  while cursor != stop {
    match cursor {
      Some(dependent) => {
        if dependent < node_count && !visit(dependent) {
          return false
        }
        cursor = post.immediate[dependent]
      }
      None => break
    }
  }
  true
}

///|
fn witness_dependents(
  post : DominatorTree,
  controller : Int32,
  successor : Int32,
  node_count : Int32,
) -> Array[Int32] {
  let dependents = []
  ignore(
    visit_witness_dependents(post, controller, successor, node_count, node => {
      dependents.push(node)
      true
    }),
  )
  dependents.sort()
  dependents
}

///|
fn sorted_witness_edges(graph : Graph) -> Array[(Int32, Int32)] {
  let edges = graph.edges.copy()
  edges.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  edges
}

///|
// Count before writing the header flag. Completeness is independent of edge
// order, and the first witness past the cap is sufficient to decide it.
fn control_witness_prefix_size(
  graph : Graph,
  post : DominatorTree,
) -> (Int32, Bool) {
  let n = graph.nodes.length()
  let mut count = 0
  for (controller, successor) in graph.edges {
    let exhausted = visit_witness_dependents(post, controller, successor, n, _ => {
      if count == max_control_witnesses {
        false
      } else {
        count += 1
        true
      }
    })
    if !exhausted {
      return (count, false)
    }
  }
  (count, true)
}

///|
// Keeping each original edge distinguishes successors that induce the same
// dependency. Return the sorted prefix and whether every witness fit.
fn bounded_control_witnesses(
  graph : Graph,
  post : DominatorTree,
) -> (Array[ControlWitness], Bool) {
  let n = graph.nodes.length()
  let witnesses : Array[ControlWitness] = []
  for (controller, successor) in sorted_witness_edges(graph) {
    for dependent in witness_dependents(post, controller, successor, n) {
      if witnesses.length() == max_control_witnesses {
        return (witnesses, false)
      }
      witnesses.push({ controller, successor, dependent, })
    }
  }
  (witnesses, true)
}

///|
// Full reports already own the postdominator tree from analyze.
fn bounded_control_witnesses_of(
  analysis : Analysis,
) -> (Array[ControlWitness], Bool) {
  bounded_control_witnesses(analysis.graph, analysis.post.parent_tree())
}

///|
fn witness_post_tree(graph : Graph) -> DominatorTree? {
  let reachable = entry_reachability(graph)
  if !graph.exits.any(exit => reachable[exit]) {
    return None
  }
  let (reverse, reverse_pred) = exit_path_adjacency(graph, reachable)
  Some(compute_dominator_tree(reverse, reverse_pred, graph.nodes.length()))
}

///|
/// Return edge-level witnesses sorted by controller, successor, then dependent.
/// As with analyze, control dependence is conditioned on finite paths reaching
/// declared terminal exits. Unreachable edges and edges without such paths are
/// excluded; this does not establish termination of every execution.
/// Only entry reachability and immediate postdominators are needed.
/// Raise GraphError if more than 65,536 witnesses would be returned.
pub fn control_dependence_witnesses(
  graph : Graph,
) -> Array[ControlWitness] raise GraphError {
  validate_graph(graph)
  guard witness_post_tree(graph) is Some(post) else { return [] }
  let (witnesses, complete) = bounded_control_witnesses(graph, post)
  if !complete {
    raise Invalid("control-dependence witness limit of 65536 exceeded")
  }
  witnesses
}

///|
/// Return all finite-exit control witnesses for one original directed edge.
/// Dependents are sorted by node index. A valid edge with no witness has an
/// empty result. Invalid graphs, indices, and missing edges raise GraphError.
/// The aggregate witness limit does not apply to this selected edge.
pub fn control_dependence_witnesses_at(
  graph : Graph,
  controller : Int32,
  successor : Int32,
) -> Array[ControlWitness] raise GraphError {
  validate_graph(graph)
  let n = graph.nodes.length()
  if controller < 0 || controller >= n {
    raise Invalid("control witness controller index is outside the graph")
  }
  if successor < 0 || successor >= n {
    raise Invalid("control witness successor index is outside the graph")
  }
  if !graph.edges.contains((controller, successor)) {
    raise Invalid("control witness edge does not exist")
  }
  guard witness_post_tree(graph) is Some(post) else { return [] }
  witness_dependents(post, controller, successor, n).map(dependent => {
    controller,
    successor,
    dependent,
  })
}
