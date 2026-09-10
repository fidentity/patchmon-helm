#!/usr/bin/env python3
"""Check that every .Values.<path> the templates reference exists in values.yaml.

Helm renders a missing path as an empty string, so a typo produces a chart that
lints, templates and installs while silently dropping a setting. This is the
cheapest way to catch that.

Usage:  python3 check-values-refs.py [chart-dir]     (default: repo root)
Exit:   0 clean, 1 unresolved references found.
"""
import glob
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

chart = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "..", "..")
chart = os.path.abspath(chart)

values_path = os.path.join(chart, "values.yaml")
if not os.path.isfile(values_path):
    sys.exit(f"no values.yaml at {values_path}")

with open(values_path) as fh:
    values = yaml.safe_load(fh)

refs = set()
for path in glob.glob(os.path.join(chart, "templates", "**", "*"), recursive=True):
    if not path.endswith((".yaml", ".tpl", ".txt")):
        continue
    with open(path) as fh:
        body = fh.read()
    for match in re.finditer(r"\.Values\.([A-Za-z0-9_.]+)", body):
        refs.add((match.group(1).rstrip("."), os.path.relpath(path, chart)))

missing = []
for ref, where in sorted(refs):
    node = values
    for part in ref.split("."):
        if isinstance(node, dict) and part in node:
            node = node[part]
        else:
            missing.append((ref, where))
            break

if missing:
    print(f"{len(missing)} unresolved .Values reference(s):")
    for ref, where in missing:
        print(f"  .Values.{ref}    <- {where}")
    sys.exit(1)

print(f"all {len(refs)} .Values references resolve")
