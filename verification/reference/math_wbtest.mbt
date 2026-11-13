///|
test "node removal distinguishes a diamond join from its branch definitions" {
  let graph = make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3])
  let (succ, pred) = adjacency(graph)
  let tree = dominance_definition(succ, pred, 0)
  assert_eq(tree.parents, [-1, 0, 0, 0])
  assert_eq(tree.frontiers[1], [false, false, false, true])
  assert_eq(tree.frontiers[2], [false, false, false, true])
  assert_eq(tree.dominators[3], [true, false, false, true])
}

///|
test "reference entry values include a use before its local definition" {
  let input = @json.parse(
    "{\"schema\":\"cairndom.program.v1\",\"graph\":{\"schema\":\"cairndom.graph.v1\",\"nodes\":[\"entry\"],\"entry\":\"entry\",\"exits\":[],\"edges\":[[\"entry\",\"entry\"]]},\"variables\":[\"x\"],\"blocks\":[{\"node\":\"entry\",\"defines\":[\"x\"],\"uses\":[\"x\"]}]}",
  )
  let report = program_expected(input)
  assert_eq(
    case_field(report, "entry_values_required"),
    Json::array([Json::string("x")]),
  )
  assert_eq(case_field(report, "status"), Json::string("locations_only"))
}
