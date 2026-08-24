"""Async Groq API client for Whisper and Chat Completions."""

import os
import time
import wave
from pathlib import Path

import aiohttp

from .config import GROQ_BASE_URL, WHISPER_MODEL, SYSTEM_PROMPTS
from .models import RequestResult


class GroqClient:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.headers = {"Authorization": f"Bearer {api_key}"}

    async def validate_key(self, session: aiohttp.ClientSession) -> bool:
        try:
            async with session.get(
                f"{GROQ_BASE_URL}/models",
                headers=self.headers,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status == 200:
                    return True
                if resp.status == 401:
                    print("ERROR: Invalid API key")
                    return False
                if resp.status == 429:
                    print("WARNING: Rate limited but key is valid")
                    return True
                print(f"WARNING: Unexpected status {resp.status}")
                return resp.status < 500
        except Exception as e:
            print(f"ERROR: Cannot reach Groq API: {e}")
            return False

    async def transcribe(
        self, session: aiohttp.ClientSession, audio_path: str, index: int
    ) -> RequestResult:
        audio_data = Path(audio_path).read_bytes()
        duration_sec = 0.0
        try:
            with wave.open(audio_path, "rb") as wf:
                duration_sec = wf.getnframes() / wf.getframerate()
        except Exception:
            pass

        boundary = f"Boundary-{os.urandom(16).hex()}"
        body = self._build_multipart(audio_data, boundary)
        headers = {
            **self.headers,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        }

        t0 = time.monotonic()
        try:
            async with session.post(
                f"{GROQ_BASE_URL}/audio/transcriptions",
                data=body, headers=headers,
                timeout=aiohttp.ClientTimeout(total=60),
            ) as resp:
                latency = (time.monotonic() - t0) * 1000
                data = await resp.json()
                rl = self._extract_ratelimit_headers(resp.headers)

                if resp.status == 200:
                    return RequestResult(
                        test="transcription", index=index, status=resp.status,
                        latency_ms=latency, audio_duration_sec=duration_sec,
                        text=data.get("text", ""), rate_limit_headers=rl,
                    )
                return RequestResult(
                    test="transcription", index=index, status=resp.status,
                    latency_ms=latency, audio_duration_sec=duration_sec,
                    error=data.get("error", {}).get("message", str(data)),
                    rate_limit_headers=rl,
                )
        except Exception as e:
            return RequestResult(
                test="transcription", index=index, status=0,
                latency_ms=(time.monotonic() - t0) * 1000,
                audio_duration_sec=duration_sec, error=str(e),
            )

    async def chat_completion(
        self, session: aiohttp.ClientSession,
        text: str, category: str, model: str, index: int,
    ) -> RequestResult:
        body = {
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPTS.get(category, SYSTEM_PROMPTS["general"])},
                {"role": "user", "content": text},
            ],
            "temperature": 0.1,
            "max_tokens": 1024,
        }
        headers = {**self.headers, "Content-Type": "application/json"}

        t0 = time.monotonic()
        try:
            async with session.post(
                f"{GROQ_BASE_URL}/chat/completions",
                json=body, headers=headers,
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                latency = (time.monotonic() - t0) * 1000
                data = await resp.json()
                rl = self._extract_ratelimit_headers(resp.headers)

                if resp.status == 200:
                    usage = data.get("usage", {})
                    result_text = ""
                    choices = data.get("choices", [])
                    if choices:
                        result_text = choices[0].get("message", {}).get("content", "")
                    return RequestResult(
                        test="llm", index=index, status=resp.status,
                        latency_ms=latency, text=result_text,
                        input_tokens=usage.get("prompt_tokens", 0),
                        output_tokens=usage.get("completion_tokens", 0),
                        model=model, category=category, rate_limit_headers=rl,
                    )
                return RequestResult(
                    test="llm", index=index, status=resp.status,
                    latency_ms=latency,
                    error=data.get("error", {}).get("message", str(data)),
                    model=model, category=category, rate_limit_headers=rl,
                )
        except Exception as e:
            return RequestResult(
                test="llm", index=index, status=0,
                latency_ms=(time.monotonic() - t0) * 1000,
                error=str(e), model=model, category=category,
            )

    def _build_multipart(self, audio_data: bytes, boundary: str) -> bytes:
        """Multipart body matching RecognitionService.swift format."""
        body = f"--{boundary}\r\n".encode()
        body += b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
        body += b"Content-Type: audio/wav\r\n\r\n"
        body += audio_data
        body += b"\r\n"
        body += f"--{boundary}\r\n".encode()
        body += b'Content-Disposition: form-data; name="model"\r\n\r\n'
        body += f"{WHISPER_MODEL}\r\n".encode()
        body += f"--{boundary}\r\n".encode()
        body += b'Content-Disposition: form-data; name="response_format"\r\n\r\n'
        body += b"json\r\n"
        body += f"--{boundary}--\r\n".encode()
        return body

    def _extract_ratelimit_headers(self, headers) -> dict:
        return {
            k: v for k, v in headers.items()
            if k.lower().startswith("x-ratelimit") or k.lower() == "retry-after"
        }
