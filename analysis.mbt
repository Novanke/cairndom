///|
/// Analyze the entry-reachable graph. Postdominance and control dependence are
/// conditioned on finite paths reaching the explicitly declared terminal exits.
pub fn analyze(input : Graph) -> Analysis raise GraphError {
  let graph = snapshot_graph(input)
  let n = graph.nodes.length()
  let (succ, pred) = adjacency(graph)
  let forward = compute_dominance(succ, pred, graph.entry)
  let reverse = Array::makei(n + 1, _ => [])
  let reverse_pred = Array::makei(n + 1, _ => [])
  for (from, to) in graph.edges {
    if forward.reachable[from] && forward.reachable[to] {
      reverse[to].push(from)
      reverse_pred[from].push(to)
    }
  }
  for exit in graph.exits {
    if forward.reachable[exit] {
      reverse[n].push(exit)
      reverse_pred[exit].push(n)
    }
  }
  let post = compute_dominance(reverse, reverse_pred, n)
  let controls = Array::makei(n, _ => Array::make(n, false))
  for (from, to) in graph.edges {
    if !post.reachable[from] || !post.reachable[to] {
      continue
    }
    if from != to && dominates(post, to, from) {
      continue
    }
    let stop = post.immediate[from]
    let mut cursor : Int32? = Some(to)
    while cursor != stop {
      match cursor {
        Some(node) => {
          if node < n {
            controls[node][from] = true
          }
          cursor = post.immediate[node]
        }
        None => break
      }
    }
  }
  let control_dependencies = controls.map(row => {
    let indices = []
    for index, yes in row {
      if yes {
        indices.push(index)
      }
    }
    indices
  })
  let (loops, components) = graph_structure(graph, forward)
  { graph, forward, post, loops, components, control_dependencies, }
}

///|
/// Iterated dominance frontier, for example SSA phi-placement candidates.
/// live_in restricts propagation to the caller's live-in nodes when provided.
/// This identifies locations only. It does not rewrite an IR or infer liveness.
pub fn iterated_frontier(
  tree : Dominance,
  definitions : Array[Int32],
  live_in~ : Array[Int32]? = None,
) -> Array[Int32] raise GraphError {
  let n = tree.reachable.length()
  if n == 0 ||
    n > max_nodes + 1 ||
    tree.immediate.length() != n ||
    tree.frontiers.length() != n {
    raise Invalid("invalid dominator tree dimensions")
  }
  let allowed = Array::make(n, live_in is None)
  if live_in is Some(nodes) {
    for node in nodes {
      if node < 0 || node >= n || !tree.reachable[node] {
        raise Invalid("live-in node is outside the reachable tree")
      }
      allowed[node] = true
    }
  }
  let queued = Array::make(n, false)
  let selected = Array::make(n, false)
  let work = []
  for node in definitions {
    if node < 0 || node >= n || !tree.reachable[node] {
      raise Invalid("definition node is outside the reachable tree")
    }
    if !queued[node] {
      queued[node] = true
      work.push(node)
    }
  }
  let mut cursor = 0
  while cursor < work.length() {
    let current = work[cursor]
    cursor += 1
    for target in tree.frontiers[current] {
      if target < 0 || target >= n || !tree.reachable[target] {
        raise Invalid("invalid dominance frontier member")
      }
      if allowed[target] && !selected[target] {
        selected[target] = true
        if !queued[target] {
          queued[target] = true
          work.push(target)
        }
      }
    }
  }
  let result = []
  for node, yes in selected {
    if yes {
      result.push(node)
    }
  }
  result
}
