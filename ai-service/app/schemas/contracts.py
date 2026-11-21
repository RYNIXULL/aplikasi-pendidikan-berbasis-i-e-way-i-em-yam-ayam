from typing import Any, Literal
from pydantic import BaseModel, Field


class SourceReference(BaseModel):
    page: int = Field(ge=1)
    chunk_index: int | None = Field(default=None, ge=0)
    excerpt: str | None = None


class UsageMetrics(BaseModel):
    provider: str
    model: str
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    estimated_cost_usd: float = 0.0
    latency_ms: int = 0


class ValidationReport(BaseModel):
    schema_valid: bool = True
    grounding_verified: bool = True
    retry_count: int = 0
    warnings: list[str] = Field(default_factory=list)


# =========================
# Extraction & Chunking
# =========================


class ExtractRequest(BaseModel):
    document_id: str
    file_url: str
    file_format: Literal["PDF", "DOCX", "PPTX"]
    filename: str


class ExtractedPage(BaseModel):
    page_number: int = Field(ge=1)
    heading: str | None = None
    raw_text: str
    normalized_text: str
    extraction_method: str
    char_count: int = Field(ge=0)


class ExtractedChunk(BaseModel):
    chunk_index: int = Field(ge=0)
    chapter_title: str | None = None
    section_title: str | None = None
    page_start: int = Field(ge=1)
    page_end: int = Field(ge=1)
    token_count: int = Field(ge=0)
    content: str
    metadata: dict[str, Any] = Field(default_factory=dict)


class ExtractResponse(BaseModel):
    page_count: int = Field(ge=0)
    word_count: int = Field(ge=0)
    requires_review: bool = False
    warnings: list[str] = Field(default_factory=list)
    pages: list[ExtractedPage]
    chunks: list[ExtractedChunk]


class EmbeddingsRequest(BaseModel):
    texts: list[str] = Field(min_length=1, max_length=256)


class EmbeddingsResponse(BaseModel):
    embeddings: list[list[float]]
    usage: UsageMetrics


# =========================
# Document Analysis
# =========================


class ChunkInput(BaseModel):
    chunk_index: int
    chapter_title: str | None = None
    page_start: int = Field(ge=1)
    page_end: int = Field(ge=1)
    content: str


class AnalyzeRequest(BaseModel):
    document_id: str
    title: str
    subject: str
    chunks: list[ChunkInput] = Field(min_length=1)


class ConceptNode(BaseModel):
    name: str
    description: str
    source_pages: list[int] = Field(default_factory=list)


class TopicNode(BaseModel):
    title: str
    concepts: list[ConceptNode] = Field(default_factory=list)


class ChapterNode(BaseModel):
    title: str
    topics: list[TopicNode] = Field(default_factory=list)


class TermDefinition(BaseModel):
    term: str
    definition: str
    source_page: int = Field(ge=1)


class DocumentAnalysisPayload(BaseModel):
    title: str
    subject: str
    main_topic: str
    language: str = "id"
    subtopics: list[str] = Field(default_factory=list)
    key_concepts: list[ConceptNode] = Field(default_factory=list)
    definitions: list[TermDefinition] = Field(default_factory=list)
    learning_objectives: list[str] = Field(default_factory=list)
    chapters: list[ChapterNode] = Field(default_factory=list)


# =========================
# Content Generation Inputs & Outputs
# =========================


class GenerationRequest(BaseModel):
    document_id: str
    document_title: str
    subject: str
    page_count: int = Field(default=1, ge=1)
    game_type: str | None = None
    analysis: dict[str, Any] | None = None
    chunks: list[ChunkInput] = Field(min_length=1)
    config: dict[str, Any] = Field(default_factory=dict)


class DetailedSection(BaseModel):
    section_title: str
    body: str
    source_reference: SourceReference


class KeyPointItem(BaseModel):
    point: str
    source_reference: SourceReference


class SummaryDefinitionItem(BaseModel):
    term: str
    definition: str
    source_reference: SourceReference


class SummaryPayload(BaseModel):
    title: str
    short_summary: str
    detailed_summary: list[DetailedSection] = Field(min_length=1)
    key_points: list[KeyPointItem] = Field(min_length=1)
    definitions: list[SummaryDefinitionItem] = Field(default_factory=list)
    conclusions: list[str] = Field(min_length=1)
    unfound_info_flags: list[str] = Field(default_factory=list)


class QuizQuestion(BaseModel):
    id: str
    question: str
    type: Literal["multiple_choice", "true_false", "short_answer", "essay"]
    options: list[str] | None = None
    correct_answer: str
    explanation: str
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    points: int = Field(default=10, gt=0)
    source_reference: SourceReference


class QuizPayload(BaseModel):
    title: str
    questions: list[QuizQuestion] = Field(min_length=1)
    unfound_info_flags: list[str] = Field(default_factory=list)


class SlideItem(BaseModel):
    slide_number: int = Field(ge=1)
    layout: Literal["title_slide", "title_content", "two_column", "summary_slide"] = "title_content"
    title: str
    subtitle: str | None = None
    content: list[str] = Field(default_factory=list)
    speaker_notes: str = ""
    visual_suggestions: list[str] = Field(default_factory=list)
    source_reference: SourceReference


class PresentationPayload(BaseModel):
    title: str
    theme_style: str = "clean_academic"
    slides: list[SlideItem] = Field(min_length=2)


class FlashcardItem(BaseModel):
    id: str
    front: str
    back: str
    term: str
    topic: str
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    source_reference: SourceReference


class FlashcardsPayload(BaseModel):
    title: str
    cards: list[FlashcardItem] = Field(min_length=1)


class MindMapNode(BaseModel):
    id: str
    label: str
    summary: str | None = None
    relationship: str | None = None
    source_reference: SourceReference
    children: list["MindMapNode"] = Field(default_factory=list)


MindMapNode.model_rebuild()


class MindMapPayload(BaseModel):
    title: str
    root: MindMapNode


class WorksheetActivity(BaseModel):
    id: str
    activity_type: str
    prompt: str
    answer_space_lines: int = Field(default=4, ge=1, le=20)
    sample_answer: str
    grading_criteria: list[str] = Field(min_length=1)
    max_points: int = Field(default=20, gt=0)
    source_reference: SourceReference


class WorksheetPayload(BaseModel):
    title: str
    instructions: str
    activities: list[WorksheetActivity] = Field(min_length=1)


# =========================
# 6 Educational Game Schemas
# =========================


class GameSettings(BaseModel):
    time_limit_seconds: int = Field(default=120, ge=15, le=1800)
    shuffle: bool = True


class GamePayload(BaseModel):
    game_type: Literal[
        "quiz_battle",
        "word_matching",
        "true_false",
        "memory_cards",
        "crossword",
        "word_puzzle",
    ]
    title: str
    instructions: str
    settings: GameSettings = Field(default_factory=GameSettings)
    max_possible_score: int = Field(gt=0)
    items: list[dict[str, Any]] = Field(default_factory=list)
    grid_size: dict[str, int] | None = None
    entries: list[dict[str, Any]] | None = None
    source_references: list[SourceReference] = Field(default_factory=list)


class GenerationEnvelope(BaseModel):
    payload: dict[str, Any]
    source_references: list[SourceReference]
    validation_report: ValidationReport
    usage: UsageMetrics


class ExportPptxRequest(BaseModel):
    presentation: PresentationPayload
    upload_url: str


class ExportPptxResponse(BaseModel):
    slide_count: int
    size_bytes: int
