#!/usr/bin/env python3
"""Gera platform/monitoring/dashboard.json. Editar aqui, não no JSON."""
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
    row("Resumo (números do post)", 0),
    panel("stat", "Latência p95 (chat)", [(f"llm:latency_seconds:p95_5m{{{CHAT}}}", "")], 0, 1, 4, 4, "s", decimals=2),
    panel("stat", "Tokens gerados/s", [("llm:generated_tokens:rate5m", "")], 4, 1, 4, 4, "none", decimals=1),
    panel("stat", "Requisições/s (200)", [("llm:ok_requests:rate5m", "")], 8, 1, 4, 4, "reqps", decimals=2),
    panel("stat", "US$ por 1k requisições", [("llm:cost_usd_per_1k_requests", "")], 12, 1, 4, 4, "currencyUSD", decimals=3,
          desc="Custo/hora do nó ÷ requisições OK por hora. Sem tráfego não há valor."),
    panel("stat", "US$ por 1M tokens", [("llm:cost_usd_per_1m_output_tokens", "")], 16, 1, 4, 4, "currencyUSD", decimals=2),
    panel("stat", "US$ por hora (nó)", [("llm:node_cost_usd_per_hour", "{{profile}}")], 20, 1, 4, 4, "currencyUSD", decimals=3,
          desc="Definido em k8s/overlays/<perfil>/cost.yaml."),

    row("Latência e vazão (gateway Istio)", 5),
    panel("timeseries", "Latência do chat", [
        (f"llm:latency_seconds:p50_5m{{{CHAT}}}", "p50"),
        (f"llm:latency_seconds:p95_5m{{{CHAT}}}", "p95"),
        (f"llm:latency_seconds:p99_5m{{{CHAT}}}", "p99"),
    ], 0, 6, 12, 8, "s", desc="Ponta a ponta, medida no ingress gateway (inclui fila e geração)."),
    panel("timeseries", "Latência p95 por rota", [("llm:latency_seconds:p95_5m", "{{request_path}}")], 12, 6, 12, 8, "s"),
    panel("timeseries", "Requisições/s por rota e status", [("llm:requests:rate1m", "{{request_path}} {{response_code}}")], 0, 14, 12, 8, "reqps"),
    panel("timeseries", "Requisições em andamento", [("llm:requests_in_flight", "em andamento")], 12, 14, 12, 8, "none",
          desc="Se fica colado no --parallel (CPU) ou cresce sem parar, a fila é o gargalo."),

    row("Tokens", 22),
    panel("timeseries", "Tokens/s", [
        ("llm:generated_tokens:rate1m", "gerados"),
        ("llm:prompt_tokens:rate1m", "prompt"),
    ], 0, 23, 12, 8, "none"),
    panel("timeseries", "Time to first token p95 (só vLLM)", [
        ("histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))", "p95"),
    ], 12, 23, 12, 8, "s"),

    row("Recursos", 31),
    panel("timeseries", "Uso de GPU", [("avg by (gpu) (DCGM_FI_DEV_GPU_UTIL)", "GPU {{gpu}}")], 0, 32, 6, 8, "percent",
          desc="DCGM exporter (perfil GPU). Vazio no perfil CPU."),
    panel("timeseries", "Memória da GPU usada", [("sum by (gpu) (DCGM_FI_DEV_FB_USED) * 1024 * 1024", "GPU {{gpu}}")], 6, 32, 6, 8, "bytes"),
    panel("timeseries", "CPU do container do modelo", [
        ('sum(rate(container_cpu_usage_seconds_total{namespace="llm", container="model"}[2m]))', "cores"),
    ], 12, 32, 6, 8, "none"),
    panel("timeseries", "Memória do container do modelo", [
        ('sum(container_memory_working_set_bytes{namespace="llm", container="model"})', "working set"),
    ], 18, 32, 6, 8, "bytes"),

    row("Custo ao longo do tempo", 40),
    panel("timeseries", "Custo por 1k requisições", [("llm:cost_usd_per_1k_requests", "US$ / 1k req")], 0, 41, 12, 8, "currencyUSD"),
    panel("timeseries", "Custo por 1M tokens gerados", [("llm:cost_usd_per_1m_output_tokens", "US$ / 1M tokens")], 12, 41, 12, 8, "currencyUSD"),
]

dashboard = {
    "uid": "llm-serving",
    "title": "LLM serving: latência, tokens e custo",
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
