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
Full JSON on this version materialized before the output limit was enforced.

In 0.8.1 the snapshot and CLI full JSON writer checks the UTF-8 byte budget
before appending each chunk. It serializes one analysis record at a time
and writes edge witnesses from a bounded array of index triples. The CLI
reserves a byte for the final newline and sends the report only after the
writer succeeds. SDK regressions cover the exact budget, one byte under,
and byte equality with the legacy serializer including the ordered witness
prefix. CLI regressions exercise the same overflow on stdout, a new output,
and an existing output, with the original diagnostic and preserved files.

On Windows with Node 22.16.0, five alternating runs per version on each test
graph used the process peak working set. The median for the over-budget graph
fell from 179.2 to 68.5 MiB. On the existing large valid stdout fixture it fell
from 75.6 to 68.8 MiB. In those runs both versions produced identical stdout,
stderr and exit status. These figures describe the two fixtures and host.

In 0.8.2 POSIX input reads compare the descriptor's actual device number
as part of both identity checks, before and after reading. The real-file
validator injects a single device-number difference at each observation.
POSIX must reject it with the corresponding I/O diagnostic. The Windows
case must produce the same analysis under the existing device compatibility
rule.

The `inspect-stages` validator interrupts a subprocess immediately before
publication, observes the surviving staged data file and missing output, and
checks empty and extra-hard-link cases in the same scratch directory. The
expected JSON comes from the MoonBit reference command. The test also checks
that the original staged bytes, existing output, and its hard link survive
inspection, that unrelated directories are skipped, and that `--out` is
rejected. The scan is bounded to 4,096 direct entries of a trusted local
directory. It reads metadata only. Ownership and writer activity are unknown.

With moonc 0.10.20+65efd5b93 and Node 22.16.0, the 0.8.2 and 0.8.1
optimized CLIs matched stdout, stderr, and exit status for 119 comparisons.
These covered 113 oracle graphs, four default CLI examples, DOT, and a
node-level JSON summary.

In 0.8.3 the public narrow queries share the immediate-dominator solver with
full analysis. The loop-boundary path computes reachable natural-loop
membership and latches without frontiers or nesting. The control witness
path uses immediate postdominators on finite paths to reachable terminal
exits, with an empty result when no declared exit is reachable. Standalone
queries avoid strong components and the full node-level control relation.

The independent MoonBit definitions check exact ordered public results for
1,536 three-node loop configurations and 2,187 three-node witness
configurations. Existing nested, irreducible and unreachable graph cases,
the exact 65,536-witness boundary, capacity errors and graph-validation
diagnostics also exercise the public paths.

In 0.8.4 the SSA snapshot and CLI share the bounded MoonBit JSON writer.
It formats one block or placement at a time and checks the remaining bytes
before each append. The plan remains available for inspection after an
export failure. The SDK's 16 MiB budget covers the body. The CLI counts
the trailing newline and keeps the two existing overflow diagnostics.

The file validator checks report bodies of 16 MiB minus one byte, exactly
16 MiB and 16 MiB plus one byte. For both failures it checks empty stdout,
the exact diagnostic and exit code, no new output, preserved existing output
and no staging residue. An external comparison with 0.8.3 matched 43 normal
SSA reports byte for byte, including 40 independent oracle cases.

On Windows 11 with Node 22.16.0 and moonc 0.10.20+65efd5b93, seven alternating
process pairs per fixture measured median peak working set. The 16,440,875-byte
valid CLI report fell from 145.77 to 143.13 MiB. An over-budget report fell
from 113.79 to 110.84 MiB, and a larger over-budget report with 512 blocks
and 512 variables fell from 225.77 to 125.96 MiB. The three fixtures matched
stdout, stderr and exit status between versions. These measurements apply
to these fixtures and this host.

In 0.8.5 `trace_use` shares the predecessor walk with `trace_values` but
only resolves the selected block and variable. Whole-program validation
still applies. A declared unreachable use returns None. Invalid indices
and undeclared uses raise GraphError.

The independent forward-state oracle covers 36,864 selected queries across
12,288 small graph configurations. The existing relation-boundary fixture
still accepts 65,536 full-report relations and rejects 65,537. Two selected
queries on the over-limit program return their complete sorted sources and
incoming-value markers. Tests also cover result ownership and malformed
facts outside the selected block.

