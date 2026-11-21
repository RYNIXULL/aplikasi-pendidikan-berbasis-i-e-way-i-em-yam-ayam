import io
import re
import unicodedata
from abc import ABC, abstractmethod
from collections import Counter
import pymupdf
from docx import Document as DocxDocument
from pptx import Presentation as PptxPresentation
from app.schemas.contracts import ExtractedPage


class OcrProvider(ABC):
    @abstractmethod
    def extract_text_from_image_bytes(self, image_bytes: bytes) -> str:
        raise NotImplementedError


class DisabledOcrProvider(OcrProvider):
    def extract_text_from_image_bytes(self, image_bytes: bytes) -> str:
        return ""


class OptionalTesseractOcrProvider(OcrProvider):
    def extract_text_from_image_bytes(self, image_bytes: bytes) -> str:
        try:
            import pytesseract  # type: ignore
            from PIL import Image  # type: ignore

            img = Image.open(io.BytesIO(image_bytes))
            return pytesseract.image_to_string(img, lang="ind+eng")
        except Exception:
            return ""


def normalize_text(text: str) -> str:
    # Normalize unicode, fix broken hyphenations, collapse excessive whitespace
    cleaned = unicodedata.normalize("NFKC", text)
    cleaned = cleaned.replace("\x00", "")
    cleaned = re.sub(r"-\s*\n\s*", "", cleaned)
    cleaned = re.sub(r"\r\n?", "\n", cleaned)
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _strip_repeating_headers_footers(pages: list[ExtractedPage]) -> list[ExtractedPage]:
    if len(pages) < 4:
        return pages

    first_lines: Counter[str] = Counter()
    last_lines: Counter[str] = Counter()
    for p in pages:
        lines = [ln.strip() for ln in p.normalized_text.splitlines() if ln.strip()]
        if lines:
            first_lines[lines[0]] += 1
            last_lines[lines[-1]] += 1

    threshold = max(3, int(len(pages) * 0.6))
    repeating_headers = {line for line, cnt in first_lines.items() if cnt >= threshold and len(line) <= 100}
    repeating_footers = {line for line, cnt in last_lines.items() if cnt >= threshold and len(line) <= 100}

    if not repeating_headers and not repeating_footers:
        return pages

    cleaned_pages: list[ExtractedPage] = []
    for p in pages:
        lines = p.normalized_text.splitlines()
        if lines and lines[0].strip() in repeating_headers:
            lines = lines[1:]
        if lines and lines[-1].strip() in repeating_footers:
            lines = lines[:-1]
        norm = "\n".join(lines).strip()
        cleaned_pages.append(
            p.model_copy(update={"normalized_text": norm, "char_count": len(norm)})
        )
    return cleaned_pages


def _detect_heading(text: str) -> str | None:
    for line in text.splitlines():
        candidate = line.strip()
        if 3 <= len(candidate) <= 120:
            if re.match(r"^(BAB|CHAPTER|UNIT|MODUL|BAGIAN|\d+\.)\b", candidate, re.IGNORECASE) or (
                candidate.isupper() and len(candidate.split()) <= 10
            ):
                return candidate
            return candidate
    return None


def extract_pdf_bytes(
    data: bytes,
    max_pages: int = 150,
    ocr_enabled: bool = False,
    ocr_provider: OcrProvider | None = None,
) -> tuple[list[ExtractedPage], list[str], bool]:
    warnings: list[str] = []
    pages: list[ExtractedPage] = []
    low_text_pages = 0
    provider = ocr_provider or (OptionalTesseractOcrProvider() if ocr_enabled else DisabledOcrProvider())

    with pymupdf.open(stream=data, filetype="pdf") as doc:
        total_pages = len(doc)
        if total_pages > max_pages:
            warnings.append(f"Document truncated to first {max_pages} of {total_pages} pages.")
        limit = min(total_pages, max_pages)

        for idx in range(limit):
            page = doc.load_page(idx)
            raw = page.get_text("text") or ""
            method = "PYMUPDF"

            if len(raw.strip()) < 40:
                if ocr_enabled:
                    pix = page.get_pixmap(dpi=200)
                    ocr_text = provider.extract_text_from_image_bytes(pix.tobytes("png"))
                    if ocr_text.strip():
                        raw = ocr_text
                        method = "OCR"
                    else:
                        low_text_pages += 1
                else:
                    low_text_pages += 1

            norm = normalize_text(raw)
            pages.append(
                ExtractedPage(
                    page_number=idx + 1,
                    heading=_detect_heading(norm),
                    raw_text=raw,
                    normalized_text=norm,
                    extraction_method=method,
                    char_count=len(norm),
                )
            )

    pages = _strip_repeating_headers_footers(pages)
    requires_review = len(pages) > 0 and (low_text_pages / len(pages)) >= 0.5
    if requires_review:
        warnings.append("Significant portion of PDF appears scanned or lacks extractable text.")
    return pages, warnings, requires_review


