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

## Next candidates

Prioritize observed correctness problems and reproducible consumers. Explicit
data-dependence inputs could support well-scoped slicing. An exact-snapshot SSA
report interface could avoid recomputing a plan already inspected by a caller.
Source-language adapters, instruction
renaming and executable IR transformations need separate contracts and designs.
No implementation or performance claim is made for these candidates.
