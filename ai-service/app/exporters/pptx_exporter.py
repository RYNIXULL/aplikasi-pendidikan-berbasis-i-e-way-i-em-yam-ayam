import io
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.util import Inches, Pt
from app.schemas.contracts import PresentationPayload


PRIMARY_NAVY = RGBColor(0x1E, 0x3A, 0x5F)
ACCENT_TEAL = RGBColor(0x0F, 0x76, 0x6E)
TEXT_DARK = RGBColor(0x1E, 0x29, 0x3B)
TEXT_MUTED = RGBColor(0x64, 0x74, 0x8B)
BG_SOFT = RGBColor(0xF8, 0xFA, 0xFC)


def build_pptx_bytes(deck: PresentationPayload) -> bytes:
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    for slide_spec in deck.slides:
        if slide_spec.layout == "title_slide":
            slide = prs.slides.add_slide(prs.slide_layouts[6])  # Blank for clean custom typography
            bg = slide.background.fill
            bg.solid()
            bg.fore_color.rgb = PRIMARY_NAVY

            title_box = slide.shapes.add_textbox(Inches(1.0), Inches(2.2), Inches(11.3), Inches(1.8))
            tf = title_box.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.text = slide_spec.title
            p.font.size = Pt(42)
            p.font.bold = True
            p.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

            if slide_spec.subtitle:
                sub_box = slide.shapes.add_textbox(Inches(1.0), Inches(4.2), Inches(11.3), Inches(1.0))
                stf = sub_box.text_frame
                sp = stf.paragraphs[0]
                sp.text = slide_spec.subtitle
                sp.font.size = Pt(22)
                sp.font.color.rgb = RGBColor(0xCB, 0xD5, 0xE1)
        else:
            slide = prs.slides.add_slide(prs.slide_layouts[6])
            bg = slide.background.fill
            bg.solid()
            bg.fore_color.rgb = BG_SOFT

            # Accent top bar
            bar = slide.shapes.add_shape(1, Inches(0), Inches(0), Inches(13.333), Inches(0.14))
            bar.fill.solid()
            bar.fill.fore_color.rgb = ACCENT_TEAL
            bar.line.fill.background()

            # Slide title
            tbox = slide.shapes.add_textbox(Inches(0.8), Inches(0.45), Inches(11.7), Inches(0.9))
            ttf = tbox.text_frame
            ttf.word_wrap = True
            tp = ttf.paragraphs[0]
            tp.text = slide_spec.title
            tp.font.size = Pt(30)
            tp.font.bold = True
            tp.font.color.rgb = PRIMARY_NAVY

            # Bullet points
            body_box = slide.shapes.add_textbox(Inches(0.9), Inches(1.55), Inches(11.5), Inches(4.9))
            btf = body_box.text_frame
            btf.word_wrap = True
            for i, bullet in enumerate(slide_spec.content):
                bp = btf.paragraphs[0] if i == 0 else btf.add_paragraph()
                bp.text = f"- {bullet}"
                bp.font.size = Pt(20)
                bp.font.color.rgb = TEXT_DARK
                bp.space_after = Pt(12)

            # Footer citation
            fbox = slide.shapes.add_textbox(Inches(0.8), Inches(6.85), Inches(11.7), Inches(0.4))
            ftf = fbox.text_frame
            fp = ftf.paragraphs[0]
            fp.text = f"Sumber: Halaman {slide_spec.source_reference.page}  |  Slide {slide_spec.slide_number}"
            fp.font.size = Pt(12)
            fp.font.color.rgb = TEXT_MUTED

        if slide_spec.speaker_notes:
            notes_slide = slide.notes_slide
            notes_slide.notes_text_frame.text = slide_spec.speaker_notes

    output = io.BytesIO()
    prs.save(output)
    return output.getvalue()
