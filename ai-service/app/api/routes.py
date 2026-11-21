import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from app.chunking.chunker import build_semantic_chunks
from app.core.config import get_settings
from app.core.security import verify_internal_request
from app.exporters.pptx_exporter import build_pptx_bytes
from app.extraction.extractors import extract_docx_bytes, extract_pdf_bytes, extract_pptx_bytes
from app.generators.engine import run_content_generation, run_document_analysis
from app.providers.factory import get_ai_provider
from app.schemas.contracts import (
    AnalyzeRequest,
    EmbeddingsRequest,
    EmbeddingsResponse,
    ExportPptxRequest,
    ExportPptxResponse,
    ExtractRequest,
    ExtractResponse,
    GenerationEnvelope,
    GenerationRequest,
)

router = APIRouter(prefix="/internal/v1", tags=["internal"])


@router.get("/health")
async def health() -> dict[str, str]:
    settings = get_settings()
    return {
        "status": "ok",
        "service": "edu-ai-service",
        "provider": settings.ai_provider,
    }


@router.post(
    "/documents/extract",
    response_model=ExtractResponse,
    dependencies=[Depends(verify_internal_request)],
)
async def extract_document(req: ExtractRequest) -> ExtractResponse:
    settings = get_settings()
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.get(req.file_url)
            resp.raise_for_status()
            file_bytes = resp.content
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Unable to fetch source document from object storage: {exc}",
        ) from exc

    if req.file_format == "PDF":
        pages, warnings, requires_review = extract_pdf_bytes(
            file_bytes,
            max_pages=settings.max_pages_per_document,
            ocr_enabled=settings.ocr_enabled,
        )
    elif req.file_format == "DOCX":
        pages, warnings, requires_review = extract_docx_bytes(file_bytes)
    else:
        pages, warnings, requires_review = extract_pptx_bytes(file_bytes)

    chunks = build_semantic_chunks(pages)
    word_count = sum(len(p.normalized_text.split()) for p in pages)
    return ExtractResponse(
        page_count=len(pages),
        word_count=word_count,
        requires_review=requires_review,
        warnings=warnings,
        pages=pages,
        chunks=chunks,
    )


@router.post(
    "/embeddings",
    response_model=EmbeddingsResponse,
    dependencies=[Depends(verify_internal_request)],
)
async def create_embeddings(req: EmbeddingsRequest) -> EmbeddingsResponse:
    provider = get_ai_provider()
    vectors, usage = await provider.generate_embedding(texts=req.texts, output_dimensionality=768)
    return EmbeddingsResponse(embeddings=vectors, usage=usage)


@router.post(
    "/documents/analyze",
    response_model=GenerationEnvelope,
    dependencies=[Depends(verify_internal_request)],
)
async def analyze_document(req: AnalyzeRequest) -> GenerationEnvelope:
    provider = get_ai_provider()
    return await run_document_analysis(provider, req)


@router.post(
    "/generate/{content_kind}",
    response_model=GenerationEnvelope,
    dependencies=[Depends(verify_internal_request)],
)
async def generate_content(content_kind: str, req: GenerationRequest) -> GenerationEnvelope:
    valid_kinds = {"summary", "quiz", "presentation", "flashcards", "mind-map", "worksheet", "game"}
    if content_kind not in valid_kinds:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported content kind '{content_kind}'.",
        )
    provider = get_ai_provider()
    try:
        return await run_content_generation(provider, content_kind, req)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.post(
    "/export/pptx",
    response_model=ExportPptxResponse,
    dependencies=[Depends(verify_internal_request)],
)
async def export_pptx(req: ExportPptxRequest) -> ExportPptxResponse:
    pptx_bytes = build_pptx_bytes(req.presentation)
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            put_resp = await client.put(
                req.upload_url,
                content=pptx_bytes,
                headers={
                    "Content-Type": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
                },
            )
            put_resp.raise_for_status()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Unable to upload exported PPTX to object storage: {exc}",
        ) from exc

    return ExportPptxResponse(
        slide_count=len(req.presentation.slides),
        size_bytes=len(pptx_bytes),
    )
