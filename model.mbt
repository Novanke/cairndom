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
fn snapshot_graph(input : Graph) -> Graph raise GraphError {
  let n = input.nodes.length()
  if n < 1 || n > max_nodes || input.edges.length() > max_edges {
    raise Invalid("graph limits are 1..512 nodes and at most 8192 edges")
  }
  if input.entry < 0 || input.entry >= n {
    raise Invalid("entry index is outside the graph")
  }
  let names : Map[String, Bool] = Map([])
  for name in input.nodes {
    if !valid_id(name) || names.contains(name) {
      raise Invalid("invalid or duplicate node ID: " + name)
    }
    names[name] = true
  }
  let pairs : Map[(Int32, Int32), Bool] = Map([])
  for (from, to) in input.edges {
    if from < 0 || from >= n || to < 0 || to >= n {
      raise Invalid("edge index is outside the graph")
    }
    if pairs.contains((from, to)) {
      raise Invalid("duplicate edge")
    }
    pairs[(from, to)] = true
  }
  let exits : Map[Int32, Bool] = Map([])
  for exit in input.exits {
    if exit < 0 || exit >= n || exits.contains(exit) {
      raise Invalid("invalid or duplicate exit")
    }
    exits[exit] = true
  }
  for (from, _) in input.edges {
    if exits.contains(from) {
      raise Invalid("declared exits must have no outgoing edges")
    }
  }
  {
    nodes: input.nodes.copy(),
    edges: input.edges.copy(),
    entry: input.entry,
    exits: input.exits.copy(),
  }
}

///|
/// Reflexive dominance is defined only for nodes reachable from the root.
pub fn dominates(
  tree : Dominance,
  ancestor : Int32,
  node : Int32,
) -> Bool raise GraphError {
  let n = tree.reachable.length()
  if tree.immediate.length() != n {
    raise Invalid("invalid dominator tree dimensions")
  }
  if ancestor < 0 || ancestor >= n || node < 0 || node >= n {
    raise Invalid("dominance query index is outside the tree")
  }
  if !tree.reachable[ancestor] || !tree.reachable[node] {
    return false
  }
  let mut cursor = node
  for _ in 0..<n {
    if cursor == ancestor {
      return true
    }
    match tree.immediate[cursor] {
      None => return false
      Some(parent) => {
        if parent < 0 || parent >= n {
          raise Invalid("invalid dominator parent index")
        }
        cursor = parent
      }
    }
  }
  raise Invalid("invalid dominator parent cycle")
}
