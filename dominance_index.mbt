///|
/// Opaque snapshot of a structurally checked dominator tree. Arrays are owned
/// privately: later mutations of the input tree cannot change indexed answers.
struct DominanceIndex {
  root_node : Int32
  reachable : Array[Bool]
  entered : Array[Int32]
  left : Array[Int32]
  depth : Array[Int32]
  ancestors : Array[Array[Int32]]
}

///|
/// Validate a public tree once, then index its parent topology. Frontier
/// validity is structural only, as with dominates; indexing cannot establish
/// that supplied dominance/frontier sets correspond to an original graph.
pub fn index_dominance(tree : Dominance) -> DominanceIndex raise GraphError {
  validate_dominance(tree)
  let n = tree.reachable.length()
  let reachable = tree.reachable.copy()
  let parents = Array::makei(n, node => tree.immediate[node].unwrap_or(node))
  let children : Array[Array[Int32]] = Array::makei(n, _ => [])
  for node in 0..<n {
    if reachable[node] && node != tree.root {
      children[parents[node]].push(node)
    }
  }
  let entered = Array::make(n, -1)
  let left = Array::make(n, -1)
  let depth = Array::make(n, -1)
  let stack = [(tree.root, false)]
  let mut clock = 0
  depth[tree.root] = 0
  while !stack.is_empty() {
    let (node, expanded) = stack.pop().unwrap()
    if expanded {
      left[node] = clock
    } else {
      entered[node] = clock
      clock += 1
      stack.push((node, true))
      for i = children[node].length() - 1; i >= 0; i = i - 1 {
        let child = children[node][i]
        depth[child] = depth[node] + 1
        stack.push((child, false))
      }
    }
  }
  let mut levels = 1
  while 1 << levels <= n {
    levels += 1
  }
  let ancestors = [parents]
  for level in 1..<levels {
    let previous = ancestors[level - 1]
    ancestors.push(Array::makei(n, node => previous[previous[node]]))
  }
  { root_node: tree.root, reachable, entered, left, depth, ancestors, }
}

///|
fn DominanceIndex::check_node(
  self : Self,
  node : Int32,
) -> Unit raise GraphError {
  if node < 0 || node >= self.reachable.length() {
    raise Invalid("dominance query index is outside the tree")
  }
}

///|
/// Root index, including the synthetic exit for a postdominator snapshot.
pub fn DominanceIndex::root(self : Self) -> Int32 {
  self.root_node
}

///|
/// Number of slots, including unreachable vertices and any synthetic exit.
pub fn DominanceIndex::node_count(self : Self) -> Int32 {
  self.reachable.length()
}

///|
/// Reachability from this tree's root. For postdominance this means a declared
/// exit is reachable within the documented finite-exit-path scope.
pub fn DominanceIndex::is_reachable(
  self : Self,
  node : Int32,
) -> Bool raise GraphError {
  self.check_node(node)
  self.reachable[node]
}

///|
/// Returns None for the root and for unreachable nodes.
pub fn DominanceIndex::immediate_parent(
  self : Self,
  node : Int32,
) -> Int32? raise GraphError {
  self.check_node(node)
  if !self.reachable[node] || node == self.root_node {
    None
  } else {
    Some(self.ancestors[0][node])
  }
}

///|
/// Constant-time interval containment after construction. Unreachable operands
/// yield false, including reflexive queries. Both indices are checked first.
pub fn DominanceIndex::dominates(
  self : Self,
  ancestor : Int32,
  node : Int32,
) -> Bool raise GraphError {
  self.check_node(ancestor)
  self.check_node(node)
  self.reachable[ancestor] &&
  self.reachable[node] &&
  self.entered[ancestor] <= self.entered[node] &&
  self.entered[node] < self.left[ancestor]
}

///|
// Both nodes are known reachable and in the index's single rooted tree.
fn DominanceIndex::common_pair(
  self : Self,
  first : Int32,
  second : Int32,
) -> Int32 {
  let mut a = first
  let mut b = second
  if self.depth[a] < self.depth[b] {
    let swap = a
    a = b
    b = swap
  }
  let difference = self.depth[a] - self.depth[b]
  for level in 0..<self.ancestors.length() {
    if (difference & (1 << level)) != 0 {
      a = self.ancestors[level][a]
    }
  }
  if a == b {
    return a
  }
  for level = self.ancestors.length() - 1; level >= 0; level = level - 1 {
    if self.ancestors[level][a] != self.ancestors[level][b] {
      a = self.ancestors[level][a]
      b = self.ancestors[level][b]
    }
  }
  self.ancestors[0][a]
}

///|
/// Nearest shared dominator of all supplied nodes, O(k log n) after indexing.
/// Empty input or any unreachable operand gives None. Every index is validated,
/// even after an unreachable operand. Postdominance can return its virtual root.
pub fn DominanceIndex::nearest_common(
  self : Self,
  nodes : Array[Int32],
) -> Int32? raise GraphError {
  let mut all_reachable = true
  for node in nodes {
    self.check_node(node)
    if !self.reachable[node] {
      all_reachable = false
    }
  }
  if nodes.is_empty() || !all_reachable {
    return None
  }
  let mut common = nodes[0]
  for i in 1..<nodes.length() {
    common = self.common_pair(common, nodes[i])
  }
  Some(common)
}
