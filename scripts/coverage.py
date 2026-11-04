#!/usr/bin/env python3
"""Merge JSON-lines test results and map them to the AC/BR/EF/NFR IDs of the requirements document.

usage: coverage.py <results.jsonl> <requirements.md> <out.json>
An ID is covered when at least one test that names it passed and no test that names it failed.
"""
import collections
import datetime
import json
import re
import sys

results = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ids = list(dict.fromkeys(re.findall(r"\| ((?:AC|BR|EF|NFR)-[A-Z0-9]+(?:-\d+)?) \|", open(sys.argv[2]).read())))
by_id = collections.defaultdict(list)
for r in results:
    for i in r["ids"].split():
        by_id[i].append(r)
coverage = {}
for i in ids:
    rs = by_id.get(i, [])
    coverage[i] = ("covered" if rs and all(r["status"] == "passed" for r in rs)
                   else "failed" if rs else "not-covered")
suites = collections.Counter((r["suite"], r["status"]) for r in results)
summary = {
    "generated": datetime.datetime.now().isoformat(timespec="seconds"),
    "tests": len(results),
    "passed": sum(r["status"] == "passed" for r in results),
    "failed": sum(r["status"] == "failed" for r in results),
    "by_suite": {f"{s}:{st}": n for (s, st), n in sorted(suites.items())},
    "requirement_ids": len(ids),
    "covered": sum(v == "covered" for v in coverage.values()),
    "not_covered": [i for i, v in coverage.items() if v == "not-covered"],
    "failed_ids": [i for i, v in coverage.items() if v == "failed"],
    "unknown_ids_in_tests": sorted(set(by_id) - set(ids)),
}
json.dump({"summary": summary, "coverage": coverage, "results": results}, open(sys.argv[3], "w"), indent=1)
print(json.dumps(summary, indent=1))
sys.exit(1 if summary["failed"] or summary["failed_ids"] else 0)
