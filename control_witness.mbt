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
fn witness_dependents(
  post : DominatorTree,
  controller : Int32,
  successor : Int32,
  node_count : Int32,
) -> Array[Int32] {
  if !post.reachable[controller] || !post.reachable[successor] {
    return []
  }
  // Start at the parent so a self-edge can retain its self-control witness.
  let stop = post.immediate[controller]
  let mut ancestor = stop
  while ancestor is Some(node) {
    if node == successor {
      return []
    }
    ancestor = post.immediate[node]
  }
  let dependents = []
  let mut cursor : Int32? = Some(successor)
  while cursor != stop {
    match cursor {
      Some(dependent) => {
        if dependent < node_count {
          dependents.push(dependent)
        }
        cursor = post.immediate[dependent]
      }
      None => break
    }
  }
  dependents.sort()
  dependents
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
  let edges = graph.edges.copy()
  edges.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  for (controller, successor) in edges {
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
  let graph = snapshot_graph(graph)
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
  let graph = snapshot_graph(graph)
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
