#!/usr/bin/env python3
"""Load test for the OpenAI-compatible API, stdlib only.

Runs a concurrency sweep and prints one JSON line per level, with the numbers
that go into the post: p50/p95/p99, req/s, tokens/s and cost per 1k requests.

    python3 loadgen.py --url http://istio-ingressgateway.istio-ingress \
        --concurrency 1,2,4,8 --requests 40 --cost-per-hour 0.35
"""
import argparse
import json
import statistics
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PROMPTS = [
    "Explain in three sentences what a Kubernetes Service is.",
    "List five best practices for writing Dockerfiles.",
    "What is the difference between a liveness and a readiness probe?",
    "Summarize what mTLS solves in a service mesh.",
    "Write a haiku about request queues.",
]


def one_request(url, model, max_tokens, i):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": PROMPTS[i % len(PROMPTS)]}],
        "max_tokens": max_tokens,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(f"{url}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.load(resp)
        usage = data.get("usage") or {}
        return {"ok": True, "latency": time.perf_counter() - start,
                "completion_tokens": usage.get("completion_tokens", 0)}
    except Exception as exc:  # noqa: BLE001 - count the error and keep the test going
        return {"ok": False, "latency": time.perf_counter() - start, "error": str(exc)[:200]}


def pct(values, p):
    if not values:
        return None
    values = sorted(values)
    k = max(0, min(len(values) - 1, round(p / 100 * len(values) + 0.5) - 1))
    return round(values[k], 3)


def run_level(args, concurrency):
    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        results = list(pool.map(lambda i: one_request(args.url, args.model, args.max_tokens, i),
                                range(args.requests)))
    wall = time.perf_counter() - start
    ok = [r for r in results if r["ok"]]
    lat = [r["latency"] for r in ok]
    tokens = sum(r["completion_tokens"] for r in ok)
    rps = len(ok) / wall if wall else 0
    summary = {
        "concurrency": concurrency,
        "requests": len(results),
        "errors": len(results) - len(ok),
        "wall_seconds": round(wall, 2),
        "latency_p50_s": pct(lat, 50),
        "latency_p95_s": pct(lat, 95),
        "latency_p99_s": pct(lat, 99),
        "latency_mean_s": round(statistics.mean(lat), 3) if lat else None,
        "requests_per_s": round(rps, 3),
        "output_tokens_per_s": round(tokens / wall, 1) if wall else 0,
        "cost_usd_per_hour": args.cost_per_hour,
        "cost_usd_per_1k_requests": round(args.cost_per_hour / (rps * 3600) * 1000, 4) if rps else None,
    }
    errors = [r["error"] for r in results if not r["ok"]][:3]
    if errors:
        summary["sample_errors"] = errors
    return summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--model", default="qwen2.5-1.5b")
    ap.add_argument("--concurrency", default="1,2,4,8")
    ap.add_argument("--requests", type=int, default=40, help="requests per level")
    ap.add_argument("--max-tokens", type=int, default=256)
    ap.add_argument("--cost-per-hour", type=float, default=0.0)
    args = ap.parse_args()
    for c in (int(x) for x in args.concurrency.split(",")):
        print(json.dumps(run_level(args, c)), flush=True)


if __name__ == "__main__":
    main()
