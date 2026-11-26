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
- Check the complete JSON byte budget as snapshot and CLI reports are
  serialized. Preserve legacy report layout and witness metadata.
- Compare actual device and inode identity before and after reads on POSIX.
  Inspect same-parent report stage candidates and their filesystem metadata
  through the read-only `inspect-stages` command.
- Query natural-loop boundaries using entry reachability, immediate dominators
  and loop membership. Query edge-level control witnesses using entry
  reachability and immediate postdominators. Both paths retain graph validation,
  ordering and capacity limits.
- Bound SSA report serialization by checking the remaining 16 MiB budget
  as block and placement records are added. Keep the existing JSON layout
  and both CLI boundary diagnostics.
- Query a single declared block/variable use through the SDK, with the same
  last-definition and incoming-value semantics as a full report, even when
  all sources together exceed the full-report relation cap.
- Request durable file output with `--out` and `--durable`. Report publication,
  parent-directory sync, and owned stage cleanup independently, with the
  existing read-only stage inspection available for residue.
- Query a selected natural-loop header from the SDK or a graph file. Return
  ordered entry, exit and back edges even when full expansion exceeds its cap.
  Use entry reachability with and without the selected header.
- Index immediate dominators or postdominators for named query batches,
  omitting frontier computation while preserving query text and diagnostics.
- Query a declared use by block and variable name from a program file or the
  SDK. The selected row is available even when the full report exceeds its
  relation limit.
- Render DOT from the graph and its immediate dominators, through the CLI or
  SDK, with the same output as the full-analysis renderer.
- Inspect the complete finite-exit control witnesses for one original directed
  edge through the SDK or CLI, including edges omitted by the aggregate limit.
- Export the JSON summary with an inclusive byte budget, checking each
  serialized record and keeping the saved analysis available after failure.
- Validate graph and program input separately from copying it. Reuse the
  decoded graph and its name index in valid program and query files, and
  retain independent arrays for saved analyses and inspection copies.
- Record the owner of a staged report and offer a read-only task inspection.
  Verify Linux and Windows process instances and report unknown on absent
  or inconsistent evidence. Preserve the original structure report.
- Keep individually confirmed task observations when sibling entries change
  inside the same inspection directory. Mark that scan as incomplete.
- Report incoming-only values directly in full value-origin analysis when
  a variable has no entry-reachable definition.
- Count the bounded control-witness prefix before full JSON export and
  serialize it one edge at a time under the existing byte budget.
- Serialize saved value-origin reports one use at a time under the existing
  byte budget.

## Next candidates

Prioritize observed correctness problems and reproducible consumers.

1. **Stage recovery.** Define a separate policy for reviewing retained reports.
   Inspection reports observations from a trusted local directory, and task
   termination alone does not establish whether publication completed.
2. **Program slicing.** Define explicit data-dependence inputs before exposing
   a slicing API. Document which relationships clients must supply.

The existing mutable Analysis API requires valid, unmodified results to
serialize. Callers can use AnalysisSnapshot for saved reports.
Value origins describe possible sources under the block-use convention, without
source-language, path-feasibility or alias reasoning. They do not classify an
incoming value as an initialization error or provide IR transformations.
Explicit data-dependence inputs could later support well-scoped slicing.
Source-language adapters, instruction renaming and executable IR transformations
need separate contracts and designs. No implementation or performance claim is
made for these candidates.
