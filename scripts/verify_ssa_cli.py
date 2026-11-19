#!/usr/bin/env python3
"""Exercise actual plan-ssa files against the independent MoonBit reference."""
import json
from host import ROOT, require, run_checks


def verify_programs(checks):
    for case in checks.reference.run("program-cases"):
        checks.check_case("plan-ssa", case["name"], case["input"], case["expected"])
    for path in sorted((ROOT / "examples").glob("*.json")):
        program = json.loads(path.read_text(encoding="utf-8"))
        if program.get("schema") == "cairndom.program.v1":
            checks.check_case("plan-ssa", "example-" + path.stem, program)


def verify(checks):
    verify_programs(checks)
    cases = checks.reference.run("host-cases")
    _, published, _, stdout = checks.file_contract("plan-ssa", "input with spaces 汉字", cases["program"])
    fresh = checks.work / "budget.out"
    for case in cases["ssa_budget"]:
        args = ["plan-ssa", checks.put_graph(case["name"], case["input"])]
        error = case["error"]
        if error is None:
            require(len(checks.invoke(args)) == 16_777_216, "exact CLI size should fit")
        else:
            for options in ([], ["--out", fresh], ["--out", published]):
                checks.invoke([*args, *options], error=error)
            require(not fresh.exists() and published.read_bytes() == stdout.encode("utf-8"),
                    "SSA limit failure published or replaced output")


if __name__ == "__main__":
    run_checks(__doc__, "SSA", verify)
