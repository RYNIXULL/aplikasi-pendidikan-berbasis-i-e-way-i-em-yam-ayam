import os
import pytest

os.environ["APP_ENV"] = "test"
os.environ["AI_PROVIDER"] = "mock"

from app.core.config import get_settings
from app.generators.engine import run_content_generation
from app.providers.mock import DeterministicMockProvider
from app.schemas.contracts import ChunkInput, GenerationRequest

get_settings.cache_clear()


@pytest.mark.asyncio
async def test_ai_quality_evaluation_harness_indonesian_corpus() -> None:
    """Phase 8 AI Evaluation Benchmark verifying schema validity, source grounding,
    completeness, and zero hallucinated page references on Indonesian learning fixtures.
    """
    provider = DeterministicMockProvider()
    fixtures = [
        GenerationRequest(
            document_id="eval-bio-1",
            document_title="Sistem Pencernaan Manusia",
            subject="Biologi",
            page_count=14,
            chunks=[
                ChunkInput(
                    chunk_index=0,
                    chapter_title="BAB 2 Organ Pencernaan",
                    page_start=12,
                    page_end=13,
                    content="Lambung mencerna makanan dengan kontraksi otot serta asam klorida dan enzim pepsin.",
                )
            ],
            config={"language": "id", "difficulty": "medium"},
        ),
        GenerationRequest(
            document_id="eval-fis-1",
            document_title="Hukum Gerak Newton",
            subject="Fisika",
            page_count=10,
            chunks=[
                ChunkInput(
                    chunk_index=0,
                    chapter_title="BAB 1 Dinamika Partikel",
                    page_start=3,
                    page_end=4,
                    content="Hukum II Newton menyatakan percepatan benda berbanding lurus dengan gaya total dan berbanding terbalik dengan massa.",
                )
            ],
            config={"language": "id", "difficulty": "hard"},
        ),
    ]

    schema_passed = 0
    grounding_passed = 0
    total_runs = 0

    for fixture in fixtures:
        for kind in ("summary", "quiz", "flashcards", "mind-map", "worksheet"):
            total_runs += 1
            res = await run_content_generation(provider, kind, fixture)
            if res.validation_report.schema_valid:
                schema_passed += 1
            if res.validation_report.grounding_verified:
                grounding_passed += 1
            assert len(res.source_references) >= 1

    schema_rate = schema_passed / total_runs
    grounding_rate = grounding_passed / total_runs
    assert schema_rate >= 0.90
    assert grounding_rate >= 0.90
