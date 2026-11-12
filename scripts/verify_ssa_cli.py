#!/usr/bin/env python3
"""Check real plan-ssa CLI files against independent dataflow definitions.

Only Python's standard library is used. Liveness uses block-set equations;
dominance frontiers use the node-removal oracle from verify_cli, and pruned
phi sites use a set-theoretic least closure. This checks locations and incoming
value requirements, not instruction renaming or executable SSA rewriting.
Build the CLI first; this script never builds MoonBit or accesses a network.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import random
import shutil
import tempfile

from verify_cli import CliChecks, dominance_definition, make_graph, reachability, require


ROOT = Path(__file__).resolve().parents[1]
ENTRY_VALUE_SEMANTICS = (
    "Variables live before entry local definitions require a caller-supplied "
    "parameter or initial value, or a missing-initialization diagnostic under "
    "the source language's rules."
)


def make_program(graph, variables, facts):
    """Facts map node indices to (defined-variable indices, used-variable indices)."""
    return {
        "schema": "cairndom.program.v1",
        "graph": graph,
        "variables": variables,
        "blocks": [
            {
                "node": graph["nodes"][node],
                "defines": [variables[index] for index in defined],
                "uses": [variables[index] for index in used],
            }
            for node, (defined, used) in facts.items()
        ],
    }


def expected_plan(program):
    graph = program["graph"]
    names = graph["nodes"]
    variables = program["variables"]
    node_index = {name: index for index, name in enumerate(names)}
    variable_index = {name: index for index, name in enumerate(variables)}
    n = len(names)
    entry = node_index[graph["entry"]]
    succ = [[] for _ in names]
    pred = [[] for _ in names]
    for source_name, target_name in graph["edges"]:
        source, target = node_index[source_name], node_index[target_name]
        succ[source].append(target)
        pred[target].append(source)
    reachable = reachability(succ, [entry])
    definitions = [set() for _ in names]
    uses = [set() for _ in names]
    for block in program["blocks"]:
        node = node_index[block["node"]]
        definitions[node] = {variable_index[name] for name in block["defines"]}
        uses[node] = {variable_index[name] for name in block["uses"]}

    # Independent whole-block set equations, rather than production's backward
    # propagation from per-variable use sites. The initial empty sets select the
    # least fixed point, including reachable cycles without any declared exit.
    live_in = [set() for _ in names]
    live_out = [set() for _ in names]
    changed = True
    while changed:
        changed = False
        for node in reversed(range(n)):
            if node not in reachable:
                continue
            outgoing = {variable for child in succ[node] if child in reachable
                        for variable in live_in[child]}
            incoming = uses[node] | (outgoing - definitions[node])
            if outgoing != live_out[node] or incoming != live_in[node]:
                live_out[node] = outgoing
                live_in[node] = incoming
                changed = True

    _, _, _, frontiers = dominance_definition(succ, pred, entry)
    placements = []
    phi_variables = [set() for _ in names]
    for variable, name in enumerate(variables):
        definition_nodes = {node for node in reachable if variable in definitions[node]}
        live_nodes = {node for node in reachable if variable in live_in[node]}
        phi_nodes = set()
        while True:
            closure = phi_nodes | {
                target for source in definition_nodes | phi_nodes
                for target in frontiers[source] if target in live_nodes
            }
            if closure == phi_nodes:
                break
            phi_nodes = closure
        for node in phi_nodes:
            phi_variables[node].add(variable)
        placements.append({
            "variable": name,
            "definition_blocks": [names[node] for node in sorted(definition_nodes)],
            "live_in_blocks": [names[node] for node in sorted(live_nodes)],
            "phi_blocks": [names[node] for node in sorted(phi_nodes)],
            "requires_entry_value": variable in live_in[entry],
        })

    def variable_names(indices):
        return [variables[index] for index in sorted(indices)]

    return {
        "schema": "cairndom.ssa-plan.v1",
        "status": "locations_only",
        "entry": graph["entry"],
        "scope": "entry_reachable_all_paths",
        "use_convention": "before_local_definition",
        "variables": variables,
        "blocks": [
            {
                "id": name,
                "reachable": node in reachable,
                "defines": variable_names(definitions[node]),
                "uses": variable_names(uses[node]),
                "live_in": variable_names(live_in[node]),
                "live_out": variable_names(live_out[node]),
                "phi_variables": variable_names(phi_variables[node]),
            }
            for node, name in enumerate(names)
        ],
        "placements": placements,
        "entry_values_required": [placement["variable"] for placement in placements
                                  if placement["requires_entry_value"]],
        "entry_value_semantics": ENTRY_VALUE_SEMANTICS,
    }


def fixtures():
    return [
        ("branch-live-dead-and-parameter", make_program(
            make_graph(6, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)], exits=[4]),
            ["value", "unused", "parameter"],
            {2: ([1, 0], []), 1: ([0, 1], []), 3: ([], [2, 0]), 5: ([2], [1])})),
        ("loop-carried-input", make_program(
            make_graph(4, [(0, 1), (1, 2), (2, 1), (1, 3)], exits=[3]),
            ["counter", "dead"], {1: ([], [0]), 2: ([1, 0], [0])})),
        ("nonzero-entry-unreachable-incoming", make_program(
            make_graph(5, [(2, 1), (1, 3), (0, 1), (4, 4)], entry=2, exits=[3]),
            ["x", "dead_only"], {0: ([0], []), 1: ([], [0]), 4: ([1], [1])})),
        ("same-block-use-before-def", make_program(
            make_graph(1, [], exits=[0]), ["x"], {0: ([0], [0])})),
        ("entry-self-loop", make_program(
            make_graph(1, [(0, 0)]), ["x"], {0: ([0], [0])})),
        ("multiple-exits", make_program(
            make_graph(4, [(0, 1), (0, 2), (1, 3)], exits=[2, 3]),
            ["parameter", "local"], {0: ([1], []), 2: ([], [1, 0]), 3: ([], [0, 1])})),
        ("permanent-cycle-is-live", make_program(
            make_graph(4, [(0, 1), (0, 2), (2, 3), (3, 2)], exits=[1]),
            ["x", "initialized"], {0: ([1], []), 2: ([], [0, 1]), 3: ([0], [])})),
        ("iterated-join-sites", make_program(
            make_graph(4, [(0, 1), (0, 2), (1, 3), (2, 3), (3, 1)]),
            ["x"], {2: ([0], []), 3: ([], [0]), 1: ([], [0])})),
        ("irreducible-joins", make_program(
            make_graph(5, [(0, 1), (0, 2), (1, 2), (2, 1), (1, 3), (2, 3), (3, 4)], exits=[4]),
            ["x", "y"], {1: ([0], [1]), 2: ([1], [0]), 3: ([], [1, 0])})),
        ("zero-variables", make_program(
            make_graph(2, [(0, 1)], exits=[1]), [], {})),
    ]


def check_program(checks, name, program):
    path = checks.put_graph(name, program)
    expected = expected_plan(program)
    actual = json.loads(checks.invoke(["plan-ssa", path]))
    require(actual == expected,
            f"SSA oracle mismatch: {name}\nexpected={expected!r}\nactual={actual!r}")
    checks.graphs += 1
    return path, expected


def verify_programs(checks):
    for name, program in fixtures():
        check_program(checks, name, program)
    example = ROOT / "examples" / "ssa-branch.json"
    check_program(checks, "example-ssa-branch", json.loads(example.read_text(encoding="utf-8")))
    rng = random.Random(0x55ACA17D0)
    for sample in range(30):
        n = rng.randint(1, 10)
        probability = rng.uniform(0.08, 0.5)
        edges = [(source, target) for source in range(n) for target in range(n)
                 if rng.random() < probability]
        terminals = [node for node in range(n) if not any(source == node for source, _ in edges)]
        exits = [node for node in terminals if rng.randrange(3) != 0]
        graph = make_graph(n, edges, entry=rng.randrange(n), exits=exits)
        variable_ids = list(range(rng.randint(0, 6)))
        rng.shuffle(variable_ids)
        variables = [f"v{variable}" for variable in variable_ids]
        facts = {}
        for node in range(n):
            defined = [variable for variable in range(len(variables)) if rng.random() < 0.38]
            used = [variable for variable in range(len(variables)) if rng.random() < 0.32
                    and not (sample % 7 == 0 and variable == len(variables) - 1)]
            rng.shuffle(defined)
            rng.shuffle(used)
            if defined or used or rng.randrange(2):
                facts[node] = (defined, used)
        program = make_program(graph, variables, facts)
        rng.shuffle(program["blocks"])
        check_program(checks, f"random-program-{sample:02d}", program)


def verify_files_and_errors(checks):
    program = fixtures()[0][1]
    path, expected = check_program(checks, "input with spaces 汉字", program)
    original = path.read_bytes()
    stdout = checks.invoke(["plan-ssa", path])
    out = checks.work / "new plan with spaces 汉字.json"
    require(checks.invoke(["plan-ssa", path, "--out", out]) == "", "--out also wrote stdout")
    require(out.read_bytes() == stdout.encode("utf-8"), "new-file bytes differ from stdout")
    require(json.loads(stdout) == expected, "file fixture changed its plan")
    require(checks.invoke(["plan-ssa", path, "--format", "json"]) == stdout,
            "explicit JSON format differs from default")
    published = out.read_bytes()
    checks.invoke(["plan-ssa", path, "--out", out], error=True)
    require(out.read_bytes() == published, "existing output was overwritten")
    checks.invoke(["plan-ssa", path, "--out", path], error=True)
    require(path.read_bytes() == original, "input was overwritten")
    missing_out = checks.work / "missing-parent" / "plan.json"
    checks.invoke(["plan-ssa", path, "--out", missing_out], error=True)
    require(not missing_out.exists(), "missing-parent error published an output")
    checks.invoke(["plan-ssa", checks.work / "missing.json"], error=True)
    checks.invoke(["plan-ssa", checks.work], error=True)

    literal = checks.work / "--program.json"
    literal.write_bytes(original)
    require(json.loads(checks.invoke(["plan-ssa", "--", literal.name])) == expected,
            "literal option-like input filename was not supported")
    require("plan-ssa INPUT" in checks.invoke(["--help"]), "plan-ssa help is unavailable")

    for number, arguments in enumerate([
        ["plan-ssa"], ["plan-ssa", path, path],
        ["plan-ssa", path, "--out"], ["plan-ssa", path, "--format"],
        ["plan-ssa", path, "--unknown"], ["plan-ssa", path, "--format", "yaml"],
        ["plan-ssa", path, "--format", "json", "--format", "json"],
        ["plan-ssa", path, "--format", "dot"],
    ]):
        rejected_out = checks.work / f"bad-option-{number}.json"
        checks.invoke([*arguments, "--out", rejected_out], error=True)
        require(not rejected_out.exists(), f"bad options published an output: {arguments}")
    checks.invoke(["plan-ssa", path, "--out", "first.json", "--out", "second.json"], error=True)
    require(not (checks.work / "first.json").exists() and not (checks.work / "second.json").exists(),
            "duplicate output options published a file")

    def reject(name, payload):
        invalid = checks.work / f"invalid-program-{name}.json"
        invalid.write_bytes(payload if isinstance(payload, bytes)
                            else json.dumps(payload, ensure_ascii=False).encode("utf-8"))
        rejected_out = checks.work / f"invalid-program-{name}.out"
        checks.invoke(["plan-ssa", invalid, "--out", rejected_out], error=True)
        require(not rejected_out.exists(), f"invalid program published an output: {name}")

    wrong_graph = {**program["graph"], "schema": "cairndom.graph.v999"}
    reject("graph-instead-of-program", program["graph"])
    reject("wrong-program-schema", {**program, "schema": "other"})
    reject("wrong-nested-graph-schema", {**program, "graph": wrong_graph})
    reject("unknown-variable", {**program, "blocks": [{"node": "n1", "defines": [], "uses": ["absent"]}]})
    reject("unknown-defined-variable", {**program, "blocks": [{"node": "n1", "defines": ["absent"], "uses": []}]})
    reject("duplicate-variable", {**program, "variables": ["x", "x"]})
    reject("duplicate-fact", {**program, "blocks": [{"node": "n1", "defines": [], "uses": ["value", "value"]}]})
    reject("duplicate-block", {**program, "blocks": [program["blocks"][0], program["blocks"][0]]})
    reject("unknown-block", {**program, "blocks": [{"node": "absent", "defines": [], "uses": []}]})
    reject("unknown-field", {**program, "surprise": True})
    reject("missing-facts", {**program, "blocks": [{"node": "n1", "uses": []}]})
    reject("json", b"{not JSON}")
    reject("utf8", b"\xff\xfe")
    reject("duplicate-key", original[:-1] + b', "schema": "cairndom.program.v1"}')

    # A failed staged write must leave neither an incomplete published report
    # nor private staging residue. CliChecks also protects an unrelated stage.
    partial = checks.failure_preload("ssa-partial-write", """
