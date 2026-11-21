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
  {
    graph: copy_graph(source.graph),
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
  self.json_text_limit(max_report_json_bytes) catch {
    Invalid(_) => raise Invalid("analysis JSON exceeds 16 MiB")
  }
}

///|
/// Write the same full report with an inclusive UTF-8 byte limit, excluding
/// any final newline added by the caller. Accepts budgets from 0 to 16 MiB.
/// The writer stops at the first over-budget fragment and returns no report.
pub fn AnalysisSnapshot::json_text_limit(
  self : Self,
  limit : Int32,
) -> String raise GraphError {
  if limit < 0 || limit > max_report_json_bytes {
    raise Invalid("analysis JSON byte limit must be between 0 and 16 MiB")
  }
  bounded_analysis_json_text(self.stored, limit, include_witnesses=true)
}

///|
/// Export node-level analysis as cairndom.analysis-summary.v1. The summary
/// keeps node-level control dependencies and skips edge-witness expansion.
/// Exports exceeding 16 MiB raise GraphError.
pub fn AnalysisSnapshot::summary_json_text(
  self : Self,
) -> String raise GraphError {
  self.summary_json_text_limit(max_report_json_bytes) catch {
    Invalid(_) => raise Invalid("analysis summary JSON exceeds 16 MiB")
  }
}

///|
/// Export the same summary with an inclusive UTF-8 byte budget between zero
/// and 16 MiB. The budget covers the body, before any caller-added newline.
pub fn AnalysisSnapshot::summary_json_text_limit(
  self : Self,
  limit : Int32,
) -> String raise GraphError {
  if limit < 0 || limit > max_report_json_bytes {
    raise Invalid(
      "analysis summary JSON byte limit must be between 0 and 16 MiB",
    )
  }
  bounded_analysis_json_text(self.stored, limit, include_witnesses=false)
}

///|
/// Serialize the same saved analysis as DOT, without recomputing analyze.
/// Validated node/edge limits bound DOT output below the JSON export limit.
pub fn AnalysisSnapshot::dot_text(self : Self) -> String {
  analysis_dot(self.stored)
}
