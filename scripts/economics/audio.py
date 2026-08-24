"""Audio corpus generation: user files, TTS + noise, or synthetic."""

import math
import random
import struct
import subprocess
import wave
from pathlib import Path

from .config import SYSTEM_PROMPTS, SAMPLE_TEXTS


class AudioGenerator:
    def __init__(self, temp_dir: Path):
        self.temp_dir = temp_dir
        self.clips: list[dict] = []

    def from_directory(self, audio_dir: Path, count: int) -> list[dict]:
        """Load and convert user-provided audio files."""
        extensions = {".wav", ".mp3", ".m4a", ".aiff", ".aif", ".flac", ".ogg"}
        files = sorted(
            [f for f in audio_dir.iterdir() if f.suffix.lower() in extensions],
            key=lambda f: f.stat().st_mtime,
        )
        if not files:
            raise FileNotFoundError(f"No audio files found in {audio_dir}")

        print(f"  Found {len(files)} audio files in {audio_dir}")
        categories = list(SYSTEM_PROMPTS.keys())
        clips = []

        for i, src in enumerate(files[:count]):
            cat = categories[i % len(categories)]
            dst = self.temp_dir / f"user_{i:03d}.wav"
            self._convert_to_wav(src, dst)
            dur = self._get_wav_duration(dst)
            if dur < 1.0:
                continue
            if dur > 60.0:
                self._trim_wav(dst, 60.0)
                dur = 60.0
            clips.append({
                "path": str(dst), "duration_sec": dur,
                "category": cat, "text": f"[user audio {src.name}]",
            })

        self.clips = clips
        return clips

    def from_tts(self, count: int) -> list[dict]:
        """Generate audio via macOS say + afconvert with noise augmentation."""
        print("  Generating audio via macOS TTS...")
        categories = list(SAMPLE_TEXTS.keys())
        clips = []

        for i in range(count):
            cat = categories[i % len(categories)]
            texts = SAMPLE_TEXTS[cat]
            text = texts[i % len(texts)]

            bucket = self._get_bucket(i, count)
            if bucket == "medium":
                text = f"{text}. {texts[(i + 1) % len(texts)]}"
            elif bucket == "long":
                extras = [texts[(i + j) % len(texts)] for j in range(1, 4)]
                text = ". ".join([text] + extras)

            aiff_path = self.temp_dir / f"tts_{i:03d}.aiff"
            wav_path = self.temp_dir / f"tts_{i:03d}.wav"

            try:
                subprocess.run(
                    ["say", "-o", str(aiff_path), text],
                    check=True, capture_output=True, timeout=30,
                )
                self._convert_to_wav(aiff_path, wav_path)
                aiff_path.unlink(missing_ok=True)
                self._augment_wav(wav_path)

                dur = self._get_wav_duration(wav_path)
                if dur < 1.0:
                    continue
                clips.append({
                    "path": str(wav_path), "duration_sec": dur,
                    "category": cat, "text": text,
                })
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                print(f"    Warning: TTS failed for clip {i}: {e}")
                continue

        self.clips = clips
        return clips

    def from_synthetic(self, count: int) -> list[dict]:
        """Fallback: generate synthetic WAV with tone + noise."""
        print("  Generating synthetic audio (fallback)...")
        categories = list(SYSTEM_PROMPTS.keys())
        clips = []

        for i in range(count):
            cat = categories[i % len(categories)]
            bucket = self._get_bucket(i, count)
            dur = {"short": random.uniform(5, 15),
                   "medium": random.uniform(15, 30),
                   "long": random.uniform(30, 60)}[bucket]

            wav_path = self.temp_dir / f"synth_{i:03d}.wav"
            self._generate_synthetic_wav(wav_path, dur)
            clips.append({
                "path": str(wav_path), "duration_sec": dur,
                "category": cat, "text": f"[synthetic audio {dur:.1f}s]",
            })

        self.clips = clips
        return clips

    def _get_bucket(self, index: int, total: int) -> str:
        short_end = int(total * 0.5)
        medium_end = short_end + int(total * 0.3)
        if index < short_end:
            return "short"
        return "medium" if index < medium_end else "long"

    def _convert_to_wav(self, src: Path, dst: Path):
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
             str(src), str(dst)],
            check=True, capture_output=True, timeout=30,
        )

    def _get_wav_duration(self, path: Path) -> float:
        with wave.open(str(path), "rb") as wf:
            return wf.getnframes() / wf.getframerate()

    def _trim_wav(self, path: Path, max_sec: float):
        with wave.open(str(path), "rb") as wf:
            params = wf.getparams()
            max_frames = int(max_sec * wf.getframerate())
            frames = wf.readframes(min(max_frames, wf.getnframes()))
        with wave.open(str(path), "wb") as wf:
            wf.setparams(params)
            wf.writeframes(frames)

    def _augment_wav(self, path: Path):
        """Add Gaussian noise and volume variation for realism."""
        with wave.open(str(path), "rb") as wf:
            params = wf.getparams()
            raw = wf.readframes(wf.getnframes())

        samples = list(struct.unpack(f"<{len(raw)//2}h", raw))
        if not samples:
            return

        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        snr_db = random.uniform(18, 25)
        noise_rms = rms / (10 ** (snr_db / 20)) if rms > 0 else 50

        vol_factor = random.uniform(0.7, 1.0)
        augmented = []
        for s in samples:
            noise = random.gauss(0, noise_rms)
            val = int(s * vol_factor + noise)
            augmented.append(max(-32768, min(32767, val)))

        # Prepend silence (real recordings have this)
        silence_frames = int(random.uniform(0.1, 0.3) * 16000)
        augmented = [0] * silence_frames + augmented

        raw_out = struct.pack(f"<{len(augmented)}h", *augmented)
        with wave.open(str(path), "wb") as wf:
            wf.setparams(params._replace(nframes=len(augmented)))
            wf.writeframes(raw_out)

    def _generate_synthetic_wav(self, path: Path, duration: float):
        sample_rate = 16000
        n_samples = int(duration * sample_rate)
        samples = []
        freqs = [random.uniform(100, 300), random.uniform(500, 1500)]
        for i in range(n_samples):
            t = i / sample_rate
            val = sum(math.sin(2 * math.pi * f * t) * 2000 for f in freqs)
            val += random.gauss(0, 500)
            val *= 0.5 + 0.5 * math.sin(2 * math.pi * 3 * t)
            samples.append(max(-32768, min(32767, int(val))))

        raw = struct.pack(f"<{len(samples)}h", *samples)
        with wave.open(str(path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(raw)
