#!/usr/bin/env python3
"""Run named query batches against independent MoonBit node-removal answers."""
import json
from host import ROOT, run_checks


def verify(checks):
    cases = checks.reference.run("query-cases")
    for case in cases:
        checks.check_case("query", case["name"], case["input"], case["expected"])
    for path in sorted((ROOT / "examples").glob("*.json")):
        value = json.loads(path.read_text(encoding="utf-8"))
        if value.get("schema") == "cairndom.queries.v1":
            checks.check_case("query", "example-" + path.stem, value)
    checks.file_contract("query", "query input 汉字", cases[0]["input"])


if __name__ == "__main__":
    run_checks(__doc__, "Query", verify)
