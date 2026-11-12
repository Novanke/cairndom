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
checks, all 57 test blocks on each backend, the optimized JavaScript build and
both SDK examples on both backends. The separate graph CLI oracle passed 115 graph cases and 159
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
The local Windows run passed 42 program oracle cases and 76 real invocations,
including Unicode/space paths, input preservation, an existing destination and
an injected partial output write. This is a file-to-report workflow; no IR
conversion or source-language semantics are inferred.

Next useful work follows correctness evidence and real consumers. Candidate
directions are efficient immutable dominance-query indexes and explicit
data-dependence inputs for program slicing. General source-language/IR parsing,
instruction ordering, variable renaming and program rewriting require separate
designs. The current phi planner reports locations and incoming-value needs;
it does not establish that an executable program has been converted to SSA.

Release verification must use the exact Git commit on public CI, publish its
Mooncakes archive, install that exact version in a new external consumer, and
compare downloaded package files to the commit before creating a matching tag.
Compiler/framework changes require rerunning the declared entry points. Personal
application information and credentials stay outside this repository.
