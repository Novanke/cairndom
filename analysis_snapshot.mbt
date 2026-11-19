///|
/// An owned full graph analysis. Inspection copies cannot change its saved
/// JSON/DOT exports; the underlying graph analysis is computed only once.
struct AnalysisSnapshot {
  stored : Analysis
}

///|
/// Compute and retain one full analysis. Serialization is deferred so a graph
/// whose JSON exceeds the export limit remains inspectable and DOT-exportable.
pub fn prepare_analysis(graph : Graph) -> AnalysisSnapshot raise GraphError {
  { stored: analyze(graph), }
}

///|
fn analysis_snapshot_tree(tree : Dominance) -> Dominance {
  {
    root: tree.root,
    reachable: tree.reachable.copy(),
    immediate: tree.immediate.copy(),
    frontiers: tree.frontiers.map(row => row.copy()),
  }
}

///|
/// Return an independently mutable inspection copy of every graph/tree, loop,
/// component and control array. Edits affect neither later reads nor exports.
pub fn AnalysisSnapshot::analysis(self : Self) -> Analysis {
  let source = self.stored
  let graph = source.graph
  {
    graph: {
      nodes: graph.nodes.copy(),
      edges: graph.edges.copy(),
      entry: graph.entry,
      exits: graph.exits.copy(),
    },
    forward: analysis_snapshot_tree(source.forward),
    post: analysis_snapshot_tree(source.post),
    loops: source.loops.map(loop_info => {
      ..loop_info,
      latches: loop_info.latches.copy(),
      members: loop_info.members.copy(),
    }),
    components: source.components.map(component => {
      ..component,
      members: component.members.copy(),
      entry_nodes: component.entry_nodes.copy(),
    }),
    control_dependencies: source.control_dependencies.map(row => row.copy()),
  }
}

///|
/// Serialize the saved analysis using the existing cairndom.analysis.v1 format.
/// Witness expansion retains its completeness flag and bounded prefix. Exports
/// exceeding 16 MiB raise GraphError without changing the saved analysis.
pub fn AnalysisSnapshot::json_text(self : Self) -> String raise GraphError {
  let text = analysis_json_text(self.stored)
  if text.length() > 16_777_216 {
    raise Invalid("analysis JSON exceeds 16 MiB")
  }
  text
}

///|
/// Serialize the same saved analysis as DOT, without recomputing analyze.
/// Validated node/edge limits bound DOT output below the JSON export limit.
pub fn AnalysisSnapshot::dot_text(self : Self) -> String {
  analysis_dot(self.stored)
}
