#!/usr/bin/env python3
"""Exercise trace-values files against the independent forward-state reference."""
import json
from host import ROOT, require, run_checks


def verify(checks):
    for case in checks.reference.run("value-origins-cases"):
        checks.check_case("trace-values", case["name"], case["input"], case["expected"])
    for path in sorted((ROOT / "examples").glob("*.json")):
        program = json.loads(path.read_text(encoding="utf-8"))
        if program.get("schema") == "cairndom.program.v1":
            checks.check_case("trace-values", "example-" + path.stem, program)
    checks.file_contract("trace-values", "value origins with spaces 汉字",
                         checks.reference.run("host-cases")["program"])
    limits = checks.reference.run("value-origin-limit-cases")
    path = checks.put_graph("value-origin-at-limit", limits["at_limit"])
    stdout = checks.invoke(["trace-values", path])
    report = json.loads(stdout)
    require(report["source_relation_count"] == 65536 and
            report["source_relation_limit"] == 65536 and len(report["uses"]) == 511,
            "exact-capacity value origins were not returned completely")
    output = checks.work / "value-origin-at-limit.out"
    require(checks.invoke(["trace-values", path, "--out", output]) == "",
            "capacity report wrote both file and stdout")
    require(output.read_bytes() == stdout.encode("utf-8"),
            "capacity file differs from complete stdout report")
    checks.reject("value-origin-over-limit", limits["over_limit"], "trace-values")


if __name__ == "__main__":
    run_checks(__doc__, "ValueOrigins", verify)
