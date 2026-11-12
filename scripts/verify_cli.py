#!/usr/bin/env python3
"""Exercise the built CLI against graph definitions and real local-file failures.

No third-party Python packages are needed. The oracle uses reachability after
node removal, not the MoonBit immediate-dominator algorithm. It checks the
documented finite-exit-path interpretation, rather than assuming termination.
Build first; this script never invokes the MoonBit compiler or accesses a network.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GRAPH_SCHEMA = "cairndom.graph.v1"
ANALYSIS_SCHEMA = "cairndom.analysis.v1"
INPUT_LIMIT = 2_097_152


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def reachability(adjacency, starts, *, blocked=None, allowed=None):
    """Reach a set of vertices, optionally deleting one vertex and other scope."""
    found = set()
    pending = list(starts)
    while pending:
        node = pending.pop()
        if node == blocked or node in found:
            continue
        if allowed is not None and node not in allowed:
            continue
        found.add(node)
        pending.extend(adjacency[node])
    return found


def dominance_definition(succ, pred, root):
    reachable = reachability(succ, [root])
    dominators = [set() for _ in succ]
    for removed in sorted(reachable):
        surviving = reachability(succ, [root], blocked=removed)
        for node in reachable - surviving:
            dominators[node].add(removed)
    # Strict dominators form a chain. Its deepest member dominates the most
    # dominators; this selects a parent without iterating an idom equation.
    parents = [None for _ in succ]
    for node in reachable - {root}:
        strict = dominators[node] - {node}
        parents[node] = max(strict, key=lambda ancestor: len(dominators[ancestor]))
    frontiers = [set() for _ in succ]
    for target in sorted(reachable):
        witnesses = set()
        for predecessor in pred[target]:
            if predecessor in reachable:
                witnesses.update(dominators[predecessor])
        for ancestor in witnesses - (dominators[target] - {target}):
            frontiers[ancestor].add(target)
    return reachable, dominators, parents, frontiers


def expected_analysis(graph):
    names = graph["nodes"]
    index = {name: position for position, name in enumerate(names)}
    n = len(names)
    entry = index[graph["entry"]]
    edges = [(index[source], index[target]) for source, target in graph["edges"]]
    exits = [index[name] for name in graph["exits"]]
    succ = [[] for _ in names]
    pred = [[] for _ in names]
    for source, target in edges:
        succ[source].append(target)
        pred[target].append(source)
    reachable, dom, parents, frontiers = dominance_definition(succ, pred, entry)

    reverse = [[] for _ in range(n + 1)]
    reverse_pred = [[] for _ in range(n + 1)]
    for source, target in edges:
        if source in reachable and target in reachable:
            reverse[target].append(source)
            reverse_pred[source].append(target)
    for terminal in exits:
        if terminal in reachable:
            reverse[n].append(terminal)
            reverse_pred[terminal].append(n)
    exit_scope, postdom, postparents, _ = dominance_definition(reverse, reverse_pred, n)

    # A node depends on a branch when it postdominates one of the branch's
    # successors, but does not strictly postdominate the branch itself.
    controls = [set() for _ in names]
    control_witnesses = []
    for controller, successor in sorted(edges):
        if controller in exit_scope and successor in exit_scope:
            for dependent in sorted(postdom[successor] - (postdom[controller] - {controller})):
                if dependent < n:
                    control_witnesses.append({"controller": names[controller],
                                              "successor": names[successor],
                                              "dependent": names[dependent]})
    for controller in sorted(exit_scope - {n}):
        successor_postdominators = set()
        for successor in succ[controller]:
            if successor in exit_scope:
                successor_postdominators.update(postdom[successor])
        for dependent in successor_postdominators - (postdom[controller] - {controller}):
            if dependent < n:
                controls[dependent].add(controller)

    # SCCs are equivalence classes of mutual reachability, independent of the
    # production DFS finishing-order algorithm.
    closures = {node: reachability(succ, [node], allowed=reachable) for node in reachable}
    remaining = set(reachable)
    components = []
    while remaining:
        first = min(remaining)
        members = {node for node in remaining if node in closures[first] and first in closures[node]}
        entries = {
            node for node in members
            if node == entry or any(p in reachable and p not in members for p in pred[node])
        }
        components.append({
            "members": [names[node] for node in sorted(members)],
            "entry_nodes": [names[node] for node in sorted(entries)],
            "cyclic": len(members) > 1 or first in succ[first],
            "multiple_entries": len(entries) > 1,
        })
        remaining.difference_update(members)

    backedges = {}
    for latch, header in edges:
        if latch in reachable and header in dom[latch]:
            backedges.setdefault(header, set()).add(latch)
    loop_sets = {}
    for header, latches in backedges.items():
        # A natural loop is the header and vertices that can reach one of its
        # latches without crossing the header. Unreachable vertices do not count.
        loop_sets[header] = {header} | reachability(
            pred, latches - {header}, blocked=header, allowed=reachable
        )
    loops = []
    for header in sorted(loop_sets):
        members = loop_sets[header]
        containers = [other for other in loop_sets if members < loop_sets[other]]
        parent = min(containers, key=lambda other: (len(loop_sets[other]), other)) if containers else None
        loops.append({
            "header": names[header],
            "latches": [names[node] for node in sorted(backedges[header])],
            "members": [names[node] for node in sorted(members)],
            "parent_header": names[parent] if parent is not None else None,
        })

    return {
        "schema": ANALYSIS_SCHEMA,
        "entry": graph["entry"],
        "exits": graph["exits"],
        "postdominator_scope": "finite_paths_reaching_declared_exits",
        "nodes": [{
            "id": name,
            "reachable": node in reachable,
            "can_reach_exit": node in exit_scope,
            "immediate_dominator": names[parents[node]] if parents[node] is not None else None,
            "dominance_frontier": [names[target] for target in sorted(frontiers[node])],
            "immediate_postdominator": names[postparents[node]] if postparents[node] is not None and postparents[node] < n else None,
            "postdominator_is_virtual_exit": postparents[node] == n,
            "control_dependencies": [names[target] for target in sorted(controls[node])],
        } for node, name in enumerate(names)],
        "natural_loops": loops,
        "components": components,
        "control_witnesses": control_witnesses,
        "control_witnesses_complete": True,
        "control_witness_limit": 65536,
    }


def make_graph(n, edges, *, entry=0, exits=()):
    names = [f"n{node}" for node in range(n)]
    return {
        "schema": GRAPH_SCHEMA,
        "nodes": names,
        "edges": [[names[source], names[target]] for source, target in edges],
        "entry": names[entry],
        "exits": [names[node] for node in exits],
    }


def fixtures():
    return [
        ("single-terminal", make_graph(1, [], exits=[0])),
        ("entry-self-loop", make_graph(2, [(0, 0), (0, 1)], exits=[1])),
        ("entry-backedge", make_graph(4, [(0, 1), (1, 2), (2, 0), (2, 3)], exits=[3])),
        ("unreachable-incoming", make_graph(6, [(0, 1), (1, 3), (2, 3), (3, 4), (4, 3), (5, 5)], entry=2)),
        ("irreducible", make_graph(6, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1), (3, 2), (3, 4), (4, 5)], exits=[5])),
        ("nested-loops", make_graph(7, [(0, 1), (1, 2), (1, 6), (2, 3), (2, 4), (3, 2), (4, 1), (4, 5), (5, 4)], exits=[6])),
        ("multiple-latches", make_graph(5, [(0, 1), (1, 2), (1, 3), (2, 1), (3, 1), (1, 4)], exits=[4])),
        ("finite-path-scope", make_graph(3, [(0, 1), (0, 2), (2, 2)], exits=[1])),
        ("multiple-exits", make_graph(4, [(0, 1), (0, 2), (1, 3)], exits=[2, 3])),
        ("unreachable-declared-exit", make_graph(3, [(0, 1)], exits=[1, 2])),
        ("empty-exit-set", make_graph(2, [(0, 1)])),
    ]


def expected_dot(graph, report):
    lines = ["digraph CairnDom {", "  rankdir=TB;"]
    for node in report["nodes"]:
        style = "solid" if node["reachable"] else "dotted"
        lines.append(f'  "{node["id"]}" [style={style}];')
    for source, target in graph["edges"]:
        lines.append(f'  "{source}" -> "{target}";')
    for node in report["nodes"]:
        if node["immediate_dominator"] is not None:
            lines.append(f'  "{node["immediate_dominator"]}" -> "{node["id"]}" [style=dashed,color=blue,label="idom"];')
    return "\n".join(lines + ["}", ""])


class CliChecks:
    def __init__(self, node, cli, work):
        self.node = node
        self.cli = cli
        self.work = work
        self.calls = 0
        self.graphs = 0
        self.skips = []
        self.foreign = work / ".cairndom-foreign"
        self.foreign.mkdir()
        (self.foreign / "keep").write_text("unrelated task\n", encoding="utf-8")

    def invoke(self, arguments, *, error=False, preload=None, timeout=30):
        command = [self.node]
        if preload is not None:
            # Node resolves --import as an ESM specifier. A Windows absolute
            # path otherwise looks like an unsupported "C:" URL scheme.
            command.extend(["--import", Path(preload).resolve().as_uri()])
        command.extend([str(self.cli), *map(str, arguments)])
        try:
            result = subprocess.run(command, cwd=self.work, capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise AssertionError(f"CLI hung for {timeout}s: {arguments}") from exc
        self.calls += 1
        require(result.returncode == (2 if error else 0),
                f"unexpected exit {result.returncode}: {arguments}; stderr={result.stderr!r}")
        if error:
            require(not result.stdout, f"error leaked stdout: {arguments}")
            try:
                diagnostic = json.loads(result.stderr.decode("utf-8"))
            except (ValueError, UnicodeError) as exc:
                raise AssertionError(f"error was not one JSON stderr diagnostic: {result.stderr!r}") from exc
            require(set(diagnostic) == {"error", "detail"} and
                    isinstance(diagnostic["error"], str) and bool(diagnostic["error"]) and
                    isinstance(diagnostic["detail"], str) and bool(diagnostic["detail"]),
                    f"malformed stderr diagnostic: {diagnostic!r}")
        else:
            require(not result.stderr, f"successful CLI emitted stderr: {result.stderr!r}")
        stages = {path.relative_to(self.work).as_posix() for path in self.work.rglob(".cairndom-*")}
        require(stages == {".cairndom-foreign"}, f"unexpected staging residue: {stages}")
        require((self.foreign / "keep").read_text(encoding="utf-8") == "unrelated task\n",
                "unrelated task file was changed")
        return result.stdout.decode("utf-8")

    def put_graph(self, name, graph):
        path = self.work / f"{name}.json"
        path.write_text(json.dumps(graph, ensure_ascii=False), encoding="utf-8")
        return path

    def check_graph(self, name, graph):
        path = self.put_graph(name, graph)
        expected = expected_analysis(graph)
        actual = json.loads(self.invoke(["analyze", path]))
        require(actual == expected, f"graph oracle mismatch: {name}\nexpected={expected!r}\nactual={actual!r}")
        self.graphs += 1
        return path, expected

    def reject(self, name, payload):
        path = self.work / f"invalid-{name}.json"
        path.write_bytes(payload if isinstance(payload, bytes) else json.dumps(payload).encode("utf-8"))
        out = self.work / f"invalid-{name}.out"
        self.invoke(["analyze", path, "--out", out], error=True)
        require(not out.exists(), f"invalid input published an output: {name}")

    def failure_preload(self, name, source):
        # Exercise URI escaping as well as Windows drive-letter conversion.
        path = self.work / f"preload {name} 汉字.mjs"
        path.write_text("import fs from 'node:fs';\n" + source, encoding="utf-8")
        return path


def verify_graphs(checks):
    for name, graph in fixtures():
        checks.check_graph(name, graph)
    for path in sorted((ROOT / "examples").glob("*.json")):
        checks.check_graph("example-" + path.stem, json.loads(path.read_text(encoding="utf-8")))
    rng = random.Random(0xCA17D0)
    for sample in range(100):
        n = rng.randint(1, 12)
        probability = rng.uniform(0.08, 0.48)
        edges = [(source, target) for source in range(n) for target in range(n)
                 if rng.random() < probability]
        terminals = [node for node in range(n) if not any(source == node for source, _ in edges)]
        exits = [node for node in terminals if rng.randrange(3) != 0]
        graph = make_graph(n, edges, entry=rng.randrange(n), exits=exits)
        checks.check_graph(f"random-{sample:03d}", graph)
    checks.check_graph("chain-512", make_graph(512, [(node, node + 1) for node in range(511)], exits=[511]))
    dense_edges = [(source, (source + offset) % 512) for source in range(512) for offset in range(1, 17)]
    require(len(dense_edges) == 8192, "edge-limit fixture is not exactly at the limit")
    checks.check_graph("edge-limit-8192", make_graph(512, dense_edges))
    checks.reject("too-many-edges", make_graph(512, dense_edges + [(0, 0)]))
    checks.reject("too-many-nodes", make_graph(513, []))


def verify_formats_and_errors(checks):
    graph = make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3)], exits=[3])
    path, report = checks.check_graph("file with spaces 汉字", graph)
    original = path.read_bytes()
    out = checks.work / "published.json"
    require(checks.invoke(["analyze", path, "--out", out]) == "", "--out also wrote stdout")
    require(json.loads(out.read_text(encoding="utf-8")) == report, "published JSON differs from stdout")
    dot = checks.invoke(["analyze", path, "--format", "dot"])
    require(dot == expected_dot(graph, report) + "\n", "DOT output does not describe the input and idoms")
    dot_out = checks.work / "published.dot"
    require(checks.invoke(["analyze", path, "--format", "dot", "--out", dot_out]) == "", "DOT --out wrote stdout")
    require(dot_out.read_text(encoding="utf-8") == dot, "DOT file and stdout differ")
    checks.invoke(["analyze", path, "--out", out], error=True)
    require(json.loads(out.read_text(encoding="utf-8")) == report, "existing output was overwritten")
    checks.invoke(["analyze", path, "--out", path], error=True)
    require(path.read_bytes() == original, "input was overwritten")
    missing_out = checks.work / "no-parent" / "result.json"
    checks.invoke(["analyze", path, "--out", missing_out], error=True)
    require(not missing_out.exists(), "missing-parent error left an output")
    checks.invoke(["analyze", path, "--out", checks.foreign], error=True)
    checks.invoke(["analyze", checks.work / "absent.json"], error=True)
    checks.invoke(["analyze", checks.work], error=True)

    for arguments in [
        ["unknown"], ["analyze"], ["analyze", path, path],
        ["analyze", path, "--format"], ["analyze", path, "--out"],
        ["analyze", path, "--format", "yaml"], ["analyze", path, "--unknown"],
        ["analyze", path, "--format", "json", "--format", "dot"],
        ["analyze", path, "--out", "a", "--out", "b"],
    ]:
        checks.invoke(arguments, error=True)
    require("analyze INPUT" in checks.invoke(["--help"]), "help is unavailable")
    literal = checks.work / "--graph.json"
    literal.write_bytes(original)
    require(json.loads(checks.invoke(["analyze", "--", literal.name])) == report,
            "-- did not enable a literal option-like filename")

    mutations = {
        "wrong-schema": {**graph, "schema": "other"},
        "unknown-field": {**graph, "surprise": True},
        "empty-nodes": {**graph, "nodes": []},
        "duplicate-node": {**graph, "nodes": graph["nodes"] + ["n0"]},
        "invalid-node": {**graph, "nodes": ["invalid id", "n1", "n2", "n3"]},
        "unknown-entry": {**graph, "entry": "absent"},
        "non-string-entry": {**graph, "entry": 0},
        "unknown-edge": {**graph, "edges": [["n0", "absent"]]},
        "duplicate-edge": {**graph, "edges": graph["edges"] + [graph["edges"][0]]},
        "bad-edge-arity": {**graph, "edges": [["n0", "n1", "n2"]]},
        "nonterminal-exit": {**graph, "exits": ["n0"]},
        "duplicate-exit": {**graph, "exits": ["n3", "n3"]},
        "non-array-exits": {**graph, "exits": "n3"},
        "missing-exits": {key: value for key, value in graph.items() if key != "exits"},
    }
    for name, payload in mutations.items():
        checks.reject(name, payload)
    checks.reject("json", b"{not JSON}")
    checks.reject("utf8", b"\xff\xfe")
    checks.reject("duplicate-key", original[:-1] + b', "entry": "n0"}')
    exact = checks.work / "exact-input-limit.json"
    exact.write_bytes(original + b" " * (INPUT_LIMIT - len(original)))
    require(json.loads(checks.invoke(["analyze", exact])) == report, "exactly 2 MiB input was rejected")
    checks.reject("input-over-limit", exact.read_bytes() + b" ")

    # Symlinks may require an elevated Windows token; CI on POSIX checks these
    # unconditionally. Record any unavailable capability rather than claiming it.
    link = checks.work / "input-link.json"
    try:
        link.symlink_to(path)
    except (OSError, NotImplementedError) as exc:
        checks.skips.append(f"symlink checks unavailable: {type(exc).__name__}")
    else:
        checks.invoke(["analyze", link], error=True)
        output_link = checks.work / "output-link.json"
        output_link.symlink_to(out)
        checks.invoke(["analyze", path, "--out", output_link], error=True)
        directory_link = checks.work / "parent-link"
        directory_link.symlink_to(checks.work, target_is_directory=True)
        checks.invoke(["analyze", directory_link / path.name], error=True)
        checks.invoke(["analyze", path, "--out", directory_link / "never.json"], error=True)
        require(not (checks.work / "never.json").exists(), "symlink parent allowed output publication")
        require(path.read_bytes() == original and json.loads(out.read_text(encoding="utf-8")) == report,
                "symlink error changed a target")
        directory_link.unlink()

    # Inject failures only into this subprocess and its private staging file.
    # Ordinary stdout/stderr descriptors and all other paths keep their real I/O.
    capture_stage_fd = """
