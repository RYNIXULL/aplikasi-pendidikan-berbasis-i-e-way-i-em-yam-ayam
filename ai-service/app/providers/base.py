from abc import ABC, abstractmethod
from typing import Any, TypeVar
from pydantic import BaseModel
from app.schemas.contracts import UsageMetrics

T = TypeVar("T", bound=BaseModel)


class AIProvider(ABC):
    @abstractmethod
    async def generate_text(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        tier: str = "fast",
    ) -> tuple[str, UsageMetrics]:
        raise NotImplementedError

    @abstractmethod
    async def generate_structured(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        response_schema: type[T],
        tier: str = "quality",
        context_hint: dict[str, Any] | None = None,
    ) -> tuple[T, UsageMetrics]:
        raise NotImplementedError

    @abstractmethod
    async def generate_embedding(
        self,
        *,
        texts: list[str],
        output_dimensionality: int = 768,
    ) -> tuple[list[list[float]], UsageMetrics]:
        raise NotImplementedError

    async def analyze_document(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        response_schema: type[T],
        context_hint: dict[str, Any] | None = None,
    ) -> tuple[T, UsageMetrics]:
        return await self.generate_structured(
            system_instruction=system_instruction,
            user_prompt=user_prompt,
            response_schema=response_schema,
            tier="quality",
            context_hint=context_hint,
        )
