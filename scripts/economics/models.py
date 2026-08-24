"""Data classes for test results and reports."""

from dataclasses import dataclass, field


@dataclass
class RequestResult:
    test: str
    index: int
    status: int
    latency_ms: float
    audio_duration_sec: float = 0.0
    text: str = ""
    error: str = ""
    input_tokens: int = 0
    output_tokens: int = 0
    model: str = ""
    category: str = ""
    rate_limit_headers: dict = field(default_factory=dict)


@dataclass
class TestReport:
    metadata: dict = field(default_factory=dict)
    test1_transcription: dict = field(default_factory=dict)
    test2_llm: dict = field(default_factory=dict)
    test3_pipeline: dict = field(default_factory=dict)
    test4_ratelimits: dict = field(default_factory=dict)
    test5_economics: dict = field(default_factory=dict)
