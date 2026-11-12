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
/// Requires an unmodified, valid result from analyze. Keeping the original edge
/// distinguishes different successors that induce the same control dependency.
/// Return the lexicographic prefix and whether every witness fit in the bound.
fn bounded_control_witnesses_of(
  analysis : Analysis,
) -> (Array[ControlWitness], Bool) {
  let n = analysis.graph.nodes.length()
  let post = analysis.post
  let witnesses : Array[ControlWitness] = []
  let edges = analysis.graph.edges.copy()
  edges.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  for (controller, successor) in edges {
    if !post.reachable[controller] || !post.reachable[successor] {
      continue
    }
    // A successor that strictly postdominates the controller induces nothing.
    // Start at the parent so a self-edge retains its self-control witness.
    let mut ancestor = post.immediate[controller]
    let mut successor_is_strict_postdominator = false
    while ancestor is Some(node) {
      if node == successor {
        successor_is_strict_postdominator = true
        break
      }
      ancestor = post.immediate[node]
    }
    if successor_is_strict_postdominator {
      continue
    }
    let stop = post.immediate[controller]
    let dependents = []
    let mut cursor : Int32? = Some(successor)
    while cursor != stop {
      match cursor {
        Some(dependent) => {
          if dependent < n {
            dependents.push(dependent)
          }
          cursor = post.immediate[dependent]
        }
        None => break
      }
    }
    dependents.sort()
    for dependent in dependents {
      if witnesses.length() == max_control_witnesses {
        return (witnesses, false)
      }
      witnesses.push({ controller, successor, dependent, })
    }
  }
  (witnesses, true)
}

///|
/// Return edge-level witnesses sorted by controller, successor, then dependent.
/// As with analyze, control dependence is conditioned on finite paths reaching
/// declared terminal exits. Unreachable edges and edges without such paths are
/// excluded; this does not establish termination of every execution.
/// Raise GraphError if more than 65,536 witnesses would be returned.
pub fn control_dependence_witnesses(
  graph : Graph,
) -> Array[ControlWitness] raise GraphError {
  let (witnesses, complete) = bounded_control_witnesses_of(analyze(graph))
  if !complete {
    raise Invalid("control-dependence witness limit of 65536 exceeded")
  }
  witnesses
}
