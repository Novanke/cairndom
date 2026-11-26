///|
#derive(Debug)
pub(all) suberror GraphError {
  Invalid(String)
}

///|
pub extend GraphError with Debug::{to_repr}

///|
/// Directed graph. Edges use indices into nodes. Exits must be terminal nodes.
pub(all) struct Graph {
  nodes : Array[String]
  edges : Array[(Int32, Int32)]
  entry : Int32
  exits : Array[Int32]
}

///|
/// root is reachable and has no immediate parent. Unreachable nodes also have
/// no parent, so consult reachable. Frontiers and arrays are in node order.
pub(all) struct Dominance {
  root : Int32
  reachable : Array[Bool]
  immediate : Array[Int32?]
  frontiers : Array[Array[Int32]]
}

///|
pub(all) struct NaturalLoop {
  header : Int32
  latches : Array[Int32]
  members : Array[Int32]
  parent : Int32?
}

///|
/// entry_nodes include the graph entry and members with external predecessors.
/// Multiple entries diagnose this SCC. They do not classify every nested cycle.
pub(all) struct Component {
  members : Array[Int32]
  entry_nodes : Array[Int32]
  cyclic : Bool
  multiple_entries : Bool
}

///|
/// post uses a virtual exit at index graph.nodes.length(). It describes finite
/// paths reaching a declared exit and does not prove program termination.
pub(all) struct Analysis {
  graph : Graph
  forward : Dominance
  post : Dominance
  loops : Array[NaturalLoop]
  components : Array[Component]
  control_dependencies : Array[Array[Int32]]
}

///|
let max_nodes : Int32 = 512

///|
let max_edges : Int32 = 8192

///|
fn adjacency(graph : Graph) -> (Array[Array[Int32]], Array[Array[Int32]]) {
  let succ = Array::makei(graph.nodes.length(), _ => [])
  let pred = Array::makei(graph.nodes.length(), _ => [])
  for (from, to) in graph.edges {
    succ[from].push(to)
    pred[to].push(from)
  }
  (succ, pred)
}

///|
fn reachable_from(
  successors : Array[Array[Int32]],
  root : Int32,
  blocked~ : Int32 = -1,
) -> Array[Bool] {
  let reachable = Array::make(successors.length(), false)
  if root == blocked {
    return reachable
  }
  let work = [root]
  reachable[root] = true
  let mut cursor = 0
  while cursor < work.length() {
    let node = work[cursor]
    cursor += 1
    for next in successors[node] {
      if next != blocked && !reachable[next] {
        reachable[next] = true
        work.push(next)
      }
    }
  }
  reachable
}

///|
fn valid_id(id : String) -> Bool {
  if id.length() < 1 || id.length() > 64 {
    return false
  }
  for ch in id {
    if !(ch >= 'a' && ch <= 'z') &&
      !(ch >= 'A' && ch <= 'Z') &&
      !(ch >= '0' && ch <= '9') &&
      ch != '_' &&
      ch != '-' &&
      ch != '.' {
      return false
    }
  }
  true
}

///|
fn validate_graph(graph : Graph) -> Unit raise GraphError {
  let n = graph.nodes.length()
  if n < 1 || n > max_nodes || graph.edges.length() > max_edges {
    raise Invalid("graph limits are 1..512 nodes and at most 8192 edges")
  }
  if graph.entry < 0 || graph.entry >= n {
    raise Invalid("entry index is outside the graph")
  }
  let names : Map[String, Bool] = Map([])
  for name in graph.nodes {
    if !valid_id(name) || names.contains(name) {
      raise Invalid("invalid or duplicate node ID: " + name)
    }
    names[name] = true
  }
  validate_graph_connections(graph)
}

