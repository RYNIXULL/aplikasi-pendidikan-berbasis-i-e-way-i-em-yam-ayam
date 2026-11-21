import hashlib
import math
from typing import Any, TypeVar
from pydantic import BaseModel
from app.core.config import get_settings
from app.providers.base import AIProvider
from app.schemas.contracts import (
    DocumentAnalysisPayload,
    FlashcardsPayload,
    GamePayload,
    MindMapPayload,
    PresentationPayload,
    QuizPayload,
    SummaryPayload,
    UsageMetrics,
    WorksheetPayload,
)

T = TypeVar("T", bound=BaseModel)


class DeterministicMockProvider(AIProvider):
    """Test-only deterministic AIProvider grounded in provided source chunks.

    Strictly forbidden outside APP_ENV=test to prevent fabricated production outputs.
    """

    def __init__(self) -> None:
        settings = get_settings()
        if settings.app_env != "test":
            raise RuntimeError("DeterministicMockProvider may only be used when APP_ENV=test.")

    async def generate_text(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        tier: str = "fast",
    ) -> tuple[str, UsageMetrics]:
        return "Test response grounded in source material.", UsageMetrics(
            provider="mock_test",
            model="deterministic-test-v1",
            prompt_tokens=50,
            completion_tokens=20,
            total_tokens=70,
            estimated_cost_usd=0.0,
            latency_ms=5,
        )

    async def generate_embedding(
        self,
        *,
        texts: list[str],
        output_dimensionality: int = 768,
    ) -> tuple[list[list[float]], UsageMetrics]:
        vectors: list[list[float]] = []
        for text in texts:
            digest = hashlib.sha256(text.encode("utf-8")).digest()
            raw = [((digest[i % len(digest)] / 255.0) * 2.0 - 1.0) for i in range(output_dimensionality)]
            norm = math.sqrt(sum(v * v for v in raw)) or 1.0
            vectors.append([round(v / norm, 6) for v in raw])
        return vectors, UsageMetrics(
            provider="mock_test",
            model="deterministic-embed-768",
            prompt_tokens=sum(len(t.split()) for t in texts),
            completion_tokens=0,
            total_tokens=sum(len(t.split()) for t in texts),
            estimated_cost_usd=0.0,
            latency_ms=3,
        )

    async def generate_structured(
        self,
        *,
        system_instruction: str,
        user_prompt: str,
        response_schema: type[T],
        tier: str = "quality",
        context_hint: dict[str, Any] | None = None,
    ) -> tuple[T, UsageMetrics]:
        hint = context_hint or {}
        title = str(hint.get("title") or "Materi Pembelajaran")
        subject = str(hint.get("subject") or "Biologi")
        first_page = int(hint.get("first_page") or 1)
        snippet = str(hint.get("snippet") or "Konsep utama berdasarkan materi sumber.")
        game_type = str(hint.get("game_type") or "word_matching")

        data: dict[str, Any]
        if response_schema is DocumentAnalysisPayload:
            data = {
                "title": title,
                "subject": subject,
                "main_topic": title,
                "language": "id",
                "subtopics": ["Konsep Dasar", "Mekanisme Utama"],
                "key_concepts": [
                    {
                        "name": f"Konsep Inti {title}",
                        "description": snippet[:180],
                        "source_pages": [first_page],
                    }
                ],
                "definitions": [
                    {
                        "term": "Konsep Utama",
                        "definition": snippet[:140],
                        "source_page": first_page,
                    }
                ],
                "learning_objectives": [f"Memahami konsep pokok pada {title}."],
                "chapters": [
                    {
                        "title": f"Bab 1: {title}",
                        "topics": [
                            {
                                "title": "Konsep Dasar",
                                "concepts": [
                                    {
                                        "name": f"Konsep Inti {title}",
                                        "description": snippet[:160],
                                        "source_pages": [first_page],
                                    }
                                ],
                            }
                        ],
                    }
                ],
            }
        elif response_schema is SummaryPayload:
            data = {
                "title": f"Rangkuman {title}",
                "short_summary": f"Ringkasan terstruktur mengenai {title}: {snippet[:160]}",
                "detailed_summary": [
                    {
                        "section_title": "Pembahasan Utama",
                        "body": snippet,
                        "source_reference": {"page": first_page, "chunk_index": 0},
                    }
                ],
                "key_points": [
                    {
                        "point": snippet[:140],
                        "source_reference": {"page": first_page, "chunk_index": 0},
                    }
                ],
                "definitions": [
                    {
                        "term": "Istilah Pokok",
                        "definition": snippet[:120],
                        "source_reference": {"page": first_page, "chunk_index": 0},
                    }
                ],
                "conclusions": [f"Pemahaman {title} berakar pada konsep kunci dalam dokumen sumber."],
                "unfound_info_flags": [],
            }
        elif response_schema is QuizPayload:
            data = {
                "title": f"Evaluasi {title}",
                "questions": [
                    {
                        "id": "q1",
                        "question": f"Pernyataan manakah yang paling sesuai dengan materi {title}?",
                        "type": "multiple_choice",
                        "options": [
                            snippet[:80],
                            "Proses yang tidak dibahas pada dokumen",
                            "Fenomena di luar cakupan materi",
                            "Pernyataan yang bertentangan dengan sumber",
                        ],
                        "correct_answer": snippet[:80],
                        "explanation": f"Berdasarkan halaman {first_page}: {snippet[:120]}",
                        "difficulty": "easy",
                        "points": 10,
                        "source_reference": {"page": first_page, "chunk_index": 0},
                    },
                    {
                        "id": "q2",
                        "question": f"Materi {title} membahas konsep penting yang tercantum pada halaman {first_page}.",
                        "type": "true_false",
                        "options": ["Benar", "Salah"],
                        "correct_answer": "Benar",
                        "explanation": f"Konsep ini dijelaskan secara eksplisit pada halaman {first_page}.",
                        "difficulty": "easy",
                        "points": 10,
                        "source_reference": {"page": first_page, "chunk_index": 0},
                    },
                ],
                "unfound_info_flags": [],
            }
        elif response_schema is PresentationPayload:
            data = {
                "title": title,
                "theme_style": "clean_academic",
                "slides": [
                    {
                        "slide_number": 1,
                        "layout": "title_slide",
                        "title": title,
                        "subtitle": f"Mata Pelajaran: {subject}",
                        "content": [],
                        "speaker_notes": "Buka kelas dengan menjelaskan tujuan pembelajaran.",
                        "visual_suggestions": ["Diagram pengantar topik"],
                        "source_reference": {"page": first_page},
                    },
                    {
                        "slide_number": 2,
                        "layout": "title_content",
                        "title": "Konsep Inti",
                        "content": [snippet[:100], "Penerapan konsep pada contoh nyata"],
                        "speaker_notes": "Tekankan poin kunci dari halaman sumber.",
                        "visual_suggestions": ["Skema alur konsep"],
                        "source_reference": {"page": first_page},
                    },
                ],
            }
        elif response_schema is FlashcardsPayload:
            data = {
                "title": f"Flashcards {title}",
                "cards": [
                    {
                        "id": "fc1",
                        "front": f"Apa konsep utama dalam {title}?",
                        "back": snippet[:140],
                        "term": title,
                        "topic": subject,
                        "difficulty": "easy",
                        "source_reference": {"page": first_page},
                    }
                ],
            }
        elif response_schema is MindMapPayload:
            data = {
                "title": f"Peta Konsep {title}",
                "root": {
                    "id": "root",
                    "label": title,
                    "summary": snippet[:100],
                    "source_reference": {"page": first_page},
                    "children": [
                        {
                            "id": "n1",
                            "label": "Konsep Utama",
                            "relationship": "mencakup",
                            "source_reference": {"page": first_page},
                            "children": [],
                        }
                    ],
                },
            }
        elif response_schema is WorksheetPayload:
            data = {
                "title": f"Lembar Kerja {title}",
                "instructions": "Bacalah materi sumber kemudian selesaikan aktivitas berikut.",
                "activities": [
                    {
                        "id": "act1",
                        "activity_type": "guided_analysis",
                        "prompt": f"Jelaskan inti pembahasan pada {title} dengan bahasa Anda sendiri.",
                        "answer_space_lines": 5,
                        "sample_answer": snippet[:160],
                        "grading_criteria": ["Ketepatan konsep sesuai sumber (100%)"],
                        "max_points": 20,
                        "source_reference": {"page": first_page},
                    }
                ],
            }
        elif response_schema is GamePayload:
            if game_type == "crossword":
                # Geometrically valid intersection: LAMBUNG (row 1, col 0 across) & ASAM (row 0, col 1 down -> shares 'A' at (1,1))
                data = {
                    "game_type": "crossword",
                    "title": f"Teka-Teki Silang {title}",
                    "instructions": "Isi kotak mendatar dan menurun sesuai petunjuk materi.",
                    "settings": {"time_limit_seconds": 180, "shuffle": False},
                    "max_possible_score": 200,
                    "grid_size": {"rows": 6, "cols": 8},
                    "entries": [
                        {
                            "number": 1,
                            "direction": "across",
                            "row": 1,
                            "col": 0,
                            "answer": "LAMBUNG",
                            "clue": "Organ pencernaan utama tempat kerja enzim pepsin",
                            "source_reference": {"page": first_page},
                        },
                        {
                            "number": 2,
                            "direction": "down",
                            "row": 1,
                            "col": 1,
                            "answer": "ASAM",
                            "clue": "Sifat larutan HCl di dalam lambung",
                            "source_reference": {"page": first_page},
                        },
                    ],
                    "source_references": [{"page": first_page}],
                }
            elif game_type == "word_puzzle":
                data = {
                    "game_type": "word_puzzle",
                    "title": f"Susun Kata {title}",
                    "instructions": "Susun huruf acak menjadi istilah yang tepat.",
                    "settings": {"time_limit_seconds": 120, "shuffle": True},
                    "max_possible_score": 100,
                    "items": [
                        {
                            "id": "wp1",
                            "target_word": "PEPSIN",
                            "clue": "Enzim pemecah protein di lambung",
                            "hint": "Diawali huruf P",
                            "points": 100,
                            "source_reference": {"page": first_page},
                        }
                    ],
                    "source_references": [{"page": first_page}],
                }
            elif game_type == "memory_cards":
                data = {
                    "game_type": "memory_cards",
                    "title": f"Kartu Memori {title}",
                    "instructions": "Cocokkan pasangan kartu konsep yang sesuai.",
                    "settings": {"time_limit_seconds": 120, "shuffle": True},
                    "max_possible_score": 200,
                    "items": [
                        {"id": "m1", "card_a": "Lambung", "card_b": "Mencerna protein", "source_reference": {"page": first_page}},
                        {"id": "m2", "card_a": "Usus Halus", "card_b": "Menyerap nutrisi", "source_reference": {"page": first_page}},
                    ],
                    "source_references": [{"page": first_page}],
                }
            elif game_type == "true_false":
                data = {
                    "game_type": "true_false",
                    "title": f"Benar atau Salah: {title}",
                    "instructions": "Tentukan apakah pernyataan berikut benar atau salah.",
                    "settings": {"time_limit_seconds": 90, "shuffle": True},
                    "max_possible_score": 100,
                    "items": [
                        {
                            "id": "tf1",
                            "statement": snippet[:100],
                            "is_true": True,
                            "explanation": f"Tercantum pada halaman {first_page}.",
                            "points": 100,
                            "source_reference": {"page": first_page},
                        }
                    ],
                    "source_references": [{"page": first_page}],
                }
            elif game_type == "quiz_battle":
                data = {
                    "game_type": "quiz_battle",
                    "title": f"Quiz Battle: {title}",
                    "instructions": "Jawab cepat dan tepat sebelum waktu habis.",
                    "settings": {"time_limit_seconds": 120, "shuffle": True},
                    "max_possible_score": 100,
                    "items": [
                        {
                            "id": "qb1",
                            "question": f"Inti materi {title} adalah?",
                            "options": [snippet[:60], "Pilihan B", "Pilihan C", "Pilihan D"],
                            "correct_answer": snippet[:60],
                            "points": 100,
                            "time_seconds": 20,
                            "explanation": f"Lihat halaman {first_page}.",
                            "source_reference": {"page": first_page},
                        }
                    ],
                    "source_references": [{"page": first_page}],
                }
            else:
                data = {
                    "game_type": "word_matching",
                    "title": f"Cocokkan Konsep: {title}",
                    "instructions": "Hubungkan istilah di kiri dengan penjelasan yang tepat di kanan.",
                    "settings": {"time_limit_seconds": 90, "shuffle": True},
                    "max_possible_score": 200,
                    "items": [
                        {"id": "wm1", "left": "Lambung", "right": "Mencerna makanan dengan HCl dan pepsin", "points": 100, "source_reference": {"page": first_page}},
                        {"id": "wm2", "left": "Usus Halus", "right": "Menyerap sari-sari makanan", "points": 100, "source_reference": {"page": first_page}},
                    ],
                    "source_references": [{"page": first_page}],
                }
        else:
            raise ValueError(f"Unsupported mock schema: {response_schema}")

        return response_schema.model_validate(data), UsageMetrics(
            provider="mock_test",
            model="deterministic-test-v1",
            prompt_tokens=120,
            completion_tokens=180,
            total_tokens=300,
            estimated_cost_usd=0.0,
            latency_ms=8,
        )