const open = fs.openSync;
let owned;
fs.openSync = function(file, flags, ...rest) {
  const fd = open.call(this, file, flags, ...rest);
  if (flags === 'wx' && String(file).endsWith('data')) owned = fd;
  return fd;
};
"""
    partial = checks.failure_preload("partial-write", capture_stage_fd + """
const write = fs.writeSync;
fs.writeSync = function(fd, buffer, offset, length, ...rest) {
  if (fd === owned) {
    write.call(this, fd, buffer, offset, Math.min(length, 7), ...rest);
    throw Error('injected partial output write');
  }
  return write.call(this, fd, buffer, offset, length, ...rest);
};
""")
    close = checks.failure_preload("close-failure", capture_stage_fd + """
const close = fs.closeSync;
fs.closeSync = function(fd) {
  close.call(this, fd);
  if (fd === owned) { owned = undefined; throw Error('injected close failure'); }
};
""")
    for name, preload in [("partial-write", partial), ("close-failure", close)]:
        output = checks.work / f"{name}.out"
        checks.invoke(["analyze", path, "--out", output], error=True, preload=preload)
        require(not output.exists(), f"{name} published incomplete output")
    race_out = checks.work / "publication-race.out"
    race = checks.failure_preload("publication-race", """
const link = fs.linkSync;
fs.linkSync = function(source, target) {
  fs.writeFileSync(target, 'other task won\\n', {flag:'wx'});
  return link.call(this, source, target);
};
""")
    checks.invoke(["analyze", path, "--out", race_out], error=True, preload=race)
    require(race_out.read_text(encoding="utf-8") == "other task won\n", "publication race overwrote another task")

    if os.name == "posix" and hasattr(os, "mkfifo"):
        fifo_input = checks.work / "replace-with-fifo.json"
        fifo_input.write_bytes(original)
        prepared_fifo = checks.work / "prepared.fifo"
        os.mkfifo(prepared_fifo)
        preload = checks.failure_preload("fifo-replacement", f"""