In 0.8.6 opt-in `--durable` writes the normal report through the exclusive
hard-link path. It records publication, directory synchronization, and
owned stage cleanup separately in `cairndom.durable-output.v1`. The output
parent is opened before staging and rechecked by device and inode. Directory
sync follows the cleanup attempt, including a failed cleanup after publication.
The receipt records the host's observations in a trusted local directory.
A directory sync acknowledges that directory's entries. It is distinct from
the earlier report file sync and from cleanup itself. See the
[Linux fsync manual](https://man7.org/linux/man-pages/man2/fsync.2.html#DESCRIPTION)
and the [Node.js fsyncSync contract](https://nodejs.org/download/release/v22.16.0/docs/api/fs.html#fsfsyncsyncfd).

The real-file validator checks Linux directory fsync ordering, normal report
bytes, refusal to replace an existing output, and Windows refusal before
creating a stage. It injects a failed directory sync after publication and
a failed unlink of this invocation's staged file. Both checks preserve the
published file and verify the distinct receipt states. The retained stage
is observed via `inspect-stages`. A separate 137-case CLI byte comparison
with 0.8.5 covered default reports, file publication, diagnostics and
read-only inspection. Help adds one line documenting the opt-in flag.

In 0.8.7 `loop_boundary_at` shares membership and edge collection with the
full boundary API. The selected path computes entry reachability and
immediate dominators, then expands one header's loop. An independent
forward-path definition checks 4,608 selected queries across 1,536 small
graph configurations. The existing 295,119-record dense case still rejects
full expansion. Header 60 returns one entering edge, 3,600 ordered leaving
edges and 59 ordered back edges in the same graph.

The file validator checks named edge lists on a nested loop and a separate
dense graph, plus known non-headers, an unreachable self-loop, a header
beginning with two hyphens, invalid arguments, and non-overwriting file output.

In 0.8.8 named query batches build their immutable index directly from
immediate parents and reachability. Forward queries root at the graph entry;
post queries root at the virtual exit of the finite-exit-path graph. The
public index constructor still validates caller-supplied parent and frontier
arrays before indexing. A 512-node reversed chain with two terminal exits
exercises both index roots, long ancestor jumps and virtual exit serialization.
An external comparison with 0.8.7 matched 54 CLI cases byte for byte,
including both query directions, dense graphs, diagnostics and file output.

In 0.8.9 `trace-use` and `trace_use_json_text` reuse the selected-use analysis
and the full report's row serializer. The report includes the requested names
and the complete matching row. A declared unreachable use has a null row.
The existing program validation, input diagnostics, and atomic new-file output
apply. MoonBit tests check exact JSON, invalid names, undeclared uses, and an
over-limit program with 256 ordered definitions for one use. The real-file
test compares a selected row from an over-limit file with its corresponding
full-report row from the exact-limit fixture and verifies output refusal.
On Windows with moonc 0.10.20+65efd5b93 and Node 22.16.0, all 91 test blocks
passed on Wasm GC and JS, alongside the SDK examples and 441 real process
invocations. A separate 0.8.8 comparison matched 52 legacy CLI cases byte for
byte. The new CLI was also checked with hyphen-prefixed IDs, an unreachable use,
invalid selectors, and successful publication followed by overwrite refusal.

In 0.8.10 `graph_dot` and the CLI's `--format dot` path validate the graph
and compute only entry reachability and immediate dominators. The direct and
analysis-based exports use one renderer. The SDK test covers a nonzero entry,
an unreachable predecessor, nested cycles, and rejection of a nonterminal
declared exit. An external comparison matched 115 CLI DOT cases byte for byte
against both the independent reference and 0.8.9. The comparison also checked
19 invalid-input diagnostics, new-file publication, and overwrite refusal.

On Windows with Node 22.16.0 and moonc 0.10.20+65efd5b93, DOT generation on one
already parsed 512-node, 8,192-edge graph took a median 16.298 ms per call
in 0.8.9 and 1.582 ms in 0.8.10. Nine alternating process pairs, each with
10 warmups and 24 timed calls, measured the optimized JS analysis and rendering
paths. This excludes process startup, input parsing, and file I/O. Both
versions produced identical DOT bytes. The local release suite also passed
92 tests per backend, all SDK examples, and 441 real CLI invocations.

In 0.8.11 the selected-edge SDK and `control-witness` CLI return all witnesses
for one original directed edge from the finite-exit postdominator tree. They
share the dependent walk and ordering with the aggregate report. An independent
finite-path oracle exercises 8,748 selected original edges across 2,187 small
graph configurations. The aggregate still accepts exactly 65,536 witnesses.
In the overflowing fixture the edge `n28 → n88` returns 39 dependents, including
those missing from the bounded prefix, and `n48 → n49` returns all 78 even
though its entire edge is missing from the prefix. The CLI regression also
checks the selected answer on a graph whose full JSON exceeds 16 MiB and
verifies that its output refuses to replace an existing file.
With moonc 0.10.20+65efd5b93 and Node 22.16.0, local verification passed
93 tests per backend, all SDK examples, and 443 real CLI invocations.
The Windows host could not create symlinks and lacks POSIX FIFOs.
An external CLI comparison matched 113 full reports against the independent
oracle and 0.8.10 byte for byte, plus both dense witness-limit fixtures.
It also matched 104 selected edges against the oracle and checked selector
diagnostics, hyphen-prefixed IDs, and new-file publication.

In 0.8.12 `summary_json_text` and `summary_json_text_limit` serialize each
section a record at a time with the same MoonBit writer used by the full
report. The writer checks the remaining byte budget before appending text.
The SDK budget covers the body, and the CLI reserves one byte for the trailing
newline before serialization. An over-budget CLI call emits the existing
diagnostic and creates no output file or stage.

The comparison with 0.8.11 matched 113 summaries byte for byte and against
the independent oracle. Actual files exercised bodies of 16 MiB minus one
byte, exactly 16 MiB, and 16 MiB plus one byte. The first produces exactly
16 MiB on CLI stdout; the other two reproduce the same CLI limit error.
New-file and existing-file checks verify publication or refusal without
staging residue. The SDK tests cover exact budgets and access to the saved
analysis and DOT after rejection. The local suite passed 95 tests per backend,
all SDK examples, and 443 real CLI invocations on Node.js 22.16.0 and
moonc 0.10.20+65efd5b93.

The peak-memory fixtures have 512 nodes and 1,022 edges. A directed chain
connects nodes 0 through 511, with back edges from node 510 to nodes 0 through
510 and node 511 as the only declared exit. For exact CLI capacity, identifier
widths are 47 for node 0, 51 for nodes 1 through 260, 50 for nodes 261 through
510, and 10 for node 511. Pad distinct ASCII IDs to those widths. Moving one
character from the ID of node 1 to that of node 0 adds one output byte.
The oversized fixture uses 64-byte identifiers and would produce a
20,364,442-byte body using the unbounded summary layout.

On Windows, seven alternating pairs of fresh Node.js 22.16.0 processes
measured the median of `GetProcessMemoryInfo` peak working sets. The exact
16 MiB CLI output fell from 157.23 to 153.72 MiB. The rejected oversized
summary fell from 124.96 to 113.62 MiB. Peaks cover file input, analysis,
serialization, and any output. Exit status, stdout, and stderr matched in
every pair. These are process-level measurements for the two fixtures.

In 0.8.13 graph validation checks input without taking ownership of its
arrays. Read-only graph queries and exports validate the mutable public input
at their boundary. Analysis, SSA planning and value-origin results make
separate copies when they retain source data, and snapshot inspections still
return independently mutable data. SSA solves liveness and dominance on its
already validated copy. Sorts keep their local copies of edge order.

The wire decoder creates its own graph and name index. Program and query
parsers consume the already decoded nested JSON value and reuse the same
index. A valid graph is shallow and fits the standalone compact-text limit
at the maximum supported sizes. Malformed nested graphs use the original
compact-text validation path to retain size, depth, and error precedence.
Regression tests exercise competing decode and structural errors, nested
graph depth, and independence after source mutation.

An external comparison with 0.8.12 matched the exact output bytes and the
independent reference for 113 graph JSON reports, 113 DOT graphs, 40 SSA
reports, 10 named query batches and 43 value-origin reports. All 44 malformed
diagnostics matched the old bytes, including competing errors and nested
depth limits. The dense fixture also passed new-file and overwrite-refusal
checks. Local verification ran 97 tests per backend, all SDK examples and
443 real CLI invocations. The Windows host skipped symlink creation and
POSIX FIFO replacement checks due to platform capability.

The benchmark uses 512 nodes named `n000` through `n511`, padded on the right
with `a` to 64 ASCII bytes. Add edges from lower to higher indices in
increasing gap order, then ascending source order, stopping at 8,192 edges.
Node 0 is the entry and node 511 is the exit. The graph file is 1,148,618
bytes. The postdominator batch includes 16 dominance checks and 16 pairwise
common-ancestor queries. The SSA fixture defines one variable at nodes 0 and
1 and uses it at node 511.

Windows and Node.js 22.16.0 ran nine alternating fresh process pairs against
the optimized JavaScript of each version. The table gives median wall time
and median `GetProcessMemoryInfo` peak working set for the complete CLI
process, including startup, file input and report output.

| Workflow | Wall time 0.8.12 to 0.8.13 | Peak working set 0.8.12 to 0.8.13 |
| --- | ---: | ---: |
| Named postdominator batch | 204.22 to 190.70 ms | 58.32 to 50.59 MiB |
| SSA planning | 251.08 to 220.47 ms | 66.22 to 57.19 MiB |
| Single-edge witness | 188.70 to 182.29 ms | 50.99 to 50.66 MiB |

Separate SDK timing ran six warmups and 20 measured calls per process, using
the same nine-pair procedure. Its timed loop covers the selected operation,
with startup, file input and digest computation outside the timing. Mean
time per call, reported as the median across processes, was 7.703 to 7.337 ms
for `parse_graph` and 1.759 to 1.783 ms for a typed witness query, which
continues to validate each input. Process peaks were 79.41 to 79.49 MiB
and 60.82 to 59.62 MiB respectively. All timed results matched.

In 0.8.14 both report output modes can record an owner within the stage before
writing data. MoonBit validates the versioned owner record and classifies
activity from its local process scope, PID and start token. The record binds
the parent and stage directory identities and the original stage name.
The filesystem adapter bounds owner reads to 4 KiB and checks stable path or
descriptor identity. It accepts a single-linked regular owner file and
rechecks the directory and marker after the process snapshot.

Linux uses the procfs boot and PID namespace identities and the process start
tick. Windows uses the local machine scope and the process creation time via
one hidden, time-limited Windows PowerShell probe. Confirmed absence, a
terminated process, or reuse of a PID within the matching scope yields
`abandoned`. Unavailable evidence yields `unknown`. The marker belongs to
the trusted-local workflow and is not an authentication mechanism. Cleanup
still targets only files created by the current writer. Inspection only reads
filesystem and process evidence and cannot establish publication on its own.

The host test pauses a real writer before the publication step, inspects
`active`, kills and reaps it, then verifies `abandoned` with the same task
ID and output name. Legacy names still report `unknown` in detailed mode.
An external comparison matched six legacy v1 entries byte for byte with
0.8.13. It also checked missing, malformed and oversized metadata, a copied
marker in another directory, and a stage containing an unrelated file.
Snapshots of stage contents, report data and a preexisting hard link survived
repeated inspection. The owner and data remain available in a retained stage.
Windows local verification passed 97 tests per backend, all SDK examples and
445 real CLI invocations with Node.js 22.16.0 and moonc 0.10.20+65efd5b93.
The local host lacked symlink creation capability and POSIX FIFO support.

In 0.8.15 detailed stage inspection can return observations during sibling
directory-entry changes. If the parent identity still matches, the report
marks `scan_complete: false` and checks the individual owner records before
reporting activity. This optional field applies to a scan that previously
failed with an I/O diagnostic. Stable detailed reports and the original v1
format keep their existing output. A missing or replaced parent still fails
the directory check. The host regression creates an unrelated sibling entry as
enumeration finishes and exercises both command forms on the same stage. The
MoonBit CLI regression covers an unchanged process, PID reuse, confirmed exit,
missing or unrecognized process evidence, and mismatched process scopes.
Local Windows verification passed 97 Wasm GC tests, 98 JavaScript tests, all
three SDK examples on both backends, and 448 real CLI invocations on the same
toolchain. Symlink creation and the POSIX FIFO test were unavailable locally.

In 0.8.16 full value-origin analysis gathers reachable uses and marks which
variables have reachable definitions in the same scan. Every reachable use
of a variable without a reachable definition gets one incoming-value
relation. Variables with reachable definitions still use the existing
predecessor search, including definitions from earlier loop iterations.
The new regression combines reachable definitions, definitions confined
to dead blocks, entry values and a permanent loop. It compares the saved
rows with a forward oracle and the SDK single-use query. The existing
capacity fixture exercises exactly 65,536 relations and rejects the next
incoming-value relation with the same error.

The CLI benchmark uses nodes `b0` through `b511` and 32 variables. Each
participating node connects to the next 16 nodes in cyclic index order.
The entry is `b0` and the declared exit list is empty. The read-only fixture
uses all variables at every node. The unreachable fixture excludes `b511`
from the cycle, defines all variables there and omits the first variable's
use at `b510`. The mixed fixture defines the first eight variables at
nodes 8, 128, 256 and 384 and omits uses at `b511`.

Seven alternating pairs of fresh Node.js 22.16.0 processes on Windows
compared the installed 0.8.15 CLI and the optimized 0.8.16 CLI. The times
are fixture-specific median wall times for input, analysis and stdout.

| Fixture | Report rows | 0.8.15 | 0.8.16 |
| --- | ---: | ---: | ---: |
| No definitions | 16,384 | 905 ms | 224 ms |
| Definitions only in the unreachable block | 16,351 | 902 ms | 231 ms |
| Mixed reachable definitions and entry values | 16,352 | 919 ms | 412 ms |

Every timed result matched stdout, stderr and exit status. Five selected
use queries, the relation limit and undeclared-use diagnostics, and one
2,183,547-byte `--out` report also matched the prior release.
Local verification passed 98 Wasm GC tests, 99 JavaScript tests, all
three SDK examples on both backends and 448 real CLI invocations. The
Windows host skipped symlink and POSIX FIFO checks due to platform capability.

In 0.8.17 bounded full JSON counts witnesses until the first witness beyond
65,536, then writes the ordered prefix one original edge at a time. The
writer holds at most one edge's dependent indices alongside its output.
This preserves the completeness flag, numeric index order, field order
and inclusive byte budget. The legacy JSON formatter and array-returning
query remain available. Regression cases exercise 65,536 and 65,537
witnesses, a truncated prefix ending inside one edge, and a byte limit
that cuts off the first witness row. SDK and CLI exports still reject an
over-budget result before returning it or publishing it to a file.

The 98-node exact-limit fixture from `control_witness_wbtest.mbt` produces
6,051,050 CLI stdout bytes. The 128-node fixture `witness_overflow_graph`
induces 112,368 logical witnesses and produces a 6,116,701-byte report with
the bounded prefix. Padding its node IDs to 64 ASCII bytes exceeds the
byte budget. An independent check counted and compared every retained
witness. Report bytes, error bytes, new-file output and refusal to
overwrite an existing file matched 0.8.16.

Seven alternating fresh process pairs used Node.js 22.16.0 on Windows.
The following values are medians of wall time and peak working set over
the full CLI run, including input, analysis and output.

| Fixture | Wall time 0.8.16 to 0.8.17 | Peak working set 0.8.16 to 0.8.17 |
| --- | ---: | ---: |
| Exactly 65,536 witnesses | 272.31 to 268.99 ms | 82.26 to 78.79 MiB |
| Truncated witness prefix | 289.86 to 268.86 ms | 87.89 to 79.38 MiB |
| Oversized JSON body | 256.66 to 241.92 ms | 69.13 to 65.74 MiB |

A separate SDK timing uses the 128-node fixture and a 143,832-byte budget
that ends before the first witness row. Each fresh process prepared one
analysis, warmed it with four calls and measured 12 export calls. Across
seven alternating pairs, the median per-call time was 6.168 to 2.661 ms
and process peak working set was 84.41 to 57.92 MiB. The byte-limit
diagnostic matched in every call.
Local verification passed 98 Wasm GC tests, 99 JavaScript tests, all three
SDK examples on both backends and 448 CLI invocations. Windows skipped
the symlink and POSIX FIFO cases due to local platform capability.

In 0.8.18 a selected loop query finds candidate latches using two entry
traversals. A reachable predecessor of the selected header is a latch if
blocking the header makes that predecessor unreachable. The shared loop
collector walks backward from confirmed latches through reachable nodes
and stops at the header. Each reachable predecessor of a dominated
member other than the header is dominated as well. Full analysis keeps
its existing immediate-dominator tree and uses it to find latches.

The independent boundary oracle checks all 1,536 three-node graph and
entry combinations for both full and selected queries. The irreducible
fixture now also checks that a self-loop counts as a back edge and a
bypassable predecessor in the same component counts as an entering
edge. The dense fixture still exercises the 65,536-edge aggregate cap
and the complete selected result.

An external comparison with 0.8.17 checked six selected reports against an
independent path oracle. The report bytes, two diagnostics, new-file output
and refusal to overwrite an existing file matched. Full JSON and summaries
also matched on the dense loop, irreducible self-loop and entry-loop fixtures.

The timed graphs have 512 nodes. The dense forward graph adds edges in
increasing distance and source order up to 8,192 edges. The dense loop
graph follows a chain from node 0 to 510, adds edges 509 to 64, 511 to
511 and 511 to 64, then adds backward edges between nodes 64 and 509 in
increasing distance and source order up to 8,192 edges. The selected
loop at node 64 has one entering edge, one leaving edge and 19 back edges.

Windows and Node.js 22.16.0 ran seven alternating fresh process pairs
against the optimized JavaScript of each version. The CLI time includes
startup, input and output. Each SDK process parsed once, warmed up with
25 calls and timed 30 to 160 queries depending on the fixture. The SDK
results are median per-call times including graph validation.

| Selected node | CLI time 0.8.17 to 0.8.18 | SDK time per call 0.8.17 to 0.8.18 |
| --- | ---: | ---: |
| Chain node 256 | 126.26 to 125.31 ms | 0.122 to 0.101 ms |
| Dense forward graph node 256 | 150.75 to 145.44 ms | 0.980 to 0.858 ms |
| Dense loop header 64 | 158.05 to 155.39 ms | 2.011 to 1.738 ms |
| Dense loop graph unreachable node 511 | 154.24 to 149.55 ms | 1.077 to 0.992 ms |

For header 64 the median process peak working set was 46.64 to 46.72 MiB
in the CLI measurement and 65.44 to 74.72 MiB in the repeated SDK
measurement. These peaks include Node.js runtime allocations and vary
by fixture and process history.
Local verification passed 98 Wasm GC tests, 99 JavaScript tests, all three
SDK examples on both backends and 448 CLI invocations. Windows skipped
the symlink and POSIX FIFO cases due to local platform capability.

In 0.8.19 full value-origin exports serialize one use row at a time and
reuse the JSON spelling of repeated identifiers. The saved analysis
retains the source relation count already computed during analysis.
The byte budget is checked during export using the existing 16 MiB
limit. Field and row order, indentation, the CLI newline and the
single-use report remain compatible. The exact 65,536-source fixture
also checks the serialized count; the next source yields the existing
relation-limit diagnostic.

The benchmark compares 0.8.18 and 0.8.19 with seven alternating fresh
Node.js 22.16.0 process pairs on Windows. Both fixtures use 64-byte
ASCII IDs. The use-heavy fixture is a 512-node chain that reads 32
variables at each node and contains 16,384 uses. Its report body is
4,049,743 bytes. The relation-heavy fixture uses 511 report rows and
the exact 65,536-source graph in `value_origins_wbtest.mbt`. Its
report body is 5,090,017 bytes.

| Fixture | CLI wall time | CLI peak working set | SDK per export |
| --- | ---: | ---: | ---: |
| 16,384 uses | 234.12 to 184.26 ms | 105.50 to 64.50 MiB | 40.426 to 5.610 ms |
| 65,536 source relations | 205.14 to 176.52 ms | 77.56 to 61.17 MiB | 22.827 to 2.967 ms |

The table shows medians. CLI figures include startup, input, analysis
and output. Each SDK process analyzed once, warmed up with four exports
and measured 12 exports of the same saved report. Its median peak
working set was 269.67 to 107.77 MiB for the use-heavy fixture and
194.39 to 95.05 MiB for the relation-heavy fixture. Full report bytes,
selected uses, diagnostics, new-file output and refusal to overwrite
matched the prior release.
Local verification passed 98 Wasm GC tests, 99 JavaScript tests, all
three SDK examples on both backends and 448 CLI invocations. The
Windows host skipped symlink and POSIX FIFO cases due to platform capability.

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
