#!/usr/bin/env python3
"""Aggregate an eval run's per-task results (a .jsonl from evals/run.sh) into a
scorecard: per-task pass-rate (over --repeat), per-surface, overall, total time.

Usage: python3 evals/score.py <results.jsonl>
Prints a table to stdout and writes <results>.scorecard.json next to it.
The aggregate() function is importable (unit-tested in evals/tests/).
"""
import json
import os
import sys
from collections import defaultdict


def aggregate(records):
    """records: list of {task, pass(0|1), rc, secs}. Returns a scorecard dict."""
    by_task = defaultdict(lambda: {"runs": 0, "passes": 0, "secs": 0})
    for r in records:
        t = by_task[r["task"]]
        t["runs"] += 1
        t["passes"] += int(r.get("pass", 0))
        t["secs"] += int(r.get("secs", 0))
    tasks = {}
    by_surface = defaultdict(lambda: {"runs": 0, "passes": 0})
    for name, t in sorted(by_task.items()):
        rate = t["passes"] / t["runs"] if t["runs"] else 0.0
        tasks[name] = {"runs": t["runs"], "passes": t["passes"],
                       "pass_rate": round(rate, 3),
                       "avg_secs": round(t["secs"] / t["runs"], 1) if t["runs"] else 0}
        surface = name.split("/", 1)[0]
        by_surface[surface]["runs"] += t["runs"]
        by_surface[surface]["passes"] += t["passes"]
    surfaces = {s: {"runs": v["runs"], "passes": v["passes"],
                    "pass_rate": round(v["passes"] / v["runs"], 3) if v["runs"] else 0.0}
                for s, v in sorted(by_surface.items())}
    total_runs = sum(t["runs"] for t in by_task.values())
    total_passes = sum(t["passes"] for t in by_task.values())
    return {
        "overall": {"runs": total_runs, "passes": total_passes,
                    "pass_rate": round(total_passes / total_runs, 3) if total_runs else 0.0},
        "surfaces": surfaces,
        "tasks": tasks,
    }


def _print(card, label):
    print(f"\n=== scorecard: {label} ===")
    print(f"{'TASK':40} {'PASS':>8} {'RATE':>6} {'AVG s':>7}")
    for name, t in card["tasks"].items():
        print(f"{name:40} {str(t['passes'])+'/'+str(t['runs']):>8} {t['pass_rate']:>6} {t['avg_secs']:>7}")
    print("-" * 64)
    for s, v in card["surfaces"].items():
        print(f"{s+' (surface)':40} {str(v['passes'])+'/'+str(v['runs']):>8} {v['pass_rate']:>6}")
    o = card["overall"]
    print(f"{'OVERALL':40} {str(o['passes'])+'/'+str(o['runs']):>8} {o['pass_rate']:>6}")


def main():
    path = sys.argv[1]
    records = [json.loads(line) for line in open(path) if line.strip()]
    card = aggregate(records)
    label = os.path.splitext(os.path.basename(path))[0]
    _print(card, label)
    out = os.path.splitext(path)[0] + ".scorecard.json"
    with open(out, "w") as f:
        json.dump(card, f, indent=2)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