const open = fs.openSync;
let owned;
fs.openSync = function(file, flags, ...rest) {
  const fd = open.call(this, file, flags, ...rest);
  if (flags === 'wx' && String(file).endsWith('data')) owned = fd;
  return fd;
};
const write = fs.writeSync;
fs.writeSync = function(fd, buffer, offset, length, ...rest) {
  if (fd === owned) {
    write.call(this, fd, buffer, offset, Math.min(length, 7), ...rest);
    throw Error('injected partial SSA plan write');
  }
  return write.call(this, fd, buffer, offset, length, ...rest);
};
""")
    interrupted = checks.work / "incomplete-plan.json"
    checks.invoke(["plan-ssa", path, "--out", interrupted], error=True, preload=partial)
    require(not interrupted.exists(), "partial write published an incomplete SSA plan")
    require(path.read_bytes() == original and out.read_bytes() == published,
            "error checks changed a successful input or output")


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
    with tempfile.TemporaryDirectory(prefix="cairndom-ssa-verify-") as directory:
        checks = CliChecks(node, cli, Path(directory))
        verify_programs(checks)
        verify_files_and_errors(checks)
        print(f"SSA CLI verification passed: {checks.graphs} program oracle cases, "
              f"{checks.calls} real CLI invocations; locations only.")


if __name__ == "__main__":
    main()
