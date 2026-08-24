#!/usr/bin/env python3
"""
Groq Economics Validation — automated cost model testing for Flow Mac.

Usage:
    python3 scripts/economics_validation.py --api-key gsk_xxx
    python3 scripts/economics_validation.py --api-key gsk_xxx --quick
    python3 scripts/economics_validation.py --api-key gsk_xxx --audio-dir ~/recordings/
    python3 scripts/economics_validation.py --api-key gsk_xxx --skip-ratelimit
"""

import argparse
import asyncio
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import aiohttp

from economics.audio import AudioGenerator
from economics.calculator import (
    EconomicsCalculator, print_report, save_report,
)
from economics.client import GroqClient
from economics.config import PRICING_STALE_DAYS, PRICING_VERIFIED_DATE, WHISPER_COST_PER_MIN
from economics.models import TestReport
from economics.runner import TestRunner


def check_pricing_staleness():
    try:
        verified = datetime.strptime(PRICING_VERIFIED_DATE, "%Y-%m-%d")
        age = (datetime.now() - verified).days
        if age > PRICING_STALE_DAYS:
            print(
                f"\n  WARNING: Pricing constants last verified {age} days ago "
                f"({PRICING_VERIFIED_DATE}). Check groq.com/pricing.\n"
            )
    except ValueError:
        pass


async def main():
    parser = argparse.ArgumentParser(description="Groq Economics Validation for Flow Mac")
    parser.add_argument("--api-key", required=True, help="Groq API key (gsk_...)")
    parser.add_argument("--quick", action="store_true", help="Quick mode: 10 requests")
    parser.add_argument("--skip-ratelimit", action="store_true", help="Skip rate limit testing")
    parser.add_argument("--audio-dir", type=str, help="Directory with real audio files")
    parser.add_argument("--output", type=str, default="scripts", help="Output dir for report")
    parser.add_argument("--count", type=int, default=100, help="Number of test requests")

    args = parser.parse_args()
    count = min(args.count, 10) if args.quick else args.count

    print(f"\n{'='*55}")
    print(f"  GROQ ECONOMICS VALIDATION")
    print(f"  Mode: {'QUICK (10 requests)' if args.quick else f'FULL ({count} requests)'}")
    print(f"  Rate limit test: {'SKIP' if args.skip_ratelimit else 'YES'}")
    print(f"{'='*55}")

    check_pricing_staleness()

    # Validate API key
    print("\n  Phase 0: Setup")
    print("  Validating API key...")
    client = GroqClient(args.api_key)
    async with aiohttp.ClientSession() as session:
        if not await client.validate_key(session):
            print("  FATAL: API key validation failed. Aborting.")
            sys.exit(1)
    print("  API key valid.")

    # Generate audio corpus
    temp_dir = Path(tempfile.mkdtemp(prefix="flowmac_econ_"))
    try:
        gen = AudioGenerator(temp_dir)

        if args.audio_dir:
            audio_path = Path(args.audio_dir)
            if not audio_path.is_dir():
                print(f"  ERROR: {args.audio_dir} is not a directory")
                sys.exit(1)
            print(f"  Loading audio from {args.audio_dir}...")
            clips = gen.from_directory(audio_path, count)
        else:
            try:
                subprocess.run(["say", "--version"], capture_output=True, timeout=5)
                print("  Generating audio corpus via macOS TTS...")
                clips = gen.from_tts(count)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                print("  macOS TTS not available, using synthetic audio...")
                clips = gen.from_synthetic(count)

        if not clips:
            print("  FATAL: No audio clips generated")
            sys.exit(1)

        total_audio = sum(c["duration_sec"] for c in clips)
        print(f"  Generated {len(clips)} clips, total {total_audio:.1f}s ({total_audio/60:.1f} min)")

        # Run tests
        report = TestReport()
        report.metadata = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "mode": "quick" if args.quick else "full",
            "target_count": count,
            "actual_clips": len(clips),
            "total_audio_seconds": round(total_audio, 1),
            "audio_source": "user_provided" if args.audio_dir else "tts_augmented",
            "pricing_verified_date": PRICING_VERIFIED_DATE,
        }

        t_start = time.monotonic()

        async with aiohttp.ClientSession() as session:
            runner = TestRunner(client, clips, args.quick)

            t1 = await runner.run_test1(session)
            report.test1_transcription = EconomicsCalculator.calc_transcription_stats(t1)

            t2 = await runner.run_test2(session, t1)
            report.test2_llm = EconomicsCalculator.calc_llm_stats(t2)

            t3 = await runner.run_test3(session)
            report.test3_pipeline = EconomicsCalculator.calc_pipeline_stats(t3)

            if not args.skip_ratelimit:
                report.test4_ratelimits = await runner.run_test4(session)
            else:
                report.test4_ratelimits = {"skipped": True}
                print(f"\n  TEST 4: Rate limits — SKIPPED")

        report.test5_economics = EconomicsCalculator.calc_economics(
            WHISPER_COST_PER_MIN, report.test2_llm
        )

        report.metadata["total_duration_seconds"] = round(time.monotonic() - t_start, 1)

        # Output
        output_dir = Path(args.output)
        output_dir.mkdir(parents=True, exist_ok=True)
        json_path = save_report(report, output_dir)

        print_report(report)
        print(f"  Full report saved to: {json_path}")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    asyncio.run(main())
