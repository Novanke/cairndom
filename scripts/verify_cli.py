#!/usr/bin/env python3
"""Exercise real graph files; independent algorithms and cases run in MoonBit."""
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path
from host import require, run_checks

INPUT_LIMIT = 2_097_152


def verify_formats_and_errors(checks):
    fixtures = checks.reference.run("host-cases")
    graph = fixtures["graph"]
    path, out, original, stdout = checks.file_contract("analyze", "file with spaces 汉字", graph)
    report = json.loads(stdout)
    verify_input_device(checks, path, report)
    verify_stage_inspection(checks, path)
    verify_durable_output(checks, path, out, fixtures)
    verify_loop_boundaries(checks, fixtures["loop_boundaries"])
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
    controller, successor = nodes[48:50]
    command = ["control-witness", path, "--controller", controller, f"--successor={successor}"]
    require(json.loads(checks.invoke(command)) == {
        "schema": "cairndom.control-witness.v1", "controller": controller,
        "successor": successor, "dependents": nodes[49:127],
    }, "selected edge lost witnesses past the full-report capacity")
    checks.invoke([*command, "--out", existing], error=True)
    require(set(checks.work.rglob("*")) == before and existing.read_bytes() == b"keep this output\n",
            "selected edge changed existing output or left a stage")


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
    stop = checks.failure_preload("interrupt-publication", """
fs.linkSync = () => {
  fs.writeFileSync(process.argv.at(-1) + ".ready", "");
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0);
};
""")
    with tempfile.TemporaryDirectory(prefix="cairndom-stage-test-") as directory:
        root = Path(directory).resolve()
        target = root / "report.json"
        ready = root / "report.json.ready"
        tasks = ["inspect-stages", "--tasks", root]
        args = [checks.node, "--import", stop.as_uri(), str(checks.cli), "analyze", graph, "--out", target]
        writer = subprocess.Popen(args, cwd=checks.work)
        try:
            for _ in range(1000):
                if ready.exists() or writer.poll() is not None:
                    break
                time.sleep(0.02)
            require(ready.exists(), "writer did not reach publication")
            stage, = root.glob(".cairndom-*")
            data, owner = stage / "data", stage / "owner.json"
            original, marker = data.read_bytes(), owner.read_bytes()
            active, = json.loads(checks.invoke(tasks))["entries"]
            require((active["ownership"], active["activity"], active["output"]) ==
                    ("recorded", "active", target.name) and active["task_id"], "wrong active writer")
        finally:
            writer.kill()
            writer.wait(timeout=10)
        checks.calls += 1
        require(not target.exists(), "report survived interruption")
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
        stable = checks.invoke(tasks)
        report = json.loads(stable)
        require(report["schema"] == "cairndom.stage-inspection.v2", "wrong task report schema")
        entries = {entry["name"]: entry for entry in report["entries"]}
        dead = entries[stage.name]
        require(dead["activity"] == "abandoned" and dead["task_id"] == active["task_id"], "wrong abandoned writer")
        for legacy in (empty, linked):
            entry = entries[legacy.name]
            require((entry["ownership"], entry["activity"], entry["task_id"]) ==
                    ("unverified", "unknown", None), "wrong legacy ownership")
        checks.invoke([*command, "--out", target], error=True)
        require(before == set(root.rglob("*")) and data.read_bytes() == original
                and owner.read_bytes() == marker
                and target.read_bytes() == b"existing output" and os.path.samefile(linked / "data", target),
                "inspection changed files or hard links")
        def when_scan_closes(action):
            return f"""
const open = fs.opendirSync;
fs.opendirSync = (path, ...options) => {{
  const dir = open(path, ...options);
  if (path === process.argv.at(-1)) {{
    const close = dir.closeSync.bind(dir);
    dir.closeSync = () => {{ {action} close(); }};
  }}
  return dir;
}};
"""
        churn = checks.failure_preload("stage-scan-churn", when_scan_closes("fs.mkdtempSync(path + '/unrelated-');"))
        partial = json.loads(checks.invoke(tasks, preload=churn))
        require(partial.pop("scan_complete", None) is False and partial == report,
                "scan did not preserve confirmed tasks with incomplete coverage")
        checks.invoke(command, preload=churn,
                      error={"error": "io", "detail": "inspection directory changed during reading"})
        require(checks.invoke(tasks) == stable, "stable task report bytes changed")
        added_link = foreign / "concurrent-link"
        link = f"fs.linkSync({json.dumps(str(data))}, {json.dumps(str(added_link))});"
        data_change = checks.failure_preload("stage-data-churn", when_scan_closes(link))
        changed = json.loads(checks.invoke(tasks, preload=data_change))
        entries[stage.name] = dict(dead, observation="changed", possible_residue=False,
                                   ownership="unverified", activity="unknown", task_id=None, output=None)
        require(changed == dict(report, entries=list(entries.values())),
                "task report confirmed stale staged data")
        require(os.path.samefile(data, added_link) and data.read_bytes() == original
                and owner.read_bytes() == marker, "inspection changed the staged data or its link")
        entries[stage.name] = dict(dead, observation="data_with_other_links")
        require(json.loads(checks.invoke(tasks)) == dict(report, entries=list(entries.values())),
                "rescan did not confirm the current link count")


