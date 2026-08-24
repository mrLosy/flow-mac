"""Test runner — orchestrates all 5 tests."""

import asyncio
import random
import time

import aiohttp

from .config import LLM_PRICING
from .client import GroqClient
from .models import RequestResult


def normalized_edit_distance(a: str, b: str) -> float:
    """Normalized Levenshtein (matches SemanticCorrectionService.swift)."""
    m, n = len(a), len(b)
    if m == 0 and n == 0:
        return 0.0
    prev = list(range(n + 1))
    for i in range(1, m + 1):
        curr = [i] + [0] * n
        for j in range(1, n + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        prev = curr
    return prev[n] / max(m, n)


class TestRunner:
    def __init__(self, client: GroqClient, clips: list[dict], quick: bool = False):
        self.client = client
        self.clips = clips
        self.quick = quick
        self.count = min(10, len(clips)) if quick else len(clips)
        self.test_clips = clips[:self.count]

    async def run_test1(self, session: aiohttp.ClientSession) -> list[RequestResult]:
        """Test 1: Transcription cost."""
        print(f"\n{'='*50}")
        print(f"  TEST 1: Transcription ({self.count} requests)")
        print(f"{'='*50}")

        results = []
        for i, clip in enumerate(self.test_clips):
            result = await self.client.transcribe(session, clip["path"], i)
            result.category = clip["category"]
            results.append(result)

            status = "OK" if result.status == 200 else f"ERR {result.status}"
            print(
                f"  [{i+1:3d}/{self.count}] {status}  "
                f"{result.audio_duration_sec:5.1f}s  "
                f"{result.latency_ms:6.0f}ms  {clip['category']:8s}"
            )

            if result.status == 429:
                wait = float(result.rate_limit_headers.get("retry-after", "2"))
                print(f"         Rate limited, waiting {wait:.0f}s...")
                await asyncio.sleep(wait + random.uniform(0, 1))
            else:
                await asyncio.sleep(0.2)

        return results

    async def run_test2(
        self, session: aiohttp.ClientSession, transcriptions: list[RequestResult],
    ) -> dict[str, list[RequestResult]]:
        """Test 2: LLM cost — both models."""
        results = {}
        for model in LLM_PRICING:
            label = LLM_PRICING[model]["label"]
            print(f"\n{'='*50}")
            print(f"  TEST 2: LLM — {label} ({self.count} requests)")
            print(f"{'='*50}")

            model_results = []
            for i, tr in enumerate(transcriptions[:self.count]):
                if tr.status != 200 or not tr.text:
                    continue
                result = await self.client.chat_completion(
                    session, tr.text, tr.category, model, i
                )
                model_results.append(result)

                status = "OK" if result.status == 200 else f"ERR {result.status}"
                tokens = f"in={result.input_tokens} out={result.output_tokens}"
                print(
                    f"  [{i+1:3d}/{self.count}] {status}  "
                    f"{result.latency_ms:6.0f}ms  {tokens:20s}  {tr.category:8s}"
                )

                if result.status == 429:
                    wait = float(result.rate_limit_headers.get("retry-after", "5"))
                    print(f"         Rate limited, waiting {wait:.0f}s...")
                    await asyncio.sleep(wait + random.uniform(0, 1))
                else:
                    await asyncio.sleep(0.3)

            results[model] = model_results
        return results

    async def run_test3(self, session: aiohttp.ClientSession) -> list[dict]:
        """Test 3: Combined pipeline — Whisper -> LLM (8b)."""
        model = "llama-3.1-8b-instant"
        print(f"\n{'='*50}")
        print(f"  TEST 3: Combined Pipeline ({self.count} requests)")
        print(f"{'='*50}")

        results = []
        for i, clip in enumerate(self.test_clips):
            t0 = time.monotonic()
            tr = await self.client.transcribe(session, clip["path"], i)
            if tr.status != 200 or not tr.text:
                print(f"  [{i+1:3d}/{self.count}] SKIP (transcription failed)")
                await asyncio.sleep(0.3)
                continue

            llm = await self.client.chat_completion(
                session, tr.text, clip["category"], model, i
            )
            e2e_ms = (time.monotonic() - t0) * 1000

            distance = 0.0
            rejected = False
            if llm.status == 200 and llm.text:
                distance = normalized_edit_distance(tr.text.lower(), llm.text.lower())
                rejected = distance > 0.25

            results.append({
                "index": i, "audio_sec": clip["duration_sec"],
                "category": clip["category"],
                "whisper_latency_ms": tr.latency_ms,
                "llm_latency_ms": llm.latency_ms,
                "e2e_latency_ms": e2e_ms,
                "whisper_ok": tr.status == 200, "llm_ok": llm.status == 200,
                "input_tokens": llm.input_tokens, "output_tokens": llm.output_tokens,
                "edit_distance": distance, "safe_merge_rejected": rejected,
            })

            status = "OK" if (tr.status == 200 and llm.status == 200) else "ERR"
            tag = " [REJECTED]" if rejected else ""
            print(
                f"  [{i+1:3d}/{self.count}] {status}  e2e={e2e_ms:6.0f}ms  "
                f"dist={distance:.2f}{tag}"
            )

            if tr.status == 429 or llm.status == 429:
                await asyncio.sleep(3)
            else:
                await asyncio.sleep(0.3)

        return results

    async def run_test4(self, session: aiohttp.ClientSession) -> dict:
        """Test 4: Rate limit testing."""
        print(f"\n{'='*50}")
        print(f"  TEST 4: Rate Limits")
        print(f"{'='*50}")

        short_clips = sorted(self.clips, key=lambda c: c["duration_sec"])[:20]
        if len(short_clips) < 5:
            print("  Not enough clips, skipping")
            return {"skipped": True}

        report = {}

        # 4a: Burst 20 concurrent
        print(f"\n  4a: Burst test (20 concurrent transcriptions)")
        tasks = [self.client.transcribe(session, c["path"], i)
                 for i, c in enumerate(short_clips)]
        burst = await asyncio.gather(*tasks)
        passed = sum(1 for r in burst if r.status == 200)
        limited = sum(1 for r in burst if r.status == 429)
        print(f"      Passed: {passed}/{len(burst)}, 429s: {limited}")
        report["burst_20"] = {
            "total": len(burst), "passed": passed, "rate_limited_429": limited,
        }

        await asyncio.sleep(3)

        # 4b: Sustained load
        duration = 15 if self.quick else 60
        rps = 5
        print(f"\n  4b: Sustained {rps} req/sec for {duration}s")
        cycle = short_clips * 20
        sustained = []
        first_429 = None
        t_start = time.monotonic()
        idx = 0

        while time.monotonic() - t_start < duration and idx < len(cycle):
            result = await self.client.transcribe(session, cycle[idx]["path"], idx)
            sustained.append(result)
            if result.status == 429 and first_429 is None:
                first_429 = idx
                print(f"      First 429 at request #{idx}")
            idx += 1
            elapsed = time.monotonic() - t_start
            expected = idx / rps
            if expected > elapsed:
                await asyncio.sleep(expected - elapsed)

        s_passed = sum(1 for r in sustained if r.status == 200)
        s_429 = sum(1 for r in sustained if r.status == 429)
        print(f"      Total: {len(sustained)}, passed: {s_passed}, 429s: {s_429}")
        report["sustained"] = {
            "target_rps": rps, "duration_sec": duration,
            "total_sent": len(sustained), "passed": s_passed,
            "rate_limited_429": s_429, "first_429_at_request": first_429,
        }

        await asyncio.sleep(3)

        # 4c: LLM burst 35
        print(f"\n  4c: LLM burst (35 rapid chat completions)")
        sample = "Hello this is a test of the speech recognition system"
        llm_tasks = [
            self.client.chat_completion(session, sample, "general", "llama-3.1-8b-instant", i)
            for i in range(35)
        ]
        llm_burst = await asyncio.gather(*llm_tasks)
        l_passed = sum(1 for r in llm_burst if r.status == 200)
        l_429 = sum(1 for r in llm_burst if r.status == 429)
        print(f"      Passed: {l_passed}/35, 429s: {l_429}")
        report["llm_burst_35"] = {
            "total": 35, "passed": l_passed, "rate_limited_429": l_429,
        }

        # Sample rate limit headers
        all_results = list(burst) + sustained + list(llm_burst)
        for r in reversed(all_results):
            if r.rate_limit_headers:
                report["rate_limit_headers_sample"] = r.rate_limit_headers
                break

        return report
