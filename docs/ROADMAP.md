# CairnDom development directions

## Implemented workflows

- Read a graph JSON file, diagnose reachability/dominance/finite-exit control
  dependence and natural loops, and publish a new JSON or DOT report.
- Explain control dependence by original branch edges, with explicit completeness
  metadata for bounded JSON witness expansion.
- Query natural-loop entry, exit and back edges through the SDK, with bounded
  expansion and complete-result errors rather than partial arrays.
- Construct or edit a graph in the SDK and save a valid graph wire file.
- Read or build named variable definitions/uses, compute all-path reachable
  liveness, and plan pruned phi locations plus required entry values.
- Run the same graph/SSA workflows as a pure MoonBit SDK consumer or the Node CLI.
- Index a checked dominance tree once and perform repeated dominance and nearest
  common-region queries without sharing mutable tree arrays.
- Read named query batches and distinguish unreachable/empty results from the
  virtual postdominator exit in an offline JSON report.
- Verify independent algorithms and portable cases in MoonBit while keeping real
  filesystem, pipe and injected host failures in a shared process adapter.
- Prepare an owned SSA snapshot, inspect defensive copies, then export the exact
  saved computation after caller inputs or inspection views have changed.
- Query postdominance directly through the SDK or named JSON batches without
  computing forward dominators, control dependencies, natural loops or SCCs.
- Explain each reachable block-variable use with its possible last-definition
  blocks and incoming-value requirement, retain an owned SDK result, and export
  the same complete named report through `trace-values` without overwriting files.
- Prepare an owned full graph-analysis snapshot, inspect deep copies, and export
  the saved JSON/DOT after callers change their input or displayed result.
- Export a distinct node-level JSON summary without building edge witnesses.

## Next candidates

Prioritize observed correctness problems and reproducible consumers.

1. **Report generation.** The summary format skips edge expansion when only node
   analysis is needed. Full JSON still materializes before its size check.
   Investigate checking the budget during serialization while preserving default
   bytes and witness completeness metadata.
2. **File identity and recovery.** Review platform-specific file identity checks
   and design read-only discovery of abandoned stages before considering an
   ownership protocol for cleanup. The current scope is trusted local directories.
3. **Cost of narrow queries.** Loop-boundary and edge-witness callers still run
   full analysis. Evaluate dedicated paths and check result parity before any
   performance claim.

The existing mutable Analysis API requires valid, unmodified results to
serialize. Callers can use AnalysisSnapshot for saved reports.
Value origins describe possible sources under the block-use convention, without
source-language, path-feasibility or alias reasoning. They do not classify an
incoming value as an initialization error or provide IR transformations.
Explicit data-dependence inputs could later support well-scoped slicing.
Source-language adapters, instruction renaming and executable IR transformations
need separate contracts and designs. No implementation or performance claim is
made for these candidates.
