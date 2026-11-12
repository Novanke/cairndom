///|
/// Intersect two known immediate-dominator chains using reverse-postorder ranks.
fn intersect_dominators(
  parents : Array[Int32],
  ranks : Array[Int32],
  left : Int32,
  right : Int32,
) -> Int32 {
  let mut a = left
  let mut b = right
  while a != b {
    while ranks[a] > ranks[b] {
      a = parents[a]
    }
    while ranks[b] > ranks[a] {
      b = parents[b]
    }
  }
  a
}

///|
/// Cooper-Harvey-Kennedy iteration over DFS reverse postorder. The caller supplies
/// valid adjacency arrays and a valid root, including a virtual root if needed.
fn compute_dominance(
  succ : Array[Array[Int32]],
  pred : Array[Array[Int32]],
  root : Int32,
) -> Dominance {
  let n = succ.length()
  let reachable = Array::make(n, false)
  let postorder : Array[Int32] = []
  // Explicit DFS frames avoid dependence on the host's recursion limit.
  let dfs_nodes = Array::make(n, 0)
  let dfs_next = Array::make(n, 0)
  let mut top = 0
  dfs_nodes[0] = root
  reachable[root] = true
  while top >= 0 {
    let node = dfs_nodes[top]
    if dfs_next[top] < succ[node].length() {
      let child = succ[node][dfs_next[top]]
      dfs_next[top] = dfs_next[top] + 1
      if !reachable[child] {
        reachable[child] = true
        top = top + 1
        dfs_nodes[top] = child
        dfs_next[top] = 0
      }
    } else {
      postorder.push(node)
      top = top - 1
    }
  }
  let rpo : Array[Int32] = []
  let ranks = Array::make(n, -1)
  for i in 0..<postorder.length() {
    let node = postorder[postorder.length() - 1 - i]
    ranks[node] = i
    rpo.push(node)
  }
  // The internal root is its own parent; -1 denotes a not-yet-known parent.
  let parents = Array::make(n, -1)
  parents[root] = root
  let mut changed = true
  while changed {
    changed = false
    for i in 1..<rpo.length() {
      let node = rpo[i]
      let mut parent = -1
      for predecessor in pred[node] {
        if parents[predecessor] >= 0 {
          parent = if parent < 0 {
            predecessor
          } else {
            intersect_dominators(parents, ranks, parent, predecessor)
          }
        }
      }
      if parent != parents[node] {
        parents[node] = parent
        changed = true
      }
    }
  }
  let immediate : Array[Int32?] = Array::make(n, None)
  for node in rpo {
    if node != root {
      immediate[node] = Some(parents[node])
    }
  }
  let marks = Array::makei(n, _ => Array::make(n, false))
  for target in rpo {
    for predecessor in pred[target] {
      if reachable[predecessor] {
        let mut runner = predecessor
        while true {
          // A strict dominator of target cannot contain target in its frontier.
          // The root has no strict dominator, so an edge back to it must also
          // put root in its own frontier. This includes a one-node self-loop.
          if target != root && runner == parents[target] {
            break
          }
          marks[runner][target] = true
          if runner == root {
            break
          }
          runner = parents[runner]
        }
      }
    }
  }
  let frontiers = Array::makei(n, _ => [])
  for node in 0..<n {
    for target in 0..<n {
      if marks[node][target] {
        frontiers[node].push(target)
      }
    }
  }
  { root, reachable, immediate, frontiers, }
}

///|
/// Compute entry-rooted immediate dominators and dominance frontiers. Only paths
/// reachable from entry participate; unreachable predecessors are ignored.
pub fn dominators(graph : Graph) -> Dominance raise GraphError {
  let snapshot = snapshot_graph(graph)
  let (succ, pred) = adjacency(snapshot)
  compute_dominance(succ, pred, snapshot.entry)
}
