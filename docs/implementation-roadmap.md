# Implementation Roadmap & Discovery Analysis

**Version:** 1.0  
**Phase:** Phase 0 — Project Discovery & Planning  
**Aligned Sources:** Master Execution Prompt, `prd.md.txt` (v1.0), `rnd.md.txt` (v1.0)

---

## 1. Phase 0 Discovery Findings

### 1.1. Current Workspace State
Inspection of `d:\proyek\mobile` confirmed a greenfield repository containing only:
- `d:\proyek\mobile\prd.md.txt`
- `d:\proyek\mobile\rnd.md.txt`

No Flutter app, Node.js service, Python service, Dockerfiles, migrations, `.gitignore`, or `.git` repository exist yet.

### 1.2. Verified Host Toolchain
| Tool | Observed Version / Status | Architectural Impact |
|---|---|---|
| Flutter / Dart | `3.29.3` (channel `stable`) / Dart `3.7.2` | Compatible with Riverpod, GoRouter, Dio, Drift, Freezed |
| Node.js / npm | `v25.8.0` / `11.13.0` | Ready for Express + TypeScript + Prisma + Vitest |
| Python (PATH default) | `3.14.3` | Too new for several native C-extension wheels |
| Python (via `uv` / `py`) | `3.12.14` (Astral/uv) & `3.13` & `3.11`; `uv 0.12.9` | Pin `ai-service` cleanly to Python `3.12` via `uv` and Docker `python:3.12-slim` |
| Docker / Compose | `29.4.3` / Compose `v5.1.3` | Ready to containerize PostgreSQL + `pgvector`, Redis, and MinIO locally |
| `psql` (native CLI) | Not installed on Windows host | Use `docker compose exec postgres psql` or Node/Prisma scripts |
| Git | `2.54.0.windows.1` | Ready to initialize after creating strict `.gitignore` |

---

## 2. Gap Analysis & Requirement Clarifications

Comparing `prd.md.txt`, `rnd.md.txt`, and the Master Execution Prompt reveals the following gaps or minor divergences requiring documented defaults and stakeholder confirmation:

| Area | Finding Across Specs | Recommended Baseline Default | Stakeholder Confirmation Needed? |
|---|---|---|---|
| **Product Name & Android `applicationId`** | Not specified in PRD/R&D. | Working internal title: `EduAI Ecosystem`; package ID placeholder `com.example.edu_ai` (update before release signing). | Confirm final brand name & reverse-domain ID. |
| **Default Language** | PRD/R&D are in Indonesian (`id`), Master Prompt is in English (`en`). | Bilingual support (`id` & `en`) via Flutter localization (`l10n`), defaulting UI to Indonesian (`id`) and prompting AI in the document's detected language. | Confirm default mobile UI locale (`id` vs `en`). |
| **PRD MVP vs Master Roadmap** | PRD Section 7 excludes PPTX, Games, and Advanced Analytics from MVP; Master Section 14 sequences them into Phases 6–8. | Treat **Phases 1–5** as the **Core MVP Milestone** (proving end-to-end doc -> summary/quiz -> classroom -> student grading), then deliver **Phases 6–8** cleanly as Expansion Phases. | Informational (already aligned in Phases 1–8). |
| **Teacher Role Self-Registration** | PRD says users pick Teacher or Student role at registration; open teacher signup risks student impersonation in production. | Phase 1 supports self-selected `TEACHER`/`STUDENT` for development & pilot ease, with an extensible `status` (`PENDING_VERIFICATION` / invite code toggle via env flag) for production rollout. | Confirm whether pilot needs teacher verification codes. |
| **Password Reset Delivery** | PRD Section 4.1 requires password reset; no email/SMTP vendor specified. | Implement full token/OTP persistence & endpoints with a `MailProvider` interface: dev uses console/Mailpit logger, prod uses SMTP env config. | Confirm SMTP provider when ready for staging. |
| **Upload Limits & OCR Trigger** | Large scanned PDFs can exhaust memory/latency if unconstrained. | Enforce `25 MB` max upload, max `150` pages per document in MVP, and trigger OCR only per page where extracted text < 40 chars (capped safely). | Confirm file size / page ceilings. |
| **Gemini API Key & Budget** | Master Prompt targets Gemini API; no key exists in workspace yet. | Isolate in backend/AI `.env` (never committed). Support `DeterministicMockProvider` strictly in automated tests when `APP_ENV=test`. | Provide `GEMINI_API_KEY` locally in Phase 3+. |

