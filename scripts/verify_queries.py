#!/usr/bin/env python3
"""Run named query batches against independent MoonBit node-removal answers."""
from host import run_checks


def verify(checks):
    cases = checks.check_inputs("query", "query-cases", "cairndom.queries.v1")
    checks.file_contract("query", "query input 汉字", cases[0]["input"])


if __name__ == "__main__":
    run_checks(__doc__, "Query", verify)
