"""Economics calculator and report generation."""

import json
import statistics
from datetime import datetime
from pathlib import Path

from .config import (
    DOCUMENTED_COST_PER_MIN, LLM_PRICING, TIERS,
    WHISPER_COST_PER_MIN, PRICING_VERIFIED_DATE,
)
from .models import RequestResult, TestReport


class EconomicsCalculator:
    @staticmethod
    def calc_transcription_stats(results: list[RequestResult]) -> dict:
        ok = [r for r in results if r.status == 200]
        if not ok:
            return {"error": "No successful transcriptions"}

        total_audio_min = sum(r.audio_duration_sec for r in ok) / 60
        latencies = sorted(r.latency_ms for r in ok)

        return {
            "total_requests": len(results),
            "successful": len(ok),
            "errors": len(results) - len(ok),
            "error_rate_pct": round((len(results) - len(ok)) / len(results) * 100, 1),
            "total_audio_minutes": round(total_audio_min, 2),
            "calculated_cost_usd": round(total_audio_min * WHISPER_COST_PER_MIN, 6),
            "cost_per_minute_usd": WHISPER_COST_PER_MIN,
            "latency_ms": {
                "p50": round(latencies[len(latencies) // 2], 0),
                "p95": round(latencies[int(len(latencies) * 0.95)], 0),
                "p99": round(latencies[int(len(latencies) * 0.99)], 0),
                "avg": round(statistics.mean(latencies), 0),
                "min": round(latencies[0], 0),
                "max": round(latencies[-1], 0),
            },
            "by_duration_bucket": _bucket_stats(ok),
        }

    @staticmethod
    def calc_llm_stats(results_by_model: dict[str, list[RequestResult]]) -> dict:
        report = {}
        for model, results in results_by_model.items():
            ok = [r for r in results if r.status == 200]
            if not ok:
                report[model] = {"error": "No successful requests"}
                continue

            pricing = LLM_PRICING[model]
            avg_in = statistics.mean(r.input_tokens for r in ok)
            avg_out = statistics.mean(r.output_tokens for r in ok)
            cost_per_req = (
                avg_in * pricing["input_per_1m"] / 1_000_000
                + avg_out * pricing["output_per_1m"] / 1_000_000
            )
            latencies = sorted(r.latency_ms for r in ok)

            report[model] = {
                "label": pricing["label"],
                "total_requests": len(results),
                "successful": len(ok),
                "avg_input_tokens": round(avg_in, 1),
                "avg_output_tokens": round(avg_out, 1),
                "cost_per_request_usd": round(cost_per_req, 8),
                "cost_per_audio_minute_usd": round(cost_per_req, 8),
                "latency_ms": {
                    "p50": round(latencies[len(latencies) // 2], 0),
                    "p95": round(latencies[int(len(latencies) * 0.95)], 0),
                    "avg": round(statistics.mean(latencies), 0),
                },
            }

        models = [m for m in report if "cost_per_request_usd" in report.get(m, {})]
        if len(models) == 2:
            c0 = report[models[0]]["cost_per_request_usd"]
            c1 = report[models[1]]["cost_per_request_usd"]
            if c0 > 0:
                ratio = c1 / c0
                report["model_comparison"] = {
                    "cost_ratio_70b_vs_8b": round(ratio, 1),
                    "note": f"70B is {ratio:.0f}x more expensive than 8B",
                }
        return report

    @staticmethod
    def calc_pipeline_stats(results: list[dict]) -> dict:
        if not results:
            return {"error": "No pipeline results"}
        ok = [r for r in results if r["whisper_ok"] and r["llm_ok"]]
        if not ok:
            return {"error": "No successful pipeline runs"}

        e2e = sorted(r["e2e_latency_ms"] for r in ok)
        rejected = sum(1 for r in ok if r["safe_merge_rejected"])

        return {
            "total": len(results), "successful": len(ok),
            "e2e_latency_ms": {
                "p50": round(e2e[len(e2e) // 2], 0),
                "p95": round(e2e[int(len(e2e) * 0.95)], 0),
                "avg": round(statistics.mean(e2e), 0),
            },
            "safe_merge_rejected_count": rejected,
            "safe_merge_rejected_pct": round(rejected / len(ok) * 100, 1),
            "avg_edit_distance": round(statistics.mean(r["edit_distance"] for r in ok), 3),
        }

    @staticmethod
    def calc_economics(whisper_cost: float, llm_stats: dict) -> dict:
        llm_8b = llm_70b = 0.0
        for model, stats in llm_stats.items():
            if model == "model_comparison" or not isinstance(stats, dict):
                continue
            cost = stats.get("cost_per_audio_minute_usd", 0)
            if "8b" in model:
                llm_8b = cost
            elif "70b" in model:
                llm_70b = cost

        actual = whisper_cost + llm_8b
        diff = ((actual - DOCUMENTED_COST_PER_MIN) / DOCUMENTED_COST_PER_MIN * 100
                if DOCUMENTED_COST_PER_MIN > 0 else 0)

        tiers = {}
        for name, tier in TIERS.items():
            cost = tier["quota_min"] * actual
            revenue = tier["revenue_after_apple"]
            margin = ((revenue - cost) / revenue * 100) if revenue > 0 else -100
            tiers[name] = {
                "quota_min": tier["quota_min"],
                "monthly_cost_usd": round(cost, 4),
                "price_usd": tier["price_usd"],
                "revenue_after_apple_usd": round(revenue, 2),
                "margin_pct": round(margin, 1),
            }

        return {
            "whisper_cost_per_min_usd": whisper_cost,
            "llm_8b_cost_per_min_usd": llm_8b,
            "llm_70b_cost_per_min_usd": llm_70b,
            "actual_cost_per_min_usd": round(actual, 8),
            "documented_cost_per_min_usd": DOCUMENTED_COST_PER_MIN,
            "difference_pct": round(diff, 1),
            "model_mismatch": "Code uses llama-3.1-8b, doc assumes llama-3.3-70b",
            "tiers": tiers,
        }


def _bucket_stats(results: list[RequestResult]) -> dict:
    buckets = {"short_5_15s": [], "medium_15_30s": [], "long_30_60s": []}
    for r in results:
        if r.audio_duration_sec <= 15:
            buckets["short_5_15s"].append(r)
        elif r.audio_duration_sec <= 30:
            buckets["medium_15_30s"].append(r)
        else:
            buckets["long_30_60s"].append(r)

    return {
        name: {
            "count": len(items),
            "avg_latency_ms": round(statistics.mean(r.latency_ms for r in items), 0),
            "avg_audio_sec": round(statistics.mean(r.audio_duration_sec for r in items), 1),
        }
        for name, items in buckets.items() if items
    }


def print_report(report: TestReport):
    econ = report.test5_economics
    t1 = report.test1_transcription
    t4 = report.test4_ratelimits
    t3 = report.test3_pipeline

    print(f"\n{'='*55}")
    print(f"  GROQ ECONOMICS VALIDATION REPORT")
    print(f"  {report.metadata.get('timestamp', '')}")
    print(f"{'='*55}")

    if econ.get("model_mismatch"):
        print(f"\n  WARNING: {econ['model_mismatch']}")

    print(f"\n  COST PER AUDIO MINUTE:")
    print(f"    Whisper:      ${econ.get('whisper_cost_per_min_usd', 0):.6f}  "
          f"(expected ${WHISPER_COST_PER_MIN:.6f})")
    print(f"    LLM (8b):     ${econ.get('llm_8b_cost_per_min_usd', 0):.6f}  "
          f"(doc expects $0.001064)")
    print(f"    LLM (70b):    ${econ.get('llm_70b_cost_per_min_usd', 0):.6f}  "
          f"(for reference)")
    actual = econ.get("actual_cost_per_min_usd", 0)
    diff = econ.get("difference_pct", 0)
    print(f"    Combined:     ${actual:.6f}  "
          f"(doc ${DOCUMENTED_COST_PER_MIN:.5f}, diff: {diff:+.1f}%)")

    print(f"\n  TRANSCRIPTION ({t1.get('total_requests', 0)} requests):")
    print(f"    Success: {t1.get('successful', 0)}/{t1.get('total_requests', 0)}  "
          f"Audio: {t1.get('total_audio_minutes', 0):.1f} min")
    lat = t1.get("latency_ms", {})
    print(f"    Latency: p50={lat.get('p50', 0):.0f}ms  "
          f"p95={lat.get('p95', 0):.0f}ms  p99={lat.get('p99', 0):.0f}ms")

    print(f"\n  TIER MARGINS:")
    for name, data in econ.get("tiers", {}).items():
        print(f"    {name.capitalize():8s} ({data['quota_min']:3d} min):  "
              f"cost ${data['monthly_cost_usd']:.2f}  "
              f"revenue ${data['revenue_after_apple_usd']:.2f}  "
              f"margin: {data['margin_pct']:.1f}%")

    if t4 and not t4.get("skipped"):
        print(f"\n  RATE LIMITS:")
        if "burst_20" in t4:
            b = t4["burst_20"]
            print(f"    Burst 20:       {b['passed']}/{b['total']} passed, "
                  f"{b['rate_limited_429']} limited")
        if "sustained" in t4:
            s = t4["sustained"]
            f429 = s.get("first_429_at_request")
            print(f"    Sustained {s['target_rps']}rps: {s['passed']}/{s['total_sent']} passed, "
                  f"first 429 at {'#' + str(f429) if f429 is not None else 'none'}")
        if "llm_burst_35" in t4:
            l = t4["llm_burst_35"]
            print(f"    LLM burst 35:   {l['passed']}/35 passed, "
                  f"{l['rate_limited_429']} limited")

    if t3 and not t3.get("error"):
        print(f"\n  PIPELINE (end-to-end):")
        e2e = t3.get("e2e_latency_ms", {})
        print(f"    Latency: p50={e2e.get('p50', 0):.0f}ms  "
              f"p95={e2e.get('p95', 0):.0f}ms")
        print(f"    safeMerge rejected: {t3.get('safe_merge_rejected_pct', 0):.1f}%")

    print(f"\n  {'─'*50}")
    if actual < DOCUMENTED_COST_PER_MIN:
        print(f"  VERDICT: Economics BETTER than modeled. Safe to proceed.")
    elif actual < DOCUMENTED_COST_PER_MIN * 1.5:
        print(f"  VERDICT: Economics within acceptable range.")
    else:
        print(f"  VERDICT: Economics WORSE than modeled. Review pricing!")
    print(f"{'='*55}\n")


def save_report(report: TestReport, output_dir: Path) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"economics_report_{ts}.json"
    data = {
        "metadata": report.metadata,
        "test1_transcription": report.test1_transcription,
        "test2_llm": report.test2_llm,
        "test3_pipeline": report.test3_pipeline,
        "test4_ratelimits": report.test4_ratelimits,
        "test5_economics": report.test5_economics,
    }
    path.write_text(json.dumps(data, indent=2, default=str))
    return path