---

## 3. Cross-Specification Phase Alignment

| Master Phase | Scope Summary | PRD Roadmap Alignment | R&D Stage Alignment | Milestone Tier |
|---|---|---|---|---|
| **Phase 0** | Discovery, Architecture, ERD, API Contract, Roadmap, ADRs | Pre-Phase | Pre-Stage | Planning Gate |
| **Phase 1** | Repo scaffold, Infra (PG+pgvector, Redis, MinIO), Design System, Auth, Role Shells | Phase 1 (Partial) | Stage 1 | Core MVP |
| **Phase 2** | Document upload, validation, S3 storage, BullMQ pipeline infra, doc CRUD | Phase 1 (Complete) | Stage 1–2 | Core MVP |
| **Phase 3** | PDF/DOCX/PPTX extraction, OCR fallback, normalization, chunking, embeddings, analysis | Phase 2 | Stage 2 | Core MVP |
| **Phase 4** | AIProvider (Gemini), Summary & Quiz generators, validation, editor, versioning, approval | Phase 2 | Stage 3 | Core MVP |
| **Phase 5** | Classrooms, codes, enrollment, publishing, student learning, quiz submission & grading | Phase 3 | Stage 4 | **Core MVP Complete** |
| **Phase 6** | Presentation JSON + `.pptx` synthesis, Flashcards, Mind Maps, Worksheets | Phase 4 | Stage 5 | Expansion |
| **Phase 7** | Educational Game schemas, 6 Flutter renderers, scoring, history, leaderboards | Phase 5 | Stage 5 | Expansion |
| **Phase 8** | Learning analytics, performance tuning, security audit, AI cost telemetry, UAT | Phase 6 | Stage 6 | Production Readiness |

---

## 4. Detailed Phase Breakdown & Acceptance Gates

### Phase 0 — Project Discovery and Planning
- **Objective:** Inspect workspace & toolchain, reconcile PRD/R&D/Master Prompt, lock architecture, ERD, API contracts, roadmap, and ADRs before writing application code.
- **Deliverables:** `docs/architecture.md`, `docs/erd.md`, `docs/api-contract.md`, `docs/implementation-roadmap.md`, `docs/technical-decisions.md`.
- **Acceptance Criteria:** All 5 documents exist, are mutually consistent, cover all 24 entities and all endpoints, contain zero leaked secrets, and receive explicit user sign-off.

### Phase 1 — Foundation
- **Objective:** Establish multi-service project skeletons, Docker infra, Prisma migrations, Flutter design system, secure auth with refresh-token rotation, and separate Teacher/Student navigation shells.
- **Scope:**
  - Root `.gitignore` & `.env.example`; `infra/docker-compose.yml` (PostgreSQL 16 + `pgvector`, Redis 7, MinIO).
  - Node.js Express + TypeScript setup, Pino logger, Zod env config, Prisma schema & initial migration for Domain A (`users`, `user_profiles`, `refresh_tokens`, `password_reset_tokens`, `audit_logs`) + core enums.
  - Auth endpoints (`/auth/register`, `/login`, `/refresh`, `/logout`, `/logout-all`, `/forgot-password`, `/reset-password`, `/me`, `/users/me/profile`, `/users/me/password`) with Argon2id + token family reuse detection + RBAC.
  - Python 3.12 FastAPI skeleton (`/internal/v1/health`) with `uv` lockfile and HMAC internal auth middleware.
  - Flutter app setup (`Riverpod`, `GoRouter`, `Dio` + refresh interceptor, `FlutterSecureStorage`, `Drift` setup), full UI Design System (`PrimaryButton`, `SecondaryButton`, `InputField`, `SearchField`, `ContentCard`, `DocumentCard`, `SubjectBadge`, `AppProgressIndicator`, `EmptyState`, `ErrorState`, `LoadingState`, restrained frosted-glass `BottomNavigation`, `ConfirmationDialog`, `AppToast`), zero emojis/sparkles/native `alert()`, plus Teacher & Student placeholder dashboards.