///|
// The caller has already checked node IDs, limits and the entry reference.
fn validate_graph_connections(graph : Graph) -> Unit raise GraphError {
  let n = graph.nodes.length()
  // Allocate a destination bitmap only for nodes that have outgoing edges.
  let outgoing : Array[Array[Int32]] = Array::make(n, [])
  let words_per_node = (n + 31) / 32
  for (from, to) in graph.edges {
    if from < 0 || from >= n || to < 0 || to >= n {
      raise Invalid("edge index is outside the graph")
    }
    if outgoing[from].is_empty() {
      outgoing[from] = Array::make(words_per_node, 0)
    }
    let row = outgoing[from]
    let word = to / 32
    let bit = 1 << (to % 32)
    if (row[word] & bit) != 0 {
      raise Invalid("duplicate edge")
    }
    row[word] = row[word] | bit
  }
  let seen_exit = Array::make(n, false)
  for exit in graph.exits {
    if exit < 0 || exit >= n || seen_exit[exit] {
      raise Invalid("invalid or duplicate exit")
    }
    seen_exit[exit] = true
  }
  for exit in graph.exits {
    if !outgoing[exit].is_empty() {
      raise Invalid("declared exits must have no outgoing edges")
    }
  }
}

///|
fn copy_graph(input : Graph) -> Graph {
  {
    nodes: input.nodes.copy(),
    edges: input.edges.copy(),
    entry: input.entry,
    exits: input.exits.copy(),
  }
}

///|
/// Reflexive dominance is defined only for nodes reachable from the root.
/// Public mutable trees are checked structurally before answering any query.
pub fn dominates(
  tree : Dominance,
  ancestor : Int32,
  node : Int32,
) -> Bool raise GraphError {
  validate_dominance(tree)
  let n = tree.reachable.length()
  if ancestor < 0 || ancestor >= n || node < 0 || node >= n {
    raise Invalid("dominance query index is outside the tree")
  }
  tree.parent_tree().dominates(ancestor, node)
}

///|
// The parent tree comes from the solver or a validated public Dominance.
fn DominatorTree::dominates(
  self : Self,
  ancestor : Int32,
  node : Int32,
) -> Bool {
  let n = self.reachable.length()
  if !self.reachable[ancestor] || !self.reachable[node] {
    return false
  }
  let mut cursor = node
  for _ in 0..<n {
    if cursor == ancestor {
      return true
    }
    match self.immediate[cursor] {
      None => return false
      Some(parent) => cursor = parent
    }
  }
  false
}

///|
// A tree cannot prove that supplied frontier sets match an original graph.
// It can reject cycles, broken parent chains and invalid set members before use.
fn validate_dominance(tree : Dominance) -> Unit raise GraphError {
  let n = tree.reachable.length()
  if n < 1 ||
    n > max_nodes + 1 ||
    tree.immediate.length() != n ||
    tree.frontiers.length() != n {
    raise Invalid("invalid dominator tree dimensions")
  }
  if tree.root < 0 ||
    tree.root >= n ||
    !tree.reachable[tree.root] ||
    tree.immediate[tree.root] is Some(_) {
    raise Invalid("invalid dominator root")
  }
  let frontier_seen = Array::make(n, -1)
  for node in 0..<n {
    if !tree.reachable[node] {
      if tree.immediate[node] is Some(_) || !tree.frontiers[node].is_empty() {
        raise Invalid("unreachable nodes must have no parent or frontier")
      }
    } else if node != tree.root {
      match tree.immediate[node] {
        Some(parent) if parent >= 0 && parent < n && tree.reachable[parent] =>
          ()
        _ => raise Invalid("reachable dominator node has no valid parent")
      }
    }
    if tree.frontiers[node].length() > n {
      raise Invalid("oversized dominance frontier")
    }
    for target in tree.frontiers[node] {
      if target < 0 ||
        target >= n ||
        !tree.reachable[target] ||
        frontier_seen[target] == node {
        raise Invalid("invalid or duplicate dominance frontier member")
      }
      frontier_seen[target] = node
    }
  }
  let state = Array::make(n, 0)
  state[tree.root] = 2
  for node in 0..<n {
    if !tree.reachable[node] || state[node] == 2 {
      continue
    }
    let chain = []
    let mut cursor = node
    while state[cursor] == 0 {
      state[cursor] = 1
      chain.push(cursor)
      cursor = tree.immediate[cursor].unwrap()
    }
    if state[cursor] == 1 {
      raise Invalid("invalid dominator parent cycle")
    }
    for target in chain {
      state[target] = 2
    }
  }
}
