# CairnDom technical verification

The supported compiler is moonc 0.10.20 or newer. Development verification uses
moonc 0.10.20+65efd5b93, moon 0.1.20261104 (940aa18), and Node.js 22.16.0.
Run `moon version --all` to record the actual local tools.

The pure library has no runtime dependencies outside the standard library. Both
Wasm GC and JavaScript checks and tests use `--deny-warn`. The SDK example is an
actual public-API consumer. The CLI uses the optimized JavaScript build.

The core tests include all 1,536 combinations of three-node directed graphs and
root selection. An independent node-removal definition determines whether each
node dominates each reachable target, then derives immediate parents and
frontiers. This oracle also covers entry self-loops and incoming edges.

Focused tests cover diamonds, nonzero roots, unreachable predecessors,
irreducible cycles, nested natural loops, merged latches and closest loop
containment. Additional checks cover multiple exits, absent exits, a branch
leading into a permanent cycle, liveness-pruned iterated frontiers, input copies,
strict schema parsing and malformed typed graphs.

`python scripts/verify_cli.py` executes actual files and independently checks
reported relationships. It also exercises output refusal, malformed inputs and
filesystem limits. Its `--node` and `--cli` arguments allow the same checks against
a separately installed registry consumer.

Local verification on Windows with the versions above passed both backend
checks, all 89 test blocks on each backend, the optimized JavaScript build and
the SDK examples on both backends. The separate graph CLI oracle passed 115 graph cases and 161
actual process invocations, including maximum graph limits, exact input size,
partial writes, close failures and a competing output writer. Windows symlink
checks were skipped because this account cannot create symlinks; FIFO
replacement checks require POSIX. The Linux CI job must exercise these paths
before publication. These are correctness checks, not performance measurements.

The postdominator scope is finite paths reaching explicit terminal exits in the
entry-reachable graph. It is not a termination analysis. SCC multi-entry flags do
not constitute a complete nested irreducibility classifier. The current graph
limits are 512 nodes and 8,192 edges. CHK is an iterative algorithm with quadratic
worst-case behavior; no performance benchmark or adoption claim is made.

The 0.2.0 implementation adds structural validation before public dominance
queries, bounded edge-level control witnesses, natural-loop boundary edges,
graph wire round trips, named block-variable fact import/export, backward
liveness and live-in-pruned phi planning. A node-removal/set-definition oracle
checks control witnesses; a finite-path use-before-definition oracle checks
liveness, including permanent cycles. Separate SSA integration tests derive
dominance and iterated frontier closure independently from production code.

Dense real graph cases check exact witness capacity and rejection of oversized
loop-boundary expansion. A valid maximum typed program checks the 2 MiB program
export guard; dense liveness checks the 16 MiB SSA report guard. SDK APIs reject
oversized complete witnesses/boundaries instead of silently returning partial
results. Analysis JSON can retain a bounded witness prefix but explicitly marks
`control_witnesses_complete: false`; node-level control relations remain complete.

`python scripts/verify_ssa_cli.py` checks named fact files through the optimized
`plan-ssa` command, independently calculating liveness and pruned phi closure,
and exercising input/format errors and non-overwriting publication. Both scripts
support `--node` and `--cli` for verification of a separately installed package.
The latest local Windows run passed 43 program oracle cases and 78 real invocations,
including Unicode/space paths, input preservation, an existing destination and
an injected partial output write. This is a file-to-report workflow; no IR
conversion or source-language semantics are inferred.

The 0.3.0 implementation builds an opaque, independently owned dominance index
with DFS intervals and binary-lifting ancestors. Exhaustive independent tests
compare dominance and nearest-common answers, including unreachable nodes,
mutated source arrays, nonzero roots and the 513-slot postdominator bound.
The query CLI reuses one index for strict named batches; twelve real batch/file
cases passed 44 invocations against node-removal/set-intersection references.

