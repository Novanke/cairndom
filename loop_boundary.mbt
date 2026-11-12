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
/// Requires an unmodified, valid result from analyze. Returned edge arrays are
/// fresh copies and do not share storage with the graph or natural-loop arrays.
fn loop_boundaries_of(
  analysis : Analysis,
) -> Array[LoopBoundary] raise GraphError {
  let n = analysis.graph.nodes.length()
  let edges = analysis.graph.edges.copy()
  edges.sort_by(fn(left, right) {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else {
      left.1.compare(right.1)
    }
  })
  let boundaries : Array[LoopBoundary] = []
  let mut emitted_edges = 0
  for natural_loop in analysis.loops {
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
      if !analysis.forward.reachable[from] || !analysis.forward.reachable[to] {
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
/// Raise GraphError if the combined edge lists would exceed 65,536 pairs.
pub fn loop_boundaries(graph : Graph) -> Array[LoopBoundary] raise GraphError {
  loop_boundaries_of(analyze(graph))
}
