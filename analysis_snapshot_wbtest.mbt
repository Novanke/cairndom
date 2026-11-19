///|
fn analysis_snapshot_test_graph() -> Graph {
  {
    nodes: ["dead", "entry", "outer", "inner", "body", "latch", "exit"],
    edges: [
      (1, 2),
      (2, 3),
      (2, 6),
      (3, 4),
      (4, 3),
      (3, 3),
      (3, 5),
      (5, 2),
      (0, 3),
    ],
    entry: 1,
    exits: [6],
  }
}

///|
// JSON does not expose every tree field, including postdominance frontiers.
// Check the entire inspection model as well as its serialized representations.
fn analysis_snapshot_test_equal(
  actual : Analysis,
  expected : Analysis,
) -> Unit raise {
  assert_eq(actual.graph.nodes, expected.graph.nodes)
  assert_eq(actual.graph.edges, expected.graph.edges)
  assert_eq(actual.graph.entry, expected.graph.entry)
  assert_eq(actual.graph.exits, expected.graph.exits)
  for
    (left, right) in [
      (actual.forward, expected.forward),
      (actual.post, expected.post),
    ] {
    assert_eq(left.root, right.root)
    assert_eq(left.reachable, right.reachable)
    assert_eq(left.immediate, right.immediate)
    assert_eq(left.frontiers, right.frontiers)
  }
  assert_eq(actual.loops.length(), expected.loops.length())
  for index, natural_loop in actual.loops {
    let wanted = expected.loops[index]
    assert_eq(natural_loop.header, wanted.header)
    assert_eq(natural_loop.latches, wanted.latches)
    assert_eq(natural_loop.members, wanted.members)
    assert_eq(natural_loop.parent, wanted.parent)
  }
  assert_eq(actual.components.length(), expected.components.length())
  for index, component in actual.components {
    let wanted = expected.components[index]
    assert_eq(component.members, wanted.members)
    assert_eq(component.entry_nodes, wanted.entry_nodes)
    assert_eq(component.cyclic, wanted.cyclic)
    assert_eq(component.multiple_entries, wanted.multiple_entries)
  }
  assert_eq(actual.control_dependencies, expected.control_dependencies)
}

///|
test "analysis snapshot saves exact JSON and DOT after every exported array is corrupted" {
  let input = analysis_snapshot_test_graph()
  let expected = analyze(input)
  let saved = prepare_analysis(input)
  let json = saved.json_text()
  let dot = saved.dot_text()
  assert_eq(json, analysis_json_text(expected))
  assert_eq(dot, analysis_dot(expected))
  assert_eq(expected.loops.length(), 2)
  assert_true(
    expected.loops.any(natural_loop => natural_loop.parent is Some(_)),
  )
  let first = saved.analysis()
  let second = saved.analysis()
  analysis_snapshot_test_equal(first, expected)
  analysis_snapshot_test_equal(second, expected)
  input.nodes.clear()
  input.edges.clear()
  input.exits.clear()
  first.graph.nodes.clear()
  first.graph.edges.clear()
  first.graph.exits.clear()
  for tree in [first.forward, first.post] {
    tree.reachable.clear()
    tree.immediate.clear()
    for frontier in tree.frontiers {
      frontier.push(-1)
    }
    tree.frontiers.clear()
  }
  for index, natural_loop in first.loops {
    natural_loop.latches.push(-1)
    natural_loop.members.push(-1)
    first.loops[index] = { ..natural_loop, header: -1, parent: Some(999), }
  }
  first.loops.clear()
  for index, component in first.components {
    component.members.push(-1)
    component.entry_nodes.push(-1)
    first.components[index] = {
      ..component,
      cyclic: !component.cyclic,
      multiple_entries: !component.multiple_entries,
    }
  }
  first.components.clear()
  for controls in first.control_dependencies {
    controls.push(-1)
  }
  first.control_dependencies.clear()
  // This also proves export does not depend on the now-invalid original input
  // or on an earlier mutable inspection value.
  analysis_snapshot_test_equal(second, expected)
  analysis_snapshot_test_equal(saved.analysis(), expected)
  assert_eq(saved.json_text(), json)
  assert_eq(saved.dot_text(), dot)
}

///|
test "analysis inspection copies keep coincident loop component and tree arrays separate" {
  let input : Graph = {
    nodes: ["entry"],
    edges: [(0, 0)],
    entry: 0,
    exits: [],
  }
  let saved = prepare_analysis(input)
  let expected = analyze(input)
  let view = saved.analysis()
  let other = saved.analysis()
  assert_eq(view.loops[0].latches, [0])
  assert_eq(view.loops[0].members, [0])
  assert_eq(view.components[0].members, [0])
  assert_eq(view.components[0].entry_nodes, [0])
  view.loops[0].latches.clear()
  assert_eq(view.loops[0].members, [0])
  assert_eq(view.components[0].members, [0])
  view.components[0].members.clear()
  assert_eq(view.components[0].entry_nodes, [0])
  assert_eq(view.loops[0].members, [0])
  view.forward.frontiers[0].clear()
  assert_eq(view.post.frontiers, [[], []])
  view.post.frontiers[0].push(-1)
  assert_eq(view.post.frontiers[1], [])
  view.control_dependencies[0].push(-1)
  assert_eq(view.forward.frontiers[0], [])
  view.graph.nodes[0] = "edited"
  assert_eq(other.graph.nodes, ["entry"])
  analysis_snapshot_test_equal(other, expected)
  analysis_snapshot_test_equal(saved.analysis(), expected)
  assert_eq(saved.json_text(), analysis_json_text(expected))
  assert_eq(saved.dot_text(), analysis_dot(expected))
}