const open = fs.openSync;
const target = {json.dumps(str(fifo_input))};
const prepared = {json.dumps(str(prepared_fifo))};
let replaced = false;
fs.openSync = function(file, ...args) {{
  if (String(file) === target && !replaced) {{
    replaced = true;
    fs.renameSync(prepared, target);
  }}
  return open.call(this, file, ...args);
}};
""")
        fifo_out = checks.work / "fifo-replacement.out"
        checks.invoke(["analyze", fifo_input, "--out", fifo_out], error=True,
                      preload=preload, timeout=5)
        require(not fifo_out.exists(), "FIFO replacement published an output")
    else:
        checks.skips.append("POSIX FIFO replacement race unavailable on this platform")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default="node", help="Node.js 22.16+ executable")
    parser.add_argument("--cli", type=Path, default=ROOT / "_build/js/release/build/cmd/main/main.js",
                        help="already-built CairnDom CLI JavaScript file")
    arguments = parser.parse_args()
    node = shutil.which(arguments.node)
    require(node is not None, f"Node executable not found: {arguments.node}")
    cli = arguments.cli.resolve()
    require(cli.is_file(), f"Build the JS release CLI before checking it: {cli}")
    with tempfile.TemporaryDirectory(prefix="cairndom-verify-") as directory:
        checks = CliChecks(node, cli, Path(directory))
        verify_graphs(checks)
        verify_formats_and_errors(checks)
        print(f"CLI verification passed: {checks.graphs} graph oracle cases, {checks.calls} real CLI invocations.")
        for skipped in checks.skips:
            print(f"SKIP: {skipped}")


if __name__ == "__main__":
    main()
