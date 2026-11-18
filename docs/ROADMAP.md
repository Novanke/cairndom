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

## Next candidates

Prioritize observed correctness problems and reproducible consumers. The 0.6.0
review found no new confirmed mathematical bug. It considered per-use value
origins (now implemented), owned graph reports and safe abandoned-stage cleanup.
Owned graph reports could support inspect/edit/export clients, but the current
mutable Analysis contract still requires valid, unmodified results to serialize.
Safe cleanup of abandoned `.cairndom-*` stages needs explicit ownership markers;
the current CLI discloses possible leftovers and does not blindly delete them.
Value origins describe possible sources under the block-use convention, without
source-language, path-feasibility or alias reasoning. They do not classify an
incoming value as an initialization error or provide IR transformations.
Explicit data-dependence inputs could later support well-scoped slicing.
Source-language adapters, instruction renaming and executable IR transformations
need separate contracts and designs. No implementation or performance claim is
made for these candidates.
