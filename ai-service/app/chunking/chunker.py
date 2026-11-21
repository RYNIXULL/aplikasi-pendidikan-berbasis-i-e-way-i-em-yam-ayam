import re
from app.schemas.contracts import ExtractedChunk, ExtractedPage


def estimate_tokens(text: str) -> int:
    # Fast, conservative heuristic (~1.3 tokens per word for Indonesian/English)
    words = len(text.split())
    return max(1, int(words * 1.3))


def build_semantic_chunks(
    pages: list[ExtractedPage],
    target_tokens: int = 650,
    overlap_tokens: int = 80,
) -> list[ExtractedChunk]:
    chunks: list[ExtractedChunk] = []
    current_chapter: str | None = None
    current_section: str | None = None

    buffer_paragraphs: list[tuple[int, str]] = []
    buffer_tokens = 0

    def flush_chunk() -> None:
        nonlocal buffer_paragraphs, buffer_tokens
        if not buffer_paragraphs:
            return
        text = "\n\n".join(p for _, p in buffer_paragraphs).strip()
        if not text:
            buffer_paragraphs = []
            buffer_tokens = 0
            return
        page_nums = [pg for pg, _ in buffer_paragraphs]
        chunks.append(
            ExtractedChunk(
                chunk_index=len(chunks),
                chapter_title=current_chapter,
                section_title=current_section,
                page_start=min(page_nums),
                page_end=max(page_nums),
                token_count=estimate_tokens(text),
                content=text,
                metadata={
                    "chapter": current_chapter,
                    "section": current_section,
                },
            )
        )

        # Keep trailing overlap paragraphs to preserve cross-chunk continuity
        kept: list[tuple[int, str]] = []
        kept_tokens = 0
        for item in reversed(buffer_paragraphs):
            t = estimate_tokens(item[1])
            if kept_tokens + t <= overlap_tokens:
                kept.insert(0, item)
                kept_tokens += t
            else:
                break
        buffer_paragraphs = kept
        buffer_tokens = kept_tokens

    chapter_pattern = re.compile(r"^(#\s*)?(BAB|CHAPTER|UNIT|MODUL)\b", re.IGNORECASE)
    section_pattern = re.compile(r"^(##\s*|\d+\.\d+\s+)")

    for page in pages:
        if not page.normalized_text.strip():
            continue
        paragraphs = [p.strip() for p in re.split(r"\n{2,}", page.normalized_text) if p.strip()]
        for para in paragraphs:
            if chapter_pattern.match(para):
                if buffer_paragraphs:
                    flush_chunk()
                current_chapter = para.lstrip("# ").strip()[:240]
                current_section = None
            elif section_pattern.match(para):
                current_section = para.lstrip("# ").strip()[:240]

            para_tokens = estimate_tokens(para)
            if buffer_paragraphs and buffer_tokens + para_tokens > target_tokens:
                flush_chunk()

            buffer_paragraphs.append((page.page_number, para))
            buffer_tokens += para_tokens

    flush_chunk()
    return chunks
