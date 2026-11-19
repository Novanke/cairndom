#!/usr/bin/env python3
"""Exercise actual plan-ssa files against the independent MoonBit reference."""
from host import require, run_checks


def verify(checks):
    checks.check_inputs("plan-ssa", "program-cases", "cairndom.program.v1")
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
