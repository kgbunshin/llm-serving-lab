#!/usr/bin/env python3
"""Imprime o custo/hora definido em k8s/overlays/<perfil>/cost.yaml."""
import re
import sys
from pathlib import Path

text = (Path(__file__).resolve().parent.parent / f"k8s/overlays/{sys.argv[1]}/cost.yaml").read_text()
expr = re.search(r"vector\(([0-9.+\s]+)\)", text).group(1)
print(round(sum(float(x) for x in expr.split("+")), 4))
