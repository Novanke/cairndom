///|
fn graph_structure(
  graph : Graph,
  forward : Dominance,
) -> (Array[NaturalLoop], Array[Component]) {
  let n = graph.nodes.length()
  let (succ, pred) = adjacency(graph)

  // Finish an iterative DFS before traversing the reversed graph.
  let seen = Array::make(n, false)
  let finished : Array[Int32] = []
  for start in 0..<n {
    if !forward.reachable[start] || seen[start] {
      continue
    }
    let stack = [(start, false)]
    while !stack.is_empty() {
      let (node, expanded) = stack.pop().unwrap()
      if expanded {
        finished.push(node)
        continue
      }
      if seen[node] {
        continue
      }
      seen[node] = true
      stack.push((node, true))
      for next in succ[node] {
        if forward.reachable[next] && !seen[next] {
          stack.push((next, false))
        }
      }
    }
  }
  let assigned = Array::make(n, false)
  let groups : Array[Array[Int32]] = []
  for index = finished.length() - 1; index >= 0; index = index - 1 {
    let start = finished[index]
    if assigned[start] {
      continue
    }
    let members = []
    let stack = [start]
    assigned[start] = true
    while !stack.is_empty() {
      let node = stack.pop().unwrap()
      members.push(node)
      for previous in pred[node] {
        if forward.reachable[previous] && !assigned[previous] {
          assigned[previous] = true
          stack.push(previous)
        }
      }
    }
    members.sort()
    groups.push(members)
  }
  groups.sort_by(fn(left, right) { left[0].compare(right[0]) })
  let group_index = Array::make(n, -1)
  for index, members in groups {
    for node in members {
      group_index[node] = index
    }
  }
  let components : Array[Component] = []
  for index, members in groups {
    let entry_nodes = []
    for node in members {
      if node == graph.entry ||
        pred[node].any(fn(previous) {
          forward.reachable[previous] && group_index[previous] != index
        }) {
        entry_nodes.push(node)
      }
    }
    components.push({
      members,
      entry_nodes,
      cyclic: members.length() > 1 || succ[members[0]].contains(members[0]),
      multiple_entries: entry_nodes.length() > 1,
    })
  }

  // Collect all back edges for a header before taking predecessor closure.
  let by_header : Array[Array[Int32]] = Array::makei(n, _ => [])
  for (latch, header) in graph.edges {
    if dominates_validated(forward, header, latch) {
      by_header[header].push(latch)
    }
  }
  let loops : Array[NaturalLoop] = []
  let loop_membership : Array[Array[Bool]] = []
  for header, latches in by_header {
    if latches.is_empty() {
      continue
    }
    latches.sort()
    let included = Array::make(n, false)
    let considered = Array::make(n, false)
    let stack : Array[Int32] = []
    included[header] = true
    considered[header] = true
    for latch in latches {
      if !included[latch] {
        included[latch] = true
        considered[latch] = true
        stack.push(latch)
      }
    }
    while !stack.is_empty() {
      let node = stack.pop().unwrap()
      for previous in pred[node] {
        if considered[previous] || !forward.reachable[previous] {
          continue
        }
        considered[previous] = true
        if dominates_validated(forward, header, previous) {
          included[previous] = true
          stack.push(previous)
        }
      }
    }
    let members = []
    for node in 0..<n {
      if included[node] {
        members.push(node)
      }
    }
    loops.push({ header, latches: latches.copy(), members, parent: None, })
    loop_membership.push(included)
  }
  for index, natural_loop in loops {
    let mut parent : Int32? = None
    let mut parent_size = n + 1
    for candidate, outer in loops {
      if outer.members.length() <= natural_loop.members.length() ||
        outer.members.length() >= parent_size {
        continue
      }
      if natural_loop.members.all(fn(node) { loop_membership[candidate][node] }) {
        parent = Some(candidate)
        parent_size = outer.members.length()
      }
    }
    loops[index] = { ..natural_loop, parent, }
  }
  (loops, components)
}
