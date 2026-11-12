///|
fn main raise {
  let graph : @dom.Graph = {
    nodes: ["entry", "left", "right", "join", "exit"],
    entry: 0,
    exits: [4],
    edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
  }
  let result = @dom.analyze(graph)
  assert_eq(result.forward.immediate[3], Some(0))
  assert_true(@dom.dominates(result.forward, 0, 4))
  assert_false(@dom.dominates(result.forward, 1, 3))
  let sites = @dom.iterated_frontier(result.forward, [1, 2])
  assert_eq(sites, [3])
  assert_eq(result.post.immediate[0], Some(3))
  assert_eq(result.control_dependencies[1], [0])
  println(@dom.analysis_json_text(result))
  println(
    "SSA phi candidate nodes: " + sites.map(i => graph.nodes[i]).join(", "),
  )
}
