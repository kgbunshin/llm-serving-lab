#!/usr/bin/env python3
"""Generates platform/monitoring/dashboard.json. Edit here, not in the JSON."""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}
CHAT = 'request_path="/v1/chat/completions"'
_id = 0


def panel(kind, title, targets, x, y, w, h, unit, desc="", decimals=None, extra=None):
    global _id
    _id += 1
    p = {
        "id": _id, "type": kind, "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"datasource": DS, "expr": e, "legendFormat": l, "refId": chr(65 + i)}
                    for i, (e, l) in enumerate(targets)],
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "options": {},
    }
    if decimals is not None:
        p["fieldConfig"]["defaults"]["decimals"] = decimals
    if kind == "timeseries":
        p["fieldConfig"]["defaults"]["custom"] = {"lineWidth": 2, "fillOpacity": 0, "showPoints": "never"}
        p["options"] = {"legend": {"displayMode": "list", "placement": "bottom"},
                        "tooltip": {"mode": "multi", "sort": "desc"}}
    if kind == "stat":
        p["options"] = {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "none",
                        "graphMode": "area", "textMode": "value"}
    if extra:
        p.update(extra)
    return p


def row(title, y):
    global _id
    _id += 1
    return {"id": _id, "type": "row", "title": title, "collapsed": False,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


panels = [
    row("Summary (numbers for the post)", 0),
    panel("stat", "p95 latency (chat)", [(f"llm:latency_seconds:p95_5m{{{CHAT}}}", "")], 0, 1, 4, 4, "s", decimals=2),
    panel("stat", "Generated tokens/s", [("llm:generated_tokens:rate5m", "")], 4, 1, 4, 4, "none", decimals=1),
    panel("stat", "Requests/s (200)", [("llm:ok_requests:rate5m", "")], 8, 1, 4, 4, "reqps", decimals=2),
    panel("stat", "US$ per 1k requests", [("llm:cost_usd_per_1k_requests", "")], 12, 1, 4, 4, "currencyUSD", decimals=3,
          desc="Node cost/hour ÷ OK requests per hour. No traffic, no value."),
    panel("stat", "US$ per 1M tokens", [("llm:cost_usd_per_1m_output_tokens", "")], 16, 1, 4, 4, "currencyUSD", decimals=2),
    panel("stat", "US$ per hour (node)", [("llm:node_cost_usd_per_hour", "{{profile}}")], 20, 1, 4, 4, "currencyUSD", decimals=3,
          desc="Set in k8s/overlays/<profile>/cost.yaml."),

    row("Latency and throughput (Istio gateway)", 5),
    panel("timeseries", "Chat latency", [
        (f"llm:latency_seconds:p50_5m{{{CHAT}}}", "p50"),
        (f"llm:latency_seconds:p95_5m{{{CHAT}}}", "p95"),
        (f"llm:latency_seconds:p99_5m{{{CHAT}}}", "p99"),
    ], 0, 6, 12, 8, "s", desc="End to end, measured at the ingress gateway (includes queueing and generation)."),
    panel("timeseries", "p95 latency by route", [("llm:latency_seconds:p95_5m", "{{request_path}}")], 12, 6, 12, 8, "s"),
    panel("timeseries", "Requests/s by route and status", [("llm:requests:rate1m", "{{request_path}} {{response_code}}")], 0, 14, 12, 8, "reqps"),
    panel("timeseries", "Requests in flight", [("llm:requests_in_flight", "in flight")], 12, 14, 12, 8, "none",
          desc="If it sits at --parallel (CPU) or keeps growing, the queue is the bottleneck."),

    row("Tokens", 22),
    panel("timeseries", "Tokens/s", [
        ("llm:generated_tokens:rate1m", "generated"),
        ("llm:prompt_tokens:rate1m", "prompt"),
    ], 0, 23, 12, 8, "none"),
    panel("timeseries", "Time to first token p95 (vLLM only)", [
        ("histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))", "p95"),
    ], 12, 23, 12, 8, "s"),

    row("Resources", 31),
    panel("timeseries", "GPU utilization", [("avg by (gpu) (DCGM_FI_DEV_GPU_UTIL)", "GPU {{gpu}}")], 0, 32, 6, 8, "percent",
          desc="DCGM exporter (GPU profile). Empty on the CPU profile."),
    panel("timeseries", "GPU memory used", [("sum by (gpu) (DCGM_FI_DEV_FB_USED) * 1024 * 1024", "GPU {{gpu}}")], 6, 32, 6, 8, "bytes"),
    panel("timeseries", "Model container CPU", [
        ('sum(rate(container_cpu_usage_seconds_total{namespace="llm", container="model"}[2m]))', "cores"),
    ], 12, 32, 6, 8, "none"),
    panel("timeseries", "Model container memory", [
        ('sum(container_memory_working_set_bytes{namespace="llm", container="model"})', "working set"),
    ], 18, 32, 6, 8, "bytes"),

    row("Cost over time", 40),
    panel("timeseries", "Cost per 1k requests", [("llm:cost_usd_per_1k_requests", "US$ / 1k req")], 0, 41, 12, 8, "currencyUSD"),
    panel("timeseries", "Cost per 1M generated tokens", [("llm:cost_usd_per_1m_output_tokens", "US$ / 1M tokens")], 12, 41, 12, 8, "currencyUSD"),
]

dashboard = {
    "uid": "llm-serving",
    "title": "LLM serving: latency, tokens and cost",
    "tags": ["llm", "istio", "cost"],
    "timezone": "browser",
    "schemaVersion": 39,
    "refresh": "15s",
    "time": {"from": "now-24h", "to": "now"},
    "panels": panels,
}

out = Path(__file__).resolve().parent.parent / "platform/monitoring/dashboard.json"
out.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n")
print(f"wrote {out}")
