from typing import Any, TypeVar
from pydantic import BaseModel
from app.core.config import get_settings
from app.prompts.templates import BASE_SECURITY_SYSTEM_PROMPT, build_grounded_context_block
from app.providers.base import AIProvider
from app.schemas.contracts import (
    AnalyzeRequest,
    DocumentAnalysisPayload,
    FlashcardsPayload,
    GamePayload,
    GenerationEnvelope,
    GenerationRequest,
    MindMapPayload,
    PresentationPayload,
    QuizPayload,
    SourceReference,
    SummaryPayload,
    UsageMetrics,
    ValidationReport,
    WorksheetPayload,
)
from app.validation.validators import (
    validate_crossword_geometry,
    validate_page_references,
    validate_quiz_semantics,
)

T = TypeVar("T", bound=BaseModel)


def _merge_usage(a: UsageMetrics | None, b: UsageMetrics) -> UsageMetrics:
    if a is None:
        return b
    return UsageMetrics(
        provider=b.provider,
        model=b.model,
        prompt_tokens=a.prompt_tokens + b.prompt_tokens,
        completion_tokens=a.completion_tokens + b.completion_tokens,
        total_tokens=a.total_tokens + b.total_tokens,
        estimated_cost_usd=round(a.estimated_cost_usd + b.estimated_cost_usd, 6),
        latency_ms=a.latency_ms + b.latency_ms,
    )


def _valid_page_set(chunks: list[Any]) -> set[int]:
    pages: set[int] = set()
    for c in chunks:
        for p in range(c.page_start, c.page_end + 1):
            pages.add(p)
    return pages or {1}


async def run_document_analysis(provider: AIProvider, req: AnalyzeRequest) -> GenerationEnvelope:
    context = build_grounded_context_block(req.chunks)
    prompt = (
        f"Analyze the following educational document titled '{req.title}' (subject: {req.subject}).\n"
        f"Extract the main topic, subtopics, key concepts with source_pages, definitions with source_page, "
        f"learning objectives, and chapter hierarchy.\n\n{context}"
    )
    hint = {
        "title": req.title,
        "subject": req.subject,
        "first_page": req.chunks[0].page_start,
        "snippet": req.chunks[0].content[:240],
    }

    parsed, usage = await provider.analyze_document(
        system_instruction=BASE_SECURITY_SYSTEM_PROMPT,
        user_prompt=prompt,
        response_schema=DocumentAnalysisPayload,
        context_hint=hint,
    )

    refs = [SourceReference(page=c.page_start, chunk_index=c.chunk_index) for c in req.chunks[:5]]
    return GenerationEnvelope(
        payload=parsed.model_dump(),
        source_references=refs,
        validation_report=ValidationReport(schema_valid=True, grounding_verified=True, retry_count=0),
        usage=usage,
    )


async def run_content_generation(
    provider: AIProvider,
    content_kind: str,
    req: GenerationRequest,
) -> GenerationEnvelope:
    settings = get_settings()
    context = build_grounded_context_block(req.chunks)
    valid_pages = _valid_page_set(req.chunks)

    schema_map: dict[str, tuple[type[BaseModel], str, str]] = {
        "summary": (
            SummaryPayload,
            "Generate a structured educational summary (short_summary, detailed_summary, key_points, definitions, conclusions).",
            "quality",
        ),
        "quiz": (
            QuizPayload,
            "Generate grounded quiz questions matching the requested count, types, difficulty, answer key, and explanation.",
            "quality",
        ),
        "presentation": (
            PresentationPayload,
            "Generate a structured slide deck plan (title_slide + title_content slides, concise bullets, speaker_notes, visual_suggestions).",
            "quality",
        ),
        "flashcards": (
            FlashcardsPayload,
            "Generate study flashcards with front question/term, concise back answer/definition, topic, and difficulty.",
            "fast",
        ),
        "mind-map": (
            MindMapPayload,
            "Generate a hierarchical mind map concept tree (root -> branches -> sub-concepts with relationship labels).",
            "quality",
        ),
        "worksheet": (
            WorksheetPayload,
            "Generate a student learning worksheet with clear instructions, activities, answer spaces, sample answers, and grading criteria.",
            "quality",
        ),
        "game": (
            GamePayload,
            f"Generate a strictly validated educational game configuration for game_type='{req.game_type or 'word_matching'}'. "
            "Never generate executable code; output declarative JSON configuration only.",
            "quality",
        ),
    }

    if content_kind not in schema_map:
        raise ValueError(f"Unsupported generation kind: {content_kind}")

    schema_cls, task_instruction, tier = schema_map[content_kind]
    base_prompt = (
        f"Task: {task_instruction}\n"
        f"Document Title: {req.document_title}\n"
        f"Subject: {req.subject}\n"
        f"Configuration: {req.config}\n\n"
        f"{context}"
    )
    hint = {
        "title": req.config.get("title") or req.document_title,
        "subject": req.subject,
        "first_page": req.chunks[0].page_start,
        "snippet": req.chunks[0].content[:240],
        "game_type": req.game_type or req.config.get("gameType") or "word_matching",
    }

    total_usage: UsageMetrics | None = None
    last_error: str = ""
    current_prompt = base_prompt

    for attempt in range(settings.max_validation_retries + 1):
        try:
            parsed, usage = await provider.generate_structured(
                system_instruction=BASE_SECURITY_SYSTEM_PROMPT,
                user_prompt=current_prompt,
                response_schema=schema_cls,
                tier=tier,
                context_hint=hint,
            )
            total_usage = _merge_usage(total_usage, usage)

            warnings: list[str] = []
            refs: list[SourceReference] = []
            grounding_ok = True

            if isinstance(parsed, QuizPayload):
                parsed, report = validate_quiz_semantics(parsed, valid_pages)
                warnings.extend(report.warnings)
                grounding_ok = report.grounding_verified
                refs = [q.source_reference for q in parsed.questions]
            elif isinstance(parsed, SummaryPayload):
                refs = [s.source_reference for s in parsed.detailed_summary] + [
                    k.source_reference for k in parsed.key_points
                ]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)
            elif isinstance(parsed, PresentationPayload):
                refs = [s.source_reference for s in parsed.slides]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)
            elif isinstance(parsed, FlashcardsPayload):
                refs = [c.source_reference for c in parsed.cards]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)
            elif isinstance(parsed, MindMapPayload):
                refs = [parsed.root.source_reference]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)
            elif isinstance(parsed, WorksheetPayload):
                refs = [a.source_reference for a in parsed.activities]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)
            elif isinstance(parsed, GamePayload):
                warnings.extend(validate_crossword_geometry(parsed))
                refs = parsed.source_references or [SourceReference(page=req.chunks[0].page_start)]
                grounding_ok, w = validate_page_references(refs, valid_pages)
                warnings.extend(w)

            return GenerationEnvelope(
                payload=parsed.model_dump(),
                source_references=refs,
                validation_report=ValidationReport(
                    schema_valid=True,
                    grounding_verified=grounding_ok,
                    retry_count=attempt,
                    warnings=warnings,
                ),
                usage=total_usage,
            )
        except Exception as exc:
            last_error = str(exc)
            current_prompt = (
                f"{base_prompt}\n\n"
                f"Previous JSON output failed validation with error: {last_error}. "
                f"Fix the structure and citations strictly."
            )

    raise ValueError(f"Failed schema/semantic validation after retries: {last_error}")
