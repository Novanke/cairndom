#!/usr/bin/env python3
"""Exercise real graph files; independent algorithms and cases run in MoonBit."""
import json
import os
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
    graph = checks.reference.run("host-cases")["graph"]
    path, out, original, stdout = checks.file_contract("analyze", "file with spaces 汉字", graph)
    report = json.loads(stdout)
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

def verify(checks):
    verify_graphs(checks)
    verify_formats_and_errors(checks)


if __name__ == "__main__":
    run_checks(__doc__, "Graph", verify)
