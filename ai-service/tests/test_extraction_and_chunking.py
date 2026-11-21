import io
import pymupdf
from docx import Document as DocxDocument
from pptx import Presentation as PptxPresentation
from app.chunking.chunker import build_semantic_chunks
from app.extraction.extractors import (
    extract_docx_bytes,
    extract_pdf_bytes,
    extract_pptx_bytes,
    normalize_text,
)


def _create_sample_pdf() -> bytes:
    doc = pymupdf.open()
    page1 = doc.new_page()
    page1.insert_text(
        (72, 72),
        "BAB 1 SISTEM PENCERNAAN MANUSIA\n\n"
        "Sistem pencernaan berfungsi memecah makanan menjadi nutrisi yang dapat diserap tubuh.\n"
        "Mulut melakukan pencernaan mekanis melalui gigi dan kimiawi melalui enzim amilase.",
    )
    page2 = doc.new_page()
    page2.insert_text(
        (72, 72),
        "1.2 Organ Lambung\n\n"
        "Lambung menghasilkan asam klorida (HCl) untuk membunuh mikroorganisme serta enzim pepsin "
        "yang memecah protein menjadi pepton.",
    )
    data = doc.tobytes()
    doc.close()
    return data


def _create_sample_docx() -> bytes:
    doc = DocxDocument()
    doc.add_heading("BAB 1 Fotosintesis", level=1)
    doc.add_paragraph(
        "Fotosintesis adalah proses penyusunan glukosa dari air dan karbon dioksida dengan bantuan cahaya matahari."
    )
    table = doc.add_table(rows=2, cols=2)
    table.rows[0].cells[0].text = "Tahap"
    table.rows[0].cells[1].text = "Lokasi"
    table.rows[1].cells[0].text = "Reaksi Terang"
    table.rows[1].cells[1].text = "Tilakoid"
    buf = io.BytesIO()
    doc.save(buf)
    return buf.getvalue()


def _create_sample_pptx() -> bytes:
    prs = PptxPresentation()
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = "Hukum Newton"
    slide.placeholders[1].text = "Hukum I Newton menjelaskan kelembaman benda.\nHukum II Newton: F = m x a."
    slide.notes_slide.notes_text_frame.text = "Berikan contoh nyata sabuk pengaman di mobil."
    buf = io.BytesIO()
    prs.save(buf)
    return buf.getvalue()


def test_normalize_text_repairs_hyphenation_and_whitespace() -> None:
    raw = "pencer-\nnaan   makanan\r\n\r\n\r\noleh   lambung"
    assert normalize_text(raw) == "pencernaan makanan\n\noleh lambung"


def test_extract_pdf_and_build_semantic_chunks() -> None:
    pages, warnings, requires_review = extract_pdf_bytes(_create_sample_pdf())
    assert len(pages) == 2
    assert requires_review is False
    assert "pepsin" in pages[1].normalized_text.lower()

    chunks = build_semantic_chunks(pages, target_tokens=100, overlap_tokens=20)
    assert len(chunks) >= 1
    assert chunks[0].page_start == 1
    assert chunks[0].chapter_title is not None


def test_extract_docx_with_headings_and_tables() -> None:
    pages, _warnings, requires_review = extract_docx_bytes(_create_sample_docx())
    assert len(pages) >= 1
    assert requires_review is False
    combined = "\n".join(p.normalized_text for p in pages)
    assert "Fotosintesis" in combined
    assert "Tilakoid" in combined


def test_extract_pptx_with_speaker_notes() -> None:
    pages, _warnings, requires_review = extract_pptx_bytes(_create_sample_pptx())
    assert len(pages) == 1
    assert requires_review is False
    assert "Hukum Newton" in pages[0].normalized_text
    assert "sabuk pengaman" in pages[0].normalized_text
