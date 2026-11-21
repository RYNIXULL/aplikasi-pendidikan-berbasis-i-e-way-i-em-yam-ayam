import json
import time
from typing import Any, TypeVar
from google import genai
from google.genai import types
from pydantic import BaseModel
from app.core.config import get_settings
from app.providers.base import AIProvider
from app.schemas.contracts import UsageMetrics

T = TypeVar("T", bound=BaseModel)

# Approximate USD per 1M tokens for operational telemetry budgeting
MODEL_PRICING_PER_1M: dict[str, tuple[float, float]] = {
    "gemini-2.5-flash": (0.15, 0.60),
    "gemini-2.5-pro": (1.25, 5.00),
    "text-embedding-004": (0.02, 0.0),
}


def _estimate_cost(model: str, prompt_tokens: int, completion_tokens: int) -> float:
    in_rate, out_rate = MODEL_PRICING_PER_1M.get(model, (0.30, 1.20))
    return round((prompt_tokens * in_rate + completion_tokens * out_rate) / 1_000_000, 6)


class GeminiProvider(AIProvider):
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.gemini_api_key:
            raise RuntimeError(
                "GEMINI_API_KEY is not configured. Set it in ai-service/.env before running Gemini calls."
            )
        self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model_fast = settings.gemini_model_fast
        self._model_quality = settings.gemini_model_quality
        self._embedding_model = settings.gemini_embedding_model

    def _select_model(self, tier: str) -> str:
        return self._model_quality if tier == "quality" else self._model_fast

    async def generate_text(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        tier: str = "fast",
    ) -> tuple[str, UsageMetrics]:
        model = self._select_model(tier)
        t0 = time.perf_counter()
        response = self._client.models.generate_content(
            model=model,
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.3,
            ),
        )
        latency_ms = int((time.perf_counter() - t0) * 1000)
        usage_meta = getattr(response, "usage_metadata", None)
        p_tok = int(getattr(usage_meta, "prompt_token_count", 0) or 0)
        c_tok = int(getattr(usage_meta, "candidates_token_count", 0) or 0)
        usage = UsageMetrics(
            provider="gemini",
            model=model,
            prompt_tokens=p_tok,
            completion_tokens=c_tok,
            total_tokens=p_tok + c_tok,
            estimated_cost_usd=_estimate_cost(model, p_tok, c_tok),
            latency_ms=latency_ms,
        )
        return (response.text or "").strip(), usage

    async def generate_structured(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        response_schema: type[T],
        tier: str = "quality",
        context_hint: dict[str, Any] | None = None,
    ) -> tuple[T, UsageMetrics]:
        model = self._select_model(tier)
        t0 = time.perf_counter()
        response = self._client.models.generate_content(
            model=model,
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.2,
            ),
        )
        latency_ms = int((time.perf_counter() - t0) * 1000)
        raw_text = (response.text or "{}").strip()
        parsed_dict = json.loads(raw_text)
        validated = response_schema.model_validate(parsed_dict)

        usage_meta = getattr(response, "usage_metadata", None)
        p_tok = int(getattr(usage_meta, "prompt_token_count", 0) or 0)
        c_tok = int(getattr(usage_meta, "candidates_token_count", 0) or 0)
        usage = UsageMetrics(
            provider="gemini",
            model=model,
            prompt_tokens=p_tok,
            completion_tokens=c_tok,
            total_tokens=p_tok + c_tok,
            estimated_cost_usd=_estimate_cost(model, p_tok, c_tok),
            latency_ms=latency_ms,
        )
        return validated, usage

    async def generate_embedding(
        self,
        *,
        texts: list[str],
        output_dimensionality: int = 768,
    ) -> tuple[list[list[float]], UsageMetrics]:
        t0 = time.perf_counter()
        embeddings: list[list[float]] = []
        for text in texts:
            result = self._client.models.embed_content(
                model=self._embedding_model,
                contents=text,
                config=types.EmbedContentConfig(output_dimensionality=output_dimensionality),
            )
            vec = list(result.embeddings[0].values)
            embeddings.append(vec)
        latency_ms = int((time.perf_counter() - t0) * 1000)
        approx_tokens = sum(max(1, len(t.split())) for t in texts)
        usage = UsageMetrics(
            provider="gemini",
            model=self._embedding_model,
            prompt_tokens=approx_tokens,
            completion_tokens=0,
            total_tokens=approx_tokens,
            estimated_cost_usd=_estimate_cost(self._embedding_model, approx_tokens, 0),
            latency_ms=latency_ms,
        )
        return embeddings, usage
