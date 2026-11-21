from app.core.config import get_settings
from app.providers.base import AIProvider
from app.providers.gemini import GeminiProvider
from app.providers.mock import DeterministicMockProvider


def get_ai_provider() -> AIProvider:
    settings = get_settings()
    if settings.app_env == "test" and settings.ai_provider == "mock":
        return DeterministicMockProvider()
    if settings.ai_provider == "gemini":
        return GeminiProvider()
    raise ValueError(f"Unsupported AI_PROVIDER configuration: {settings.ai_provider}")
