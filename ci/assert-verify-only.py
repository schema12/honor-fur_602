#!/usr/bin/env python3
"""Assert, at run time, that the workflow executing this is verify-only.

This is a belt-and-braces guard. The workflow file itself is checked in CI
before merge, but this runs inside the actual job: if anyone ever adds a build
job or a compile command to this workflow, the run fails immediately instead of
silently starting a multi-hour compile.

Usage: assert-verify-only.py <workflow.yml> [expected-job ...]
"""
import re
import sys

import yaml

# Anything that could start an OpenWrt build.
FORBIDDEN = (
    "make defconfig", "make download", "make menuconfig", "make -j",
    "make world", "make tools", "feeds update", "feeds install",
    "scripts/feeds", "diy-part2", "toolchain",
)


def main():
    path = sys.argv[1]
    expected = set(sys.argv[2:]) or {"verify"}

    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)

    jobs = doc.get("jobs") or {}
    print(f"    jobs in this workflow: {sorted(jobs)}")

    problems = []
    if set(jobs) != expected:
        problems.append(f"expected jobs {sorted(expected)}, found {sorted(jobs)}")

    for jname, job in jobs.items():
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            script = step.get("run") or ""
            for needle in FORBIDDEN:
                if needle in script:
                    problems.append(f"{jname}/{step.get('name')!r} contains {needle!r}")
            # A bare `make` on its own line is also a build.
            for m in re.finditer(r"(?m)^\s*make\s*(\S*)", script):
                problems.append(f"{jname}/{step.get('name')!r} invokes make {m.group(1)!r}")

    if problems:
        print("    VERIFY-ONLY ASSERTION FAILED:")
        for p in problems:
            print(f"      {p}")
        return 1

    n_steps = sum(len((j.get("steps") or [])) for j in jobs.values())
    print(f"    no compile command in any of {n_steps} step(s)  OK")
    print("    this run cannot compile anything")
    return 0


if __name__ == "__main__":
    sys.exit(main())
