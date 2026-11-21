from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "development"
    port: int = 8000
    internal_service_token: str = "dev-only-internal-service-token-replace"
    internal_hmac_secret: str = "dev-only-internal-hmac-secret-replace-32"

    ai_provider: str = "gemini"
    gemini_api_key: str = ""
    gemini_model_fast: str = "gemini-2.5-flash"
    gemini_model_quality: str = "gemini-2.5-pro"
    gemini_embedding_model: str = "text-embedding-004"

    ocr_enabled: bool = False
    max_pages_per_document: int = 150
    max_validation_retries: int = 2


@lru_cache
def get_settings() -> Settings:
    return Settings()
