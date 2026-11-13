///|
fn main raise {
  let graph : @dom.Graph = {
    nodes: ["entry", "left", "right", "join", "exit", "dead"],
    edges: [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)],
    entry: 0,
    exits: [4],
  }
  let tree = @dom.dominators(graph)
  let index = @dom.index_dominance(tree)
  assert_true(index.dominates(0, 3))
  assert_eq(index.nearest_common([1, 2]), Some(0))
  assert_eq(index.nearest_common([3, 4]), Some(3))
  assert_eq(index.nearest_common([5, 4]), None)
  tree.immediate[1] = Some(2)
  tree.immediate[2] = Some(1)
  assert_eq(index.nearest_common([1, 2]), Some(0))
  let post = @dom.index_dominance(@dom.analyze(graph).post)
  assert_eq(post.nearest_common([1, 2]), Some(3))
  let request = Json::object(
    Map([
      ("schema", Json::string("cairndom.queries.v1")),
      ("graph", @json.parse(@dom.graph_json_text(graph))),
      ("tree", Json::string("forward")),
      (
        "queries",
        Json::array([
          Json::object(
            Map([
              ("operation", Json::string("nearest_common")),
              (
                "nodes",
                Json::array([Json::string("left"), Json::string("right")]),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  )
  println(@dom.query_json_text(request.stringify()))
}