Stdout previously used console logging, which could swallow a closed-pipe error
and exit successfully. The stream adapter now observes callbacks/error events,
handles backpressure and routes failures through the MoonBit JSON diagnostic.
Thirty-seven real invocations cover analyze/plan-ssa/query/trace-values/help, closed stdout/stderr,
callback and event failures, synchronous throws, and an independently consumed
3,504,328-byte report with a slow reader. Partial stdout bytes cannot be rolled
back; the atomic new-file convention applies to `--out` only. The bridge follows
[Node 22 process I/O](https://nodejs.org/download/release/v22.16.0/docs/api/process.html#a-note-on-process-io)
and [write callback semantics](https://nodejs.org/download/release/v22.16.0/docs/api/stream.html#writablewritechunk-encoding-callback).

Reference mathematics and portable cases now live in `verification/reference`.
They use production graph/program parsers and types, but do not call production
analysis algorithms or serializers to derive expected answers. Before removing
the old Python mathematics, the migrated reference was compared with an external
backup: 113 reports, 113 DOT strings and 40 SSA reports matched exactly. Ten query
batches (425 answers) also matched the original node-removal definitions.
Python remains the shared host for files, processes, pipes and fault injection.
Use `--oracle` to select a separately compiled reference command when needed.

The 0.4.0 SDK adds `prepare_ssa` and an opaque `SsaSnapshot`. The previous
`ssa_plan_json_text(program)` convenience function computed a fresh result, so
callers could not export the exact plan already inspected without recomputing.
This is an API usability improvement, not a newly discovered mathematical bug.
The snapshot retains a single privately owned planning result. `plan()` returns
deep copies of every nested graph/fact/liveness/placement array, and `json_text()`
serializes the private result directly through the existing 16 MiB guard. The
updated SSA SDK example demonstrates inspection, edits to both caller inputs and
inspection copies, then unchanged export. The JSON schema, CLI output and
existing planning entry points retain their contracts. Oversized reports remain
inspectable but cannot be exported; editing an inspection copy does not alter
the saved computation. Four snapshot regression blocks cover all nested array
boundaries, independent inspection copies, legacy JSON equality, malformed
inputs, nonzero entries, unreachable facts and permanent loops. The shared dense
report regression also verifies that an oversized saved plan remains inspectable
while JSON export fails explicitly. The 0.4.0 local run passed both backend
checks/tests, all three SDK examples on both backends, the optimized JS build and
the four host verification entry points (312 actual CLI invocations). The same
Windows symlink/POSIX FIFO skips above apply. No runtime speed benchmark is claimed.

The 0.5.0 review found no new mathematical error, but post-only named queries
called `analyze(graph).post`, unnecessarily constructing forward dominators,
control relations, loops and SCCs. `postdominators(graph)` now validates the full
graph, traverses entry reachability and computes only the reversed finite-exit
dominator tree. Full `analyze` shares the same private postdominator helper with
its existing forward reachability result. The SDK JSON/CLI post-query path uses
the standalone function. JSON schemas and answers remain unchanged; the query
SDK example runs the new public entry point. This is a reduction in the work
selected by the call path, not a measured wall-clock performance claim.

Five postdominance regression blocks compare the standalone tree with an
independent node-removal definition and the full-analysis result. Exhaustive
enumeration covers 2,187 three-node graph/root/valid-terminal-exit configurations.
Focused cases cover nonzero entry, incoming edges, self-loops, permanent cycles,
unreachable predecessors/exits, absent exits, terminal entry, the 513-slot tree
for 512 original nodes, independently owned arrays and malformed typed graphs.
The local 0.5.0 run passed both backend checks and all 79 test blocks per backend,
all three SDK examples on both backends, the optimized JS build, and the four
host validators (312 actual CLI invocations). Windows symlink creation and POSIX
FIFO checks have the previously recorded local skips; public Linux CI must pass
before publication.

The 0.6.0 review considered per-use value origins, owned analysis reports and
safe cleanup of abandoned output stages, with no new confirmed math bug. The
selected API gap was that `requires_entry_value` only described a variable-wide
SSA requirement; a caller could not identify each affected use or its possible
last-definition blocks. `trace_values` now explains those uses under the existing
FlowProgram convention. It searches backwards from each use, stopping at local
definitions, while treating an entry value and loop-carried definitions as
separate possible sources. Permanent loops participate and unreachable facts
are validated but excluded. The opaque result owns its program and returns deep
copies, so inspection edits cannot alter its saved JSON report.

Five regression blocks use an independent forward `(block, last source)` state
walk, recording uses before replacing a local definition. They check all 12,288
three-node graph/root/definition-subset configurations, focused branches and
overwrites, entry backedges, self-use/definition loops, permanent cycles,
unreachable facts, sorted output, ownership, empty variables and malformed inputs.
Exactly 65,536 source relations are accepted, including incoming-value tokens;
one additional token rejects the entire computation. The CLI capacity check
publishes the exact-limit result and verifies that the overflow creates no file.

The independent real-file reference now checks `trace-values` using forward
source states rather than the production backward search. It uses production
types/parsers only, not production trace/liveness/SSA algorithms. The new sample
shows a partially defined branch, caller-supplied parameter, overwrite and
unreachable block. `examples/ssa_sdk` also checks inspection/export ownership.
The named report states `possible_origins`, not a source-language initialization
proof; it does not solve path feasibility, aliases or statement ordering.

Local 0.6.0 verification passed both backend checks and all 84 test blocks per
backend, the optimized JS build, all three SDK examples on both backends and all
five host validators. These passed 115 graph cases / 161 CLI invocations,
43 SSA cases / 78 invocations, 12 query cases / 44 invocations, 37 stdout
invocations and 46 value-origin cases / 84 invocations, for 404 real CLI calls.
The value-origin validator includes Unicode/space paths, argument/input errors,
existing-output/input preservation, partial staged writes and both relation
capacity boundaries. The documented Windows symlink/POSIX FIFO skips remain;
the matching public Linux job is required before publication.

The 0.7.0 review considered owned graph reports, safe abandoned-stage cleanup and
explicit data-dependence inputs, without a new confirmed mathematical bug. The
selected API gap was that mutable Analysis values must remain valid and
unmodified for the existing serializers. `prepare_analysis` now retains one
private full analysis; `AnalysisSnapshot.analysis()` deep-copies graph arrays,
both trees and their frontier rows, loops, components and control dependencies.
JSON/DOT describe that saved computation even after input/inspection edits.
Exports still serialize values and derive bounded edge witnesses each time;
they do not rerun full analysis or cache the wire text. Existing witness-prefix
and completeness metadata remain intact.

Five regression blocks verify every nested array category and scalar record,
legacy JSON/DOT equality, independent inspection copies, finite-exit/no-exit
scope, irreducible/nested loops, unreachable data, the 512-node/513-slot maximum
and malformed inputs. A dense graph checks both the bounded witness prefix and
an actual JSON result over 16 MiB: SDK JSON export raises GraphError while the
saved analysis remains inspectable and DOT-exportable. Preparation does not
eagerly serialize. The CLI still uses its existing serializer/limit path, so
its error classification and all existing entry points are unchanged.

Local 0.7.0 verification passed both backend checks and all 89 test blocks per
backend, the optimized JS build, all three SDK examples on both backends and the
five host validators (404 actual CLI calls). The public SDK example mutates its
input and inspection copy, then checks stable saved JSON/DOT. Windows symlink
and POSIX FIFO skips remain as documented; matching public Linux and Windows
CI must pass before publication.

The 0.8.0 defensive source review found that full JSON builds edge witnesses
before checking report size and that the CLI allocated UTF-8 buffers only to
count output bytes. The opt-in `cairndom.analysis-summary.v1` format shares all
node-level analysis fields and skips edge-witness generation. The existing
dense SDK regression verifies that the summary is exportable and exactly
matches the full report after removing witness fields and changing the schema.
The CLI preserves the byte limit, including its final newline, and writes
stdout without allocating a separate encoding buffer solely for validation.
The JS host uses [Node.js Buffer.byteLength](https://nodejs.org/download/release/v22.16.0/docs/api/buffer.html#static-method-bufferbytelengthstring-encoding).

Both backends passed all 89 tests and the three SDK examples. The five real-file
and stdout validators covered the summary schema, file/stdout byte parity,
destination refusal and command scoping in addition to their existing cases.
The four default CLI example reports matched the prior version byte for byte.
Full JSON still materializes before the output limit is enforced.

Next useful work follows correctness evidence and real consumers. Candidate
directions include safe stage ownership/cleanup and explicit data-dependence inputs for program
slicing. General source-language/IR parsing,
instruction ordering, variable renaming and program rewriting require separate
designs. The current phi planner reports locations and incoming-value needs;
it does not establish that an executable program has been converted to SSA.

Release verification must use the exact Git commit on public CI, publish its
Mooncakes archive, install that exact version in a new external consumer, and
compare downloaded package files to the commit before creating a matching tag.
Compiler/framework changes require rerunning the declared entry points. Personal
application information and credentials stay outside this repository.
