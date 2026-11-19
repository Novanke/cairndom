///|
/// Original entry-reachable edges entering, leaving, and returning to the header
/// of a natural loop. Each edge list is sorted by source then target index.
#derive(Eq, Debug)
pub(all) struct LoopBoundary {
  header : Int32
  entering_edges : Array[(Int32, Int32)]
  leaving_edges : Array[(Int32, Int32)]
  back_edges : Array[(Int32, Int32)]
}

///|
pub extend LoopBoundary with Eq::{equal, not_equal}

///|
pub extend LoopBoundary with Debug::{to_repr}

///|
let max_loop_boundary_edges : Int32 = 65536

///|
// The graph and natural loops are already validated and entry-reachable.
fn loop_boundaries_of(
  graph : Graph,
  reachable : Array[Bool],
  loops : Array[NaturalLoop],
) -> Array[LoopBoundary] raise GraphError {
  if loops.is_empty() {
    return []
  }
  let n = graph.nodes.length()
  let edges = graph.edges.copy()
  edges.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  let boundaries : Array[LoopBoundary] = []
  let mut emitted_edges = 0
  for natural_loop in loops {
    let members = Array::make(n, false)
    let latches = Array::make(n, false)
    for node in natural_loop.members {
      members[node] = true
    }
    for latch in natural_loop.latches {
      latches[latch] = true
    }
    let entering_edges = []
    let leaving_edges = []
    let back_edges = []
    for (from, to) in edges {
      if !reachable[from] || !reachable[to] {
        continue
      }
      if !members[from] && members[to] {
        if emitted_edges == max_loop_boundary_edges {
          raise Invalid("loop boundary edge limit of 65536 exceeded")
        }
        emitted_edges += 1
        entering_edges.push((from, to))
      }
      if members[from] && !members[to] {
        if emitted_edges == max_loop_boundary_edges {
          raise Invalid("loop boundary edge limit of 65536 exceeded")
        }
        emitted_edges += 1
        leaving_edges.push((from, to))
      }
      if to == natural_loop.header && latches[from] {
        if emitted_edges == max_loop_boundary_edges {
          raise Invalid("loop boundary edge limit of 65536 exceeded")
        }
        emitted_edges += 1
        back_edges.push((from, to))
      }
    }
    boundaries.push({
      header: natural_loop.header,
      entering_edges,
      leaving_edges,
      back_edges,
    })
  }
  boundaries
}

///|
/// Describe natural-loop boundaries in header order, excluding unreachable
/// edges. A loop containing the graph entry has no synthetic entering edge.
/// An empty leaving-edge list describes graph structure, not termination.
/// Only entry reachability, immediate dominators and loop membership are
/// needed. Raise GraphError if the combined lists exceed 65,536 edge pairs.
pub fn loop_boundaries(graph : Graph) -> Array[LoopBoundary] raise GraphError {
  let graph = snapshot_graph(graph)
  let (succ, pred) = adjacency(graph)
  let forward = compute_dominator_tree(succ, pred, graph.entry)
  let loops = natural_loops(graph, pred, forward, nest=false)
  loop_boundaries_of(graph, forward.reachable, loops)
}