- **Acceptance Criteria & Tests:**
  - `docker compose up` starts PG, Redis, MinIO healthy; `prisma migrate` runs cleanly.
  - Vitest integration tests pass for register, login, token refresh, reuse detection revocation, role guards (`TEACHER` vs `STUDENT`), and profile update.
  - Flutter unit, repository, GoRouter guard, and widget tests pass (`flutter test`).

### Phase 2 — Document Management
- **Objective:** Enable teachers to securely upload, inspect, manage, and delete PDF, DOCX, and PPTX files backed by private S3 storage and BullMQ queue infrastructure.
- **Scope:**
  - Prisma migration for `documents` table.
  - Multi-layer server upload validation (extension, MIME, magic bytes, zip-bomb protection, 25 MB cap).
  - Private MinIO/S3 object storage adapter + short-lived pre-signed download URLs.
  - `POST /documents`, `GET /documents`, `GET /documents/:id`, `PATCH /documents/:id`, `DELETE /documents/:id`, `GET /documents/:id/status`, `GET /documents/:id/download-url`.
  - BullMQ `doc-processing` queue skeleton + worker lifecycle.
  - Flutter Teacher `My Materials` screens (upload picker, validation error toasts, document list with search/filter, status badges, detail view, delete confirmation dialog).
- **Acceptance Criteria & Tests:**
  - Malicious/oversized/spoofed files rejected with `400`/`413`/`415`; valid files land in private S3.
  - IDOR tests prove Teacher B cannot read, download, or delete Teacher A's document (`403`/`404`).

### Phase 3 — AI Document Intelligence
- **Objective:** Extract, normalize, chunk, embed, and structurally analyze uploaded PDF/DOCX/PPTX documents into persistent grounded knowledge.
- **Scope:**
  - Prisma migration for `document_pages`, `document_chunks` (`vector(768)` + HNSW index), `document_analyses`, and `ai_usage_logs`.
  - Python extraction pipeline (`PyMuPDF`, `python-docx`, `python-pptx`, selective OCR fallback for image-only PDF pages).
  - Structure-aware semantic chunker preserving page numbers and headings.
  - `AIProvider` abstraction + initial `GeminiProvider` (`google-genai` SDK) for embeddings and structured `DocumentAnalysis`.
  - SHA-256 unchanged-document analysis reuse guard.
  - Flutter Document Detail analysis viewer (chapters, key concepts, definitions, learning objectives, source page tags) + live polling progress indicator.
- **Acceptance Criteria & Tests:**
  - Pytest verifies extraction accuracy across sample PDF, DOCX, and PPTX fixtures plus chunk page references.
  - Re-uploading/re-checking identical SHA-256 skips duplicate LLM analysis costs.
  - Prompt-injection payload embedded inside a test PDF does not alter `DocumentAnalysis` schema or leak system instructions.

### Phase 4 — AI Content Generation (Summary & Quiz)
- **Objective:** Deliver grounded Summary and Quiz generation with strict schema validation, teacher editor, version history, and mandatory approval gate.
- **Scope:**
  - Prisma migration for `generation_jobs`, `generated_contents`, `generation_versions`.
  - Node.js `ai-orchestration` and `contents` modules (idempotent `POST /ai/generate`, quota checks, `pgvector` RAG context retrieval).
  - Python `SummaryGenerator` and `QuizGenerator` with Pydantic validation + max-2 retry repair loop + source citation verification.
  - Flutter Teacher `AI Generator` wizard + `Content Editor` (edit summary sections, edit/reorder/add/remove quiz questions, restore versions, preview, explicit Approve button).
- **Acceptance Criteria & Tests:**
  - >= 90% schema pass rate across test documents; ungrounded claims flagged cleanly.
  - Teacher edits create immutable `generation_versions`; unapproved `DRAFT` content cannot be published (`400 CONTENT_NOT_APPROVED`).

