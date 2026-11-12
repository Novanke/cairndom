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
checks, all 17 test blocks on each backend, the optimized JavaScript build and
both SDK example runs. The separate CLI oracle passed 115 graph cases and 159
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

Next useful work follows correctness evidence and real consumers. Candidate
directions are edge-by-edge control-dependence witnesses, caller-provided liveness
integration, and efficient repeated dominance queries. General IR parsing and
program rewriting require separate designs and are not part of this release.

Release verification must use the exact Git commit on public CI, publish its
Mooncakes archive, install that exact version in a new external consumer, and
compare downloaded package files to the commit before creating a matching tag.
Compiler/framework changes require rerunning the declared entry points. Personal
application information and credentials stay outside this repository.
