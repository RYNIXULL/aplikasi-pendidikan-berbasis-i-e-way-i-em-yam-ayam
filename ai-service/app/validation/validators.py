import re
from app.schemas.contracts import GamePayload, QuizPayload, SourceReference, ValidationReport


def validate_page_references(
    refs: list[SourceReference],
    valid_pages: set[int],
) -> tuple[bool, list[str]]:
    warnings: list[str] = []
    if not valid_pages:
        return True, warnings
    max_page = max(valid_pages)
    all_valid = True
    for ref in refs:
        if ref.page < 1 or ref.page > max_page:
            all_valid = False
            warnings.append(f"Out-of-range source_reference page {ref.page} (valid: 1..{max_page}).")
    return all_valid, warnings


def validate_quiz_semantics(quiz: QuizPayload, valid_pages: set[int]) -> tuple[QuizPayload, ValidationReport]:
    warnings: list[str] = []
    seen_prompts: set[str] = set()
    cleaned_questions = []

    for q in quiz.questions:
        norm_prompt = re.sub(r"\s+", " ", q.question.strip().lower())
        if norm_prompt in seen_prompts:
            warnings.append(f"Removed duplicate question: {q.id}")
            continue
        seen_prompts.add(norm_prompt)

        if q.type == "multiple_choice":
            if not q.options or len(q.options) < 3:
                raise ValueError(f"Multiple choice question {q.id} must have at least 3 options.")
            if len({o.strip().lower() for o in q.options}) != len(q.options):
                raise ValueError(f"Multiple choice question {q.id} contains duplicate options.")
            if q.correct_answer not in q.options:
                raise ValueError(f"Multiple choice question {q.id} correct_answer not in options.")
        elif q.type == "true_false":
            if q.options and q.correct_answer not in q.options:
                raise ValueError(f"True/False question {q.id} correct_answer not in options.")

        cleaned_questions.append(q)

    if not cleaned_questions:
        raise ValueError("Quiz contains zero valid questions after validation.")

    cleaned_quiz = quiz.model_copy(update={"questions": cleaned_questions})
    refs = [q.source_reference for q in cleaned_questions]
    grounding_ok, ref_warnings = validate_page_references(refs, valid_pages)
    warnings.extend(ref_warnings)

    return cleaned_quiz, ValidationReport(
        schema_valid=True,
        grounding_verified=grounding_ok,
        warnings=warnings,
    )


def validate_crossword_geometry(game: GamePayload) -> list[str]:
    if game.game_type != "crossword":
        return []
    if not game.grid_size or not game.entries:
        raise ValueError("Crossword game must provide grid_size and non-empty entries.")

    rows = game.grid_size.get("rows", 0)
    cols = game.grid_size.get("cols", 0)
    if rows < 3 or cols < 3 or rows > 25 or cols > 25:
        raise ValueError("Crossword grid dimensions must be between 3x3 and 25x25.")

    grid: dict[tuple[int, int], str] = {}
    for entry in game.entries:
        answer = str(entry.get("answer", "")).strip().upper()
        if not re.fullmatch(r"[A-Z]{2,20}", answer):
            raise ValueError(f"Invalid crossword answer '{answer}': must be 2-20 uppercase A-Z letters.")
        direction = entry.get("direction")
        r = int(entry.get("row", -1))
        c = int(entry.get("col", -1))
        if direction not in ("across", "down"):
            raise ValueError(f"Invalid crossword direction: {direction}")

        for i, ch in enumerate(answer):
            rr = r + (i if direction == "down" else 0)
            cc = c + (i if direction == "across" else 0)
            if rr < 0 or cc < 0 or rr >= rows or cc >= cols:
                raise ValueError(f"Crossword entry '{answer}' exceeds grid bounds at ({rr}, {cc}).")
            existing = grid.get((rr, cc))
            if existing is not None and existing != ch:
                raise ValueError(
                    f"Crossword intersection conflict at ({rr}, {cc}): '{existing}' vs '{ch}'."
                )
            grid[(rr, cc)] = ch

    return []