def verify_durable_output(checks, graph, legacy, fixtures):
    command = ["analyze", graph, "--durable"]
    checks.invoke(command, error=True)
    content = legacy.read_bytes()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory).resolve()
        for name, expected in fixtures["durable_reports"].items():
            if (name == "unsupported" and os.name != "nt" or
                    expected["published"] and os.name != "posix"):
                continue
            target = legacy if name == "existing" else root / name
            preload = (checks.failure_preload(name, f"const mode = {json.dumps(name)};\n" +
                                              fixtures["durable_preload"]) if expected["published"] else None)
            code = 0 if name == "success" else 2
            result = json.loads(checks.invoke([*command, "--out", target], preload=preload, exit_code=code))
            stage = result.pop("stage_path")
            require(Path(result.pop("output")) == target and result == expected, f"{name}: wrong receipt {result}")
            if expected["stage_created"]:
                stage = Path(stage)
                require(stage.parent == root and stage.name.startswith(".cairndom-")
                        and stage.exists() != expected["stage_cleaned"], f"{name}: wrong stage path {stage}")
                if not expected["stage_cleaned"]:
                    checks.invoke(["inspect-stages", root])
                    require(os.path.samefile(stage / "data", target), "inspection changed retained stage")
            else:
                require(stage is None and (target == legacy or not any(root.iterdir())),
                        f"{name}: unexpected stage path or directory entries")
            if name == "existing" or expected["published"]:
                require(target.read_bytes() == content, f"{name}: changed report bytes")
            else:
                require(not target.exists(), f"{name}: unexpected report")


def verify_loop_boundaries(checks, cases):
    for number, case in enumerate(cases):
        path = checks.put_graph(f"loop-boundary-{number}", case["input"])
        for expected in case["reports"]:
            header = expected["header"]
            options = [f"--header={header}"] if header.startswith("--") else ["--header", header]
            command = ["loop-boundary", path, *options]
            stdout = checks.invoke(command)
            require(json.loads(stdout) == expected, f"wrong loop boundary for {header}")
            if header == "--inner":
                target = checks.work / "loop-boundary.out"
                require(checks.invoke([*command, "--out", target]) == "", "file output wrote stdout")
                checks.invoke([*command, "--out", target], error=True)
                require(target.read_bytes() == stdout.encode("utf-8"), "boundary file differs from stdout")
        if number == 0:
            checks.bad_arguments("loop-boundary", path)


def verify(checks):
    checks.check_inputs("analyze", "graph-cases", "cairndom.graph.v1",
                        other_schemas=("cairndom.program.v1", "cairndom.queries.v1"))
    verify_formats_and_errors(checks)
    verify_analysis_output_limit(checks)


if __name__ == "__main__":
    run_checks(__doc__, "Graph", verify)
