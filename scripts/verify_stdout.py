#!/usr/bin/env python3
"""Check real CLI stdout completion and closed-stream failures without building."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from host import diagnostic, require, setup


def invoke(node, cli, arguments, *, preload=None, close_stdout=False, close_stderr=False):
    command = [node]
    if preload is not None:
        command.extend(["--import", preload.as_uri()])
    command.extend([str(cli), *map(str, arguments)])
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
        if close_stdout:
            child.stdout.close()
            child.stdout = None
        if close_stderr:
            child.stderr.close()
            child.stderr = None
        try:
            stdout, stderr = child.communicate(timeout=10)
        except subprocess.TimeoutExpired as exc:
            child.kill()
            child.communicate()
            raise AssertionError(f"CLI hung: {arguments}") from exc
        return child.returncode, stdout or b"", stderr or b""


def require_io_error(result, label, *, prefix=b""):
    code, stdout, stderr = result
    require(code == 2, f"{label}: expected exit 2, got {code}; stderr={stderr!r}")
    require(stdout == prefix, f"{label}: unexpected stdout {stdout!r}")
    require(diagnostic(stderr)["error"] == "io", f"{label}: expected one JSON I/O diagnostic")


def invoke_slow_reader(node, cli, arguments):
    chunks = []
    with subprocess.Popen([node, str(cli), *map(str, arguments)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
        def consume():
            while chunk := child.stdout.read(4096):
                chunks.append(chunk)
                time.sleep(0.001)

        reader = threading.Thread(target=consume, daemon=True)
        reader.start()
        try:
            code = child.wait(timeout=30)
        except subprocess.TimeoutExpired as exc:
            child.kill()
            child.wait()
            reader.join(timeout=10)
            raise AssertionError("large stdout hung with a slow reader") from exc
        reader.join(timeout=10)
        require(not reader.is_alive(), "slow stdout reader did not reach EOF")
        return code, b"".join(chunks), child.stderr.read()


def main():
    node, cli, reference = setup(__doc__)
    fixtures = reference.run("host-cases")
    calls = 0
    with tempfile.TemporaryDirectory(prefix="cairndom-stdout-") as directory:
        work = Path(directory)
        graph = fixtures["stdout_graph"]
        graph_path = work / "graph.json"
        graph_path.write_text(json.dumps(graph), encoding="utf-8")
        program_path = work / "program.json"
        program_path.write_text(json.dumps(fixtures["stdout_program"]), encoding="utf-8")
        query_path = work / "queries.json"
        query_path.write_text(json.dumps(reference.run("query-cases")[0]["input"]), encoding="utf-8")
        preloads = {}
        for name, action in {
            "backpressure": "write.call(this, text, callback); return false;",
            "callback-error": (
                "write.call(this, Buffer.from(text).subarray(0, 7), () => {"
                " const error = Error('injected stdout callback failure');"
                " callback(error); this.emit('error', error); }); return false;"),
            "error-event": (
                "queueMicrotask(() => this.emit('error', Error('injected stdout error event')));"
                " return false;"),
            "sync-throw": "throw Error('injected synchronous stdout failure');",
        }.items():
            preload = work / f"{name}.mjs"
            preload.write_text(
                "const output = process.stdout;\nconst write = output.write;\n"
                f"output.write = function(text, callback) {{ {action} }};\n",
                encoding="utf-8")
            preloads[name] = preload

        for name, command in [("analyze", ["analyze", graph_path]),
                              ("plan-ssa", ["plan-ssa", program_path]),
                              ("query", ["query", query_path]),
                              ("help", ["--help"])]:
            code, expected, stderr = invoke(node, cli, command)
            calls += 1
            require(code == 0 and expected.endswith(b"\n") and not stderr,
                    f"{name}: normal stdout failed: exit={code}, stderr={stderr!r}")
            if name == "help":
                require(b"analyze INPUT" in expected, "help text is missing")
            else:
                require(json.loads(expected)["schema"] == {
                    "analyze": "cairndom.analysis.v1", "plan-ssa": "cairndom.ssa-plan.v1", "query": "cairndom.answers.v1"}[name],
                    f"{name}: normal report schema is wrong")
            require_io_error(invoke(node, cli, command, close_stdout=True), name + " closed stdout")
            code, stdout, stderr = invoke(node, cli, command, close_stdout=True, close_stderr=True)
            require(code == 2 and not stdout and not stderr,
                    f"{name}: closed stdout/stderr escaped the I/O error path: exit={code}")
            require(invoke(node, cli, command, preload=preloads["backpressure"]) == (0, expected, b""),
                    f"{name}: a false write result lost queued output")
            require_io_error(invoke(node, cli, command, preload=preloads["callback-error"]),
                             name + " partial stdout callback failure", prefix=expected[:7])
            for failure in ["error-event", "sync-throw"]:
                require_io_error(invoke(node, cli, command, preload=preloads[failure]),
                                 name + " " + failure)
            calls += 6

        large_graph = fixtures["large_stdout_graph"]
        large_path = work / "large.json"
        large_path.write_text(json.dumps(large_graph, separators=(",", ":")), encoding="utf-8")
        command = ["analyze", large_path]
        code, expected, stderr = invoke(node, cli, command)
        require(code == 0 and not stderr and len(expected) > 1_048_576,
                f"large fixture did not produce a report over 1 MiB: exit={code}, bytes={len(expected)}")
        require(invoke_slow_reader(node, cli, command) == (0, expected, b""),
                "large report changed or failed under stdout backpressure")
        calls += 2
    print(f"Stdout verification passed: {calls} real CLI invocations.")


if __name__ == "__main__":
    main()
