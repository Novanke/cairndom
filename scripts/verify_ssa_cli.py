#!/usr/bin/env python3
"""Exercise actual plan-ssa files against the independent MoonBit reference."""
import json
from host import ROOT, run_checks


def verify_programs(checks):
    for case in checks.reference.run("program-cases"):
        checks.check_case("plan-ssa", case["name"], case["input"], case["expected"])
    for path in sorted((ROOT / "examples").glob("*.json")):
        program = json.loads(path.read_text(encoding="utf-8"))
        if program.get("schema") == "cairndom.program.v1":
            checks.check_case("plan-ssa", "example-" + path.stem, program)


def verify(checks):
    verify_programs(checks)
    checks.file_contract("plan-ssa", "input with spaces 汉字", checks.reference.run("host-cases")["program"])


if __name__ == "__main__":
    run_checks(__doc__, "SSA", verify)
