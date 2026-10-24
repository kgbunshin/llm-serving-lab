#!/usr/bin/env python3
"""Prints the cost/hour set in k8s/overlays/<profile>/cost.yaml."""
import re
import sys
from pathlib import Path

text = (Path(__file__).resolve().parent.parent / f"k8s/overlays/{sys.argv[1]}/cost.yaml").read_text()
expr = re.search(r"vector\(([0-9.+\s]+)\)", text).group(1)
print(round(sum(float(x) for x in expr.split("+")), 4))
