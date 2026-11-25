///|
// The graph is validated and entry_reachable has one slot per original node.
// Full analysis already owns this reachability result; standalone queries need
// only a traversal, not the forward dominator tree or any structural analysis.
fn exit_path_adjacency(
  graph : Graph,
  entry_reachable : Array[Bool],
) -> (Array[Array[Int32]], Array[Array[Int32]]) {
  let n = graph.nodes.length()
  let reverse : Array[Array[Int32]] = Array::makei(n + 1, _ => [])
  let reverse_pred : Array[Array[Int32]] = Array::makei(n + 1, _ => [])
  for (from, to) in graph.edges {
    if entry_reachable[from] && entry_reachable[to] {
      reverse[to].push(from)
      reverse_pred[from].push(to)
    }
  }
  for exit in graph.exits {
    if entry_reachable[exit] {
      reverse[n].push(exit)
      reverse_pred[exit].push(n)
    }
  }
  (reverse, reverse_pred)
}

///|
fn compute_postdominance(graph : Graph, reachable : Array[Bool]) -> Dominance {
  let (reverse, reverse_pred) = exit_path_adjacency(graph, reachable)
  compute_dominance(reverse, reverse_pred, graph.nodes.length())
}

///|
fn entry_reachability(graph : Graph) -> Array[Bool] {
  let n = graph.nodes.length()
  let succ : Array[Array[Int32]] = Array::makei(n, _ => [])
  for (from, to) in graph.edges {
    succ[from].push(to)
  }
  reachable_from(succ, graph.entry)
}

///|
/// Compute postdominance without forward dominators, control dependencies,
/// loops or SCCs. Scope is finite paths from entry reaching declared terminal
/// exits, exactly as analyze(graph).post; this is not a termination proof.
/// The root is the virtual exit at graph.nodes.length(), and all arrays have
/// one extra slot for it. With no reachable declared exit only that root is
/// reachable. Returned arrays are independently owned.
pub fn postdominators(graph : Graph) -> Dominance raise GraphError {
  validate_graph(graph)
  compute_postdominance(graph, entry_reachability(graph))
}