def extract_docx_bytes(data: bytes) -> tuple[list[ExtractedPage], list[str], bool]:
    doc = DocxDocument(io.BytesIO(data))
    blocks: list[str] = []

    for para in doc.paragraphs:
        txt = para.text.strip()
        if txt:
            style_name = (para.style.name if para.style else "") or ""
            if style_name.lower().startswith("heading"):
                blocks.append(f"# {txt}")
            else:
                blocks.append(txt)

    for table in doc.tables:
        rows_txt = []
        for row in table.rows:
            cells = [cell.text.strip().replace("\n", " ") for cell in row.cells]
            if any(cells):
                rows_txt.append(" | ".join(cells))
        if rows_txt:
            blocks.append("\n".join(rows_txt))

    # Group into logical pages (~2400 chars per page) preserving headings
    pages: list[ExtractedPage] = []
    current_lines: list[str] = []
    current_len = 0
    page_num = 1

    for block in blocks:
        if current_lines and (current_len + len(block) > 2400 or block.startswith("# ")):
            raw = "\n\n".join(current_lines)
            norm = normalize_text(raw)
            pages.append(
                ExtractedPage(
                    page_number=page_num,
                    heading=_detect_heading(norm.replace("# ", "")),
                    raw_text=raw,
                    normalized_text=norm,
                    extraction_method="DOCX",
                    char_count=len(norm),
                )
            )
            page_num += 1
            current_lines = []
            current_len = 0
        current_lines.append(block)
        current_len += len(block)

    if current_lines:
        raw = "\n\n".join(current_lines)
        norm = normalize_text(raw)
        pages.append(
            ExtractedPage(
                page_number=page_num,
                heading=_detect_heading(norm.replace("# ", "")),
                raw_text=raw,
                normalized_text=norm,
                extraction_method="DOCX",
                char_count=len(norm),
            )
        )

    warnings: list[str] = []
    requires_review = sum(p.char_count for p in pages) < 30
    if requires_review:
        warnings.append("DOCX document contains very little extractable text.")
    return pages, warnings, requires_review


def extract_pptx_bytes(data: bytes) -> tuple[list[ExtractedPage], list[str], bool]:
    prs = PptxPresentation(io.BytesIO(data))
    pages: list[ExtractedPage] = []

    for idx, slide in enumerate(prs.slides, start=1):
        parts: list[str] = []
        slide_title: str | None = None

        for shape in slide.shapes:
            if shape.has_text_frame:
                text = shape.text_frame.text.strip()
                if text:
                    if slide_title is None and shape == getattr(slide.shapes, "title", None):
                        slide_title = text
                    parts.append(text)
            if shape.has_table:
                for row in shape.table.rows:
                    row_cells = [c.text.strip() for c in row.cells]
                    if any(row_cells):
                        parts.append(" | ".join(row_cells))

        if slide.has_notes_slide and slide.notes_slide.notes_text_frame:
            notes = slide.notes_slide.notes_text_frame.text.strip()
            if notes:
                parts.append(f"Catatan Presenter: {notes}")

        raw = "\n".join(parts)
        norm = normalize_text(raw)
        pages.append(
            ExtractedPage(
                page_number=idx,
                heading=slide_title or _detect_heading(norm),
                raw_text=raw,
                normalized_text=norm,
                extraction_method="PPTX",
                char_count=len(norm),
            )
        )

    warnings: list[str] = []
    requires_review = sum(p.char_count for p in pages) < 30
    if requires_review:
        warnings.append("PPTX presentation contains very little extractable text.")
    return pages, warnings, requires_review
