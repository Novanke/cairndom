#!/usr/bin/env python3
"""Exercise real graph files; independent algorithms and cases run in MoonBit."""
import json
import os
import tempfile
from pathlib import Path
from host import ROOT, require, run_checks

INPUT_LIMIT = 2_097_152


def verify_graphs(checks):
    for case in checks.reference.run("graph-cases"):
        checks.check_case("analyze", case["name"], case["input"], case["expected"])
    for path in sorted((ROOT / "examples").glob("*.json")):
        value = json.loads(path.read_text(encoding="utf-8"))
        if value.get("schema") == "cairndom.graph.v1":
            checks.check_case("analyze", "example-" + path.stem, value)
        else:
            require(value.get("schema") in {"cairndom.program.v1", "cairndom.queries.v1"},
                    f"Unknown example schema: {path}")


def verify_formats_and_errors(checks):
    fixtures = checks.reference.run("host-cases")
    graph = fixtures["graph"]
    path, out, original, stdout = checks.file_contract("analyze", "file with spaces 汉字", graph)
    report = json.loads(stdout)
    verify_input_device(checks, path, report)
    verify_stage_inspection(checks, path)
    expected_summary = report.copy()
    expected_summary["schema"] = "cairndom.analysis-summary.v1"
    for field in ("control_witnesses", "control_witnesses_complete", "control_witness_limit"):
        del expected_summary[field]
    summary_command = ["analyze", path, "--format", "json-summary"]
    summary = checks.invoke(summary_command)
    require(json.loads(summary) == expected_summary, "JSON summary changed graph analysis fields")
    summary_out = checks.work / "published-summary.json"
    require(checks.invoke([*summary_command, "--out", summary_out]) == "", "summary --out wrote stdout")
    require(summary_out.read_bytes() == summary.encode("utf-8"), "summary file and stdout differ")
    checks.invoke([*summary_command, "--out", summary_out], error=True)
    require(summary_out.read_bytes() == summary.encode("utf-8"), "summary replaced existing output")
    program = checks.put_graph("summary-unsupported-command", fixtures["program"])
    checks.invoke(["plan-ssa", program, "--format", "json-summary"], error=True)
    dot = checks.invoke(["analyze", path, "--format", "dot"])
    require(dot == checks.reference.run("graph", graph)["dot"] + "\n", "DOT output does not describe the input and idoms")
    dot_out = checks.work / "published.dot"
    require(checks.invoke(["analyze", path, "--format", "dot", "--out", dot_out]) == "", "DOT --out wrote stdout")
    require(dot_out.read_text(encoding="utf-8") == dot, "DOT file and stdout differ")
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
        checks.invoke(["inspect-stages", directory_link], error=True)
        require(not (checks.work / "never.json").exists(), "symlink parent allowed output publication")
        require(path.read_bytes() == original and json.loads(out.read_text(encoding="utf-8")) == report,
                "symlink error changed a target")
        directory_link.unlink()

    close = checks.staged_failure("close-failure", "close")
    close_out = checks.work / "close-failure.out"
    checks.invoke(["analyze", path, "--out", close_out], error=True, preload=close)
    require(not close_out.exists(), "close failure published incomplete output")
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

def verify_analysis_output_limit(checks):
    graph = checks.reference.run("host-cases")["large_stdout_graph"].copy()
    nodes = graph["nodes"]
    # Parallel controllers enter different points of a shared chain. The
    # full report expands their witnesses, while the summary keeps node sets.
    controllers = nodes[1:49]
    graph["edges"] = [[nodes[0], controller] for controller in controllers]
    graph["edges"].extend([controller, nodes[-1]] for controller in controllers)
    graph["edges"].extend([controller, entry] for controller in controllers for entry in nodes[49:89])
    graph["edges"].extend([nodes[index], nodes[index + 1]] for index in range(49, 127))
    path = checks.put_graph("dense-analysis", graph)
    unopened = checks.work / "oversized-new.json"
    existing = checks.work / "oversized-existing.json"
    existing.write_bytes(b"keep this output\n")
    before = set(checks.work.rglob("*"))
    for options in ([], ["--out", unopened], ["--out", existing]):
        checks.invoke(["analyze", path, *options], error={"error": "limit", "detail": "output exceeds 16 MiB"})
        require(set(checks.work.rglob("*")) == before and existing.read_bytes() == b"keep this output\n",
                "oversized analysis created a target or stage, or changed existing output")
    summary = json.loads(checks.invoke(["analyze", path, "--format", "json-summary"]))
    require(summary["schema"] == "cairndom.analysis-summary.v1" and
            summary["nodes"][49]["control_dependencies"] == controllers,
            "summary lost node-level control dependencies for the oversized analysis")


def verify_input_device(checks, path, report):
    for phase, moment in enumerate(("before", "during"), 1):
        preload = checks.failure_preload("descriptor-" + moment, f"""
const open = fs.openSync, stat = fs.fstatSync;
let input, reads = 0;
fs.openSync = function(file, ...args) {{
  const fd = open.call(this, file, ...args);
  if (String(file) === {json.dumps(str(path))}) input = fd;
  return fd;
}};
fs.fstatSync = function(fd, ...args) {{
  const result = stat.call(this, fd, ...args);
  if (fd === input && ++reads === {phase}) result.dev += 1n;
  return result;
}};
process.on("exit", () => {{ if (reads < {phase}) process.exitCode = 92; }});
""")
        command = ["analyze", path]
        if os.name == "posix":
            checks.invoke(command, error={"error": "io", "detail": f"input changed {moment} reading"},
                          preload=preload)
        else:
            require(json.loads(checks.invoke(command, preload=preload)) == report,
                    "Windows device handling changed")


def verify_stage_inspection(checks, graph):
    stop = checks.failure_preload("interrupt-publication", "fs.linkSync = () => process.exit(91);")
    with tempfile.TemporaryDirectory(prefix="cairndom-stage-test-") as directory:
        root = Path(directory).resolve()
        target = root / "report.json"
        checks.invoke(["analyze", graph, "--out", target], preload=stop, exit_code=91)
        require(not target.exists(), "report survived interruption")
        stage, = root.iterdir()
        data = stage / "data"
        original = data.read_bytes()
        fixtures = [root / (".cairndom-00000" + digit) for digit in "123"]
        empty, linked = [path for path in fixtures if path != stage][:2]
        foreign = root / ".cairndom-foreign"
        empty.mkdir()
        linked.mkdir()
        (foreign / ".cairndom-000003").mkdir(parents=True)
        target.write_bytes(b"existing output")
        os.link(target, linked / "data")
        command = ["inspect-stages", root]
        before = set(root.rglob("*"))
        expected = checks.reference.run("stage-report", [str(root), stage.name, empty.name, linked.name])
        require(json.loads(checks.invoke(command)) == expected, "incorrect stage observations")
        checks.invoke([*command, "--out", target], error=True)
        require(before == set(root.rglob("*")) and data.read_bytes() == original
                and target.read_bytes() == b"existing output" and os.path.samefile(linked / "data", target),
                "inspection changed files or hard links")


def verify(checks):
    verify_graphs(checks)
    verify_formats_and_errors(checks)
    verify_analysis_output_limit(checks)


if __name__ == "__main__":
    run_checks(__doc__, "Graph", verify)
