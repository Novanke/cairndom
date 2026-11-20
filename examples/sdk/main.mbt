///|
fn main raise {
  let graph : @dom.Graph = {
    nodes: ["entry", "left", "right", "join", "exit"],
    entry: 0,
    exits: [4],
    edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
  }
  let saved = @dom.prepare_analysis(graph)
  let result = saved.analysis()
  assert_eq(result.forward.immediate[3], Some(0))
  assert_true(@dom.dominates(result.forward, 0, 4))
  assert_false(@dom.dominates(result.forward, 1, 3))
  let sites = @dom.iterated_frontier(result.forward, [1, 2])
  assert_eq(sites, [3])
  assert_eq(result.post.immediate[0], Some(3))
  assert_eq(result.control_dependencies[1], [0])
  let report = saved.json_text()
  let dot = saved.dot_text()
  assert_eq(@dom.graph_dot(graph), dot)
  let site_names = sites.map(i => graph.nodes[i]).join(", ")
  // An editor may mutate both the input and its displayed result. The saved
  // computation still exports the same graph and analysis that was inspected.
  graph.nodes.clear()
  graph.edges.clear()
  graph.exits.clear()
  result.graph.nodes.clear()
  result.forward.frontiers[1].clear()
  result.control_dependencies[1].clear()
  assert_eq(saved.analysis().forward.frontiers[1], [3])
  assert_eq(saved.analysis().control_dependencies[1], [0])
  assert_eq(saved.json_text(), report)
  assert_eq(saved.dot_text(), dot)
  println(report)
  println("SSA phi candidate nodes: " + site_names)
}
