import hashlib
import hmac
import io
import json
import os
import time
from fastapi.testclient import TestClient
from pptx import Presentation

os.environ["APP_ENV"] = "test"
os.environ["AI_PROVIDER"] = "mock"

from app.core.config import get_settings
from app.exporters.pptx_exporter import build_pptx_bytes
from app.main import app
from app.schemas.contracts import PresentationPayload

get_settings.cache_clear()
client = TestClient(app)


def _signed_headers(payload: dict) -> tuple[str, dict[str, str]]:
    settings = get_settings()
    raw = json.dumps(payload)
    ts = str(int(time.time()))
    sig = hmac.new(
        settings.internal_hmac_secret.encode("utf-8"),
        f"{ts}.{raw}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return raw, {
        "Content-Type": "application/json",
        "X-Internal-Service-Token": settings.internal_service_token,
        "X-Internal-Timestamp": ts,
        "X-Internal-Signature": sig,
    }


def test_health_endpoint() -> None:
    res = client.get("/internal/v1/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_internal_endpoints_reject_missing_hmac_signature() -> None:
    res = client.post("/internal/v1/embeddings", json={"texts": ["Biologi"]})
    assert res.status_code == 401


def test_signed_embeddings_analysis_and_all_generators() -> None:
    # 1. Embeddings (768-dim)
    emb_body, headers = _signed_headers({"texts": ["Lambung mencerna makanan dengan pepsin."]})
    emb_res = client.post("/internal/v1/embeddings", content=emb_body, headers=headers)
    assert emb_res.status_code == 200
    assert len(emb_res.json()["embeddings"][0]) == 768

    # 2. Material Analysis
    analyze_payload = {
        "document_id": "doc-001",
        "title": "Sistem Pencernaan Manusia",
        "subject": "Biologi",
        "chunks": [
            {
                "chunk_index": 0,
                "page_start": 12,
                "page_end": 12,
                "content": "Lambung menghasilkan asam klorida dan enzim pepsin untuk mencerna protein.",
            }
        ],
    }
    raw_a, hdr_a = _signed_headers(analyze_payload)
    a_res = client.post("/internal/v1/documents/analyze", content=raw_a, headers=hdr_a)
    assert a_res.status_code == 200
    assert a_res.json()["payload"]["subject"] == "Biologi"

    # 3. All 6 content types + all 6 game templates
    base_gen = {
        "document_id": "doc-001",
        "document_title": "Sistem Pencernaan Manusia",
        "subject": "Biologi",
        "page_count": 15,
        "chunks": analyze_payload["chunks"],
        "config": {"difficulty": "medium"},
    }
    for kind in ("summary", "quiz", "presentation", "flashcards", "mind-map", "worksheet"):
        raw, hdr = _signed_headers(base_gen)
        r = client.post(f"/internal/v1/generate/{kind}", content=raw, headers=hdr)
        assert r.status_code == 200, f"Failed for {kind}: {r.text}"
        assert r.json()["validation_report"]["schema_valid"] is True

    for game_type in (
        "quiz_battle",
        "word_matching",
        "true_false",
        "memory_cards",
        "crossword",
        "word_puzzle",
    ):
        raw, hdr = _signed_headers({**base_gen, "game_type": game_type})
        r = client.post("/internal/v1/generate/game", content=raw, headers=hdr)
        assert r.status_code == 200, f"Failed for game {game_type}: {r.text}"
        assert r.json()["payload"]["game_type"] == game_type


def test_pptx_binary_exporter_produces_valid_deck() -> None:
    deck = PresentationPayload.model_validate(
        {
            "title": "Sistem Pencernaan",
            "theme_style": "clean_academic",
            "slides": [
                {
                    "slide_number": 1,
                    "layout": "title_slide",
                    "title": "Sistem Pencernaan",
                    "subtitle": "Biologi Kelas XI",
                    "content": [],
                    "speaker_notes": "Buka dengan pertanyaan pemantik.",
                    "source_reference": {"page": 1},
                },
                {
                    "slide_number": 2,
                    "layout": "title_content",
                    "title": "Fungsi Lambung",
                    "content": ["Menghasilkan HCl", "Menghasilkan enzim pepsin"],
                    "speaker_notes": "Tekankan pencernaan kimiawi.",
                    "source_reference": {"page": 12},
                },
            ],
        }
    )
    pptx_bytes = build_pptx_bytes(deck)
    assert pptx_bytes[:4] == b"PK\x03\x04"

    # Re-open binary with python-pptx to verify structural integrity
    reloaded = Presentation(io.BytesIO(pptx_bytes))
    assert len(reloaded.slides) == 2
    assert "pepsin" in reloaded.slides[1].notes_slide.notes_text_frame.text or "kimiawi" in reloaded.slides[1].notes_slide.notes_text_frame.text
