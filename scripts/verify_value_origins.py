#!/usr/bin/env python3
"""Exercise trace-values files against the independent forward-state reference."""
import json
from host import require, run_checks


def verify(checks):
    checks.check_inputs("trace-values", "value-origins-cases", "cairndom.program.v1")
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
    selected = checks.put_graph("selected-use", limits["over_limit"])
    row = report["uses"][1]
    node, variable = row["node"], row["variable"]
    command = ["trace-use", selected, "--node", node, "--variable", variable]
    require(json.loads(checks.invoke(command)) == {
        "schema": "cairndom.use-origin.v1", "node": node, "variable": variable, "origin": row,
    }, "selected use differs after full-report overflow")
    checks.invoke([*command, "--out", output], error=True)
    require(output.read_bytes() == stdout.encode("utf-8"), "trace-use overwrote a report")


if __name__ == "__main__":
    run_checks(__doc__, "ValueOrigins", verify)