///|
test "analysis snapshots preserve exit scope irreducible components and the maximum tree dimensions" {
  let graph : Graph = {
    nodes: ["dead", "entry", "left", "right", "spin", "dead_exit"],
    edges: [(1, 2), (1, 3), (1, 4), (4, 4), (0, 2)],
    entry: 1,
    exits: [2, 3, 5],
  }
  let saved = prepare_analysis(graph)
  let view = saved.analysis()
  assert_eq(view.forward.reachable, [false, true, true, true, true, false])
  assert_eq(view.post.root, 6)
  assert_eq(view.post.reachable, [false, true, true, true, false, false, true])
  assert_eq(view.post.immediate[1], Some(6))
  assert_eq(view.control_dependencies[2], [1])
  assert_eq(view.control_dependencies[3], [1])
  let absent = prepare_analysis({ ..graph, exits: [], })
  assert_eq(absent.analysis().post.reachable, [
    false, false, false, false, false, false, true,
  ])
  assert_eq(absent.analysis().control_dependencies, Array::makei(6, _ => []))
  let entry_loop : Graph = {
    nodes: ["entry", "exit"],
    edges: [(0, 0), (0, 1)],
    entry: 0,
    exits: [1],
  }
  let irreducible : Graph = {
    nodes: ["entry", "a", "b", "exit"],
    edges: [(0, 1), (0, 2), (1, 2), (2, 1), (1, 3), (2, 3)],
    entry: 0,
    exits: [3],
  }
  assert_true(
    prepare_analysis(irreducible).analysis().components.any(component => {
      component.multiple_entries
    }),
  )
  for fixture in [graph, { ..graph, exits: [], }, entry_loop, irreducible] {
    let legacy = analyze(fixture)
    let snapshot = prepare_analysis(fixture)
    analysis_snapshot_test_equal(snapshot.analysis(), legacy)
    assert_eq(snapshot.json_text(), analysis_json_text(legacy))
    assert_eq(snapshot.dot_text(), analysis_dot(legacy))
  }
  let maximum = prepare_analysis({
    nodes: Array::makei(512, node => "n" + node.to_string()),
    edges: Array::makei(511, node => (node, node + 1)),
    entry: 0,
    exits: [511],
  })
  let bounded = maximum.analysis()
  assert_eq(bounded.graph.nodes.length(), 512)
  assert_eq(bounded.forward.reachable.length(), 512)
  assert_eq(bounded.post.reachable.length(), 513)
  assert_eq(bounded.post.root, 512)
  assert_eq(bounded.forward.immediate[511], Some(510))
  assert_eq(bounded.post.immediate[0], Some(1))
  assert_eq(bounded.post.immediate[511], Some(512))
  assert_eq(maximum.json_text(), analysis_json_text(bounded))
  assert_eq(maximum.dot_text(), analysis_dot(bounded))
}

///|
test "analysis snapshot preparation rejects invalid graphs before creating a report" {
  let graph : Graph = {
    nodes: ["entry", "exit"],
    edges: [(0, 1)],
    entry: 0,
    exits: [1],
  }
  for
    invalid in [
      { ..graph, nodes: [], },
      { ..graph, nodes: ["same", "same"], },
      { ..graph, nodes: ["bad id", "exit"], },
      { ..graph, entry: -1, },
      { ..graph, entry: 2, },
      { ..graph, edges: [(0, 2)], },
      { ..graph, edges: [(-1, 1)], },
      { ..graph, edges: [(0, 1), (0, 1)], },
      { ..graph, edges: Array::make(8193, (0, 1)), },
      { ..graph, exits: [0], },
      { ..graph, exits: [1, 1], },
      { ..graph, exits: [2], },
      { ..graph, nodes: Array::makei(513, node => "n" + node.to_string()), },
    ] {
    assert_true(
      try {
        ignore(prepare_analysis(invalid))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "oversized saved analysis remains inspectable and DOT exportable while JSON fails completely" {
  let short_names = witness_overflow_graph()
  let bounded = match @json.parse(prepare_analysis(short_names).json_text()) {
    Object(object) => object
    _ => fail("expected an analysis report object")
  }
  assert_eq(
    required(bounded, "control_witnesses_complete").stringify(),
    "false",
  )
  assert_eq(
    items(required(bounded, "control_witnesses"), 65536).length(),
    65536,
  )
  let prefix = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012345678"
  let graph : Graph = {
    ..short_names,
    nodes: Array::makei(short_names.nodes.length(), node => {
      prefix + node.to_string()
    }),
  }
  let saved = prepare_analysis(graph)
  let inspected = saved.analysis()
  assert_eq(inspected.graph.nodes.length(), 128)
  assert_eq(inspected.graph.edges.length(), 2094)
  let legacy = analysis_json_text(inspected)
  assert_true(legacy.length() > 16_777_216)
  assert_true(
    try {
      ignore(saved.json_text())
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(saved.dot_text(), analysis_dot(inspected))
  assert_true(saved.dot_text().length() > 0)
  let summary = @json.parse(saved.summary_json_text())
  let expected = match @json.parse(legacy) {
    Object(object) => object
    _ => fail("expected an analysis report object")
  }
  expected["schema"] = Json::string("cairndom.analysis-summary.v1")
  expected.remove("control_witnesses")
  expected.remove("control_witnesses_complete")
  expected.remove("control_witness_limit")
  assert_eq(summary, Json::object(expected))
  assert_eq(saved.analysis().graph.edges.length(), 2094)
  assert_eq(
    saved.analysis().control_dependencies[49],
    Array::makei(48, index => index + 1),
  )
}