### Phase 5 — Classroom & Student Learning (MVP Completion)
- **Objective:** Complete the end-to-end Teacher-to-Student educational loop with classrooms, publishing, student learning, quiz submission, and hybrid grading.
- **Scope:**
  - Prisma migration for `classrooms`, `classroom_members`, `classroom_materials`, `assessments`, `assessment_questions`, `assessment_attempts`, `assessment_answers`, `student_progress`, `learning_activities`.
  - Classroom creation, 8-char code generation, student join flow, publishing approved snapshots.
  - Assessment creation, publishing, timed student attempts, auto-grading (MCQ & True/False), manual essay grading, result reporting.
  - Flutter Student workspace (`Home`, `My Classes`, `Learning` material viewer with Drift offline caching, `Assignments` quiz runner, `Progress` results).
- **Acceptance Criteria & Tests:**
  - Full E2E suite passes: teacher signup -> upload -> analyze -> summary & quiz -> edit & approve -> create class -> publish -> student enroll -> take quiz -> auto/manual grade -> score report.
  - Strict student authorization checks pass (no peer result access, no answer-key leak during active attempt, no extra attempts beyond `max_attempts`).

### Phase 6 — Advanced Content Generators
- **Objective:** Expand multi-format generation from the shared `document_analyses` and `document_chunks` knowledge base.
- **Scope:**
  - Python `PresentationGenerator` + `python-pptx` binary exporter (`POST /contents/:id/export/pptx`).
  - `FlashcardGenerator`, `MindMapGenerator`, and `WorksheetGenerator` with strict Pydantic/Zod schemas.
  - Flutter interactive Flashcard deck viewer (flip & self-check), interactive Mind Map node graph viewer, Worksheet viewer, and PPTX slide preview/download.
- **Acceptance Criteria & Tests:**
  - Generated `.pptx` opens validly and matches slide JSON; Flutter viewers handle deep mind map hierarchies and offline caching smoothly.

### Phase 7 — Educational Game Engine
- **Objective:** Deliver the template-based educational game engine across 6 game modes with zero AI-generated code.
- **Scope:**
  - Prisma migration for `game_sessions`.
  - Python `GameGenerator` for `quiz_battle`, `word_matching`, `true_false`, `memory_cards`, `crossword` (with grid intersection validator), and `word_puzzle`.
  - Flutter 6 native game renderers (`QuizBattleRenderer`, `WordMatchingRenderer`, `TrueFalseRenderer`, `MemoryCardRenderer`, `CrosswordRenderer`, `WordPuzzleRenderer`) with timer, sound/visual feedback toggle, score breakdown, history, and classroom leaderboard.
- **Acceptance Criteria & Tests:**
  - Crossword generator passes geometric intersection validation tests 100%; backend rejects tampered scores exceeding `max_possible_score`.

### Phase 8 — Analytics, Security Hardening & Optimization
- **Objective:** Deliver teacher learning analytics, AI cost dashboards, performance optimization, security verification, and UAT readiness.
- **Scope:**
  - Prisma migration for `learning_analytics`.
  - Classroom completion rates, score distributions, per-question difficulty & commonly missed topics.
  - AI evaluation benchmark suite (Faithfulness, Relevance, Completeness, Correctness, Readability, Schema Validity on Indonesian & English corpus).
  - Load/latency tuning, security penetration checklist verification (IDOR, upload abuse, rate limits, prompt injection, secret scan), and UAT sign-off report.
- **Acceptance Criteria & Tests:**
  - Document pipeline >= 95% success on supported clean fixtures; zero high/critical security findings; UAT checklist approved.

---

## 5. Definition of Done (Every Phase)

A phase is marked `COMPLETE` only when ALL conditions hold:
1. Code complies with architectural boundaries, TypeScript/Dart/Python strict linters pass.
2. All unit, integration, authorization, and widget tests for the phase pass after the final edit.
3. No `.env`, real credentials, PII, native `alert()`, emojis, or sparkles icons exist anywhere in code or docs.
4. `.env.example` and `docs/` reflect any schema or endpoint refinements.
5. A formal Phase Execution Report (Section 16 format) is delivered and verified.
